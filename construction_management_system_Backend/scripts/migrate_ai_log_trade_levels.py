"""Generate (but do not apply) the trade -> four-level migration for the AI
decision log.

``scripts/migrate_trade_to_levels.py`` rewrites the two live trade columns
(``workers.trade`` and ``tasks.trade``). The AI decision log keeps its own
copies of the value resolved for a task -- ``final_trade`` and the human
``override_trade`` -- and those rows are what the stats endpoint groups by.
Leaving them on the abolished 16 groups would split every historical
distribution between a hand-written value and a level, so this script generates
the same kind of idempotent UPDATE statements for them.

Nothing is written to the database unless ``--execute`` is passed explicitly.
The default run writes the SQL plus a short report so the statements can be
reviewed and applied by hand inside a transaction:

    psql "$DATABASE_URL" -1 -f ai_log_trade_levels_migration.sql

``rule_trades`` and ``semantic_scores`` are JSON blobs (lists / dicts keyed by
the old group names). Rewriting keys inside those payloads is not something
that can be generated safely, so they are counted and left untouched -- the
analytics endpoints read ``final_trade`` / ``override_trade``.
"""

from __future__ import annotations

import argparse
import csv
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

BACKEND_DIR = Path(__file__).resolve().parent.parent
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from app.trade_levels import (  # noqa: E402
    MANUAL_REVIEW_VALUES,
    TRADE_LEVELS,
    TRADE_LEVEL_LABELS,
    _clean,
    trade_level,
)

# Columns on ai_decision_log that hold a single trade / level value.
TARGET_COLUMNS: Tuple[Tuple[str, str], ...] = (
    ("ai_decision_log", "final_trade"),
    ("ai_decision_log", "override_trade"),
)

# JSON columns keyed by the old group names; reported, never rewritten here.
JSON_COLUMNS: Tuple[Tuple[str, str], ...] = (
    ("ai_decision_log", "rule_trades"),
    ("ai_decision_log", "semantic_scores"),
)

MANUAL_REVIEW_CLEAN = {_clean(v) for v in MANUAL_REVIEW_VALUES}


def _sql_literal(value: Optional[str]) -> str:
    if value is None:
        return "NULL"
    return "'" + str(value).replace("'", "''") + "'"


def _column_key(table: str, column: str) -> str:
    return f"{table}.{column}"


def read_distinct_values(offline: bool) -> Dict[str, Counter]:
    """Count every distinct value currently stored in each target column."""
    if offline:
        return {}
    from sqlalchemy import text
    from app.database import engine

    found: Dict[str, Counter] = {}
    with engine.connect() as conn:
        for table, column in TARGET_COLUMNS:
            rows = conn.execute(
                text(
                    f"SELECT {column}, count(*) AS n FROM {table} "
                    f"WHERE {column} IS NOT NULL GROUP BY {column}"
                )
            ).fetchall()
            counter: Counter = Counter()
            for value, n in rows:
                counter[value] = int(n)
            found[_column_key(table, column)] = counter
    return found


def read_json_counts(offline: bool) -> Dict[str, int]:
    """How many rows still carry JSON payloads keyed by the old group names."""
    if offline:
        return {}
    from sqlalchemy import text
    from app.database import engine

    counts: Dict[str, int] = {}
    with engine.connect() as conn:
        for table, column in JSON_COLUMNS:
            row = conn.execute(
                text(f"SELECT count(*) FROM {table} WHERE {column} IS NOT NULL")
            ).scalar()
            counts[_column_key(table, column)] = int(row or 0)
    return counts


def trade_level_pairs() -> Iterable[Tuple[str, str]]:
    """Every legacy spelling that maps onto a level (offline path only)."""
    from app.trade_levels import LEGACY_FINE_ALIASES, LEVEL_ALIASES, MIGRATION_MAP

    for level, aliases in LEVEL_ALIASES.items():
        for alias in aliases:
            yield alias, level
    for fine, aliases in LEGACY_FINE_ALIASES.items():
        level = MIGRATION_MAP.get(fine)
        if not level:
            continue
        yield fine, level
        for alias in aliases:
            yield alias, level


