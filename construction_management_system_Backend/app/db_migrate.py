"""Lightweight schema migrations for existing databases (no Alembic).

BuildSmart relies on ``Base.metadata.create_all`` at startup, which creates
missing *tables* but never alters existing ones. This module adds missing
*columns* to already-existing tables so an old SQLite database keeps working
after new model fields are introduced.

Usage: call ``ensure_settings_columns(engine)`` right after ``create_all``.
"""
from sqlalchemy import inspect, text

from app import models  # noqa: F401  (registers every table on Base.metadata)

# New columns added to the settings table over time: {column: server_default}
_SETTINGS_ADDITIONS = {
    "check_in_start": "08:00",
    "check_in_end": "17:00",
    "check_out_start": "08:00",
    "check_out_end": "17:00",
    "break_start": "12:00",
    "break_end": "13:00",
}

# Work-hour corrections applied to existing settings rows on startup.
# Old defaults were 08:00-10:30 / 15:00-17:00; work hours are now 08:00-17:00
# with a lunch break 12:00-13:00.
_SETTINGS_CORRECTIONS = {
    "work_start": ("07:00 AM", "08:00 AM"),
    "late_threshold": ("07:30 AM", "08:30 AM"),
    "check_in_end": ("10:30", "17:00"),
    "check_out_start": ("15:00", "08:00"),
}

# FCM push tokens added to existing user tables over time:
# {table: {column: column_ddl}}
_FCM_COLUMN_ADDITIONS = {
    "workers": {
        "fcm_token": "VARCHAR(500)",
    },
    "supervisors": {
        "fcm_token": "VARCHAR(500)",
    },
}

# Supervisor attendance columns added to attendance_logs over time.
_ATTENDANCE_COLUMN_ADDITIONS = {
    "attendance_logs": {
        "supervisor_id": "INTEGER",
        "in_verified": "BOOLEAN NOT NULL DEFAULT 0",
        "out_verified": "BOOLEAN",
    },
}

# Task lifecycle timestamp columns added to the tasks table over time.
# SQLite accepts DATETIME (affinity); PostgreSQL needs TIMESTAMP WITH TIME ZONE
# to match models.Column(DateTime(timezone=True)).
_TASK_TIMESTAMP_COLUMNS = {
    "started_at": "DATETIME",
    "completed_at": "DATETIME",
}

_POSTGRES_TASK_TIMESTAMP_DDL = {
    "started_at": "TIMESTAMP WITH TIME ZONE",
    "completed_at": "TIMESTAMP WITH TIME ZONE",
}


def ensure_settings_columns(engine) -> list:
    """Add missing attendance-window columns to the settings table.

    Works on any SQLAlchemy engine; only touches the ``settings`` table and
    only adds columns that do not exist yet. Returns the list of added columns.
    """
    added = []
    inspector = inspect(engine)
    tables = set(inspector.get_table_names())
    if "settings" not in tables:
        return added

    existing = {c["name"] for c in inspector.get_columns("settings")}
    missing = {k: v for k, v in _SETTINGS_ADDITIONS.items() if k not in existing}
    if not missing:
        return added

    with engine.begin() as conn:
        for col, default in missing.items():
            # SQLite does NOT support parameter binding in ALTER TABLE ADD COLUMN
            # DEFAULT ? — the default must be inlined. Values are controlled
            # constants from _SETTINGS_ADDITIONS (safe against injection).
            conn.execute(
                text(
                    "ALTER TABLE settings ADD COLUMN %s VARCHAR(20) "
                    "NOT NULL DEFAULT '%s'" % (col, default)
                )
            )
            added.append(col)

    # Bring existing rows in line with the new 08:00-17:00 work hours.
    with engine.begin() as conn:
        for col, (old_val, new_val) in _SETTINGS_CORRECTIONS.items():
            conn.execute(
                text(
                    "UPDATE settings SET %s = '%s' WHERE %s = '%s'"
                    % (col, new_val, col, old_val)
                )
            )
    return added


