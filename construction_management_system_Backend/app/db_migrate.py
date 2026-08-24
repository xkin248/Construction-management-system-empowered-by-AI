"""Lightweight schema migrations for existing databases (no Alembic).

BuildSmart relies on ``Base.metadata.create_all`` at startup, which creates
missing *tables* but never alters existing ones. This module adds missing
*columns* to already-existing tables so an old SQLite database keeps working
after new model fields are introduced.

Usage: call ``ensure_settings_columns(engine)`` right after ``create_all``.
"""
from sqlalchemy import inspect, text

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
    },
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
    missing = {c: ddl for c, ddl in _ATTENDANCE_COLUMN_ADDITIONS["attendance_logs"].items() if c not in existing}
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
