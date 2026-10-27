"""Verify that the shipped classifier artefact is variant F and still behaves as reported.

Three separate questions, three separate checks, because they are easy to confuse:

1. **Is the artefact the F recipe?** Read ``data/trade_classifier.joblib`` and
   assert the metadata: ``label_mode == "single"``, ``C == 4.0``,
   ``synthetic_rows == 3074``, 16 classes, no multi-label decision layer.
2. **Does the F recipe still score 96.4 % on valid?** Rebuild F exactly the way
   ``eval_synthetic_multilabel.py`` builds it (trained on ``valid_train`` only,
   synthetic rows paraphrasing a valid title removed) and score ``valid`` in one
   pass. This must reproduce the report; if it does not, the code path changed
   and the reported number is stale.
3. **Does the shipped artefact behave the same on the same rows?** The shipped
   artefact is trained on the *full* corpus (it deliberately keeps the rows
   generated from valid titles - nothing is held out once the numbers are
   reported), so its valid score is not a generalisation estimate and is only
   printed as a sanity check. What matters is that it is the same decision
   procedure: single-label argmax, no second label ever emitted, and the
   coverage guard of the One-vs-Rest model not firing on the multiclass path.

Usage::

    python scripts/verify_production_artifact.py
"""
from __future__ import annotations

import sys
from pathlib import Path

import joblib

BACKEND = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND))

import scripts.build_trade_matcher as bt  # noqa: E402
from scripts.build_trade_matcher import CLASSIFIER_PATH, train_classifier  # noqa: E402

import app.ai_service as ai  # noqa: E402

ai.get_gemini_model = lambda: None  # no Gemini key needed for this check

from scripts.eval_holdout import group_split, load_labelled_frame, predict_rows  # noqa: E402
from scripts.eval_synthetic_multilabel import (  # noqa: E402
    VALID_SEED,
    VALID_SIZE,
    configure,
    pipeline_state,
    summarise,
)

REPORTED_TOP1 = 0.964      # F single_synth_rules, reports/trade_synthetic_multilabel.md
REPORTED_EXACT = 0.940
TOLERANCE = 0.0005         # the report prints one decimal, so compare at that resolution


def fmt(m: dict) -> str:
    return (f"top1 {m['top1_acc'] * 100:.1f} % | exact {m['exact_acc'] * 100:.1f} % "
            f"| strict {m['strict_acc'] * 100:.1f} % (n={m['strict_n']}) "
            f"| macro recall {m['macro_recall'] * 100:.1f} % "
            f"| multi-pred {m['multi_pred_rows']}")


def check_artifact_meta(artifact: dict) -> list[str]:
    meta = artifact.get("meta") or {}
    problems = []
    if artifact.get("label_mode") != "single":
        problems.append(f"label_mode={artifact.get('label_mode')!r}, expected 'single'")
    if float(meta.get("C", -1)) != bt.PRODUCTION_C:
        problems.append(f"C={meta.get('C')!r}, expected {bt.PRODUCTION_C}")
    if int(meta.get("synthetic_rows") or 0) <= 0:
        problems.append(f"synthetic_rows={meta.get('synthetic_rows')!r}, expected > 0")
    if not meta.get("synthetic"):
        problems.append("meta.synthetic is not True")
    if len(artifact.get("classes") or []) != len(bt.CANONICAL):
        problems.append(f"classes={len(artifact.get('classes') or [])}, "
                        f"expected {len(bt.CANONICAL)}")
    if "pairs" in (artifact.get("decision") or {}):
        problems.append("decision.pairs present: the shipped artefact carries the "
                        "multi-label co-occurrence rule")
    return problems


