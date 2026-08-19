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
    "check_in_end": "10:30",
    "check_out_start": "15:00",
    "check_out_end": "17:00",
    "break_start": "12:00",
    "break_end": "13:00",
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
    return added
