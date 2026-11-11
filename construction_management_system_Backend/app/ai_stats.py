"""Read-only aggregates over ``ai_decision_log``.

This module is the *consumer* side of the AI decision log. ``ai_service`` writes
one row per decision; nothing until now read those rows back, so the models
could not be evaluated on live traffic. Everything here is built from SQL
aggregates (``COUNT`` / ``GROUP BY`` / ``AVG``) - no code path pulls the whole
table into Python.

Terms used below
----------------
``total``
    Every logged decision in the filtered window (including skips).
``decided``
    Rows that produced a trade (``final_trade IS NOT NULL``). Skip rows are
    excluded because they have no prediction to evaluate.
``source``
    Which layer produced the verdict: ``rule`` (keyword/title rules),
    ``classifier`` (supervised model), ``semantic`` (centroid matcher),
    ``llm`` (Gemini fallback), ``explicit`` (user picked the trade) or ``skip``
    (nothing above the threshold).
``adopted``
    An LLM fallback that survived into a trade. ``llm_used`` counts triggers,
    ``final_trade IS NOT NULL`` decides adoption, so a low-confidence Gemini
    verdict that was thrown away is counted as triggered-but-not-adopted.
``was_overridden``
    Back-filled by ``mark_decision_overridden`` when a supervisor hand-edits the
    trade afterwards. Those rows are the (prediction, ground truth) pairs that
    can be fed back into training.
"""
from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy import case, func

from app.models import AIDecisionLog

# Keep in sync with ``ai_service.SKIP_CONFIDENCE_THRESHOLD`` (asserted in tests)
# so "low confidence" means the same thing here as in the pipeline.
DEFAULT_LOW_CONFIDENCE_THRESHOLD = 0.5

# Number of skip reasons / trades returned by default; the CLI raises it.
DEFAULT_TOP_N = 5


def _apply_filters(
    query,
    *,
    project_id: Optional[int] = None,
    start: Optional[datetime] = None,
    end: Optional[datetime] = None,
    stage: Optional[str] = None,
):
    """Apply the shared project / time / stage filter to any aggregate query."""
    if project_id is not None:
        query = query.filter(AIDecisionLog.project_id == project_id)
    if start is not None:
        query = query.filter(AIDecisionLog.created_at >= start)
    if end is not None:
        query = query.filter(AIDecisionLog.created_at <= end)
    if stage:
        query = query.filter(AIDecisionLog.stage == stage)
    return query


def _share(part: int, whole: int) -> Optional[float]:
    """Part-over-whole as a 0..1 float; ``None`` when the denominator is 0."""
    if not whole:
        return None
    return round(float(part) / float(whole), 4)


def _distinct_trade_count(db, **filters) -> int:
    """How many different trades were ever predicted (for the report header)."""
    q = _apply_filters(
        db.query(func.count(func.distinct(AIDecisionLog.final_trade))),
        **filters,
    )
    return int(q.scalar() or 0)


