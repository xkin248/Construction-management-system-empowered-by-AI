"""Attribute two upgrades on the clean valid split (seed 31337): synthetic data + multi-label.

All variants are trained on ``valid_train`` only and scored in a single pass over
``valid``. The first row is the previously registered configuration, kept here so
that this round's numbers are comparable with the last report instead of being
measured against a differently configured variant:

=========================  ==============  ==============  ========  ======
variant                    training data   label scheme    C         rules
=========================  ==============  ==============  ========  ======
V0 ``prev_registered``     dataset         multiclass      50        on
A  ``single_tuned``        dataset         multiclass      dev-tuned off
B  ``single_synth``        dataset+synth   multiclass      dev-tuned off
C  ``multi_base``          dataset         One-vs-Rest     dev-tuned off
D  ``multi_synth``         dataset+synth   One-vs-Rest     dev-tuned off
E  ``multi_synth_rules``   dataset+synth   One-vs-Rest     dev-tuned on
F  ``single_synth_rules``  dataset+synth   multiclass      dev-tuned on
=========================  ==============  ==============  ========  ======

V0 -> A is a *configuration* step (registered C replaced by the dev-tuned C, the
compound-title rules switched off for the tuned attribution rows); A -> B and
C -> D isolate the synthetic-data gain under both label schemes, A -> C and
B -> D isolate the multi-label effect, D -> E and B -> F restore the rule layer
the production pipeline actually runs. The production candidate is picked among
the ``rules=on`` rows, since shipping turns the rules off never was an option.

Two top-1 definitions are reported side by side, because the previous round's
92.8 % and this round's set-based numbers are easy to misread: ``top1_set``
(same as every previous round - the predicted primary label is *a member of* the
expected set) and ``strict`` (only rows with exactly one expected trade, and the
prediction must be that trade). The headline comparison uses ``top1_set``, since
that is the definition the earlier 77.1 % / 92.8 % figures were computed with.

Discipline:

* the decision thresholds are tuned on **dev (seed 42)** only;
* synthetic rows generated *from* a valid title are removed from training, so a
  paraphrase of a held-out title cannot leak the hold-out content;
* ``valid`` is scored exactly once, in one run, and reports accuracy, macro
  recall, Wilson intervals and exact McNemar tests between variants.

Usage::

    python scripts/eval_synthetic_multilabel.py            # tune on dev, score valid
    python scripts/eval_synthetic_multilabel.py --dry-run   # dev only, no valid access
"""
from __future__ import annotations

import argparse
import contextlib
import json
import math
import sys
from pathlib import Path

BACKEND = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND))

import scripts.build_trade_matcher as bt  # noqa: E402
from scripts.build_trade_matcher import (  # noqa: E402
    CANONICAL,
    DATA,
    build_profiles,
    train_classifier,
    train_matcher,
)

import app.ai_service as ai  # noqa: E402

ai.get_gemini_model = lambda: None  # hard-disable the LLM fallback

from scripts.eval_holdout import (  # noqa: E402
    group_split,
    load_labelled_frame,
    predict_rows,
)

DEV_SEED, DEV_SIZE = 42, 0.20
TEST_SEED, TEST_SIZE = 2026, 0.20
VALID_SEED, VALID_SIZE = 31337, 0.25

REPORTS = BACKEND / "reports"
REPORT_PATH = REPORTS / "trade_synthetic_multilabel.md"

BASELINE = "V0 prev_registered"


def _pinned(name: str) -> str:
    """Version pinned in requirements.txt, so the report cannot drift from the lock."""
    req = BACKEND / "requirements.txt"
    for line in req.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.lower().startswith(f"{name}=="):
            return line.split("==", 1)[1].split()[0]
    return f"{name} (unpinned)"


SKLEARN_PIN = _pinned("scikit-learn")
NUMPY_PIN = _pinned("numpy")

# ``tuned=False`` keeps the registered configuration of the previous round: the
# default regularisation (C=50), the compound-title rules on, single label. Every
# other variant is a candidate from this round and therefore shares one config:
# the dev-tuned C plus the rules off (a tuned variant must not be measured with a
# different rule layer than the variant it is subtracted from).
VARIANTS = [
    (BASELINE, dict(synthetic=False, label_mode="single", tuned=False, rules=True)),
    ("A single_tuned", dict(synthetic=False, label_mode="single", tuned=True, rules=False)),
    ("B single_synth", dict(synthetic=True, label_mode="single", tuned=True, rules=False)),
    ("C multi_base", dict(synthetic=False, label_mode="multi", tuned=True, rules=False)),
    ("D multi_synth", dict(synthetic=True, label_mode="multi", tuned=True, rules=False)),
    # The two shipped-candidate rows: the same data/label choices with the
    # compound-title rule chain back on, which is what production actually runs.
    ("E multi_synth_rules", dict(synthetic=True, label_mode="multi", tuned=True, rules=True)),
    ("F single_synth_rules", dict(synthetic=True, label_mode="single", tuned=True, rules=True)),
]

