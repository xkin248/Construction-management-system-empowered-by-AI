"""Generate site-style task text for every labelled trade title, from Gemini.

Why synthetic data
------------------
The supervised classifier is trained on 542 *occupation titles* ("Carpenters",
"Tile and Stone Setters"), but the field input is a site instruction ("chip the
old plaster off the bathroom wall before tiling"). The previous report measured
that mismatch directly and listed it as the top open issue: there is no
supervision for task-shaped wording. Hand-writing thousands of instructions is
not affordable, so this script asks Gemini to write them from the titles that
*are* labelled, and keeps every generated row traceable to the title it came
from.

Reproducibility
---------------
Two API calls are never paid for twice:

* ``data/synthetic_trade_raw.jsonl``      one line per (prompt version, batch),
  written as soon as a batch returns. A rerun reuses it and only calls the API
  for batches that are missing or failed.
* ``data/synthetic_trade_tasks.jsonl``    the filtered dataset actually trained
  on, one row per accepted instruction.

``PROMPT_VERSION`` is part of both the cache key and every output row, and
``SYNTH_SEED`` is recorded next to the temperature. Changing the prompt without
bumping the version would silently mix two distributions, so the version is
stamped into the artefacts' metadata as well.

Quality gate
------------
Generation is not trusted. Each instruction has to survive:

============  ==========================================================
too_short     < 20 chars or < 4 tokens (not an instruction, just a noun)
off_topic     shares no content word with the source title nor with its
              trade's keyword vocabulary
label_drift   the declared trade does not contain the source title's trade
              (the model invented a different occupation)
multi_trade   three or more distinct trades' vocabularies match, or the
              model declares more than two trades: a "mixed bag" sample
              teaches the classifier to spread probability everywhere
duplicate     normalised text already seen
============  ==========================================================

The rejected counts are written to a stats file and quoted in the report, so
the filter's aggressiveness is visible instead of implicit.

Usage
-----
    python scripts/synth_trade_tasks.py                # resume / generate
    python scripts/synth_trade_tasks.py --limit 2      # smoke test (2 batches)
    python scripts/synth_trade_tasks.py --stats        # filter report only
"""
from __future__ import annotations

import argparse
import json
import os
import random
import re
import sys
import time
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

from dotenv import dotenv_values

BACKEND = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND))

from scripts.build_trade_matcher import (  # noqa: E402
    CANONICAL,
    DATA,
    SEED_KEYWORDS,
    build_profiles,
    clean,
)

PROMPT_VERSION = "synth-v1"
SYNTH_SEED = 20261027
TEMPERATURE = 0.9
BATCH_SIZE = 8
MIN_PER_TITLE = 8
MAX_PER_TITLE = 10
MAX_ATTEMPTS = 4
RETRY_SLEEP = 4.0

RAW_PATH = DATA / "synthetic_trade_raw.jsonl"
TASKS_PATH = DATA / "synthetic_trade_tasks.jsonl"

PROMPT = """You are writing training data for a construction-site task classifier.

The classifier maps a free-text site instruction to one or more of these trades:
{trades}

For EACH occupation title below, write {lo} to {hi} short, realistic instructions
that a site supervisor or a worker would actually type into a task app. Titles are
O*NET occupation names; the instructions must describe the WORK that occupation
does, not the job title itself.

Rules:
1. Use everyday site English. Vary the length (6-25 words) and the phrasing:
   some imperative ("chip off the old plaster..."), some descriptive
   ("need someone to ..."), a few in Bahasa Melayu (about 1 in 5).
2. Never name the occupation in the instruction. "Tile the bathroom floor" is
   good; "hire a tile setter to tile the floor" is bad, because the classifier
   would learn the title, not the work.
3. Name concrete materials, tools, rooms and defects (grout, conduit, plasterboard,
   toilet bowl, ceiling, cracked, leaking, 3 rooms, level 2 ...).
4. Most instructions need exactly ONE trade. Use two trades only when the job
   genuinely needs both (e.g. "remove the old carpet and lay vinyl in the same
   room" = flooring + tiling). Never list three.
5. Only use trade ids from the list above, spelled exactly as written.

Occupation titles ({n} of them):
{titles}

Return ONLY minified JSON, no markdown fence, in exactly this shape:
{{"tasks":[{{"title":"<exact title as given>","items":[{{"text":"<instruction>","trades":["<trade id>"],"lang":"en|ms"}}]}}]}}

Every title must appear exactly once in "tasks", with {lo}-{hi} items."""