def ensure_fcm_columns(engine) -> list:
    """Add missing fcm_token columns to workers/supervisors on old databases.

    Column is nullable so existing rows need no default; new installs get the
    column from ``Base.metadata.create_all`` directly.
    """
    added = []
    inspector = inspect(engine)
    tables = set(inspector.get_table_names())

    for table_name, columns in _FCM_COLUMN_ADDITIONS.items():
        if table_name not in tables:
            continue
        existing = {c["name"] for c in inspector.get_columns(table_name)}
        missing = {c: ddl for c, ddl in columns.items() if c not in existing}
        if not missing:
            continue
        with engine.begin() as conn:
            for col, ddl in missing.items():
                conn.execute(
                    text("ALTER TABLE %s ADD COLUMN %s %s" % (table_name, col, ddl))
                )
                added.append(f"{table_name}.{col}")
    return added


def ensure_attendance_columns(engine) -> list:
    """Add supervisor attendance support to attendance_logs on old databases.

    Adds a nullable ``supervisor_id`` column and (on PostgreSQL) drops the
    NOT NULL constraint on ``worker_id`` so a supervisor can clock in without
    a worker profile. SQLite cannot alter NOT NULL constraints in place, so
    supervisor check-in there is only available on fresh databases.
    """
    added = []
    inspector = inspect(engine)
    tables = set(inspector.get_table_names())
    if "attendance_logs" not in tables:
        return added

    existing = {c["name"] for c in inspector.get_columns("attendance_logs")}
    additions = dict(_ATTENDANCE_COLUMN_ADDITIONS["attendance_logs"])
    if engine.dialect.name == "postgresql":
        # PostgreSQL does not coerce integer ``0`` to BOOLEAN in a DEFAULT
        # expression. The old SQLite-friendly DDL therefore aborted the whole
        # startup migration before later columns (including specialties) ran.
        additions["in_verified"] = "BOOLEAN NOT NULL DEFAULT FALSE"
    missing = {c: ddl for c, ddl in additions.items() if c not in existing}
    if missing:
        with engine.begin() as conn:
            for col, ddl in missing.items():
                conn.execute(
                    text("ALTER TABLE attendance_logs ADD COLUMN %s %s" % (col, ddl))
                )
                added.append(f"attendance_logs.{col}")

    # PostgreSQL: allow supervisor rows (worker_id NULL).
    if engine.dialect.name == "postgresql":
        with engine.begin() as conn:
            conn.execute(
                text("ALTER TABLE attendance_logs ALTER COLUMN worker_id DROP NOT NULL")
            )
    return added


def ensure_task_timestamp_columns(engine) -> list:
    """Add started_at / completed_at columns to the tasks table on old databases.

    Mirrors the Task model change: both columns are nullable timestamps, so
    existing rows need no default. The DDL type follows the dialect (DATETIME
    for SQLite, TIMESTAMP WITH TIME ZONE for PostgreSQL); the function is
    intentionally generic so the same code can run against both engines.
    """
    added = []
    inspector = inspect(engine)
    tables = set(inspector.get_table_names())
    if "tasks" not in tables:
        return added

    is_postgres = engine.dialect.name == "postgresql"
    ddl_map = _POSTGRES_TASK_TIMESTAMP_DDL if is_postgres else _TASK_TIMESTAMP_COLUMNS
    existing = {c["name"] for c in inspector.get_columns("tasks")}
    missing = {c: ddl for c, ddl in ddl_map.items() if c not in existing}
    if not missing:
        return added

    with engine.begin() as conn:
        for col, ddl in missing.items():
            conn.execute(
                text("ALTER TABLE tasks ADD COLUMN %s %s" % (col, ddl))
            )
            added.append(f"tasks.{col}")
    return added


# SQLite accepts INTEGER / TEXT (affinity); PostgreSQL uses the same names.
_TASK_PROGRESS_COLUMNS = {
    "progress": "INTEGER",
    "completion_note": "TEXT",
}

_POSTGRES_TASK_PROGRESS_DDL = {
    "progress": "INTEGER",
    "completion_note": "TEXT",
}


