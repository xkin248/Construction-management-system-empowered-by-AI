"""Idempotency tests for the schema migrations behind the decision-log and
task-reopen work.

Two gaps are covered:

* ``ai_decision_log`` had no composite ``(project_id, created_at, stage)`` index,
  so every stats/report query scanned the table. ``create_all`` never adds an
  index to a table it did not create, hence an explicit, idempotent migration.
* ``task_progress_logs`` needed nullable audit columns for the reopen trail
  (who / when / from -> to / why) on databases created before them.

Both helpers must be safe to run on every boot, i.e. a second call is a no-op and
never raises.
"""
import pytest
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.pool import StaticPool

from app import db_migrate, models
from app.db_migrate import (
    ensure_ai_decision_log_indexes,
    ensure_ai_decision_log_table,
    ensure_task_progress_log_audit_columns,
)

INDEX_NAME = "ix_ai_decision_log_project_created_stage"

# The legacy shape: the table exists but carries no composite index.
LEGACY_AI_DECISION_LOG_DDL = """
CREATE TABLE ai_decision_log (
    log_id INTEGER PRIMARY KEY AUTOINCREMENT,
    stage VARCHAR(30) NOT NULL DEFAULT 'trade_resolution',
    task_id INTEGER,
    project_id INTEGER,
    task_text TEXT,
    rule_trades TEXT,
    semantic_scores TEXT,
    final_trade VARCHAR(100),
    source VARCHAR(20) NOT NULL DEFAULT 'rule',
    confidence FLOAT,
    elapsed_ms INTEGER,
    llm_used BOOLEAN NOT NULL DEFAULT 0,
    llm_reason TEXT,
    skip_reason TEXT,
    was_overridden BOOLEAN NOT NULL DEFAULT 0,
    override_trade VARCHAR(100),
    created_at DATETIME
)
"""

# The legacy timeline table: no audit columns yet.
LEGACY_TASK_PROGRESS_LOG_DDL = """
CREATE TABLE task_progress_logs (
    log_id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id INTEGER NOT NULL,
    from_status VARCHAR(30),
    to_status VARCHAR(30),
    note TEXT,
    created_at DATETIME
)
"""


@pytest.fixture()
def legacy_engine():
    eng = create_engine("sqlite://", connect_args={"check_same_thread": False},
                        poolclass=StaticPool)
    with eng.begin() as conn:
        conn.execute(text(LEGACY_AI_DECISION_LOG_DDL))
        conn.execute(text(LEGACY_TASK_PROGRESS_LOG_DDL))
    yield eng
    eng.dispose()


def _index_names(engine, table):
    return {idx.get("name") for idx in inspect(engine).get_indexes(table)}


# ── composite index on ai_decision_log ──────────────────────────────────────

def test_index_created_on_legacy_table(legacy_engine):
    assert INDEX_NAME not in _index_names(legacy_engine, "ai_decision_log")

    created = ensure_ai_decision_log_indexes(legacy_engine)
    assert created == [INDEX_NAME]
    assert INDEX_NAME in _index_names(legacy_engine, "ai_decision_log")


def test_index_columns_and_order(legacy_engine):
    ensure_ai_decision_log_indexes(legacy_engine)
    indexes = {i["name"]: i for i in inspect(legacy_engine).get_indexes("ai_decision_log")}
    assert indexes[INDEX_NAME]["column_names"] == ["project_id", "created_at", "stage"]


def test_index_migration_is_idempotent(legacy_engine):
    assert ensure_ai_decision_log_indexes(legacy_engine) == [INDEX_NAME]
    # Running again must neither raise nor report work.
    assert ensure_ai_decision_log_indexes(legacy_engine) == []
    assert ensure_ai_decision_log_indexes(legacy_engine) == []
    assert INDEX_NAME in _index_names(legacy_engine, "ai_decision_log")


def test_index_migration_noops_without_table():
    eng = create_engine("sqlite://", connect_args={"check_same_thread": False},
                        poolclass=StaticPool)
    try:
        assert ensure_ai_decision_log_indexes(eng) == []
    finally:
        eng.dispose()


