"""Tests for the AI decision audit log and the ambiguous-trade LLM fallback.

Covers:
* ``ai_decision_log`` rows written by ``analyze_task`` (trade_resolution) and
  ``auto_assign_tasks`` (auto_assign, skipped on dry runs),
* back-filling ``was_overridden`` when a supervisor edits the trade,
* the Gemini fallback in ``_resolve_detected_trades``: confident verdict wins,
  low-confidence verdict skips, and every degradation path (no key, exception,
  unparsable answer) keeps the previous rule/semantic behaviour.
"""
import json

import pytest

from app import ai_service
from app.models import AIDecisionLog, Project, Task, Worker


@pytest.fixture()
def no_gemini(monkeypatch):
    """Force the offline path so no network call leaves the test process."""
    monkeypatch.setattr(ai_service, "get_gemini_model", lambda: None)


@pytest.fixture()
def project(db):
    proj = Project(project_name="Demo Site", location_address="KL", status="active", progress=0)
    db.add(proj)
    db.commit()
    db.refresh(proj)
    return proj


# ── decision log writing ────────────────────────────────────────────────────

def test_analyze_task_writes_trade_resolution_log(db, project, no_gemini, monkeypatch):
    # Force the keyword path: this test asserts the classic rule/log wiring, and the
    # supervised classifier (which now runs first) is covered by test_trade_keywords.py.
    monkeypatch.setattr(ai_service, "_TRADE_CLASSIFIER", False)
    monkeypatch.setattr(ai_service, "_semantic_trade_scores",
                        lambda text: {"electrical": 0.92, "plumbing": 0.11})
    monkeypatch.setattr(ai_service, "_detect_trade_groups", lambda text: {"electrical"})

    result = ai_service.analyze_task(
        db, {"task_name": "Install wiring", "description": "run cables"}, project.project_id
    )
    db.commit()

    assert result["matched_trades"] == ["electrical"]
    row = db.query(AIDecisionLog).one()
    assert row.stage == "trade_resolution"
    assert row.project_id == project.project_id
    assert row.final_trade == "electrical"
    assert row.source == "rule"
    assert row.confidence == pytest.approx(0.92, abs=1e-6)
    assert row.elapsed_ms is not None and row.elapsed_ms >= 0
    assert row.was_overridden is False
    assert json.loads(row.semantic_scores)["electrical"] == pytest.approx(0.92, abs=1e-4)


def test_analyze_task_logs_skip_for_vague_text(db, project, no_gemini, monkeypatch):
    monkeypatch.setattr(ai_service, "_semantic_trade_scores", lambda text: {})
    monkeypatch.setattr(ai_service, "_detect_trade_groups", lambda text: set())

    result = ai_service.analyze_task(db, {"task_name": "test", "description": "test"}, project.project_id)
    db.commit()

    assert result["low_confidence"] is True
    row = db.query(AIDecisionLog).one()
    assert row.source == "skip"
    assert row.final_trade is None
    assert row.skip_reason


def test_auto_assign_writes_decision_log(db, project, no_gemini, monkeypatch):
    db.add(Worker(name="Ali", trade="electrician", project_id=project.project_id))
    task = Task(task_name="Install electrical wiring", description="run cables",
                project_id=project.project_id, status="pending")
    db.add(task)
    db.commit()
    db.refresh(task)

    monkeypatch.setattr(ai_service, "_semantic_trade_scores",
                        lambda text: {"electrical": 0.88, "plumbing": 0.05})

    ai_service.auto_assign_tasks(db, project_id=project.project_id, dry_run=False)
    db.commit()

    row = db.query(AIDecisionLog).filter(AIDecisionLog.task_id == task.task_id).one()
    assert row.stage == "auto_assign"
    assert row.final_trade == "electrical"
    assert row.source in ("rule", "semantic", "classifier", "title-rule")
    assert row.confidence > 0
    assert row.llm_used is False


def test_auto_assign_dry_run_writes_no_log(db, project, no_gemini, monkeypatch):
    db.add(Worker(name="Ali", trade="electrician", project_id=project.project_id))
    db.add(Task(task_name="Install electrical wiring", description="run cables",
                project_id=project.project_id, status="pending"))
    db.commit()
    monkeypatch.setattr(ai_service, "_semantic_trade_scores",
                        lambda text: {"electrical": 0.88, "plumbing": 0.05})

    ai_service.auto_assign_tasks(db, project_id=project.project_id, dry_run=True)
    db.commit()

    assert db.query(AIDecisionLog).count() == 0


def test_mark_decision_overridden_flags_latest_row(db, project):
    db.add(AIDecisionLog(stage="auto_assign", project_id=project.project_id,
                         final_trade="electrical", source="rule", confidence=0.9))
    db.commit()
    row_id = db.query(AIDecisionLog).one().log_id

    updated = ai_service.mark_decision_overridden(db, None, "plumbing")  # no task id -> no-op
    assert updated == 0

    log_row = db.query(AIDecisionLog).filter(AIDecisionLog.log_id == row_id).one()
    log_row.task_id = 12345
    db.commit()

    assert ai_service.mark_decision_overridden(db, 12345, "plumbing") == 1
    db.commit()
    log_row = db.query(AIDecisionLog).filter(AIDecisionLog.log_id == row_id).one()
    assert log_row.was_overridden is True
    assert log_row.override_trade == "plumbing"