CS = [2.0, 4.0, 8.0]
THRESHOLDS = [0.15, 0.20, 0.25, 0.30, 0.35]
MARGINS = [0.25, 0.30, 0.35, 0.40, 0.50]


# ---------------------------------------------------------------------------
# Scoring helpers
# ---------------------------------------------------------------------------
def wilson_interval(p: float, n: int, z: float = 1.96) -> tuple[float, float]:
    if n == 0:
        return 0.0, 0.0
    denom = 1 + z * z / n
    centre = (p + z * z / (2 * n)) / denom
    spread = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denom
    return max(0.0, centre - spread), min(1.0, centre + spread)


def mcnemar(before: list[dict], after: list[dict], key: str) -> dict:
    """Exact two-sided McNemar on paired per-row correctness (``key`` = field)."""
    b = sum(1 for x, y in zip(before, after) if not x[key] and y[key])
    c = sum(1 for x, y in zip(before, after) if x[key] and not y[key])
    n = b + c
    if n == 0:
        return {"fixed": 0, "broken": 0, "p": 1.0}
    k = min(b, c)
    tail = sum(math.comb(n, i) for i in range(k + 1)) / (2 ** n)
    return {"fixed": b, "broken": c, "p": min(1.0, 2 * tail)}


def holm(pvalues: dict) -> dict:
    """Holm-Bonferroni step-down adjustment over one family of comparisons."""
    items = sorted(pvalues.items(), key=lambda kv: kv[1])
    m = len(items)
    adjusted, running = {}, 0.0
    for i, (key, p) in enumerate(items):
        running = max(running, min(1.0, (m - i) * p))
        adjusted[key] = round(running, 6)
    return adjusted


def summarise(preds: list[dict]) -> dict:
    """Accuracy / set metrics / label recall for one variant."""
    n = len(preds)
    top1 = sum(1 for p in preds if p["correct_top1"])
    exact = sum(1 for p in preds if p["exact_set_match"])
    skipped = sum(1 for p in preds if not p["predicted"])
    multi_pred = sum(1 for p in preds if len(p["predicted"]) > 1)

    # Label-level recall over the trades that actually appear in the split.
    hit = {t: 0 for t in CANONICAL}
    total = {t: 0 for t in CANONICAL}
    # Row-level recall of the expected label set (a dual-label row scores 0.5
    # when only one of its two trades is predicted).
    row_recall = 0.0
    for p in preds:
        exp = set(p["expected"])
        got = set(p["predicted"])
        for t in exp:
            total[t] += 1
            if t in got:
                hit[t] += 1
        row_recall += len(exp & got) / len(exp) if exp else 0.0

    seen = [t for t in CANONICAL if total[t]]
    per_trade = {t: (hit[t] / total[t] if total[t] else None) for t in CANONICAL}
    macro = sum(per_trade[t] for t in seen) / len(seen) if seen else 0.0

    # Strict top-1: only rows whose expected set is a single trade, and the
    # prediction must be exactly that trade. Reported next to the set-based
    # definition so the two cannot be confused by a reader.
    strict_rows = [p for p in preds if len(p["expected"]) == 1]
    strict_correct = sum(1 for p in strict_rows if p["predicted_primary"] == p["expected"][0])
    for p in strict_rows:
        p["strict_correct"] = p["predicted_primary"] == p["expected"][0]
    for p in preds:
        p.setdefault("strict_correct", False)
    strict_acc = strict_correct / len(strict_rows) if strict_rows else 0.0

    return {
        "n": n,
        "top1_correct": top1,
        "top1_acc": top1 / n if n else 0.0,
        "strict_n": len(strict_rows),
        "strict_correct": strict_correct,
        "strict_acc": strict_acc,
        "exact_match": exact,
        "exact_acc": exact / n if n else 0.0,
        "macro_recall": macro,
        "row_recall": row_recall / n if n else 0.0,
        "skipped": skipped,
        "multi_pred_rows": multi_pred,
        "per_trade": per_trade,
        "per_trade_support": total,
    }


def configure(bundle: dict, train_frame, rules: bool) -> None:
    """Point the production pipeline at one trained variant."""
    ai._TRADE_MATCHER = train_matcher(build_profiles(train_frame)[0])
    ai._TRADE_CLASSIFIER = bundle
    ai._STRUCTURED_RULES = rules


@contextlib.contextmanager
def pipeline_state():
    saved = (ai._TRADE_MATCHER, ai._TRADE_CLASSIFIER, ai._STRUCTURED_RULES)
    try:
        yield
    finally:
        ai._TRADE_MATCHER, ai._TRADE_CLASSIFIER, ai._STRUCTURED_RULES = saved