def test_index_present_on_fresh_database(engine):
    """Declared on the model, so create_all already builds it."""
    assert INDEX_NAME in _index_names(engine, "ai_decision_log")
    assert ensure_ai_decision_log_indexes(engine) == []


def test_index_matches_model_definition(engine):
    model_indexes = {idx.name: idx for idx in models.AIDecisionLog.__table__.indexes}
    assert INDEX_NAME in model_indexes
    assert [c.name for c in model_indexes[INDEX_NAME].columns] == [
        "project_id", "created_at", "stage",
    ]
    assert db_migrate._AI_DECISION_LOG_INDEX["name"] == INDEX_NAME
    assert db_migrate._AI_DECISION_LOG_INDEX["columns"] == ("project_id", "created_at", "stage")


def test_ensure_table_then_index_order_independent():
    """A bootstrap that runs the index helper before the table helper must not crash."""
    eng = create_engine("sqlite://", connect_args={"check_same_thread": False},
                        poolclass=StaticPool)
    try:
        assert ensure_ai_decision_log_indexes(eng) == []  # table missing -> no-op
        assert ensure_ai_decision_log_table(eng) is True
        # ``table.create`` emits the model's indexes as well, so the follow-up
        # index pass finds the work already done instead of duplicating it.
        assert ensure_ai_decision_log_indexes(eng) == []
        assert INDEX_NAME in _index_names(eng, "ai_decision_log")
    finally:
        eng.dispose()


def test_index_does_not_change_row_count(legacy_engine):
    with legacy_engine.begin() as conn:
        conn.execute(text(
            "INSERT INTO ai_decision_log (stage, project_id, final_trade, source) "
            "VALUES ('auto_assign', 1, 'electrical', 'rule')"
        ))
    ensure_ai_decision_log_indexes(legacy_engine)
    ensure_ai_decision_log_indexes(legacy_engine)
    with legacy_engine.connect() as conn:
        assert conn.execute(text("SELECT COUNT(*) FROM ai_decision_log")).scalar() == 1


# ── reopen audit columns on task_progress_logs ──────────────────────────────

def test_audit_columns_added_to_legacy_table(legacy_engine):
    existing = {c["name"] for c in inspect(legacy_engine).get_columns("task_progress_logs")}
    assert "action" not in existing

    added = ensure_task_progress_log_audit_columns(legacy_engine)
    assert set(added) == {
        "task_progress_logs.action",
        "task_progress_logs.changed_by_id",
        "task_progress_logs.changed_by_name",
        "task_progress_logs.reason",
    }

    columns = {c["name"]: c for c in inspect(legacy_engine).get_columns("task_progress_logs")}
    for name in ("action", "changed_by_id", "changed_by_name", "reason"):
        assert name in columns
        assert columns[name]["nullable"] is True  # old rows need no backfill


def test_audit_columns_migration_is_idempotent(legacy_engine):
    ensure_task_progress_log_audit_columns(legacy_engine)
    assert ensure_task_progress_log_audit_columns(legacy_engine) == []


def test_audit_columns_noop_on_fresh_database(engine):
    assert ensure_task_progress_log_audit_columns(engine) == []


def test_audit_columns_preserve_existing_rows(legacy_engine):
    with legacy_engine.begin() as conn:
        conn.execute(text(
            "INSERT INTO task_progress_logs (task_id, from_status, to_status, note) "
            "VALUES (1, 'pending', 'in_progress', 'started')"
        ))
    ensure_task_progress_log_audit_columns(legacy_engine)
    with legacy_engine.connect() as conn:
        row = conn.execute(text(
            "SELECT note, action, changed_by_name, reason FROM task_progress_logs"
        )).first()
    assert row[0] == "started"
    assert row[1] is None and row[2] is None and row[3] is None


def test_audit_columns_missing_table_is_noop():
    eng = create_engine("sqlite://", connect_args={"check_same_thread": False},
                        poolclass=StaticPool)
    try:
        assert ensure_task_progress_log_audit_columns(eng) == []
    finally:
        eng.dispose()
