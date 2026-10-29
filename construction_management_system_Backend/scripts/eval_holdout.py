"""Real holdout evaluation for the BuildSmart trade matcher.

Why this exists
---------------
``scripts/eval_trade_matcher.py`` scores 75 hand-written cases that were derived
from the same seed keywords used to build the model, so its accuracy is
optimistic and cannot tell us how the matcher behaves on unseen wording.

This is the dev / tuning split (seed 42). It is **not** a generalisation estimate:

1. Load ``data/job_categorization.parquet`` and keep only the rows whose
   ``category`` is mapped to one of the 16 canonical construction trades
   (``CATEGORY_MAP``). Unmapped O*NET categories are out of scope — the system
   never claims to classify them.
2. Split titles into 80% train / 20% holdout with a **fixed random seed**
   (default 42). The split is grouped by cleaned title so the same text can
   never appear on both sides.
3. Retrain the TF-IDF matcher on the 80% only (``train_matcher``), so holdout
   titles are unseen during training — no data leakage.
4. Score the holdout with the **production pipeline**, i.e.
   ``ai_service.resolve_trade_decision()`` — keyword detection →
   ``_resolve_detected_trades`` arbitration → semantic scoring. Gemini is
   disabled (``get_gemini_model`` patched to ``None``) so the numbers isolate
   the rule + semantic layers instead of whatever an LLM happens to answer.
5. Also score the currently shipped ``data/trade_matcher.joblib`` on the same
   holdout to quantify the optimism caused by training on the test rows.
6. Write a markdown report (accuracy, per-trade recall, confusion matrix,
   top failure cases with decision source and scores) plus the raw per-row
   predictions as CSV.

Run (from ``construction_management_system_Backend``):

    python scripts/eval_holdout.py                    # write report
    python scripts/eval_holdout.py --test-size 0.2 --seed 42
    python scripts/eval_holdout.py --no-refresh-production-model

Exit code is 0 even when accuracy is low: this is a measurement tool.
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import random
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path

import joblib
import pandas as pd

BACKEND = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND))
sys.path.insert(0, str(BACKEND / "scripts"))

from build_trade_matcher import (  # noqa: E402
    CANONICAL,
    CATEGORY_MAP,
    DATA,
    artifact_fingerprint,
    build_profiles,
    clean,
    predictions_path,
    train_matcher,
)

# ---------------------------------------------------------------------------
# Isolation: the evaluation must not call Gemini. Clearing the key before the
# import stops ai_service from ever building a client, and patching
# get_gemini_model() to None makes the fallback deterministically degrade to the
# rule/semantic result even if an API key is present in the environment.
# ---------------------------------------------------------------------------
os.environ["GEMINI_API_KEY"] = ""
os.environ["GOOGLE_API_KEY"] = ""

import app.ai_service as ai  # noqa: E402

ai.get_gemini_model = lambda: None  # noqa: E731 - hard-disable LLM fallback


# ---------------------------------------------------------------------------
# Dataset helpers
# ---------------------------------------------------------------------------
def load_labelled_frame() -> tuple[pd.DataFrame, dict]:
    """Return rows mapped to canonical trades plus dataset statistics."""
    df = pd.read_parquet(DATA / "job_categorization.parquet")
    stats = {
        "rows_total": int(len(df)),
        "categories_total": int(df["category"].nunique()),
    }

    cat_to_trades: dict[str, list[str]] = defaultdict(list)
    for trade in CANONICAL:
        for cat in CATEGORY_MAP.get(trade, []):
            cat_to_trades[cat].append(trade)

    df = df.copy()
    df["expected"] = df["category"].map(
        lambda c: tuple(t for t in cat_to_trades.get(c, ()) if t in CANONICAL)
    )
    labelled = df[df["expected"].map(len) > 0].copy()
    labelled["text"] = labelled["title"].map(clean)
    labelled = labelled[labelled["text"] != ""]

    stats["rows_labelled"] = int(len(labelled))
    stats["rows_unmapped"] = stats["rows_total"] - stats["rows_labelled"]
    stats["categories_mapped"] = int(labelled["category"].nunique())
    multi = labelled[labelled["expected"].map(len) > 1]
    stats["rows_multi_label"] = int(len(multi))
    stats["multi_label_categories"] = sorted(multi["category"].unique().tolist())
    return labelled, stats


def group_split(labelled: pd.DataFrame, test_size: float, seed: int):
    """Group-aware split by cleaned title (identical text never straddles)."""
    groups = sorted(labelled["text"].unique().tolist())
    rng = random.Random(seed)
    rng.shuffle(groups)
    n_test = max(1, int(round(len(groups) * test_size)))
    test_groups = set(groups[:n_test])
    mask = labelled["text"].isin(test_groups)
    return labelled[~mask].copy(), labelled[mask].copy(), groups, sorted(test_groups)


def primary_label(expected: tuple[str, ...]) -> str:
    """Deterministic single label for the confusion matrix (canonical order)."""
    for trade in CANONICAL:
        if trade in expected:
            return trade
    return expected[0]


# ---------------------------------------------------------------------------
# Prediction using the production pipeline
# ---------------------------------------------------------------------------
def predict_rows(frame: pd.DataFrame) -> list[dict]:
    rows = []
    for rec in frame.itertuples(index=False):
        text = rec.text
        decision = ai.resolve_trade_decision(text, "")
        preds = sorted(decision["detected_trades"])
        scores = {k: float(v) for k, v in (decision["semantic_scores"] or {}).items()}
        if len(preds) > 1:
            # Tie-break by score then canonical order, deterministic for the report.
            pred_primary = max(
                preds, key=lambda t: (scores.get(t, 0.0), -CANONICAL.index(t))
            )
        elif preds:
            pred_primary = preds[0]
        else:
            pred_primary = None

        expected = tuple(rec.expected)
        trace = decision["trace"] or {}
        rows.append(
            {
                "text": text,
                "category": rec.category,
                "expected": list(expected),
                "expected_primary": primary_label(expected),
                "predicted": preds,
                "predicted_primary": pred_primary,
                "correct_top1": pred_primary in expected if pred_primary else False,
                "exact_set_match": set(preds) == set(expected),
                "source": trace.get("source") or decision["trade_source"],
                "confidence": round(float(decision["confidence"]), 4),
                "keyword_trades": sorted(decision["keyword_trades"]),
                "raw_scores": {k: round(v, 4) for k, v in
                               sorted((decision["raw_semantic_scores"] or {}).items(),
                                      key=lambda kv: -kv[1])[:3]},
                "scores": {k: round(v, 4) for k, v in scores.items()},
            }
        )
    return rows


def metrics(preds: list[dict]) -> dict:
    n = len(preds)
    correct = sum(1 for p in preds if p["correct_top1"])
    exact = sum(1 for p in preds if p["exact_set_match"])
    skipped = sum(1 for p in preds if not p["predicted"])

    per_trade = {}
    for trade in CANONICAL:
        support = [p for p in preds if trade in p["expected"]]
        # Recall is credited per expected trade: any prediction that is a member of
        # the expected set counts (so tiling/flooring style ambiguities are not
        # double-penalised). Strict recall below only credits the primary label.
        hits = [p for p in support if p["correct_top1"]]
        strict_support = [p for p in preds if p["expected_primary"] == trade]
        strict_hits = [p for p in strict_support if p["predicted_primary"] == trade]
        per_trade[trade] = {
            "support": len(support),
            "recall": (len(hits) / len(support)) if support else None,
            "strict_support": len(strict_support),
            "strict_recall": (len(strict_hits) / len(strict_support)) if strict_support else None,
        }

    by_source = defaultdict(lambda: {"n": 0, "correct": 0})
    for p in preds:
        key = p["source"] if p["predicted"] else "skip"
        by_source[key]["n"] += 1
        by_source[key]["correct"] += 1 if p["correct_top1"] else 0

    return {
        "n": n,
        "accuracy": correct / n if n else 0.0,
        "exact_set_accuracy": exact / n if n else 0.0,
        "skipped": skipped,
        "skip_rate": skipped / n if n else 0.0,
        "per_trade": per_trade,
        "by_source": dict(by_source),
        "macro_recall": _mean([v["recall"] for v in per_trade.values()]),
        "macro_strict_recall": _mean([v["strict_recall"] for v in per_trade.values()]),
    }


def _mean(values) -> float:
    vals = [v for v in values if v is not None]
    return sum(vals) / len(vals) if vals else 0.0


def confusion(preds: list[dict]) -> tuple[list[str], list[str], dict]:
    """Matrix over trades seen as expected primary OR predicted (plus skip).

    Returns (row_labels, col_labels, matrix); all-zero rows are dropped so a trade
    that only ever appears as a secondary label does not add an empty row, while
    it is still kept as a column if the model predicted it.
    """
    trades = [
        t for t in CANONICAL
        if any(p["expected_primary"] == t or p["predicted_primary"] == t for p in preds)
    ]
    cols = list(trades)
    if any(not p["predicted_primary"] for p in preds):
        cols.append("skip")
    matrix = {row: {col: 0 for col in cols} for row in trades}
    for p in preds:
        matrix[p["expected_primary"]][p["predicted_primary"] or "skip"] += 1
    rows = [r for r in trades if sum(matrix[r].values()) > 0]
    return rows, cols, matrix


def failures(preds: list[dict], limit: int = 15) -> list[dict]:
    bad = [p for p in preds if not p["correct_top1"]]
    skip_first = sorted(bad, key=lambda p: (bool(p["predicted"]), -len(p["text"])))
    return skip_first[:limit]


# ---------------------------------------------------------------------------
# Report rendering
# ---------------------------------------------------------------------------
def fmt_pct(value) -> str:
    return "n/a" if value is None else f"{value * 100:.1f}%"


def render_report(ctx: dict) -> str:
    honest = ctx["honest_metrics"]
    prod = ctx["prod_metrics"]
    stats = ctx["stats"]
    top_preds = ctx["honest_preds"]
    lines: list[str] = []
    add = lines.append

    add("# Trade Matcher - dev split evaluation (tuning set, seed 42)")
    add("")
    add("> **This is the dev / tuning split, not a generalisation estimate.**")
    add("> The keyword tables were designed against the failures of exactly these 104 rows,")
    add("> so the accuracy below is an upper bound fitted to this split. The honest number")
    add("> comes from the untouched test split in `reports/trade_matcher_tuning.md`")
    add("> (`scripts/eval_trade_test.py`, seed 2026, scored once).")
    add("")
    add(f"- Generated: {ctx['generated_at']}")
    add(f"- Script: `scripts/eval_holdout.py` (re-runnable, fixed seed)")
    add(f"- Data: `data/job_categorization.parquet`")
    add(f"- Seed: `{ctx['seed']}`, holdout size: `{ctx['test_size']:.0%}` "
        f"(grouped by cleaned title, identical text never splits)")
    add(f"- LLM fallback: **disabled** (`get_gemini_model()` patched to `None`), "
        f"so scores reflect the rule + semantic layers only")
    add(f"- Pipeline under test: `ai_service.resolve_trade_decision()` "
        f"(keyword detection → `_resolve_detected_trades` arbitration → semantic scoring)")
    add("")

    add("## 1. Data and split")
    add("")
    add("| Item | Value |")
    add("| --- | --- |")
    add(f"| Dataset rows | {stats['rows_total']} |")
    add(f"| Categories in dataset | {stats['categories_total']} |")
    add(f"| Rows mapped to the 16 canonical trades | {stats['rows_labelled']} "
        f"({stats['categories_mapped']} categories) |")
    add(f"| Rows excluded (not a construction trade) | {stats['rows_unmapped']} |")
    add(f"| Rows with ambiguous multi-trade category | {stats['rows_multi_label']} |")
    add(f"| Train rows (80%, model fit) | {ctx['n_train']} |")
    add(f"| Holdout rows (20%, scored) | {honest['n']} |")
    add(f"| Unique titles in train / holdout | {ctx['n_train_groups']} / {ctx['n_test_groups']} |")
    add("")
    if stats["multi_label_categories"]:
        add("Ambiguous categories (a title legitimately belongs to more than one trade, "
            "e.g. floor covering appears under both `tiling` and `flooring`). A prediction "
            "is counted correct when it equals any of the expected trades; the confusion "
            "matrix uses the first trade in canonical order:")
        add("")
        for cat in stats["multi_label_categories"]:
            trades = [t for t in CANONICAL
                      if cat in CATEGORY_MAP.get(t, [])]
            add(f"- `{cat}` → {' / '.join(trades)}")
        add("")

    add("## 2. Headline accuracy")
    add("")
    add("| Metric | Honest holdout (model retrained on 80%) | Shipped model `data/trade_matcher.joblib` (trained on 100%) |")
    add("| --- | --- | --- |")
    add(f"| Top-1 accuracy (prediction ∈ expected trades) | **{fmt_pct(honest['accuracy'])}** | {fmt_pct(prod['accuracy'])} |")
    add(f"| Exact trade-set match | {fmt_pct(honest['exact_set_accuracy'])} | {fmt_pct(prod['exact_set_accuracy'])} |")
    add(f"| Macro recall over 16 trades | {fmt_pct(honest['macro_recall'])} | {fmt_pct(prod['macro_recall'])} |")
    add(f"| Macro strict recall (primary label) | {fmt_pct(honest['macro_strict_recall'])} | {fmt_pct(prod['macro_strict_recall'])} |")
    add(f"| No trade identified (skip) | {honest['skipped']} ({fmt_pct(honest['skip_rate'])}) | "
        f"{prod['skipped']} ({fmt_pct(prod['skip_rate'])}) |")
    add("")
    gap = prod["accuracy"] - honest["accuracy"]
    add(f"The shipped model was fitted on the full dataset, so it has already seen every "
        f"holdout title. It scores {fmt_pct(prod['accuracy'])} versus "
        f"{fmt_pct(honest['accuracy'])} for the leak-free model — a "
        f"{gap * 100:+.1f} pp optimism that quantifies how much of the previously reported "
        f"accuracy came from memorising the training titles rather than generalising.")
    add("")

    add("## 3. Per-trade recall (dev split)")
    add("")
    add("`Recall` credits a row when the decision is correct for that trade, i.e. the predicted "
        "trade is a member of the expected set; ambiguous categories therefore give credit to "
        "every trade they can legitimately map to. `Strict recall` only credits the primary "
        "label, so it drops for trades that are usually the secondary side of an ambiguity "
        "(e.g. `flooring`, `insulation`).")
    add("")
    add("| Trade | Support (rows where trade is expected) | Recall | Primary support | Strict recall |")
    add("| --- | ---: | ---: | ---: | ---: |")
    for trade in CANONICAL:
        m = honest["per_trade"][trade]
        add(f"| {trade} | {m['support']} | {fmt_pct(m['recall'])} | "
            f"{m['strict_support']} | {fmt_pct(m['strict_recall'])} |")
    add("")
    zero = [t for t, m in honest["per_trade"].items() if m["recall"] == 0.0]
    if zero:
        add(f"Trades with **zero** recall on the holdout: {', '.join(f'`{t}`' for t in zero)}.")
        add("")

    add("## 4. Decision source breakdown (dev split)")
    add("")
    add("| Source | Rows | Correct | Accuracy |")
    add("| --- | ---: | ---: | ---: |")
    for src, agg in sorted(honest["by_source"].items(), key=lambda kv: -kv[1]["n"]):
        acc = agg["correct"] / agg["n"] if agg["n"] else 0.0
        add(f"| {src} | {agg['n']} | {agg['correct']} | {fmt_pct(acc)} |")
    add("")

    add("## 5. Confusion matrix (dev split)")
    add("")
    labels, cols, matrix = ctx["confusion"]
    add("Rows = expected trade (primary label), columns = predicted trade, `skip` = no trade "
        "identified. Diagonal cells are correct. Off-diagonal cells are not automatically wrong: "
        "when a category maps to several trades (e.g. floor covering → tiling / flooring), the "
        "prediction still counts as correct if it matches any expected trade.")
    add("")
    header = "| expected \\ predicted | " + " | ".join(cols) + " |"
    add(header)
    add("| --- | " + " | ".join("---:" for _ in cols) + " |")
    for row in labels:
        cells = []
        for col in cols:
            value = matrix[row][col]
            if row == col and value:
                cells.append(f"**{value}**")
            else:
                cells.append(str(value) if value else "·")
        add(f"| **{row}** | " + " | ".join(cells) + " |")
    add("")

    add("## 6. Top failure cases (dev split)")
    add("")
    add("`confidence` is the raw pipeline confidence; for semantic decisions it can exceed 1.0 "
        "because the score formula adds a seed-hit bonus on top of the normalised cosine "
        "similarity. `Top semantic scores` are the highest-scoring trades of the semantic layer.")
    add("")
    fails = ctx["failures"]
    if not fails:
        add("No failures on the holdout.")
        add("")
    else:
        add("| # | Task text (as cleaned) | Expected | Predicted | Source | Confidence | Top semantic scores |")
        add("| ---: | --- | --- | --- | --- | ---: | --- |")
        for i, f in enumerate(fails, 1):
            predicted = ", ".join(f["predicted"]) if f["predicted"] else "skip"
            scores = ", ".join(f"{k}={v}" for k, v in f["raw_scores"].items()) or "-"
            text = f["text"].replace("|", "/")
            add(f"| {i} | {text} | {', '.join(f['expected'])} | {predicted} | "
                f"{f['source']} | {f['confidence']:.2f} | {scores} |")
        add("")
        skipped = [f for f in fails if not f["predicted"]]
        if skipped:
            add(f"{len(skipped)} of the shown cases were **skipped**: no keyword hit and the "
                f"semantic layer had no decisive winner (either no trade reached 0.5, or the best "
                f"trade beat the runner-up by less than the 0.15 gap required by the semantic "
                f"supplement). With only 80% of the titles in training, their wording is out of "
                f"vocabulary, which is exactly the generalisation gap this evaluation measures.")
            add("")

    add("## 7. Production model status")
    add("")
    prod_info = ctx["prod_status"]
    add(f"- Full-data retrain reproduces the shipped artefact: "
        f"**{'yes' if prod_info['identical'] else 'no'}**")
    add(f"- Vocabulary size: shipped {prod_info['shipped_vocab']}, full retrain {prod_info['fresh_vocab']}")
    add(f"- Per-trade profile title counts: shipped "
        f"{prod_info['shipped_title_total']}, full retrain {prod_info['fresh_title_total']}")
    add(f"- Prediction agreement on the holdout between shipped and full-retrain model: "
        f"{fmt_pct(prod_info['agreement'])}")
    add(f"- Action taken: {prod_info['action']}")
    add("")
    if prod_info["differences"]:
        add("| Trade | Shipped titles | Full-retrain titles |")
        add("| --- | ---: | ---: |")
        for trade, (old, new) in prod_info["differences"].items():
            add(f"| {trade} | {old} | {new} |")
        add("")
    else:
        add("No per-trade profile differences against the shipped artefact: the shipped model was "
            "already trained on the full dataset with the current `CATEGORY_MAP` and seed keywords, "
            "so the holdout experiment does not require a production refresh.")
        add("")

    add("## 8. How to read these numbers")
    add("")
    add("- **This split is the dev / tuning set.** The keyword tables in `app/ai_service.py` were "
        "revised against its failures, so the accuracy above is an upper bound fitted to these rows - "
        "do not quote it as the model's generalisation. Use `reports/trade_matcher_tuning.md` "
        "(fresh test split, seed 2026) for that.")
    add("- The gap is not purely \"the model is weak\": the 80% model also has a smaller TF-IDF "
        "vocabulary (some holdout words never appear in the 80% titles), which is a realistic "
        "stand-in for new site wording the production model has not seen.")
    add("- Holdout per-trade support is small (1–17 rows per trade), so a single miss moves a "
        "recall figure by tens of percentage points. Treat per-trade recall as directional and "
        "rerun with `--seed` variations before drawing per-trade conclusions.")
    add("- The test labels are O*NET occupation titles, not free-text site task descriptions; "
        "real tasks are usually longer and more descriptive, which the keyword layer handles "
        "better than a bare two-word title.")
    add("- LLM fallback was disabled on purpose: these numbers describe the deterministic "
        "rule + semantic layers. Production additionally benefits from the Gemini fallback, so "
        "the live skip rate should be lower than the one reported here.")
    add("")

    add("## 9. How to reproduce")
    add("")
    add("```bash")
    add("cd construction_management_system_Backend")
    add(f"python scripts/eval_holdout.py --seed {ctx['seed']} --test-size {ctx['test_size']}")
    add("```")
    add("")
    add(f"Per-row predictions for this run are in `{ctx['predictions_name']}` "
        "(cleaned text, expected trades, predicted trades, decision source, confidence, scores). "
        f"The filename carries the classifier artefact hash ({ctx['fingerprint']}), so these rows "
        "cannot be confused with a run from a different model.")
    add("")
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--test-size", type=float, default=0.2,
                        help="holdout fraction (default 0.2)")
    parser.add_argument("--seed", type=int, default=42, help="random seed (default 42)")
    parser.add_argument("--report", default="reports/trade_matcher_holdout_eval.md",
                        help="markdown report path (relative to Backend/)")
    parser.add_argument("--predictions", default=None,
                        help="per-row predictions CSV path (relative to Backend/); "
                             "defaults to reports/holdout_predictions_<artefact hash>.csv")
    parser.add_argument("--no-refresh-production-model", action="store_true",
                        help="do not rewrite data/trade_matcher.joblib even if a full "
                             "retrain differs from the shipped artefact")
    args = parser.parse_args()

    labelled, stats = load_labelled_frame()
    if len(labelled) < 50:
        print("Not enough labelled rows to evaluate", file=sys.stderr)
        return 1

    train_df, test_df, all_groups, test_groups = group_split(labelled, args.test_size, args.seed)
    print(f"labelled rows: {len(labelled)} | train: {len(train_df)} | holdout: {len(test_df)}")

    # --- shipped production artefact, loaded before we swap the global -----------------
    shipped_path = DATA / "trade_matcher.joblib"
    shipped = joblib.load(shipped_path)

    # Classifier layer pinned OFF for the whole run. ai_service lazily loads
    # data/trade_classifier.joblib, which is trained on every labelled row - i.e.
    # on the very rows this script holds out. Leaving it loaded meant "shipped
    # model accuracy" was measuring memorisation instead of the matcher swap it
    # was written to measure. Classifier numbers belong to
    # scripts/eval_trade_validation.py, which retrains per split.
    original_classifier = ai._TRADE_CLASSIFIER
    ai._TRADE_CLASSIFIER = False

    # --- leak-free model: trained on the 80% only -------------------------------------
    profiles_train, _, _ = build_profiles(train_df)
    honest_matcher = train_matcher(profiles_train)
    workdir = Path(os.environ.get("TEMP") or "/tmp") / "buildsmart_eval"
    workdir.mkdir(parents=True, exist_ok=True)
    holdout_model_path = workdir / "trade_matcher_holdout80.joblib"
    joblib.dump(honest_matcher, holdout_model_path)
    print(f"holdout model (80% only): {holdout_model_path}")

    # --- score with the production pipeline, LLM disabled -----------------------------
    original_matcher = ai._TRADE_MATCHER
    try:
        ai._TRADE_MATCHER = honest_matcher
        honest_preds = predict_rows(test_df)
        ai._TRADE_MATCHER = shipped
        prod_preds = predict_rows(test_df)
    finally:
        ai._TRADE_MATCHER = original_matcher

    honest_metrics = metrics(honest_preds)
    prod_metrics = metrics(prod_preds)

    # --- full-data retrain vs shipped artefact ---------------------------------------
    profiles_full, _, _ = build_profiles(labelled)
    full_matcher = train_matcher(profiles_full)
    shipped_profiles_path = DATA / "trade_profiles.json"
    shipped_profiles = {}
    if shipped_profiles_path.exists():
        shipped_profiles = json.loads(shipped_profiles_path.read_text(encoding="utf-8"))

    differences = {
        trade: (len(shipped_profiles.get(trade, [])), len(profiles_full[trade]))
        for trade in CANONICAL
        if len(shipped_profiles.get(trade, [])) != len(profiles_full[trade])
    }
    shipped_vocab = len(shipped["vectorizer"].vocabulary_)
    fresh_vocab = len(full_matcher["vectorizer"].vocabulary_)

    ai._TRADE_MATCHER = full_matcher
    try:
        full_preds = predict_rows(test_df)
    finally:
        ai._TRADE_MATCHER = original_matcher
        ai._TRADE_CLASSIFIER = original_classifier
    agree = sum(
        1 for a, b in zip(prod_preds, full_preds)
        if a["predicted"] == b["predicted"]
    ) / len(full_preds) if full_preds else 0.0

    identical = (
        shipped_vocab == fresh_vocab
        and not differences
        and agree == 1.0
        and shipped["trade_vectors"].shape == full_matcher["trade_vectors"].shape
        and (shipped["trade_vectors"] != full_matcher["trade_vectors"]).nnz == 0
    )

    if identical:
        action = "no refresh needed — shipped artefact already equals a full-data retrain"
    elif args.no_refresh_production_model:
        action = ("skipped (--no-refresh-production-model); shipped artefact left untouched "
                  "even though a full retrain differs")
    else:
        joblib.dump(full_matcher, shipped_path)
        shipped_profiles_path.write_text(
            json.dumps(profiles_full, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        action = ("shipped artefact rewritten from a full-data retrain "
                  "(`data/trade_matcher.joblib` + `data/trade_profiles.json`)")
        print("production model refreshed:", shipped_path)

    prod_status = {
        "identical": identical,
        "shipped_vocab": shipped_vocab,
        "fresh_vocab": fresh_vocab,
        "shipped_title_total": sum(len(v) for v in shipped_profiles.values()),
        "fresh_title_total": sum(len(v) for v in profiles_full.values()),
        "agreement": agree,
        "action": action,
        "differences": differences,
    }

    conf = confusion(honest_preds)
    ctx = {
        "generated_at": datetime.now().strftime("%Y-%m-%d %H:%M"),
        "seed": args.seed,
        "test_size": args.test_size,
        "stats": stats,
        "n_train": len(train_df),
        "n_test_groups": len(test_groups),
        "n_train_groups": len(all_groups) - len(test_groups),
        "honest_metrics": honest_metrics,
        "prod_metrics": prod_metrics,
        "honest_preds": honest_preds,
        "confusion": conf,
        "failures": failures(honest_preds),
        "prod_status": prod_status,
        "predictions_name": args.predictions,
        "fingerprint": artifact_fingerprint()["short"],
    }

    if args.predictions is None:
        args.predictions = f"reports/{predictions_path('holdout_predictions').name}"

    report_path = BACKEND / args.report
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(render_report(ctx), encoding="utf-8")

    csv_path = BACKEND / args.predictions
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow([
            "text", "category", "expected", "predicted", "expected_primary",
            "predicted_primary", "correct_top1", "source", "confidence",
            "scores",
        ])
        for p in honest_preds:
            writer.writerow([
                p["text"], p["category"], "|".join(p["expected"]),
                "|".join(p["predicted"]), p["expected_primary"],
                p["predicted_primary"] or "skip", p["correct_top1"], p["source"],
                f"{p['confidence']:.4f}",
                json.dumps(p["scores"], ensure_ascii=False),
            ])

    print(f"dev-split accuracy (tuned on): {honest_metrics['accuracy'] * 100:.1f}% "
          f"(n={honest_metrics['n']}, skipped={honest_metrics['skipped']})")
    print(f"shipped model accuracy:  {prod_metrics['accuracy'] * 100:.1f}%")
    print(f"report: {report_path}")
    print(f"predictions: {csv_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