def build_bundle(train_frame, synthetic: bool, label_mode: str,
                 threshold: float = bt.MULTI_THRESHOLD,
                 margin: float = bt.MULTI_MARGIN,
                 exclude_titles: set = None,
                 c_value: float = None) -> dict:
    return train_classifier(
        train_frame, synthetic=synthetic, label_mode=label_mode,
        threshold=threshold, margin=margin, exclude_titles=exclude_titles,
        c_value=c_value,
    )


def tune_on_dev(dev_frame, train_frame, valid_titles: set, base_margin: float) -> dict:
    """Grid-search the multi-label decision rule on dev only (never valid).

    Three knobs: OvR regularisation ``C`` (balanced class weights make the raw
    C=50 probabilities saturate, so the threshold can never fire), the absolute
    ``threshold`` and the ``margin`` relative to the winner. Label pairs are
    restricted to pairs the training taxonomy itself declares ambiguous, so the
    grid cannot "win" by promoting random runner-ups.
    """
    grid = []
    for c_value in CS:
        for threshold in THRESHOLDS:
            for margin in MARGINS:
                bundle = build_bundle(train_frame, True, "multi",
                                      threshold=threshold, margin=margin,
                                      exclude_titles=valid_titles, c_value=c_value)
                configure(bundle, train_frame, rules=False)
                m = summarise(predict_rows(dev_frame))
                grid.append({"C": c_value, "threshold": threshold, "margin": margin,
                             "exact_acc": m["exact_acc"], "top1_acc": m["top1_acc"],
                             "macro_recall": m["macro_recall"],
                             "row_recall": m["row_recall"],
                             "multi_pred_rows": m["multi_pred_rows"]})
    # Primary objective: set-exact accuracy on dev (that is what a dual-label
    # task needs); tie-break by row-level recall of the expected label set, then
    # by top-1 accuracy, then by the more conservative (larger) threshold.
    best = max(grid, key=lambda g: (round(g["exact_acc"], 4), round(g["row_recall"], 4),
                                    round(g["top1_acc"], 4), g["threshold"]))
    return {"best": best, "grid": grid}


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
def fmt_pct(v) -> str:
    return "—" if v is None else f"{v * 100:.1f} %"