def load_titles() -> dict[str, list[str]]:
    """``{cleaned title: [trades]}`` for every mapped dataset title."""
    profiles, _, _ = build_profiles()
    by_title: dict[str, list[str]] = defaultdict(list)
    for trade, titles in profiles.items():
        for raw in titles:
            text = clean(raw)
            if text and trade not in by_title[text]:
                by_title[text].append(trade)
    return {t: sorted(v, key=CANONICAL.index) for t, v in sorted(by_title.items())}


def _api_key() -> tuple[str, str]:
    env = dotenv_values(BACKEND / ".env")
    key = (env.get("GEMINI_API_KEY") or os.environ.get("GEMINI_API_KEY") or "").strip()
    model = (env.get("GEMINI_MODEL") or os.environ.get("GEMINI_MODEL") or "gemini-2.0-flash").strip()
    return key, model


MISSING_LANG_RE = re.compile(r',\s*"(en|ms)"\s*\}')


def _repair(text: str) -> str:
    """Fix the two malformations Gemini actually produces.

    1. ``"trades":["x"],"ms"}``  - the ``lang`` key is dropped now and then.
    2. Nothing else is patched: guessing further would corrupt valid payloads.
    """
    return MISSING_LANG_RE.sub(lambda m: f',"lang":"{m.group(1)}"', text)


def _extract_json(text: str):
    """Parse the first JSON object/array in a model answer (fences tolerated)."""
    text = (text or "").strip()
    if not text:
        return None
    fence = re.search(r"```(?:json)?\s*(.+?)```", text, re.S)
    if fence:
        text = fence.group(1).strip()
    for opener, closer in (("{", "}"), ("[", "]")):
        start = text.find(opener)
        end = text.rfind(closer)
        if start >= 0 and end > start:
            blob = text[start:end + 1]
            for candidate in (blob, _repair(blob)):
                try:
                    return json.loads(candidate)
                except json.JSONDecodeError:
                    continue
    for candidate in (text, _repair(text)):
        try:
            return json.loads(candidate)
        except json.JSONDecodeError:
            continue
    return None


def _response_text(resp) -> str:
    """Join every text part of the first candidate.

    Gemini splits long answers into many streamed parts, so ``resp.text`` raises
    instead of returning the string when the payload is chunked.
    """
    candidates = getattr(resp, "candidates", None) or []
    if not candidates:
        return ""
    parts = getattr(candidates[0].content, "parts", None) or []
    return "".join(getattr(p, "text", "") or "" for p in parts)


def _batch_prompt(titles: list[str], trade_of: dict[str, list[str]]) -> str:
    lines = [
        f'{i}. title: "{t}" | trade: {"/".join(trade_of[t])}'
        for i, t in enumerate(titles, 1)
    ]
    return PROMPT.format(
        trades=", ".join(CANONICAL),
        lo=MIN_PER_TITLE,
        hi=MAX_PER_TITLE,
        n=len(titles),
        titles="\n".join(lines),
    )


def _load_raw() -> dict[str, dict]:
    """``{cache key: batch record}`` from the raw JSONL (resumable)."""
    cache: dict[str, dict] = {}
    if not RAW_PATH.exists():
        return cache
    for line in RAW_PATH.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            continue
        if rec.get("prompt_version") == PROMPT_VERSION and rec.get("items"):
            cache[rec["key"]] = rec
    return cache


def _append_raw(rec: dict) -> None:
    RAW_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(RAW_PATH, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(rec, ensure_ascii=False) + "\n")


def _key(titles: list[str]) -> str:
    return f"{PROMPT_VERSION}:{hash(tuple(titles)) & 0xFFFFFFFF:08x}"