def build_update_statements(
    found: Dict[str, Counter], offline: bool
) -> Tuple[List[str], List[dict], List[dict]]:
    """Return ``(statements, mapped_rows, unmapped_rows)``."""
    statements: List[str] = []
    mapped_rows: List[dict] = []
    unmapped_rows: List[dict] = []

    if offline:
        # No database read: emit one UPDATE per legacy word so the file can be
        # produced on a machine that cannot reach the database.
        pairs: List[Tuple[str, str]] = []
        seen = set()
        for legacy, level in sorted(trade_level_pairs()):
            if _clean(legacy) in seen:
                continue
            seen.add(_clean(legacy))
            pairs.append((legacy, level))
        for table, column in TARGET_COLUMNS:
            for raw, level in pairs:
                statements.append(
                    f"UPDATE {table} SET {column} = {_sql_literal(level)} "
                    f"WHERE lower(trim({column})) = lower(trim({_sql_literal(raw)}));"
                )
                mapped_rows.append(
                    {
                        "column": _column_key(table, column),
                        "raw_value": raw,
                        "target_level": level,
                        "rows": "n/a (offline)",
                    }
                )
        return statements, mapped_rows, unmapped_rows

    for key, counter in found.items():
        table, column = key.split(".", 1)
        for raw, count in sorted(counter.items(), key=lambda kv: str(kv[0])):
            level = trade_level(raw)
            if level is None:
                unmapped_rows.append(
                    {
                        "column": key,
                        "raw_value": raw,
                        "rows": count,
                        "reason": "manual review"
                        if _clean(raw) in MANUAL_REVIEW_CLEAN
                        else "no mapping",
                    }
                )
                continue
            if _clean(raw) == _clean(level):
                mapped_rows.append(
                    {
                        "column": key,
                        "raw_value": raw,
                        "target_level": level,
                        "rows": count,
                        "note": "already a level",
                    }
                )
                continue
            statements.append(
                f"UPDATE {table} SET {column} = {_sql_literal(level)} "
                f"WHERE lower(trim({column})) = lower(trim({_sql_literal(raw)}));"
            )
            mapped_rows.append(
                {
                    "column": key,
                    "raw_value": raw,
                    "target_level": level,
                    "rows": count,
                }
            )
    return statements, mapped_rows, unmapped_rows


def render_sql(
    statements: Iterable[str],
    unmapped: Optional[List[dict]] = None,
    json_counts: Optional[Dict[str, int]] = None,
) -> str:
    header = [
        "-- BuildSmart: ai_decision_log trade -> four skill level migration",
        "-- Generated by scripts/migrate_ai_log_trade_levels.py",
        f"-- Generated at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        "-- Target levels: " + ", ".join(TRADE_LEVEL_LABELS[lv] for lv in TRADE_LEVELS),
        "--",
        "-- This file was NOT executed by the generator. Review it, back up the",
        "-- database, then run it inside a transaction:",
        '--     psql "$DATABASE_URL" -1 -f ai_log_trade_levels_migration.sql',
        "-- Every UPDATE is idempotent (matched on lower(trim(column))), so a",
        "-- partially applied run can be repeated safely.",
        "",
        "BEGIN;",
    ]
    if unmapped:
        header.append("--")
        header.append(
            "-- Values below could not be mapped and are deliberately left untouched."
        )
        header.append(
            "-- Decide them by hand before the write endpoints start rejecting unlisted values:"
        )
        for row in unmapped:
            header.append(
                f"--   {row['column']} = {_sql_literal(row['raw_value'])} "
                f"({row['rows']} rows, {row['reason']})"
            )
    body = list(statements) or ["-- Nothing to update: no legacy trade values were found."]
    footer = ["", "-- Verification: must return zero legacy rows after the migration."]
    for table, column in TARGET_COLUMNS:
        for level in TRADE_LEVELS:
            footer.append(
                f"-- SELECT count(*) FROM {table} "
                f"WHERE lower(trim({column})) = {_sql_literal(level)};"
            )
    if json_counts:
        footer.append("")
        footer.append(
            "-- JSON payloads still keyed by the old group names (not rewritten here):"
        )
        for key, count in json_counts.items():
            footer.append(f"--   {key}: {count} row(s)")
    footer.append("COMMIT;")
    return "\n".join(header + body + footer)