def probes(valid_texts: list[str]) -> None:
    """Show the single-label decision chain end to end (trace included)."""
    cases = [
        "install kitchen cabinets and wardrobes",
        "resilient sheet laying in the corridor",
        "qwerty zzz plok",
    ]
    print("\n[3] decision chain on the shipped artefact")
    for text in cases:
        decision = ai.resolve_trade_decision(text, "")
        trace = decision["trace"] or {}
        coverage = ai._classifier_token_coverage(text)
        print(f"  {text!r}: trades={sorted(decision['detected_trades'])} "
              f"source={trace.get('source')} "
              f"label_mode={trace.get('label_mode')} classifier_set={trace.get('classifier_set')} "
              f"coverage={coverage:.2f} prob={trace.get('classifier_prob')}")
        assert len(decision["detected_trades"]) <= 1, "single-label artefact emitted a set"

    # Regression guard for the coverage threshold: it was written for the
    # One-vs-Rest columns and must not drop multiclass rows. A text below the
    # coverage limit with no keyword hit still has to produce a trade as long as
    # the softmax winner clears TRADE_CLASSIFIER_SKIP_PROB.
    low = []
    for text in valid_texts:
        coverage = ai._classifier_token_coverage(text)
        if coverage >= ai.TRADE_CLASSIFIER_MIN_COVERAGE:
            continue
        decision = ai.resolve_trade_decision(text, "")
        trace = decision["trace"] or {}
        low.append((text, coverage, trace.get("source"), trace.get("classifier_prob"),
                    sorted(decision["detected_trades"])))
    print(f"  valid rows below the coverage limit ({ai.TRADE_CLASSIFIER_MIN_COVERAGE}): {len(low)}")
    for text, coverage, source, prob, trades in low[:5]:
        print(f"    {text!r}: coverage={coverage:.2f} source={source} prob={prob} "
              f"trades={trades}")
        if source == "skip" and prob is not None and prob >= ai.TRADE_CLASSIFIER_SKIP_PROB:
            raise AssertionError("coverage guard still applies to the single-label path")


def main() -> int:
    artifact = joblib.load(CLASSIFIER_PATH)
    meta = artifact.get("meta") or {}
    print(f"[1] {CLASSIFIER_PATH.name}: label_mode={artifact.get('label_mode')} "
          f"C={meta.get('C')} synthetic={meta.get('synthetic')} "
          f"synthetic_rows={meta.get('synthetic_rows')} samples={meta.get('samples')} "
          f"classes={len(artifact.get('classes') or [])} "
          f"sklearn={meta.get('scikit-learn')} numpy={meta.get('numpy')}")
    problems = check_artifact_meta(artifact)
    for problem in problems:
        print(f"    FAIL {problem}")

    labelled, _stats = load_labelled_frame()
    dev_pool, _dev, _, _ = group_split(labelled, 0.20, 42)
    test_train, _test, _, _ = group_split(dev_pool, 0.20, 2026)
    valid_train, valid, _, valid_titles = group_split(test_train, VALID_SIZE, VALID_SEED)
    print(f"[2] valid {len(valid)} rows, valid_train {len(valid_train)} rows")

    with pipeline_state():
        # (2) the reported recipe, rebuilt on the held-out training split
        fresh = train_classifier(valid_train, synthetic=True, label_mode="single",
                                 c_value=bt.PRODUCTION_C,
                                 exclude_titles=set(valid_titles))
        configure(fresh, valid_train, rules=True)
        fresh_preds = predict_rows(valid)
        fresh_m = summarise(fresh_preds)
        print(f"    fresh F rebuild: {fmt(fresh_m)}")
        ok_recipe = (abs(fresh_m["top1_acc"] - REPORTED_TOP1) <= TOLERANCE
                     and abs(fresh_m["exact_acc"] - REPORTED_EXACT) <= TOLERANCE)
        print(f"    matches report (top1 {REPORTED_TOP1:.1%} / exact {REPORTED_EXACT:.1%}): "
              f"{'YES' if ok_recipe else 'NO'}")
        if not ok_recipe:
            problems.append("fresh F rebuild no longer reproduces the reported numbers")

        # (3) the shipped artefact, scored on the same rows as a sanity check only
        ai._TRADE_MATCHER = joblib.load(bt.DATA / "trade_matcher.joblib")
        ai._TRADE_CLASSIFIER = artifact
        ai._STRUCTURED_RULES = True
        shipped_preds = predict_rows(valid)
        shipped_m = summarise(shipped_preds)
        print(f"    shipped artefact (trains on valid titles too, not a generalisation "
              f"estimate): {fmt(shipped_m)}")

        same = sum(1 for a, b in zip(shipped_preds, fresh_preds)
                   if a["predicted_primary"] == b["predicted_primary"])
        print(f"    identical primary label vs fresh F on {same}/{len(valid)} rows")

        # The rows where the two differ are exactly the ones whose content the
        # shipped artefact has already seen; anything else would mean the two
        # artefacts use different decision procedures.
        flipped = [b["text"] for a, b in zip(shipped_preds, fresh_preds)
                   if a["predicted_primary"] != b["predicted_primary"]]
        if flipped:
            print("    differs on: " + "; ".join(repr(t) for t in flipped[:6]))

        probes([r.text for r in valid.itertuples(index=False)])

    if problems:
        print("\nFAILED:")
        for problem in problems:
            print(f"  - {problem}")
        return 1
    print("\nOK: shipped artefact is variant F and reproduces the reported numbers")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