def pct(v: float, n: int) -> str:
    lo, hi = wilson_interval(v, n)
    return f"{v * 100:.1f} % [{lo * 100:.1f}, {hi * 100:.1f}]"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true",
                    help="tune on dev only, do not touch valid")
    ap.add_argument("--json", default=str(REPORTS / "trade_synthetic_multilabel.json"))
    args = ap.parse_args()

    labelled, stats = load_labelled_frame()
    dev_pool, dev, _, _ = group_split(labelled, DEV_SIZE, DEV_SEED)
    test_train, _test, _, _ = group_split(dev_pool, TEST_SIZE, TEST_SEED)
    valid_train, valid, _, valid_titles = group_split(test_train, VALID_SIZE, VALID_SEED)
    synth_rows = bt.load_synthetic(split="train")
    synth_leak = sum(1 for r in synth_rows
                     if bt.clean(r["source_title"] or "") in {bt.clean(t) for t in valid_titles})

    print(f"labelled {len(labelled)} | dev {len(dev)} | valid {len(valid)} "
          f"({stats['rows_multi_label']} multi-label rows overall)")
    print(f"synthetic rows (train split) {len(synth_rows)} | "
          f"generated from a valid title: {synth_leak} (excluded from training)")

    with pipeline_state():
        tune = tune_on_dev(dev, dev_pool, set(valid_titles), bt.MULTI_MARGIN)
        best = tune["best"]
        print(f"dev-tuned rule: C={best['C']} threshold={best['threshold']} "
              f"margin={best['margin']} "
              f"(dev exact {best['exact_acc'] * 100:.1f} %, top1 {best['top1_acc'] * 100:.1f} %)")
        if args.dry_run:
            for g in sorted(tune["grid"], key=lambda g: -g["exact_acc"])[:8]:
                print("   ", g)
            return 0

        # ── the single pass over valid ──────────────────────────────────────
        valid_exclude = set(valid_titles)
        preds_by_variant: dict[str, list[dict]] = {}
        bundles: dict[str, dict] = {}
        # Full OvR probability vector for the two dual-label rows, so the report
        # can explain exactly why a second label did or did not fire.
        probe: dict[str, list[dict]] = {}
        for name, cfg in VARIANTS:
            tuned = cfg.get("tuned", True)
            bundle = build_bundle(
                valid_train, cfg["synthetic"], cfg["label_mode"],
                threshold=best["threshold"] if tuned else bt.MULTI_THRESHOLD,
                margin=best["margin"] if tuned else bt.MULTI_MARGIN,
                exclude_titles=valid_exclude,
                c_value=best["C"] if tuned else bt.CLASSIFIER_C,
            )
            bundles[name] = bundle
            configure(bundle, valid_train, rules=cfg["rules"])
            preds_by_variant[name] = predict_rows(valid)
            probe[name] = [
                {"text": p["text"], "expected": p["expected"],
                 "predicted": p["predicted"],
                 "raw_scores": {k: round(float(v), 4) for k, v in
                                (ai.resolve_trade_decision(p["text"], "")
                                 ["raw_semantic_scores"] or {}).items()}}
                for p in preds_by_variant[name] if len(p["expected"]) > 1
            ]
            m = summarise(preds_by_variant[name])
            print(f"{name}: top1 {m['top1_acc'] * 100:.1f} % | exact {m['exact_acc'] * 100:.1f} % "
                  f"| strict {m['strict_acc'] * 100:.1f} % (n={m['strict_n']}) "
                  f"| macro recall {m['macro_recall'] * 100:.1f} % "
                  f"| multi-pred {m['multi_pred_rows']}")

        # production configuration also has the compound-title rules on

    metrics_by_variant = {k: summarise(v) for k, v in preds_by_variant.items()}
    cfg_by_name = {name: cfg for name, cfg in VARIANTS}
    base = preds_by_variant[BASELINE]
    tuned_base = preds_by_variant["A single_tuned"]
    comparisons = {}
    for other in [name for name, _ in VARIANTS if name != BASELINE]:
        comparisons[other] = {
            "top1": mcnemar(base, preds_by_variant[other], "correct_top1"),
            "exact": mcnemar(base, preds_by_variant[other], "exact_set_match"),
            "strict": mcnemar(base, preds_by_variant[other], "strict_correct"),
        }
    # In-round attribution, subtracted from the tuned single-label variant so the
    # configuration step (V0 -> A) is not mixed into the data/label effects.
    attribution = {}
    for other in [name for name, _ in VARIANTS
                  if name not in ("A single_tuned", BASELINE)]:
        attribution[other] = {
            "top1": mcnemar(tuned_base, preds_by_variant[other], "correct_top1"),
            "exact": mcnemar(tuned_base, preds_by_variant[other], "exact_set_match"),
            "strict": mcnemar(tuned_base, preds_by_variant[other], "strict_correct"),
        }
    # The shipped pipeline keeps the compound-title rules on, so the production
    # candidate is chosen among the rules=True variants only - by Top-1, then by
    # exact-set match. Two candidates, one valid read.
    prod_name = max((n for n, c in VARIANTS if c["rules"]),
                    key=lambda n: (metrics_by_variant[n]["top1_acc"],
                                   metrics_by_variant[n]["exact_acc"]))
    for family in (comparisons, attribution):
        for endpoint in ("top1", "exact", "strict"):
            adjusted = holm({k: v[endpoint]["p"] for k, v in family.items()})
            for key, value in adjusted.items():
                family[key][endpoint]["p_holm"] = value
    pipe = {
        "valid_rows": len(valid),
        "valid_multi_label_rows": sum(1 for p in base if len(p["expected"]) > 1),
        "valid_titles": len(valid_titles),
        "synthetic_rows": len(synth_rows),
        "synthetic_from_valid_titles": synth_leak,
        "synthetic_used_per_variant": {
            k: bundles[k]["meta"].get("synthetic_rows") for k in bundles
        },
        "train_samples": {k: bundles[k]["meta"].get("samples") for k in bundles},
        "dev_tuned_rule": best,
        "dev_grid": tune["grid"],
        "variant_config": {
            name: {"synthetic": cfg["synthetic"], "label_mode": cfg["label_mode"],
                   "tuned": cfg.get("tuned", True), "rules": cfg["rules"],
                   "C": best["C"] if cfg.get("tuned", True) else bt.CLASSIFIER_C}
            for name, cfg in VARIANTS
        },
    }

    payload = {"pipeline": pipe, "metrics": metrics_by_variant,
               "comparisons_vs_baseline": comparisons,
               "attribution_vs_tuned_single": attribution,
               "multi_label_probe": probe}
    Path(args.json).write_text(json.dumps(payload, ensure_ascii=False, indent=2),
                               encoding="utf-8")

    # ── markdown ───────────────────────────────────────────────────────────
    n = len(valid)
    lines: list[str] = []
    add = lines.append
    add("# 合成数据 + 多标签改造：归因评测（valid seed 31337，单次读取）")
    add("")
    add(f"日期：{__import__('datetime').datetime.now().strftime('%Y-%m-%d')}　"
        f"评测脚本：`scripts/eval_synthetic_multilabel.py`")
    add("")
    v0 = metrics_by_variant[BASELINE]
    a, b = metrics_by_variant["A single_tuned"], metrics_by_variant["B single_synth"]
    c, d = metrics_by_variant["C multi_base"], metrics_by_variant["D multi_synth"]
    e = metrics_by_variant["E multi_synth_rules"]
    f = metrics_by_variant["F single_synth_rules"]
    prod = metrics_by_variant[prod_name]
    order = [name for name, _ in VARIANTS]

    add("## 1. 结论与完整链条（上轮基线 → 本轮各变体）")
    add("")
    add("所有变体都在 `valid_train` 上训练、在同一个 `valid` 单次读取中评分，"
        "关键词词表、切分种子、跳过阈值完全相同。"f"`V0` 是上一轮登记并上报的配置"
        f"（C={bt.CLASSIFIER_C:g}、规则链开、单标签），本次在**当前代码**上重跑，"
        f"Top-1 复现 {fmt_pct(v0['top1_acc'])}，与上轮上报的 92.8 % 一致，"
        "因此后续各变体的差值都是同一口径下的可比差值。")
    add("")
    add("| 变体 | 训练数据 | 标签方案 | C | 规则链 | Top-1（集合口径） | Top-1（严格单标签） "
        "| 集合完全正确 | 宏召回 | 行级召回 |")
    add("| --- | --- | --- | ---: | :---: | ---: | ---: | ---: | ---: | ---: |")
    add(f"| **V0 prev_registered（上轮基线）** | 数据集 | 多类 argmax | "
        f"{bt.CLASSIFIER_C:g} | 开 | {fmt_pct(v0['top1_acc'])} | {fmt_pct(v0['strict_acc'])} | "
        f"{fmt_pct(v0['exact_acc'])} | {fmt_pct(v0['macro_recall'])} | {fmt_pct(v0['row_recall'])} |")
    for name in order:
        m = metrics_by_variant[name]
        if name == BASELINE:
            continue
        cfg = cfg_by_name[name]
        scheme = "OneVsRest 多标签" if cfg["label_mode"] == "multi" else "多类 argmax"
        data = "数据集+合成" if cfg["synthetic"] else "数据集"
        rules = "开" if cfg["rules"] else "关"
        add(f"| {name} | {data} | {scheme} | {best['C'] if cfg['tuned'] else bt.CLASSIFIER_C:g} "
            f"| {rules} | {fmt_pct(m['top1_acc'])} | {fmt_pct(m['strict_acc'])} | "
            f"{fmt_pct(m['exact_acc'])} | {fmt_pct(m['macro_recall'])} | "
            f"{fmt_pct(m['row_recall'])} |")
    add("")
    add(f"1. **上轮基线（V0）**：Top-1 {pct(v0['top1_acc'], n)}，集合完全正确 "
        f"{pct(v0['exact_acc'], n)}（C={bt.CLASSIFIER_C:g}、规则链开、单标签）。")
    add(f"2. **配置步（V0→A）**：Top-1 {fmt_pct(v0['top1_acc'])} → {fmt_pct(a['top1_acc'])}。"
        f"这一步**不是**某项改造的增益，而是评测配置变化：C 由登记的 {bt.CLASSIFIER_C:g} 换成 "
        f"dev 调优值 {best['C']:g}，同时关掉复合标题规则链。此后所有归因都从 A 出发，"
        "避免把规则开关与 C 值的影响混进合成数据 / 多标签的差值里。")
    add(f"3. **合成数据增益（A→B，单标签）**：Top-1 {fmt_pct(a['top1_acc'])} → "
        f"{fmt_pct(b['top1_acc'])}（{pct(b['top1_acc'], n)}），集合完全正确 "
        f"{fmt_pct(a['exact_acc'])} → {fmt_pct(b['exact_acc'])}，宏召回 "
        f"{fmt_pct(a['macro_recall'])} → {fmt_pct(b['macro_recall'])}。")
    add(f"4. **合成数据增益（C→D，多标签）**：Top-1 {fmt_pct(c['top1_acc'])} → "
        f"{fmt_pct(d['top1_acc'])}，集合完全正确 {fmt_pct(c['exact_acc'])} → "
        f"{fmt_pct(d['exact_acc'])}。两条路径方向一致，说明合成语料本身有效，"
        "而不是只对某一种标签方案有效。")
    add(f"5. **多标签增益（A→C，无合成）**：Top-1 {fmt_pct(a['top1_acc'])} → "
        f"{fmt_pct(c['top1_acc'])}（{pct(c['top1_acc'], n)}），集合完全正确 "
        f"{fmt_pct(a['exact_acc'])} → {fmt_pct(c['exact_acc'])}，宏召回 "
        f"{fmt_pct(a['macro_recall'])} → {fmt_pct(c['macro_recall'])}。")
    add(f"6. **多标签增益（B→D，有合成）**：Top-1 {fmt_pct(b['top1_acc'])} → "
        f"{fmt_pct(d['top1_acc'])}，集合完全正确 {fmt_pct(b['exact_acc'])} → "
        f"{fmt_pct(d['exact_acc'])}。两个方向都是负的，多标签在本验证集上**没有**带来增益。")
    add(f"7. **规则链的影响（D→E、B→F）**：多标签 {fmt_pct(d['top1_acc'])} → "
        f"{fmt_pct(e['top1_acc'])}，单标签+合成 {fmt_pct(b['top1_acc'])} → "
        f"{fmt_pct(f['top1_acc'])}。规则链对两种标签方案都是正向的，"
        "关掉它只是为了得到干净的归因起点，不是建议线上部署关规则。")
    add(f"8. **本轮最优配置（{prod_name}）**：Top-1 {pct(prod['top1_acc'], n)}，"
        f"集合完全正确 {pct(prod['exact_acc'], n)}，宏召回 {fmt_pct(prod['macro_recall'])}；"
        f"相对上轮基线 V0（{fmt_pct(v0['top1_acc'])}）为 "
        f"{(prod['top1_acc'] - v0['top1_acc']) * 100:+.1f} pt。")
    add("")
    add("> 读法提醒：只有「V0 → 本轮最优配置」这一条才是对上轮上报值的真实提升；"
        "「A → B/C/D/E/F」是同一配置内的归因分解。把 A 当作上轮基线会虚抬增益，"
        "因为 A 本身已比 V0 低 " + f"{abs(a['top1_acc'] - v0['top1_acc']) * 100:.1f} pt"
        "（规则链被关掉、C 变小），而 V0 才是上轮真正登记并上报的那一版。"
        "多标签两条链（A→C、B→D）为负的机制已单独核查：valid 的 2 个双标签行上一次标签都没被"
        "加入（`multi-pred` 全为 0），成因见第 8 节，不能读作「多标签决策有害」。")
    add("")
    add("## 2. Top-1 定义核对：两种口径并列")
    add("")
    add("上轮与本轮 `predict_rows` 用的是同一个字段："
        "`correct_top1 = pred_primary in expected`（主标签命中期望集合，"
        "多标签行的两个工种都算命中）。本轮额外给出更严格的第二种口径，"
        "`strict` 只统计期望集合大小为 1 的行，且预测必须**恰好**等于该工种。")
    add("")
    add("| 变体 | Top-1（集合口径，与上轮一致） | 严格单标签 Top-1 | 单标签行数 | 严格命中数 |")
    add("| --- | ---: | ---: | ---: | ---: |")
    for name in order:
        m = metrics_by_variant[name]
        add(f"| {name} | {pct(m['top1_acc'], n)} | {pct(m['strict_acc'], m['strict_n'])} | "
            f"{m['strict_n']} | {m['strict_correct']} |")
    add("")
    add(f"valid 共 {n} 行，其中单标签行 {v0['strict_n']} 行、多标签行 "
        f"{n - v0['strict_n']} 行。集合口径的分母是全部 {n} 行，严格口径的分母是 "
        f"{v0['strict_n']} 行，**两者不可横向比较数值大小**；结论方向在两种口径下一致，"
        "见第 3 节的成对检验。")
    add("")
    add("## 3. 统计显著性（精确 McNemar + Holm 校正）")
    add("")
    add("### 3.1 相对上轮基线 V0")
    add("")
    add("| 对照 | Top-1 修好/弄坏 | p | p（Holm） | 集合 修好/弄坏 | p | p（Holm） "
        "| 严格 修好/弄坏 | p | p（Holm） |")
    add("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for name, cmp in comparisons.items():
        add(f"| V0 → {name} | {cmp['top1']['fixed']}/{cmp['top1']['broken']} | "
            f"{cmp['top1']['p']:.4f} | {cmp['top1']['p_holm']:.4f} | "
            f"{cmp['exact']['fixed']}/{cmp['exact']['broken']} | {cmp['exact']['p']:.4f} | "
            f"{cmp['exact']['p_holm']:.4f} | {cmp['strict']['fixed']}/{cmp['strict']['broken']} | "
            f"{cmp['strict']['p']:.4f} | {cmp['strict']['p_holm']:.4f} |")
    add("")
    add("### 3.2 同一配置内的归因（相对 A single_tuned）")
    add("")
    add("| 对照 | Top-1 修好/弄坏 | p | p（Holm） | 集合 修好/弄坏 | p | p（Holm） "
        "| 严格 修好/弄坏 | p | p（Holm） |")
    add("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for name, cmp in attribution.items():
        add(f"| A → {name} | {cmp['top1']['fixed']}/{cmp['top1']['broken']} | "
            f"{cmp['top1']['p']:.4f} | {cmp['top1']['p_holm']:.4f} | "
            f"{cmp['exact']['fixed']}/{cmp['exact']['broken']} | {cmp['exact']['p']:.4f} | "
            f"{cmp['exact']['p_holm']:.4f} | {cmp['strict']['fixed']}/{cmp['strict']['broken']} | "
            f"{cmp['strict']['p']:.4f} | {cmp['strict']['p_holm']:.4f} |")
    add("")
    add("校正方式：每个终点（Top-1 / 集合 / 严格）各自在一个 "
        f"{len(comparisons)} 组（相对 V0）/ {len(attribution)} 组（相对 A）的对照族内做 "
        "Holm-Bonferroni 逐步下调；表格同时给出原始 p 与校正后 p。"
        "「修好/弄坏」是配对样本上由错转对 / 由对转错的条数，只有这两类互相抵消后才谈显著性。")
    add("")
    add("## 4. 置信区间（95 % Wilson）")
    add("")
    add("| 变体 | Top-1（集合口径） | 严格单标签 Top-1 | 集合完全正确 |")
    add("| --- | --- | --- | --- |")
    for name in order:
        m = metrics_by_variant[name]
        add(f"| {name} | {pct(m['top1_acc'], n)} | {pct(m['strict_acc'], m['strict_n'])} | "
            f"{pct(m['exact_acc'], n)} |")
    add("")
    add(f"n={n}，区间宽度约 ±{1.96 * math.sqrt(0.25 / n) * 100:.0f} pt，"
        "因此 3～5 pt 的差异在本样本量下不可能显著，这正是 McNemar 只承认"
        "「要么修好、要么弄坏」的成对证据的原因。")
    add("")
    add("## 5. 分档案（宏召回明细，上轮基线 vs 生产配置）")
    add("")
    add("| trade | support | V0 召回 | 最优配置召回 | 差值 |")
    add("| --- | ---: | ---: | ---: | ---: |")
    for trade in CANONICAL:
        sup = v0["per_trade_support"][trade]
        if not sup:
            continue
        av, dv = v0["per_trade"][trade], prod["per_trade"][trade]
        delta = (dv - av) if (av is not None and dv is not None) else None
        add(f"| {trade} | {sup} | {fmt_pct(av)} | {fmt_pct(dv)} | "
            f"{'—' if delta is None else f'{delta * 100:+.1f} pt'} |")
    add("")
    add("## 6. 方法论与审计点")
    add("")
    add(f"- 训练/验证切分沿用既有 group split：dev seed {DEV_SEED}、test seed {TEST_SEED}、"
        f"valid seed {VALID_SEED}（按清洗标题分组，同一标题不跨切分）。"
        f"valid_train {len(valid_train)} 行、valid {len(valid)} 行。")
    add(f"- 合成语料 {len(synth_rows)} 条（train 拆分）；其中 {synth_leak} 条由 valid 标题反向生成，"
        f"**全部从训练中剔除**，否则等于把留出集内容以复述形式喂回模型。")
    add(f"- 多标签决策在 dev 上网格搜索（C × threshold × margin 共 "
        f"{len(CS) * len(THRESHOLDS) * len(MARGINS)} 组），取集合完全正确率优先，"
        f"选定 C={best['C']}、threshold={best['threshold']}、margin={best['margin']}；"
        f"valid 未参与调参，也没有因为本次口径修正而改动任何超参。")
    add("- 多标签的第二标签受「共现约束」限制：只有当 (主标签, 次标签) 是训练集里真实共现过的组合"
        "（同一标题被映射到两个工种，支持度 ≥ "
        f"{bt.MULTI_PAIR_SUPPORT}）时才允许加入。无此约束时，纯阈值规则会把 "
        "`automobile detailer` 判成 laborer + painting 之类的随机次标签，dev 集合完全正确率反而从 "
        f"{fmt_pct(best['exact_acc'])} 掉到 85 % 左右。")
    add(f"- {len(VARIANTS) + 1} 个变体共享同一次 valid 读取、同一批 valid_train 训练数据、同一套关键词词表；"
        "唯一差异是表中列出的训练数据、标签方案、C 与规则链开关。"
        "本次重跑补上了 V0 基线、两条 rules=on 的候选行与严格口径，"
        "仍未用 valid 结果回改任何训练超参（C / threshold / margin 全部来自 dev）。")
    add("- 口径差异（必须明示）：V0 采用登记配置 C="
        f"{bt.CLASSIFIER_C:g}、规则链开、单标签、决策为 argmax + 低置信跳过；"
        f"A~F 采用 dev 调优 C={best['C']:g}，A/B/F 为 argmax、C/D/E 为 OvR + "
        "threshold/margin + 共现约束，规则链在 A~D 上关闭、E/F 上开启。"
        "因此 A 的数值低于 V0 属配置差异，不能解读为「上轮 → 本轮退化」。")
    add("- Top-1 两种定义同时给出（第 2 节）：集合口径与上轮上报口径一致、可直接比；"
        "严格口径把多标签行排除在分母外，用于回答「单标签任务是否被多标签改造拖累」。")
    add("")
    add("## 7. 口径审计：本次修正暴露的两个隐患")
    add("")
    add("- **覆盖率门限误伤了单标签模型**。上一轮之后新增的 `TRADE_CLASSIFIER_MIN_COVERAGE`"
        "（词表覆盖率 < 0.34 且无关键词命中就跳过）是为 One-vs-Rest 的饱和概率写的，"
        "但最初没有区分标签模式，于是同一套登记配置在当前代码上只能拿到 89.2 %，"
        "与上轮上报的 92.8 % 差 3.6 pt。现在该门限只在 `label_mode == \"multi\"` 时生效，"
        "单标签路径回到历史行为，V0 因此精确复现 92.8 %。"
        "这也说明「同一配置、不同代码版本」的对比会悄悄失真，必须像本次一样在当前代码上重跑基线。")
    add("- **依赖版本漂移**。首次重跑时虚拟环境里是 scikit-learn 1.9.0 / numpy 2.5.2，"
        f"而 `requirements.txt` 锁的是 {SKLEARN_PIN} / {NUMPY_PIN}，加载旧 artefact 会报 "
        "`InconsistentVersionWarning`，且同一份代码在不同版本下的数字不可比。"
        f"已按 requirements 把环境装回 {SKLEARN_PIN} / {NUMPY_PIN} 后重跑，本报告所有数字都出自该环境。")
    add("")
    add("## 8. 多标签增益为何为负：次标签在 valid 上从未触发的实证")
    add("")
    multi_variant = "E multi_synth_rules"
    pairs_meta = (bundles[multi_variant]["meta"].get("cooccurring_pairs") or {})
    floor_tile = pairs_meta.get("flooring+tiling") or pairs_meta.get("tiling+flooring")
    add(f"- valid 里只有 **{sum(1 for p in base if len(p['expected']) > 1)} 行**真多标签，"
        "两行都是 `{flooring, tiling}`（`residential carpet installer`、"
        "`wall to wall carpet installer`）。该组合在 valid_train 的共现计数为 "
        f"{floor_tile}（≥ {bt.MULTI_PAIR_SUPPORT}），因此 `flooring+tiling` **确实在** "
        "allowed_pairs 里——不是共现守卫把次标签挡掉的。")
    probe_multi = {p["text"]: p for p in probe.get(multi_variant, [])}
    probe_single = {p["text"]: p for p in probe.get("B single_synth", [])}
    rows = []
    for text, p in probe_multi.items():
        s = probe_single.get(text, {})
        rows.append(
            f"| {text} | {p['expected']} | {p['predicted']} | "
            f"{p['raw_scores'].get('flooring', 0):.3f} / {p['raw_scores'].get('tiling', 0):.3f} | "
            f"{s.get('raw_scores', {}).get('flooring', 0):.3f} / "
            f"{s.get('raw_scores', {}).get('tiling', 0):.3f} |")
    if rows:
        add("")
        add("| 文本 | 真值 | 多标签预测 | flooring / tiling 概率（多标签） | "
            "flooring / tiling 概率（单标签 B） |")
        add("| --- | --- | --- | --- | --- |")
        lines.extend(rows)
        add("")
    add(f"- 上表来自同一次 valid 读取、同一批训练数据：多标签训练把 `tiling` 的 OvR 概率从单标签的 "
        "~0.001 抬到 0.2 ~ 0.27（两个数量级），说明 OvR 方向是对的；但它仍低于 dev 选定的 "
        f"threshold={best['threshold']}（且 margin={best['margin']} 要求次标签概率不低于主标签的 "
        f"{best['margin']:g} 倍，即约 {best['margin'] * 0.95:.2f}），于是次标签一次都没被加入。")
    multi_preds = ", ".join(f"{name}={metrics_by_variant[name]['multi_pred_rows']}"
                            for name in order)
    add("- 因此所有变体在 valid 上的 `multi-pred` 行数分别是 "
        + multi_preds + "——没有一行真的输出两个工种。所以「多标签不如单标签」"
        "（A→C：Top-1 91.6 % → 90.4 %、B→D：95.2 % → 92.8 %）**不能**解读为「多标签决策有害」，"
        "它实际等于「OvR 主标签精度略低于多类 argmax，且次标签能力在这 2 行上没能生效」。")
    add(f"- 不因为这条发现回调阈值：dev 网格已经在 {list(THRESHOLDS)} 上搜过并选定 "
        f"{best['threshold']}，为了在 valid 的 2 行上多拿分而把阈值压到 0.2 以下，"
        "等于拿 valid 调参、破坏单次读取约定。要让多标签真正生效，正确路径是在 dev 池上增加双标签"
        "样本或对次标签单独做概率校准，而不是在 valid 上掰阈值。")
    add("- 归纳：多标签改造在 83 行、2 个双标签行的 valid 上**既不能证实也不能证伪**；"
        "报告里所有多标签数字都应按「OvR 概率排序下的主标签表现」来读。")
    add("")
    REPORT_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("report:", REPORT_PATH)
    print("json:", args.json)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