def generate(titles: list[str], trade_of: dict[str, list[str]], limit: int = 0,
             pause: float = 0.6, model_name: str = "", batch_size: int = BATCH_SIZE,
             max_output: int = 8192) -> dict:
    """Call Gemini for every batch that is not cached yet.

    The free tier allows 20 requests per day *per model*, so ``--model`` and
    ``--batch`` exist to trade per-call breadth against truncation risk. A 429
    stops the run instead of burning retries: the cache keeps everything already
    generated and the next run resumes where this one stopped.
    """
    key, env_model = _api_key()
    if not key:
        raise SystemExit("GEMINI_API_KEY missing in Backend/.env")
    model_name = (model_name or env_model).strip()
    import google.generativeai as genai

    genai.configure(api_key=key)
    model = genai.GenerativeModel(model_name)
    gen = {"temperature": TEMPERATURE, "top_p": 0.95, "max_output_tokens": max_output}

    cache = _load_raw()
    # Batch the *uncovered* titles only, so a change of --batch never throws
    # away work already paid for.
    covered = {t for rec in cache.values() for t in rec.get("titles", [])}
    remaining = [t for t in titles if t not in covered]
    batches = [remaining[i:i + batch_size] for i in range(0, len(remaining), batch_size)]
    todo = batches
    print(f"model {model_name} | titles {len(titles)} | covered {len(titles) - len(remaining)} | "
          f"batches to call {len(todo)} (size {batch_size})")
    if limit:
        todo = todo[:limit]

    called = failed = 0
    for idx, batch in enumerate(todo, 1):
        prompt = _batch_prompt(batch, trade_of)
        parsed = None
        for attempt in range(1, MAX_ATTEMPTS + 1):
            try:
                resp = model.generate_content(
                    prompt,
                    generation_config=gen,
                    request_options={"timeout": 180},
                )
                parsed = _extract_json(_response_text(resp))
                if isinstance(parsed, dict) and isinstance(parsed.get("tasks"), list):
                    break
                parsed = None
                raise ValueError("payload missing 'tasks'")
            except Exception as exc:  # noqa: BLE001 - retried, then recorded
                text = str(exc)
                if "429" in text or "quota" in text.lower():
                    print(f"  quota exhausted on {model_name}: stopping. "
                          f"cached so far: {called}")
                    time.sleep(0)
                    raise SystemExit(3)
                wait = RETRY_SLEEP * attempt
                print(f"  [{idx}/{len(todo)}] attempt {attempt} failed: {text[:160]} (sleep {wait:.0f}s)")
                time.sleep(wait)
        called += 1
        if parsed is None:
            failed += 1
            continue

        by_title = {}
        for entry in parsed["tasks"]:
            if not isinstance(entry, dict):
                continue
            title = clean(entry.get("title") or "")
            items = entry.get("items")
            if title in trade_of and isinstance(items, list):
                by_title[title] = items
        rec = {
            "key": _key(batch),
            "prompt_version": PROMPT_VERSION,
            "model": model_name,
            "temperature": TEMPERATURE,
            "seed": SYNTH_SEED,
            "titles": batch,
            "created_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "items": [{"title": t, "items": items} for t, items in by_title.items()],
        }
        _append_raw(rec)
        missing = [t for t in batch if t not in by_title]
        print(f"  [{idx}/{len(todo)}] ok: {len(by_title)}/{len(batch)} titles"
              + (f" (missing {missing[:2]})" if missing else ""))
        time.sleep(pause)
    return {"called": called, "failed": failed, "cached": len(batches) - len(todo)}


# ---------------------------------------------------------------------------
# Quality filter
# ---------------------------------------------------------------------------
TOKEN_RE = re.compile(r"[a-z0-9]+")
GENERIC = set(
    "the a an and or for with of to in on at by from into onto under over new old "
    "need needed want please someone some this that these those then than there here "
    "work task job site area room house floor level unit all any each per plus very "
    "make made get got put use using done doing do does it its is are be been will "
    "can could should would must also just only more most less least few many much "
    "after before while when where which who what how why not no yes ok okay still "
    "again already once twice day days week weeks hour hours".split()
)


def _tokens(text: str) -> list[str]:
    return [t for t in TOKEN_RE.findall(clean(text)) if t not in GENERIC and len(t) > 2]