def render_report(
    mapped: List[dict],
    unmapped: List[dict],
    json_counts: Dict[str, int],
    sql_path: Path,
) -> str:
    lines = ["# ai_decision_log trade -> four skill level migration report", ""]
    lines.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append(f"SQL file: `{sql_path}`")
    lines.append("")
    lines.append(
        "Target levels: " + ", ".join(TRADE_LEVEL_LABELS[lv] for lv in TRADE_LEVELS)
    )
    lines.append("")

    lines += ["## Columns rewritten", ""]
    for table, column in TARGET_COLUMNS:
        lines.append(f"- `{table}.{column}`")
    lines.append("")

    lines += ["## Mapped values", ""]
    if mapped:
        lines.append("| Column | Stored value | Becomes | Rows | Note |")
        lines.append("| --- | --- | --- | --- | --- |")
        for row in mapped:
            lines.append(
                f"| {row['column']} | {row['raw_value']} | {row['target_level']} "
                f"| {row['rows']} | {row.get('note', '')} |"
            )
    else:
        lines.append("_No legacy value found in the target columns._")
    lines.append("")

    lines += ["## Unmapped values (manual decision required)", ""]
    if unmapped:
        lines.append("| Column | Stored value | Rows | Reason |")
        lines.append("| --- | --- | --- | --- |")
        for row in unmapped:
            lines.append(
                f"| {row['column']} | {row['raw_value']} | {row['rows']} | {row['reason']} |"
            )
    else:
        lines.append("_None._")
    lines.append("")

    lines += ["## JSON payloads left untouched", ""]
    if json_counts:
        lines.append("| Column | Rows with payload |")
        lines.append("| --- | --- |")
        for key, count in json_counts.items():
            lines.append(f"| {key} | {count} |")
        lines.append("")
        lines.append(
            "These columns hold JSON keyed by the old 16 group names. They are "
            "analytical payloads: `final_trade` / `override_trade` already carry "
            "the resolved value, so API reads are unaffected."
        )
    else:
        lines.append("_No JSON payload found._")
    lines.append("")
    return "\n".join(lines)


def write_csv(rows: List[dict], path: Path) -> None:
    with path.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["column", "raw_value", "target_level", "rows", "reason"])
        for row in rows:
            writer.writerow(
                [
                    row.get("column", ""),
                    row.get("raw_value", ""),
                    row.get("target_level", ""),
                    row.get("rows", ""),
                    row.get("reason", row.get("note", "")),
                ]
            )


def execute_sql(statements: List[str]) -> int:
    """Apply the statements -- only reachable through ``--execute``."""
    from sqlalchemy import text
    from app.database import engine

    applied = 0
    with engine.begin() as conn:
        for statement in statements:
            applied += int(conn.execute(text(statement)).rowcount or 0)
    return applied


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out",
        default=str(BACKEND_DIR / "migrations"),
        help="Directory for the generated SQL / report / CSV files.",
    )
    parser.add_argument(
        "--offline",
        action="store_true",
        help="Skip the database read and emit one UPDATE per known legacy word.",
    )
    parser.add_argument(
        "--execute",
        action="store_true",
        help="Apply the generated SQL (off by default; back up the database first).",
    )
    args = parser.parse_args()

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    found = read_distinct_values(offline=args.offline)
    json_counts = read_json_counts(offline=args.offline)
    statements, mapped, unmapped = build_update_statements(found, offline=args.offline)

    sql_path = out_dir / "ai_log_trade_levels_migration.sql"
    report_path = out_dir / "ai_log_trade_levels_migration.md"
    csv_path = out_dir / "ai_log_trade_levels_migration.csv"

    sql_path.write_text(render_sql(statements, unmapped, json_counts), encoding="utf-8")
    report_path.write_text(
        render_report(mapped, unmapped, json_counts, sql_path), encoding="utf-8"
    )
    write_csv(mapped + unmapped, csv_path)

    print(f"SQL       : {sql_path}")
    print(f"Report    : {report_path}")
    print(f"CSV       : {csv_path}")
    print(f"Statements: {len(statements)}")
    print(f"Unmapped  : {len(unmapped)} value(s)")

    if unmapped:
        print("\nUnmapped values (fix app/trade_levels.py and regenerate):")
        for row in unmapped:
            print(
                f"  - {row['column']} = {row['raw_value']!r} "
                f"({row['rows']} rows, {row['reason']})"
            )

    if args.execute:
        applied = execute_sql(statements)
        print(f"\nApplied: {applied} row(s) updated.")
    else:
        print("\nGenerated only - no database write performed. Use --execute to apply.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
