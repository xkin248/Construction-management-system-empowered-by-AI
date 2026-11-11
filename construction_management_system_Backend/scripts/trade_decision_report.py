"""Markdown report over ``ai_decision_log`` - the quota/quality view of the AI.

Usage (from the backend root, inside the pinned venv)::

    .\\env\\Scripts\\python.exe scripts\\trade_decision_report.py
    .\\env\\Scripts\\python.exe scripts\\trade_decision_report.py --project-id 3 --since 2026-09-01
    .\\env\\Scripts\\python.exe scripts\\trade_decision_report.py --export-overrides

The report answers the questions that decide whether the trade classifier can be
trusted in production:

* how many decisions were logged, and how many actually produced a trade;
* which layer decided (rule / classifier / semantic / LLM / skip);
* what the pipeline refuses to guess, and why;
* whether the Gemini fallback earns its latency (triggers vs. adopted verdicts);
* how often a supervisor overrode the AI - the live error signal, and the rows
  that go back into the training set.

All statistics come from SQL aggregates (:mod:`app.ai_stats`); only the override
sample export reads rows, and it is bounded by ``--override-limit``.
"""
import argparse
import csv
import os
import sys
from datetime import date, datetime, time
from typing import Any, Dict, List, Optional

BACKEND_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if BACKEND_ROOT not in sys.path:
    sys.path.insert(0, BACKEND_ROOT)

from sqlalchemy.exc import SQLAlchemyError  # noqa: E402

from app.ai_stats import (  # noqa: E402
    DEFAULT_LOW_CONFIDENCE_THRESHOLD,
    build_decision_stats,
    empty_stats,
    fetch_override_samples,
)

DEFAULT_REPORT_PATH = os.path.join("reports", "trade_decision_report.md")
DEFAULT_OVERRIDE_CSV = os.path.join("reports", "trade_decision_overrides.csv")


# ── formatting helpers ─────────────────────────────────────────────────────

def _pct(value: Optional[float]) -> str:
    """0.4286 -> '42.86%'; None (no denominator) -> em dash."""
    return "—" if value is None else f"{value * 100:.2f}%"


def _num(value: Optional[float], digits: int = 2) -> str:
    if value is None:
        return "—"
    if digits == 0:
        return str(int(value))
    return f"{value:.{digits}f}"


def _cell(text: Any) -> str:
    """Escape pipes so free-text (task text / skip reason) cannot break a table."""
    return str(text if text is not None else "—").replace("|", "\\|").replace("\n", " ")


def _parse_dt(raw: Optional[str], *, end_of_day: bool = False) -> Optional[datetime]:
    """Accept 'YYYY-MM-DD' or a full ISO timestamp.

    A bare date used as the upper bound covers that whole day, which is what a
    human means by "--until 2026-09-30".
    """
    if not raw:
        return None
    text = raw.strip()
    try:
        if len(text) == 10:
            day = date.fromisoformat(text)
            return datetime.combine(day, time.max if end_of_day else time.min)
        return datetime.fromisoformat(text)
    except ValueError as exc:
        raise SystemExit(f"Invalid date/time value: {raw!r} ({exc})")


# ── report body ────────────────────────────────────────────────────────────