# Physical site vocabulary. Used only to decide whether a generated sentence is
# *about a construction site at all*; the trade identity is checked separately
# against the title's occupation family. Kept to concrete objects and actions on
# purpose - abstract words (safety, report, meeting) would make every sentence
# look relevant.
SITE_TERMS = set(
    "wall walls floor floors ceiling ceilings roof roofing slab column beam brick "
    "bricks block blocks clay adobe earth mortar cement concrete grout plaster stucco "
    "render skim screed tile tiles tiling carpet vinyl timber wood plank plywood board "
    "boards panel panels drywall partition frame framing stud joist rafter truss gutter "
    "downpipe drain drainage pipe pipes valve pump tank tap sink toilet bowl basin shower "
    "bidet sewer water waste leak leaking drip condensate duct ducting vent ventilation "
    "aircon compressor condenser refrigerant chiller fan coil thermostat filter wiring "
    "wire wires cable conduit socket switch breaker panelboard distribution earthing "
    "grounding voltage ampere phase transformer generator motor winding armature lamp "
    "lighting light fixture downlight trunking ladder scaffold scaffolding hoist crane "
    "excavator loader mixer drill grinder cutter saw hammer nail screw bolt anchor weld "
    "welding solder torch gas cylinder steel rebar mesh reinforcement paint painting "
    "primer sealer varnish coat coating stain glass glazing window windows door doors "
    "aluminium frame sealant silicone waterproof membrane bitumen insulation acoustic "
    "sound ceiling grid hanger bracket fixing clean cleaning sweep mop wipe debris rubbish "
    "garbage bin dump excavate digging trench backfill compact asphalt paving road kerb "
    "fence gate guardrail signage demolish demolition hacking chip chisel level levelling "
    "measure measuring cut cutting install installing replace replacing repair repairing "
    "fix fixing service servicing maintain maintenance test testing inspect inspection "
    "supervise supervising coordinate coordinating check checking".split()
)
SITE_STEMS = {t[:6] for t in SITE_TERMS}


def _stems(tokens) -> set[str]:
    """Crude 6-char stem so plaster/plastering/plasterer collapse."""
    return {t[:6] for t in tokens}


def _matches_trade(text: str) -> set[str]:
    """Trades whose seed vocabulary appears (word-boundary) in ``text``."""
    low = f" {clean(text)} "
    hits = set()
    for trade, words in SEED_KEYWORDS.items():
        for word in words:
            w = clean(word)
            if not w or len(w) < 3:
                continue
            if f" {w} " in low or f" {w}s " in low:
                hits.add(trade)
                break
    return hits


def _trade_vocab(trade: str) -> set[str]:
    return _stems(
        t for w in SEED_KEYWORDS.get(trade, []) for t in _tokens(w)
    )


def filter_rows(raw_cache: dict[str, dict], trade_of: dict[str, list[str]],
                probe_ratio: float = 0.15, seed: int = SYNTH_SEED) -> tuple[list, dict]:
    """Apply the quality gate and assign a train/probe split by source title."""
    rng = random.Random(seed)
    titles = sorted(trade_of)
    rng.shuffle(titles)
    n_probe = max(1, int(round(len(titles) * probe_ratio)))
    probe_titles = set(titles[:n_probe])

    # Relevance is judged against the whole occupation family, not the single
    # title: "ac dc rewinder" is legitimately described with motor / winding /
    # armature, words that live in sibling electrical titles.
    family: dict[str, set[str]] = {}
    for trade in CANONICAL:
        words = _trade_vocab(trade)
        for title, trades in trade_of.items():
            if trade in trades:
                words |= _stems(_tokens(title))
        family[trade] = words
    seen: set[str] = set()
    kept: list[dict] = []
    rejected = Counter()
    per_trade_kept = Counter()
    per_title_kept = Counter()

    for rec in raw_cache.values():
        for entry in rec.get("items", []):
            title = entry.get("title")
            src_trades = trade_of.get(title)
            if not src_trades:
                continue
            title_stems = _stems(_tokens(title))
            src_vocab = set().union(*(family[t] for t in src_trades))
            for item in entry.get("items", []):
                if not isinstance(item, dict):
                    rejected["malformed"] += 1
                    continue
                text = str(item.get("text") or "").strip()
                declared = [str(t).strip().lower() for t in (item.get("trades") or [])]
                declared = [t for t in declared if t in CANONICAL]
                norm = clean(text)
                toks = _tokens(text)
                if len(norm) < 20 or len(toks) < 4:
                    rejected["too_short"] += 1
                    continue
                if not declared:
                    rejected["label_drift"] += 1
                    continue
                if not set(declared) & set(src_trades):
                    rejected["label_drift"] += 1
                    continue
                if len(set(declared)) > 2:
                    rejected["multi_trade"] += 1
                    continue
                text_stems = _stems(toks)
                if not (text_stems & (title_stems | src_vocab | SITE_STEMS)):
                    rejected["off_topic"] += 1
                    continue
                matched = _matches_trade(text)
                if len(matched) >= 3:
                    rejected["multi_trade"] += 1
                    continue
                if norm in seen:
                    rejected["duplicate"] += 1
                    continue
                if per_title_kept[title] >= MAX_PER_TITLE:
                    rejected["cap"] += 1
                    continue
                seen.add(norm)
                per_title_kept[title] += 1
                per_trade_kept[src_trades[0]] += 1
                kept.append({
                    "task_text": text,
                    "trades": sorted(set(declared)),
                    "source_title": title,
                    "source_trade": src_trades[0],
                    "lang": str(item.get("lang") or "en"),
                    "split": "probe" if title in probe_titles else "train",
                    "prompt_version": PROMPT_VERSION,
                    "model": rec.get("model"),
                    "seed": SYNTH_SEED,
                })

    stats = {
        "prompt_version": PROMPT_VERSION,
        "model": next(iter(raw_cache.values())).get("model") if raw_cache else None,
        "batches_cached": len(raw_cache),
        "titles_total": len(trade_of),
        "titles_generated": len({e["title"] for r in raw_cache.values() for e in r.get("items", [])}),
        "rows_raw": sum(len(e.get("items", [])) for r in raw_cache.values() for e in r.get("items", [])),
        "rows_kept": len(kept),
        "rejected": dict(rejected),
        "probe_titles": sorted(probe_titles),
        "rows_train": sum(1 for r in kept if r["split"] == "train"),
        "rows_probe": sum(1 for r in kept if r["split"] == "probe"),
        "per_trade_kept": dict(sorted(per_trade_kept.items())),
        "titles_with_lt_min": sorted(
            t for t in trade_of if per_title_kept.get(t, 0) < MIN_PER_TITLE
        ),
    }
    return kept, stats