def ensure_task_progress_columns(engine) -> list:
    """Add progress / completion_note columns to the tasks table on old databases.

    Mirrors the Task model change (C batch): both columns are nullable, so
    existing rows need no default and the ALTER is idempotent per column.
    The DDL type is identical for SQLite and PostgreSQL here; the dialect split
    is kept for symmetry with ensure_task_timestamp_columns and future-proofing.
    """
    added = []
    inspector = inspect(engine)
    tables = set(inspector.get_table_names())
    if "tasks" not in tables:
        return added

    is_postgres = engine.dialect.name == "postgresql"
    ddl_map = _POSTGRES_TASK_PROGRESS_DDL if is_postgres else _TASK_PROGRESS_COLUMNS
    existing = {c["name"] for c in inspector.get_columns("tasks")}
    missing = {c: ddl for c, ddl in ddl_map.items() if c not in existing}
    if not missing:
        return added

    with engine.begin() as conn:
        for col, ddl in missing.items():
            conn.execute(
                text("ALTER TABLE tasks ADD COLUMN %s %s" % (col, ddl))
            )
            added.append(f"tasks.{col}")
    return added


def ensure_specialty_columns(engine) -> list:
    """Add optional worker/task specialty fields without touching old rows."""
    added = []
    inspector = inspect(engine)
    tables = {
        "workers": {"specialties": "JSON NOT NULL DEFAULT '[]'"},
        "tasks": {"required_specialty": "VARCHAR(50)"},
    }
    with engine.begin() as conn:
        for table, wanted in tables.items():
            existing = {column["name"] for column in inspector.get_columns(table)}
            for column, ddl in wanted.items():
                if column not in existing:
                    conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {column} {ddl}"))
                    added.append(f"{table}.{column}")
    return added


def ensure_ai_decision_log_table(engine) -> bool:
    """Create the ``ai_decision_log`` table on databases that predate it.

    ``Base.metadata.create_all`` already creates missing tables, but this helper
    keeps the schema bootstrap explicit (and order-independent) so an old SQLite
    file or a fresh PostgreSQL instance both end up with the audit table before
    the AI endpoints write their first decision row. Safe to call repeatedly.
    Returns True when the table exists after the call.
    """
    table = models.AIDecisionLog.__table__
    inspector = inspect(engine)
    if table.name in set(inspector.get_table_names()):
        return True
    table.create(bind=engine, checkfirst=True)
    return True


# Composite index behind the decision-log analytics (project filter + time
# window + stage grouping). Mirrors models.AIDecisionLog.__table_args__.
_AI_DECISION_LOG_INDEX = {
    "name": "ix_ai_decision_log_project_created_stage",
    "columns": ("project_id", "created_at", "stage"),
}


def ensure_ai_decision_log_indexes(engine) -> list:
    """Add the composite (project_id, created_at, stage) index if it is missing.

    ``create_all`` only creates indexes for tables it creates itself, so a
    pre-existing ``ai_decision_log`` table never receives new model indexes.
    This helper closes that gap. It is idempotent twice over: the inspector check
    skips the DDL when the index already exists, and the statement itself uses
    ``CREATE INDEX IF NOT EXISTS`` (supported by SQLite and PostgreSQL) so a
    concurrent or repeated startup cannot fail either.

    Returns the list of index names created by this call (empty when the index
    was already there), which keeps the call safe to run on every boot.
    """
    created = []
    inspector = inspect(engine)
    if "ai_decision_log" not in set(inspector.get_table_names()):
        return created

    name = _AI_DECISION_LOG_INDEX["name"]
    existing = {idx.get("name") for idx in inspector.get_indexes("ai_decision_log")}
    if name in existing:
        return created

    columns = ", ".join(_AI_DECISION_LOG_INDEX["columns"])
    with engine.begin() as conn:
        conn.execute(
            text("CREATE INDEX IF NOT EXISTS %s ON ai_decision_log (%s)" % (name, columns))
        )
    created.append(name)
    return created


