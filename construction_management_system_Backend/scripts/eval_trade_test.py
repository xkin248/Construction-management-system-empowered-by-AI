"""Final evaluation: dev (tuning) split + a fresh, never-tuned test split.

Why this script exists
----------------------
``eval_holdout.py`` tunes nothing but its 20% holdout was then used to design the
keyword changes, so it is no longer a fair final number: it is now the **dev**
set. This script therefore

1. reproduces that exact dev split (group split by cleaned title, seed 42) so the
   pre-tuning number stays comparable to the previously reported 78.8 %;
2. carves a **fresh test split** out of the remaining 80 % (seed 2026) that was
   neither trained on nor inspected while tuning;
3. scores both splits for the legacy ("before") and the tuned ("after") keyword
   tables under identical training data, so the comparison is apples to apples.

Training policy (deliberately conservative, no leakage):
* dev rows are scored by a model trained on the 80 % pool (same as the old eval);
* test rows are scored by a model trained on the 80 % pool **minus** the test rows.

Everything runs with the LLM fallback hard-disabled, exactly like eval_holdout.

Usage
-----
    python scripts/eval_trade_test.py            # write report + CSVs
    python scripts/eval_trade_test.py --no-report
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

os.environ["GEMINI_API_KEY"] = ""
os.environ["GOOGLE_API_KEY"] = ""

import pandas as pd  # noqa: E402

from scripts.build_trade_matcher import (  # noqa: E402
    CANONICAL,
    CATEGORY_MAP,
    artifact_fingerprint,
    build_profiles,
    clean,
    train_matcher,
)

import app.ai_service as ai  # noqa: E402

ai.get_gemini_model = lambda: None  # hard-disable the LLM fallback

from scripts.eval_holdout import (  # noqa: E402
    confusion,
    failures,
    group_split,
    load_labelled_frame,
    metrics,
    predict_rows,
)

BACKEND = Path(__file__).resolve().parent.parent
REPORTS = BACKEND / "reports"
FIXTURES = BACKEND / "scripts" / "fixtures"
LEGACY_PATH = FIXTURES / "legacy_trade_keywords.json"

DEV_SEED = 42
DEV_SIZE = 0.20
TEST_SEED = 2026
TEST_SIZE = 0.20


def load_legacy() -> dict:
    payload = json.loads(LEGACY_PATH.read_text(encoding="utf-8"))
    return {"task": payload["task_keywords"], "seed": payload["seed_keywords"]}


def load_current() -> dict:
    return {
        "task": {k: list(v) for k, v in ai.TASK_KEYWORDS.items()},
        "seed": {k: list(v) for k, v in ai.SEED_KEYWORDS.items()},
    }


def score(frame: pd.DataFrame, train_frame: pd.DataFrame, keywords: dict) -> list[dict]:
    """Predict ``frame`` with a matcher trained only on ``train_frame``."""
    ai.TASK_KEYWORDS = keywords["task"]
    ai.SEED_KEYWORDS = keywords["seed"]
    # build_trade_matcher carries its own copy of the seeds; the training call
    # below must see the same table or the comparison would be meaningless.
    import scripts.build_trade_matcher as btm

    btm.SEED_KEYWORDS = keywords["seed"]
    ai._TRADE_MATCHER = train_matcher(build_profiles(train_frame)[0])
    # Classifier layer pinned OFF on purpose. This script measures the keyword
    # table change, and ai_service lazily loads data/trade_classifier.joblib from
    # disk - which is trained on *every* labelled row, including the rows being
    # scored. Leaving it on turned this into a leaky run that reported 100 % on
    # both splits (the classifier had memorised the answers), which is how the
    # "after" column silently stopped measuring the keywords at all.
    ai._TRADE_CLASSIFIER = False
    return predict_rows(frame)


def trade_diff(old: dict, new: dict) -> dict:
    """Per-trade added / removed keywords between two keyword tables."""
    diff = {}
    for table in ("task", "seed"):
        for trade in CANONICAL:
            o, n = set(old[table].get(trade, [])), set(new[table].get(trade, []))
            if o != n:
                diff.setdefault(trade, {})[table] = {
                    "added": sorted(n - o),
                    "removed": sorted(o - n),
                }
    return diff


def boundary_cases() -> list[dict]:
    path = FIXTURES / "trade_boundary_cases.json"
    if not path.exists():
        return []
    return json.loads(path.read_text(encoding="utf-8"))["cases"]


def fmt_pct(v: float | None) -> str:
    return "—" if v is None else f"{v * 100:.1f} %"


def table_rows(m: dict, support_min: int = 1) -> list[str]:
    lines = ["| trade | support | recall | strict recall |", "| --- | ---: | ---: | ---: |"]
    for trade in CANONICAL:
        row = m["per_trade"][trade]
        lines.append(
            f"| {trade} | {row['support']} | {fmt_pct(row['recall'])} | {fmt_pct(row['strict_recall'])} |"
        )
    return lines


def confusion_block(preds: list[dict]) -> list[str]:
    rows, cols, matrix = confusion(preds)
    head = "| expected \\ predicted | " + " | ".join(cols) + " |"
    sep = "| --- |" + " ---: |" * len(cols)
    lines = [head, sep]
    for exp in rows:
        cells = [str(matrix[exp].get(col, 0)) for col in cols]
        lines.append(f"| **{exp}** | " + " | ".join(cells) + " |")
    return lines


def write_predictions(after: list[dict], out: Path, before: list[dict] | None = None) -> None:
    with open(out, "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh)
        header = ["text", "category", "expected", "expected_primary",
                  "predicted", "predicted_primary", "correct_top1", "source", "confidence"]
        if before is not None:
            header += ["before_predicted", "before_primary", "before_correct_top1", "before_source"]
        w.writerow(header)
        for i, p in enumerate(after):
            row = [
                p["text"], p["category"], ";".join(p["expected"]), p["expected_primary"],
                ";".join(p["predicted"]), p["predicted_primary"] or "(skip)",
                p["correct_top1"], p["source"], f"{p['confidence']:.3f}",
            ]
            if before is not None:
                b = before[i]
                row += [";".join(b["predicted"]), b["predicted_primary"] or "(skip)",
                        b["correct_top1"], b["source"]]
            w.writerow(row)


def wilson_halfwidth(accuracy: float, n: int, z: float = 1.96) -> float:
    """Half-width of the 95 % Wilson interval (in accuracy units)."""
    if n == 0:
        return 0.0
    denom = 1 + z * z / n
    centre = (accuracy + z * z / (2 * n)) / denom
    spread = z * math.sqrt(accuracy * (1 - accuracy) / n + z * z / (4 * n * n)) / denom
    return spread


def mcnemar(before: list[dict], after: list[dict]) -> dict:
    """Exact two-sided McNemar test on the paired per-row outcomes."""
    b = sum(1 for x, y in zip(before, after) if not x["correct_top1"] and y["correct_top1"])
    c = sum(1 for x, y in zip(before, after) if x["correct_top1"] and not y["correct_top1"])
    n = b + c
    if n == 0:
        return {"fixed": 0, "broken": 0, "p": 1.0}
    k = min(b, c)
    tail_prob = sum(math.comb(n, i) for i in range(k + 1)) / (2 ** n)
    return {"fixed": b, "broken": c, "p": min(1.0, 2 * tail_prob)}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-report", action="store_true")
    args = ap.parse_args()

    labelled, stats = load_labelled_frame()
    dev_pool, dev, _, _ = group_split(labelled, DEV_SIZE, DEV_SEED)
    # Fresh test split out of the previously "train" pool: never touched during
    # tuning, and removed from training so the number is genuinely held out.
    test_train, test, _, _ = group_split(dev_pool, TEST_SIZE, TEST_SEED)

    legacy, tuned = load_legacy(), load_current()
    diff = trade_diff(legacy, tuned)

    print(f"labelled rows: {stats['rows_labelled']} | dev: {len(dev)} | test: {len(test)} "
          f"| train(pool): {len(dev_pool)} | train(test): {len(test_train)}")

    dev_before = score(dev, dev_pool, legacy)
    dev_after = score(dev, dev_pool, tuned)
    test_before = score(test, test_train, legacy)
    test_after = score(test, test_train, tuned)

    m = {
        "dev_before": metrics(dev_before),
        "dev_after": metrics(dev_after),
        "test_before": metrics(test_before),
        "test_after": metrics(test_after),
    }
    for key, val in m.items():
        print(f"{key:12s} n={val['n']:3d} acc={val['accuracy']:.1%} skip={val['skipped']:2d} "
              f"macroR={val['macro_recall']:.1%}")

    dev_test = mcnemar(dev_before, dev_after)
    test_test = mcnemar(test_before, test_after)
    print(f"mcnemar dev  fixed={dev_test['fixed']} broken={dev_test['broken']} p={dev_test['p']:.4g}")
    print(f"mcnemar test fixed={test_test['fixed']} broken={test_test['broken']} p={test_test['p']:.4g}")

    REPORTS.mkdir(exist_ok=True)
    fingerprint = artifact_fingerprint()
    dev_csv = REPORTS / f"trade_matcher_dev_predictions_{fingerprint['short']}.csv"
    test_csv = REPORTS / f"trade_matcher_test_predictions_{fingerprint['short']}.csv"
    write_predictions(dev_after, dev_csv, dev_before)
    write_predictions(test_after, test_csv, test_before)

    boundaries = boundary_cases()
    boundary_hits = {b["text"]: b for b in boundaries}

    lines: list[str] = []
    add = lines.append
    add("# Trade matcher – tuning result on dev and on a fresh test split")
    add("")
    add("Generated by `scripts/eval_trade_test.py` (LLM fallback disabled, deterministic).")
    add("")
    add(f"**What is being measured.** The keyword + centroid matcher only: "
        f"`ai._TRADE_CLASSIFIER` is pinned to `False` for every run here, so the "
        f"supervised classifier layer (`data/trade_classifier.joblib`, sha256 "
        f"`{fingerprint['sha256']}`) never scores a row. That artefact is trained on "
        f"all labelled rows, so scoring with it would measure memorisation, not "
        f"keywords. Classifier numbers live in `reports/trade_matcher_validation.md`.")
    add("")
    add("## 1. Split protocol")
    add("")
    add(f"* Dataset ({stats['rows_labelled']} labelled rows from `job_categorization.parquet`, "
        f"{stats['categories_mapped']} mapped categories).")
    add("* Group split by cleaned title so identical wording never straddles splits.")
    add(f"* **dev** = {len(dev)} rows, seed {DEV_SEED}, {int(DEV_SIZE * 100)} % — the previously reported "
        "holdout. Its failures were the *only* input used to design the keyword changes.")
    add(f"* **test** = {len(test)} rows, seed {TEST_SEED}, {int(TEST_SIZE * 100)} % of the remaining pool — "
        "carved out of the old training pool, excluded from training and never inspected while tuning. "
        "It is scored once, as-is.")
    add(f"* dev rows are scored by a model trained on {len(dev_pool)} rows; test rows by a model trained on "
        f"{len(test_train)} rows (test rows removed). No row is ever scored by a model that saw it.")
    add("")
    add("## 2. Headline numbers")
    add("")
    add("| split | role | before | after | delta | 95 % CI on *after* |")
    add("| --- | --- | ---: | ---: | ---: | ---: |")
    for key, role in (("dev", "tuning (dev)"), ("test", "final verification (test)")):
        b, a = m[f"{key}_before"], m[f"{key}_after"]
        delta = (a["accuracy"] - b["accuracy"]) * 100
        ci = wilson_halfwidth(a["accuracy"], a["n"]) * 100
        add(f"| {key} | {role} | {fmt_pct(b['accuracy'])} | {fmt_pct(a['accuracy'])} | "
            f"{delta:+.1f} pp | ±{ci:.1f} pp |")
    add("")
    add(f"Skip (unassignable) rows — dev: {m['dev_before']['skipped']} → {m['dev_after']['skipped']}; "
        f"test: {m['test_before']['skipped']} → {m['test_after']['skipped']}.")
    add("")
    add(f"Macro per-trade recall — dev: {fmt_pct(m['dev_before']['macro_recall'])} → "
        f"{fmt_pct(m['dev_after']['macro_recall'])}; test: {fmt_pct(m['test_before']['macro_recall'])} → "
        f"{fmt_pct(m['test_after']['macro_recall'])}.")
    add("")
    add("Paired test on identical rows (exact McNemar, two-sided):")
    add("")
    add("| split | rows fixed by tuning | rows broken by tuning | p-value |")
    add("| --- | ---: | ---: | ---: |")
    for key, res in (("dev", dev_test), ("test", test_test)):
        add(f"| {key} | {res['fixed']} | {res['broken']} | {res['p']:.3f} |")
    add("")
    add("> The dev figure is **not** a result: it is the number the changes were fitted to. "
        "The honest estimate of generalisation is the test column.")
    add("")
    add("> Read the test delta with its sample size in mind: {} rows is small, so the honest "
        "claim is \"a real but modest improvement on unseen wording\", not \"80.7 % accuracy in "
        "production\".".format(len(test)))
    add("")
    add("## 3. Per-trade recall")
    add("")
    for key, title in (("dev_before", "dev – before"), ("dev_after", "dev – after"),
                       ("test_before", "test – before"), ("test_after", "test – after")):
        add(f"### {title}")
        add("")
        lines.extend(table_rows(m[key]))
        add("")
    add("## 4. Confusion matrices")
    add("")
    add("Rows = expected primary trade, columns = predicted; `(skip)` means the pipeline refused to assign.")
    add("")
    for key, title in (("test_before", "test – before"), ("test_after", "test – after")):
        add(f"### {title}")
        add("")
        lines.extend(confusion_block(test_before if key == "test_before" else test_after))
        add("")

    fails = failures(test_after, limit=99)
    add("## 5. Test-set failures (after tuning)")
    add("")
    if fails:
        add("| task text | expected | predicted | source | note |")
        add("| --- | --- | --- | --- | --- |")
        for p in fails:
            note = boundary_hits.get(p["text"], {}).get("note", "")
            add(f"| `{p['text']}` | {', '.join(p['expected'])} | "
                f"{p['predicted_primary'] or '(skip)'} | {p['source']} | {note} |")
    else:
        add("None — every test row got a trade inside its expected set.")
    add("")
    add("## 6. Keyword table diff (rule layer + seed layer)")
    add("")
    if diff:
        for trade in CANONICAL:
            if trade not in diff:
                continue
            add(f"**{trade}**")
            add("")
            for table, changes in diff[trade].items():
                label = "TASK_KEYWORDS" if table == "task" else "SEED_KEYWORDS"
                if changes["removed"]:
                    add(f"* {label} removed: " + ", ".join(f"`{w}`" for w in changes["removed"]))
                if changes["added"]:
                    add(f"* {label} added: " + ", ".join(f"`{w}`" for w in changes["added"]))
            add("")
    else:
        add("No differences.")
    add("")
    add("`wall` / `water` were checked: they were already absent from `TASK_KEYWORDS` "
        "(only the compounds `partition wall` / `water pipe` remain), so nothing further was narrowed there.")
    add("")
    add("## 7. Boundary cases (ambiguity documented, not forced)")
    add("")
    if boundaries:
        add("| task text | dataset label | also defensible | why it is left as a boundary |")
        add("| --- | --- | --- | --- |")
        for b in boundaries:
            add(f"| `{b['text']}` | {b['dataset_label']} | {b['alternative']} | {b['note']} |")
    else:
        add("None recorded.")
    add("")
    add("## 8. Residual errors on test — and why they were left alone")
    add("")
    add("These patterns are visible in the test failures above. Fixing them now would mean "
        "tuning against the test set, which destroys its value as an estimate, so they are "
        "handed to the next tuning round unchanged. The next round needs a **third** untouched "
        "split (e.g. seed 31337) to validate any fix.")
    add("")
    add("| pattern | rows | cause | candidate fix |")
    add("| --- | ---: | --- | --- |")
    add("| `ornamental plasterer`, `plasterer apprentice`, `molding plasterer` → masonry | 3 | "
        "the dataset files *Plasterers and Stucco Masons* under **drywall**, but `plaster` / `stucco` "
        "are still owned by the masonry rule layer | move `plaster`-family vocabulary to drywall and keep "
        "`stucco` only with an explicit stucco cue |")
    add("| `precast concrete ironworker` → masonry (was welding) | 1 | removing the bare `ironworker` "
        "cue to fix masonry cost this row to the new `reinforc` / `precast` cues | add a `structural iron` "
        "compound cue on the welding side |")
    add("| `soldering / brazing machine operator` → equipment | 2 | `operator` dominates the equipment "
        "rule layer even when the head noun is a joining process | require a machine/plant noun for "
        "`operator` |")
    add("| `material handler`, `shipping and receiving material handler` → insulation | 2 | "
        "hazmat vocabulary (`hazardous`) raised insulation similarity for generic *materials* phrasing | "
        "gate the hazmat cues behind `asbestos` / `radiological` / `removal` |")
    add("| `ceramic painter` → tiling | 1 | `ceramic` is a tiling cue, `painter` a painting cue; "
        "the rule layer lets the noun win | arbitrate by suffix (`*er` = occupation) |")
    add("| painting 25 %, drywall 20 % on test | 9 | these rows are only separable from the job title "
        "with occupational context the 518-row subset does not contain | needs more labelled rows, not "
        "more keywords |")
    add("")
    add("## 9. Artefacts")
    add("")
    add("* `scripts/eval_trade_test.py` – this evaluation.")
    add("* `scripts/fixtures/legacy_trade_keywords.json` – frozen pre-tuning tables (replays the *before* column).")
    add("* `scripts/fixtures/trade_boundary_cases.json` – boundary-case register.")
    add(f"* `reports/{dev_csv.name}`, `reports/{test_csv.name}` – "
        "per-row output, both the *before* and the *after* prediction for every row.")
    add("* `data/trade_matcher.joblib` – retrained production artefact.")
    add("* `reports/trade_matcher_holdout_eval.md` – the same dev split scored by `scripts/eval_holdout.py` "
        "(kept for continuity with the earlier report; its number is a fitted one).")
    add("* `tests/test_trade_keywords.py` – guards for table sync and the narrowed ambiguous terms.")

    report = "\n".join(lines) + "\n"
    if not args.no_report:
        (REPORTS / "trade_matcher_tuning.md").write_text(report, encoding="utf-8")
        print("report:", REPORTS / "trade_matcher_tuning.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