def trade_interleaved(trade_of: dict[str, list[str]]) -> list[str]:
    """Order titles round-robin across trades.

    Alphabetical order would put 25 consecutive ``a*`` electrical titles in the
    same batch, so one failed call would lose a whole trade. Round-robin keeps
    every batch trade-diverse.
    """
    by_trade: dict[str, list[str]] = defaultdict(list)
    for title, trades in trade_of.items():
        by_trade[trades[0]].append(title)
    queues = [list(v) for _, v in sorted(by_trade.items())]
    out: list[str] = []
    while any(queues):
        for queue in queues:
            if queue:
                out.append(queue.pop(0))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0, help="only call the first N uncached batches")
    ap.add_argument("--stats", action="store_true", help="do not call the API, only refilter")
    ap.add_argument("--pause", type=float, default=0.6, help="sleep between API calls (seconds)")
    ap.add_argument("--model", default="", help="override GEMINI_MODEL (per-model daily quota)")
    ap.add_argument("--batch", type=int, default=BATCH_SIZE, help="titles per API call")
    ap.add_argument("--max-output", type=int, default=8192, help="max_output_tokens per call")
    args = ap.parse_args()

    trade_of = load_titles()
    print(f"titles: {len(trade_of)} (multi-label: "
          f"{sum(1 for v in trade_of.values() if len(v) > 1)})")

    if not args.stats:
        info = generate(trade_interleaved(trade_of), trade_of, limit=args.limit,
                        pause=args.pause, model_name=args.model,
                        batch_size=args.batch, max_output=args.max_output)
        print("api:", info)

    cache = _load_raw()
    if not cache:
        print("no cached batches - nothing to filter")
        return 1
    kept, stats = filter_rows(cache, trade_of)

    TASKS_PATH.write_text(
        "\n".join(json.dumps(r, ensure_ascii=False) for r in kept) + "\n",
        encoding="utf-8",
    )
    stats_path = BACKEND / "reports" / "synthetic_trade_stats.json"
    stats_path.parent.mkdir(exist_ok=True)
    stats_path.write_text(json.dumps(stats, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"kept {stats['rows_kept']} / raw {stats['rows_raw']} "
          f"(train {stats['rows_train']} / probe {stats['rows_probe']})")
    print("rejected:", stats["rejected"])
    print("per trade:", stats["per_trade_kept"])
    print("titles below minimum:", len(stats["titles_with_lt_min"]))
    print("saved:", TASKS_PATH)
    print("stats:", stats_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