def test_ensure_ai_decision_log_table_is_idempotent(engine):
    from app.db_migrate import ensure_ai_decision_log_table

    ensure_ai_decision_log_table(engine)
    assert ensure_ai_decision_log_table(engine) is True   # second call must not raise
    with engine.connect() as conn:
        cols = {r[1] for r in conn.exec_driver_sql("PRAGMA table_info(ai_decision_log)")}
    assert {"task_id", "task_text", "final_trade", "source", "confidence",
            "elapsed_ms", "was_overridden", "semantic_scores"} <= cols


# ── ambiguous-trade LLM fallback ────────────────────────────────────────────

def _ambiguous_inputs():
    """Two keyword hits with almost identical semantic scores (gap < 0.1)."""
    detected = {"tiling", "flooring"}
    scores = {"tiling": 0.44, "flooring": 0.42}
    return detected, scores


def test_resolve_trusts_rule_when_scores_are_confident(monkeypatch):
    calls = []
    monkeypatch.setattr(ai_service, "_llm_trade_decision",
                        lambda text, cands: calls.append(cands) or None)
    trace = {}

    resolved = ai_service._resolve_detected_trades(
        "tile the floor", {"tiling", "flooring"}, {"tiling": 0.81, "flooring": 0.20}, trace=trace
    )

    assert resolved == {"tiling"}
    assert calls == []            # confident -> no LLM call
    assert trace["source"] == "rule"
    assert trace["llm_used"] is False


def test_resolve_calls_llm_when_ambiguous(monkeypatch):
    monkeypatch.setattr(ai_service, "_llm_trade_decision",
                        lambda text, cands: {"trade": "flooring", "confidence": 0.86,
                                             "reason": "floor tiling is flooring work"})
    detected, scores = _ambiguous_inputs()
    trace = {}

    resolved = ai_service._resolve_detected_trades("tile the bathroom floor", detected, scores, trace=trace)

    assert resolved == {"flooring"}
    assert trace["source"] == "llm"
    assert trace["llm_used"] is True
    assert trace["confidence"] == pytest.approx(0.86)
    assert trace["llm_reason"].startswith("floor tiling")


def test_resolve_skips_when_llm_confidence_is_low(monkeypatch):
    monkeypatch.setattr(ai_service, "_llm_trade_decision",
                        lambda text, cands: {"trade": "tiling", "confidence": 0.3, "reason": "unclear"})
    detected, scores = _ambiguous_inputs()
    trace = {}

    resolved = ai_service._resolve_detected_trades("tile the bathroom floor", detected, scores, trace=trace)

    assert resolved == set()      # below skip threshold -> unassignable
    assert trace["source"] == "llm"


def test_resolve_degrades_to_rules_without_llm(monkeypatch):
    monkeypatch.setattr(ai_service, "_llm_trade_decision", lambda text, cands: None)
    detected, scores = _ambiguous_inputs()
    trace = {}

    resolved = ai_service._resolve_detected_trades("tile the bathroom floor", detected, scores, trace=trace)

    assert resolved == detected   # original behaviour preserved
    assert trace["source"] == "rule"
    assert trace["llm_used"] is False


class _BoomModel:
    def generate_content(self, *args, **kwargs):
        raise TimeoutError("gemini timeout")


class _GarbageModel:
    def generate_content(self, *args, **kwargs):
        return type("R", (), {"text": "not json at all"})()


def test_llm_decision_returns_none_on_timeout(monkeypatch):
    monkeypatch.setattr(ai_service, "get_gemini_model", lambda: _BoomModel())
    assert ai_service._llm_trade_decision("tile the floor", ["tiling", "flooring"]) is None


def test_llm_decision_returns_none_on_unparsable_answer(monkeypatch):
    monkeypatch.setattr(ai_service, "get_gemini_model", lambda: _GarbageModel())
    assert ai_service._llm_trade_decision("tile the floor", ["tiling", "flooring"]) is None


def test_llm_decision_rejects_trade_outside_candidates(monkeypatch):
    payload = json.dumps({"trade": "welding", "confidence": 0.9, "reason": "x"})
    monkeypatch.setattr(ai_service, "get_gemini_model",
                        lambda: type("M", (), {"generate_content": lambda self, *a, **k: type("R", (), {"text": payload})()})())

    assert ai_service._llm_trade_decision("tile the floor", ["tiling", "flooring"]) is None


def test_llm_decision_parses_valid_payload(monkeypatch):
    payload = "```json\n" + json.dumps(
        {"trade": "Flooring", "confidence": 1.4, "reason": "floor work"}
    ) + "\n```"
    monkeypatch.setattr(ai_service, "get_gemini_model",
                        lambda: type("M", (), {"generate_content": lambda self, *a, **k: type("R", (), {"text": payload})()})())

    result = ai_service._llm_trade_decision("tile the floor", ["flooring", "tiling"])
    assert result is not None
    assert result["trade"] == "flooring"
    assert result["confidence"] == 1.0   # clamped