def build_decision_stats(
    db,
    *,
    project_id: Optional[int] = None,
    start: Optional[datetime] = None,
    end: Optional[datetime] = None,
    stage: Optional[str] = None,
    top_n: int = DEFAULT_TOP_N,
    low_confidence_threshold: float = DEFAULT_LOW_CONFIDENCE_THRESHOLD,
) -> Dict[str, Any]:
    """Aggregate the decision log into one JSON-serialisable report payload.

    A missing table (old deployment) or an empty result set still returns the
    full structure with zero counts and ``None`` rates, so clients never have to
    special-case "no data yet".
    """
    top_n = max(1, int(top_n or DEFAULT_TOP_N))
    filters = {"project_id": project_id, "start": start, "end": end, "stage": stage}

    total = int(_apply_filters(db.query(func.count(AIDecisionLog.log_id)), **filters).scalar() or 0)

    decided = int(
        _apply_filters(
            db.query(func.count(AIDecisionLog.log_id)).filter(AIDecisionLog.final_trade.isnot(None)),
            **filters,
        ).scalar()
        or 0
    )

    # ── source distribution ────────────────────────────────────────────────
    source_rows = _apply_filters(
        db.query(AIDecisionLog.source, func.count(AIDecisionLog.log_id)),
        **filters,
    ).group_by(AIDecisionLog.source).all()
    by_source = sorted(
        (
            {
                "source": row[0] or "unknown",
                "count": int(row[1]),
                "share": _share(int(row[1]), total),
            }
            for row in source_rows
        ),
        key=lambda item: (-item["count"], item["source"]),
    )

    # ── final trade distribution (top N) ──────────────────────────────────
    trade_rows = _apply_filters(
        db.query(AIDecisionLog.final_trade, func.count(AIDecisionLog.log_id))
        .filter(AIDecisionLog.final_trade.isnot(None)),
        **filters,
    ).group_by(AIDecisionLog.final_trade).order_by(func.count(AIDecisionLog.log_id).desc()).limit(top_n).all()
    by_final_trade = [
        {
            "final_trade": row[0],
            "count": int(row[1]),
            "share": _share(int(row[1]), decided),
        }
        for row in trade_rows
    ]

    # ── skip reasons (top N) ──────────────────────────────────────────────
    skip_rows = _apply_filters(
        db.query(AIDecisionLog.skip_reason, func.count(AIDecisionLog.log_id))
        .filter(AIDecisionLog.skip_reason.isnot(None)),
        **filters,
    ).group_by(AIDecisionLog.skip_reason).order_by(func.count(AIDecisionLog.log_id).desc()).limit(top_n).all()
    skipped_total = int(
        _apply_filters(
            db.query(func.count(AIDecisionLog.log_id)).filter(AIDecisionLog.skip_reason.isnot(None)),
            **filters,
        ).scalar()
        or 0
    )
    skip_reasons = {
        "total": skipped_total,
        "share": _share(skipped_total, total),
        "top": [
            {
                "reason": row[0],
                "count": int(row[1]),
                "share": _share(int(row[1]), skipped_total),
            }
            for row in skip_rows
        ],
    }

    # ── LLM fallback trigger / adoption ───────────────────────────────────
    llm_triggered, llm_adopted = _apply_filters(
        db.query(
            func.coalesce(
                func.sum(case((AIDecisionLog.llm_used == True, 1), else_=0)),  # noqa: E712
                0,
            ),
            func.coalesce(
                func.sum(
                    case(
                        (
                            (AIDecisionLog.llm_used == True)  # noqa: E712
                            & (AIDecisionLog.final_trade.isnot(None)),
                            1,
                        ),
                        else_=0,
                    )
                ),
                0,
            ),
        ),
        **filters,
    ).one()
    llm_triggered = int(llm_triggered or 0)
    llm_adopted = int(llm_adopted or 0)
    llm = {
        "triggered": llm_triggered,
        "adopted": llm_adopted,
        "discarded": llm_triggered - llm_adopted,
        "trigger_rate": _share(llm_triggered, total),
        "adoption_rate": _share(llm_adopted, llm_triggered),
    }

    # ── human overrides ───────────────────────────────────────────────────
    overridden = int(
        _apply_filters(
            db.query(func.count(AIDecisionLog.log_id)).filter(AIDecisionLog.was_overridden == True),  # noqa: E712
            **filters,
        ).scalar()
        or 0
    )
    overrides = {
        "was_overridden": overridden,
        "override_rate": _share(overridden, decided),
    }

    # ── latency ───────────────────────────────────────────────────────────
    avg_elapsed, min_elapsed, max_elapsed = _apply_filters(
        db.query(
            func.avg(AIDecisionLog.elapsed_ms),
            func.min(AIDecisionLog.elapsed_ms),
            func.max(AIDecisionLog.elapsed_ms),
        ).filter(AIDecisionLog.elapsed_ms.isnot(None)),
        **filters,
    ).one()
    elapsed_ms = {
        "avg": round(float(avg_elapsed), 2) if avg_elapsed is not None else None,
        "min": int(min_elapsed) if min_elapsed is not None else None,
        "max": int(max_elapsed) if max_elapsed is not None else None,
    }

    # ── low-confidence predictions ────────────────────────────────────────
    low_confidence = int(
        _apply_filters(
            db.query(func.count(AIDecisionLog.log_id)).filter(
                AIDecisionLog.final_trade.isnot(None),
                AIDecisionLog.confidence.isnot(None),
                AIDecisionLog.confidence < float(low_confidence_threshold),
            ),
            **filters,
        ).scalar()
        or 0
    )

    first_seen, last_seen = _apply_filters(
        db.query(func.min(AIDecisionLog.created_at), func.max(AIDecisionLog.created_at)),
        **filters,
    ).one()

    return {
        "filters": {
            "project_id": project_id,
            "stage": stage,
            "start": start.isoformat() if start else None,
            "end": end.isoformat() if end else None,
        },
        "total_decisions": total,
        "decided": decided,
        "skip_count": total - decided,
        "distinct_trades": _distinct_trade_count(db, **filters),
        "by_source": by_source,
        "by_final_trade": by_final_trade,
        "skip_reasons": skip_reasons,
        "llm": llm,
        "overrides": overrides,
        "elapsed_ms": elapsed_ms,
        "low_confidence": {
            "threshold": float(low_confidence_threshold),
            "count": low_confidence,
            "share": _share(low_confidence, decided),
        },
        "first_log_at": first_seen.isoformat() if first_seen else None,
        "last_log_at": last_seen.isoformat() if last_seen else None,
    }