# Audit columns added to task_progress_logs over time so a privileged status
# move (reopen) records who did it and why.
_TASK_PROGRESS_LOG_AUDIT_COLUMNS = {
    "action": "VARCHAR(30)",
    "changed_by_id": "INTEGER",
    "changed_by_name": "VARCHAR(255)",
    "reason": "TEXT",
}


def ensure_task_progress_log_audit_columns(engine) -> list:
    """Add the reopen audit columns to task_progress_logs on old databases.

    All four columns are nullable, so existing timeline rows need no backfill and
    each ALTER is independent. Returns the list of added columns.
    """
    added = []
    inspector = inspect(engine)
    if "task_progress_logs" not in set(inspector.get_table_names()):
        return added

    existing = {c["name"] for c in inspector.get_columns("task_progress_logs")}
    missing = {
        col: ddl
        for col, ddl in _TASK_PROGRESS_LOG_AUDIT_COLUMNS.items()
        if col not in existing
    }
    if not missing:
        return added

    with engine.begin() as conn:
        for col, ddl in missing.items():
            conn.execute(
                text("ALTER TABLE task_progress_logs ADD COLUMN %s %s" % (col, ddl))
            )
            added.append(f"task_progress_logs.{col}")
    return added


# ────────────────── Common daily tasks / toolbox issues ──────────────────
def ensure_common_task_tables(engine) -> None:
    """Create ``common_task_instances`` and ``toolbox_issues`` if they are absent.

    ``Base.metadata.create_all`` already builds both on a fresh database. This
    migration exists for the deployed ones: it is written as
    ``CREATE TABLE/INDEX IF NOT EXISTS`` so it can run on every boot, side by side
    with existing tables, without dropping, truncating or rewriting a single row.

    DDL is dialect-specific only where identifiers differ (auto-increment column),
    because the service runs on SQLite locally and on Postgres when deployed.
    """
    dialect = engine.dialect.name
    if dialect == "postgresql":
        id_col = "SERIAL PRIMARY KEY"
        ts = "TIMESTAMP"
    else:
        id_col = "INTEGER PRIMARY KEY AUTOINCREMENT"
        ts = "DATETIME"

    statements = [
        f"""
        CREATE TABLE IF NOT EXISTS common_task_instances (
            instance_id {id_col},
            project_id INTEGER NOT NULL REFERENCES projects(project_id),
            task_kind VARCHAR(20) NOT NULL,
            work_date DATE NOT NULL,
            status VARCHAR(20) NOT NULL DEFAULT 'pending',
            photo_path VARCHAR(500),
            completed_at {ts},
            completed_by INTEGER REFERENCES workers(worker_id),
            created_at {ts} DEFAULT CURRENT_TIMESTAMP
        )
        """,
        """
        CREATE UNIQUE INDEX IF NOT EXISTS uq_common_task_project_kind_date
            ON common_task_instances (project_id, task_kind, work_date)
        """,
        """
        CREATE INDEX IF NOT EXISTS ix_common_task_project_date
            ON common_task_instances (project_id, work_date)
        """,
        f"""
        CREATE TABLE IF NOT EXISTS toolbox_issues (
            issue_id {id_col},
            worker_id INTEGER NOT NULL REFERENCES workers(worker_id),
            project_id INTEGER REFERENCES projects(project_id),
            tool_name VARCHAR(200) NOT NULL,
            qty INTEGER NOT NULL DEFAULT 1,
            taken_at {ts} NOT NULL DEFAULT CURRENT_TIMESTAMP,
            take_photo_path VARCHAR(500),
            returned_at {ts},
            return_photo_path VARCHAR(500),
            status VARCHAR(20) NOT NULL DEFAULT 'taken'
        )
        """,
        """
        CREATE INDEX IF NOT EXISTS ix_toolbox_worker_status
            ON toolbox_issues (worker_id, status)
        """,
        """
        CREATE INDEX IF NOT EXISTS ix_toolbox_project_status
            ON toolbox_issues (project_id, status)
        """,
    ]
    with engine.begin() as conn:
        for stmt in statements:
            conn.execute(text(stmt))