def render_report(
    stats: Dict[str, Any],
    samples: Optional[List[Dict[str, Any]]] = None,
    *,
    generated_at: Optional[datetime] = None,
    override_csv: Optional[str] = None,
) -> str:
    """Render the aggregate payload (plus optional override samples) as Markdown."""
    samples = samples or []
    generated_at = generated_at or datetime.now()
    filters = stats.get("filters") or {}

    lines: List[str] = []
    lines.append("# AI 决策日志统计报表")
    lines.append("")
    lines.append(f"- 生成时间：{generated_at.strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append(f"- 项目过滤：{filters.get('project_id') if filters.get('project_id') is not None else '全部项目'}")
    lines.append(f"- 阶段过滤：{filters.get('stage') or '全部阶段（trade_resolution + auto_assign）'}")
    lines.append(f"- 时间范围：{filters.get('start') or '不限'} ~ {filters.get('end') or '不限'}")
    lines.append(
        f"- 数据窗口：{stats.get('first_log_at') or '—'} ~ {stats.get('last_log_at') or '—'}"
    )
    lines.append("")

    total = int(stats.get("total_decisions") or 0)
    decided = int(stats.get("decided") or 0)
    if total == 0:
        lines.append("> 当前过滤条件下没有任何决策日志（空表或时间范围内无数据）。"
                     "下表结构与字段含义仍然成立，指标以 “—” 表示无分母。")
        lines.append("")

    # 1. overview
    lines.append("## 1. 总览")
    lines.append("")
    lines.append("| 指标 | 数值 |")
    lines.append("| --- | --- |")
    lines.append(f"| 总判定数 | {total} |")
    lines.append(f"| 得出工种的判定数（decided） | {decided} |")
    lines.append(f"| 跳过数（skip） | {stats.get('skip_count', 0)} |")
    lines.append(f"| 判定覆盖率 | {_pct(decided / total if total else None)} |")
    lines.append(f"| 涉及工种数 | {stats.get('distinct_trades', 0)} |")
    lines.append("")

    # 2. source distribution
    lines.append("## 2. 判定来源分布（source）")
    lines.append("")
    by_source = stats.get("by_source") or []
    if by_source:
        lines.append("| source | 含义 | 次数 | 占比 |")
        lines.append("| --- | --- | --- | --- |")
        meanings = {
            "rule": "关键词 / 标题规则命中",
            "classifier": "监督分类器",
            "semantic": "语义相似度仲裁",
            "llm": "Gemini 兜底",
            "explicit": "用户指定工种",
            "skip": "无法判定，跳过",
        }
        for item in by_source:
            lines.append(
                f"| {_cell(item['source'])} | {_cell(meanings.get(item['source'], '—'))} "
                f"| {item['count']} | {_pct(item.get('share'))} |"
            )
    else:
        lines.append("无数据。")
    lines.append("")

    # 3. trade distribution
    lines.append("## 3. 判定工种分布（final_trade，Top N）")
    lines.append("")
    by_trade = stats.get("by_final_trade") or []
    if by_trade:
        lines.append("| 工种 | 次数 | 占已判定比例 |")
        lines.append("| --- | --- | --- |")
        for item in by_trade:
            lines.append(
                f"| {_cell(item['final_trade'])} | {item['count']} | {_pct(item.get('share'))} |"
            )
    else:
        lines.append("无数据。")
    lines.append("")

    # 4. skip reasons
    skip = stats.get("skip_reasons") or {}
    lines.append("## 4. 跳过原因 Top N（skip_reason）")
    lines.append("")
    lines.append(f"跳过总数：{skip.get('total', 0)}（占全部判定 {_pct(skip.get('share'))}）")
    lines.append("")
    top_skips = skip.get("top") or []
    if top_skips:
        lines.append("| 原因 | 次数 | 占跳过比例 |")
        lines.append("| --- | --- | --- |")
        for item in top_skips:
            lines.append(
                f"| {_cell(item['reason'])} | {item['count']} | {_pct(item.get('share'))} |"
            )
    else:
        lines.append("无数据。")
    lines.append("")

    # 5. LLM fallback
    llm = stats.get("llm") or {}
    lines.append("## 5. LLM 兜底效果（Gemini）")
    lines.append("")
    lines.append("| 指标 | 数值 |")
    lines.append("| --- | --- |")
    lines.append(f"| 触发次数（llm_used=true） | {llm.get('triggered', 0)} |")
    lines.append(f"| 实际采纳次数（触发且有最终工种） | {llm.get('adopted', 0)} |")
    lines.append(f"| 触发后丢弃次数（置信度不足） | {llm.get('discarded', 0)} |")
    lines.append(f"| 触发率（占全部判定） | {_pct(llm.get('trigger_rate'))} |")
    lines.append(f"| 采纳率（采纳 / 触发） | {_pct(llm.get('adoption_rate'))} |")
    lines.append("")

    # 6. overrides
    ov = stats.get("overrides") or {}
    lines.append("## 6. 人工改派（was_overridden）")
    lines.append("")
    lines.append("| 指标 | 数值 |")
    lines.append("| --- | --- |")
    lines.append(f"| 被主管改派的判定数 | {ov.get('was_overridden', 0)} |")
    lines.append(f"| 改派率（改派 / 已判定） | {_pct(ov.get('override_rate'))} |")
    lines.append("")

    # 7. latency / confidence
    elapsed = stats.get("elapsed_ms") or {}
    low = stats.get("low_confidence") or {}
    lines.append("## 7. 耗时与低置信占比")
    lines.append("")
    lines.append("| 指标 | 数值 |")
    lines.append("| --- | --- |")
    lines.append(f"| 平均耗时（ms） | {_num(elapsed.get('avg'))} |")
    lines.append(f"| 最小 / 最大耗时（ms） | {elapsed.get('min', '—')} / {elapsed.get('max', '—')} |")
    lines.append(
        f"| 低置信判定数（confidence < {low.get('threshold', DEFAULT_LOW_CONFIDENCE_THRESHOLD)}） "
        f"| {low.get('count', 0)} |"
    )
    lines.append(f"| 低置信占比（/ 已判定） | {_pct(low.get('share'))} |")
    lines.append("")

    # 8. override samples
    lines.append("## 8. 改派样本（标注回流）")
    lines.append("")
    if override_csv:
        lines.append(f"完整样本清单已导出：`{override_csv}`（共 {len(samples)} 条，字段："
                     "log_id, task_id, project_id, stage, task_text, predicted_trade, "
                     "override_trade, source, confidence, created_at）。")
        lines.append("")
    else:
        lines.append("未导出样本清单；加上 `--export-overrides` 可生成 CSV。")
        lines.append("")
    if samples:
        lines.append("| log_id | task_text | AI 判定 | 人工改派 | source | 置信度 |")
        lines.append("| --- | --- | --- | --- | --- | --- |")
        for row in samples[:20]:
            text = _cell((row.get("task_text") or "")[:80])
            lines.append(
                f"| {row.get('log_id')} | {text} | {_cell(row.get('predicted_trade'))} "
                f"| {_cell(row.get('override_trade'))} | {_cell(row.get('source'))} "
                f"| {_num(row.get('confidence'))} |"
            )
        if len(samples) > 20:
            lines.append("")
            lines.append(f"（仅展示最近 20 条，完整 {len(samples)} 条见导出文件。）")
    else:
        lines.append("当前没有改派样本：说明该时间窗内 AI 判定未被人工纠正，"
                     "或改派回填（mark_decision_overridden）尚未被触发。")
    lines.append("")

    # 9. glossary
    lines.append("## 9. 字段含义与报表用途")
    lines.append("")
    lines.append("| 字段 / 指标 | 含义 |")
    lines.append("| --- | --- |")
    lines.append("| total_decisions | 日志中的全部判定数，含跳过；等于每次 AI 决策一行。 |")
    lines.append("| decided | 有最终工种（final_trade 非空）的判定数，是各类比例的分母。 |")
    lines.append("| source | 判定来源：rule（规则）/ classifier（分类器）/ semantic（语义仲裁）"
                 " / llm（Gemini 兜底）/ explicit（人工指定）/ skip（跳过）。 |")
    lines.append("| final_trade | 本次判定最终采用的工种；skip 行为空。 |")
    lines.append("| skip_reason | 判定放弃的原因文本，用于定位规则/模型的盲区。 |")
    lines.append("| llm_used | 是否调用了 Gemini 兜底；与 final_trade 非空叠加即为“采纳”。 |")
    lines.append("| was_overridden / override_trade | 主管事后改派标记与实际改派成的工种，"
                 "构成“预测 vs 真值”标注对。 |")
    lines.append("| elapsed_ms | 单次判定耗时（毫秒）。 |")
    lines.append("| confidence | 判定置信度（0~1），低于阈值视为低置信。 |")
    lines.append("")
    lines.append("**报表用途**：")
    lines.append("")
    lines.append("1. **上线质量监控**：看 source 分布与低置信占比，判断生产流量是否仍依赖兜底或频繁跳过。")
    lines.append("2. **兜底性价比评估**：采纳率过低说明 Gemini 兜底在烧延迟却不产出，应检查提示词或候选集。")
    lines.append("3. **错误率观测**：改派率是线上最真实的人工纠错信号，可替代离线指标做回归监控。")
    lines.append("4. **训练数据回流**：导出的改派样本可直接作为标注数据回灌训练集，"
                 "下一轮重训即覆盖这些盲区。")
    lines.append("5. **性能基线**：平均耗时作为接口 SLA 的参照。")
    lines.append("")
    return "\n".join(lines)


# ── IO ─────────────────────────────────────────────────────────────────────

def export_overrides_csv(samples: List[Dict[str, Any]], path: str) -> str:
    """Write the override samples as CSV (UTF-8 with BOM so Excel opens it cleanly)."""
    directory = os.path.dirname(os.path.abspath(path))
    if directory:
        os.makedirs(directory, exist_ok=True)
    fields = ["log_id", "task_id", "project_id", "stage", "task_text",
              "predicted_trade", "override_trade", "source", "confidence", "created_at"]
    with open(path, "w", encoding="utf-8-sig", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fields)
        writer.writeheader()
        for row in samples:
            writer.writerow({key: row.get(key) for key in fields})
    return path


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Render a Markdown report over ai_decision_log and optionally "
                    "export the human-override samples."
    )
    parser.add_argument("--project-id", type=int, default=None, help="Restrict to one project")
    parser.add_argument("--since", default=None, help="Inclusive start date/time (YYYY-MM-DD or ISO)")
    parser.add_argument("--until", default=None, help="Inclusive end date/time (YYYY-MM-DD covers the whole day)")
    parser.add_argument("--stage", default=None,
                        choices=["trade_resolution", "auto_assign"], help="Restrict to one stage")
    parser.add_argument("--top-n", type=int, default=5, help="Rows in the skip-reason / trade tables")
    parser.add_argument("--low-confidence", type=float, default=DEFAULT_LOW_CONFIDENCE_THRESHOLD,
                        help="Confidence below this counts as low confidence")
    parser.add_argument("--output", default=DEFAULT_REPORT_PATH, help="Markdown output path")
    parser.add_argument("--export-overrides", nargs="?", const=DEFAULT_OVERRIDE_CSV, default=None,
                        help=f"Also export override samples as CSV (default: {DEFAULT_OVERRIDE_CSV})")
    parser.add_argument("--override-limit", type=int, default=500,
                        help="Maximum number of override samples exported")
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    args = build_parser().parse_args(argv)

    start = _parse_dt(args.since)
    end = _parse_dt(args.until, end_of_day=True)
    if start and end and start > end:
        raise SystemExit("--since must be earlier than --until")

    from app.database import SessionLocal  # imported late so --help works without a DB

    db = SessionLocal()
    samples: List[Dict[str, Any]] = []
    try:
        stats = build_decision_stats(
            db,
            project_id=args.project_id,
            start=start,
            end=end,
            stage=args.stage,
            top_n=args.top_n,
            low_confidence_threshold=args.low_confidence,
        )
        if args.export_overrides:
            samples = fetch_override_samples(
                db,
                project_id=args.project_id,
                start=start,
                end=end,
                stage=args.stage,
                limit=args.override_limit,
            )
    except SQLAlchemyError as exc:
        # A deployment that has not migrated yet has no ai_decision_log table.
        # Report the shape with zeros instead of dying mid-cron.
        db.rollback()
        print(f"WARNING: could not read ai_decision_log ({exc.__class__.__name__}); "
              "writing a zeroed report instead.", file=sys.stderr)
        stats = empty_stats(
            project_id=args.project_id,
            start=start,
            end=end,
            stage=args.stage,
            low_confidence_threshold=args.low_confidence,
        )
    finally:
        db.close()

    csv_path = None
    if args.export_overrides:
        csv_path = export_overrides_csv(samples, args.export_overrides)

    report = render_report(stats, samples, override_csv=csv_path)

    out_dir = os.path.dirname(os.path.abspath(args.output))
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as fh:
        fh.write(report)

    print(f"Report written to {args.output}")
    print(f"total_decisions={stats['total_decisions']} decided={stats['decided']} "
          f"overridden={stats['overrides']['was_overridden']} "
          f"llm_triggered={stats['llm']['triggered']} llm_adopted={stats['llm']['adopted']}")
    if csv_path:
        print(f"Override samples exported to {csv_path} ({len(samples)} rows)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