def empty_stats(
    *,
    project_id: Optional[int] = None,
    start: Optional[datetime] = None,
    end: Optional[datetime] = None,
    stage: Optional[str] = None,
    low_confidence_threshold: float = DEFAULT_LOW_CONFIDENCE_THRESHOLD,
) -> Dict[str, Any]:
    """The same payload shape with everything zeroed out.

    Used when ``ai_decision_log`` does not exist yet (a deployment that has not
    run the migration) so the dashboard still gets a renderable structure. The
    key set is asserted against ``build_decision_stats`` in the tests.
    """
    return {
        "filters": {
            "project_id": project_id,
            "stage": stage,
            "start": start.isoformat() if start else None,
            "end": end.isoformat() if end else None,
        },
        "total_decisions": 0,
        "decided": 0,
        "skip_count": 0,
        "distinct_trades": 0,
        "by_source": [],
        "by_final_trade": [],
        "skip_reasons": {"total": 0, "share": None, "top": []},
        "llm": {"triggered": 0, "adopted": 0, "discarded": 0,
                "trigger_rate": None, "adoption_rate": None},
        "overrides": {"was_overridden": 0, "override_rate": None},
        "elapsed_ms": {"avg": None, "min": None, "max": None},
        "low_confidence": {
            "threshold": float(low_confidence_threshold),
            "count": 0,
            "share": None,
        },
        "first_log_at": None,
        "last_log_at": None,
    }


def fetch_override_samples(
    db,
    *,
    project_id: Optional[int] = None,
    start: Optional[datetime] = None,
    end: Optional[datetime] = None,
    stage: Optional[str] = None,
    limit: int = 500,
) -> List[Dict[str, Any]]:
    """Hand-edited decisions, newest first - the labelled samples for retraining.

    This is the one function that returns rows instead of counts, so it is
    always bounded by ``limit`` and only selects the columns the export needs.
    """
    filters = {"project_id": project_id, "start": start, "end": end, "stage": stage}
    rows = _apply_filters(
        db.query(
            AIDecisionLog.log_id,
            AIDecisionLog.task_id,
            AIDecisionLog.project_id,
            AIDecisionLog.stage,
            AIDecisionLog.task_text,
            AIDecisionLog.final_trade,
            AIDecisionLog.override_trade,
            AIDecisionLog.source,
            AIDecisionLog.confidence,
            AIDecisionLog.created_at,
        ).filter(AIDecisionLog.was_overridden == True),  # noqa: E712
        **filters,
    ).order_by(AIDecisionLog.log_id.desc()).limit(max(1, int(limit))).all()

    return [
        {
            "log_id": r[0],
            "task_id": r[1],
            "project_id": r[2],
            "stage": r[3],
            "task_text": r[4] or "",
            "predicted_trade": r[5],
            "override_trade": r[6],
            "source": r[7],
            "confidence": r[8],
            "created_at": r[9].isoformat() if r[9] else None,
        }
        for r in rows
    ]
