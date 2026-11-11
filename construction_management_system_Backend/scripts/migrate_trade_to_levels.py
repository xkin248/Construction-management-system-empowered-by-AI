"""Generate (never execute) the trade -> four-level data migration.

The backend now stores only the four skill levels defined in
``app.trade_levels`` (general worker / semi skilled worker / skilled worker /
foreman). Historical rows still hold one of the retired 16 fine-grained trades
("Carpenter", "tukang kayu", "Site Supervisor", ...), which the API rejects on
the next write, so they must be rewritten once.

SAFETY: this script is a generator. It reads the current distinct trade values
and writes a SQL file plus a report into the output directory. It refuses to
run any UPDATE unless ``--execute`` is passed explicitly, and the default run
never touches the database.

Usage (from the backend directory):

    # 1) Inspect what is in the database and produce the SQL file (default)
    python scripts/migrate_trade_to_levels.py

    # 2) Offline mode: skip the database read, emit UPDATEs for the full
    #    static MIGRATION_MAP / alias table instead
    python scripts/migrate_trade_to_levels.py --offline

    # 3) Apply the generated file (explicit opt-in, run it yourself)
    python scripts/migrate_trade_to_levels.py --execute

Outputs (default directory: ./migrations):
    trade_levels_migration.sql   - idempotent UPDATE statements + verification
    trade_levels_migration.md    - what was found, what each value maps to,
                                   and every value that could not be mapped
"""

from __future__ import annotations

import argparse
import csv
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from app.trade_levels import (  # noqa: E402
    LEVEL_ALIASES,
    MANUAL_REVIEW_VALUES,
    MIGRATION_MAP,
    TRADE_LEVEL_LABELS,
    TRADE_LEVELS,
    _clean,  # shared normaliser so the script and the API agree on spelling
)

# Tables holding a trade column that must be rewritten.
TARGET_TABLES: Tuple[str, ...] = ("workers", "tasks")


def _sql_literal(value: Optional[str]) -> str:
    """Quote *value* as a SQL string literal (NULL stays NULL)."""
    if value is None:
        return "NULL"
    return "'" + str(value).replace("'", "''") + "'"


def _mapping_for(value: Optional[str]) -> Optional[str]:
    """Resolve one stored value to one of the four levels (None = unknown)."""
    from app.trade_levels import trade_level

    return trade_level(value)


def read_distinct_values(offline: bool) -> Dict[str, Counter]:
    """Return ``{table: Counter(raw_value)}`` for the trade column.

    ``raw_value`` keeps the original casing so the generated UPDATE can match
    it with ``lower(trim(trade))`` and the report shows what operators typed.
    """
    if offline:
        return {}

    from sqlalchemy import text

    from app.database import engine

    found: Dict[str, Counter] = {}
    with engine.connect() as conn:
        for table in TARGET_TABLES:
            rows = conn.execute(
                text(f"SELECT trade, count(*) AS n FROM {table} GROUP BY trade")
            ).fetchall()
            counter: Counter = Counter()
            for trade, n in rows:
                counter[trade] = int(n)
            found[table] = counter
    return found


def build_update_statements(found: Dict[str, Counter], offline: bool) -> Tuple[List[str], List[dict], List[dict]]:
    """Build the UPDATE statements plus the report rows.

    Returns ``(statements, mapped_rows, unmapped_rows)``.
    """
    statements: List[str] = []
    mapped_rows: List[dict] = []
    unmapped_rows: List[dict] = []

    if offline:
        # No database read: emit one UPDATE per alias / legacy value so the
        # file is complete even when the DB is unreachable from this machine.
        pairs: List[Tuple[str, str]] = []
        seen = set()
        for level, aliases in LEVEL_ALIASES.items():
            for alias in aliases:
                if _clean(alias) in seen:
                    continue
                seen.add(_clean(alias))
                pairs.append((alias, level))
        for legacy, level in MIGRATION_MAP.items():
            if _clean(legacy) in seen:
                continue
            seen.add(_clean(legacy))
            pairs.append((legacy, level))

        for table in TARGET_TABLES:
            for raw, level in pairs:
                statements.append(
                    f"UPDATE {table} SET trade = {_sql_literal(level)} "
                    f"WHERE lower(trim(trade)) = lower(trim({_sql_literal(raw)}));"
                )
                mapped_rows.append(
                    {"table": table, "raw_value": raw, "target_level": level, "rows": "n/a (offline)"}
                )
        return statements, mapped_rows, unmapped_rows

    for table, counter in found.items():
        for raw, count in sorted(counter.items(), key=lambda kv: str(kv[0])):
            if raw is None:
                # NULL trade is legal (trade is optional) - nothing to do.
                mapped_rows.append(
                    {"table": table, "raw_value": "(NULL)", "target_level": "(left as NULL)", "rows": count}
                )
                continue
            level = _mapping_for(raw)
            if level is None:
                reason = "manual review" if _clean(raw) in {_clean(v) for v in MANUAL_REVIEW_VALUES} else "no mapping"
                unmapped_rows.append({"table": table, "raw_value": raw, "rows": count, "reason": reason})
                continue
            if _clean(raw) == level:
                mapped_rows.append(
                    {"table": table, "raw_value": raw, "target_level": level, "rows": count, "note": "already a level"}
                )
                continue
            statements.append(
                f"UPDATE {table} SET trade = {_sql_literal(level)} "
                f"WHERE lower(trim(trade)) = lower(trim({_sql_literal(raw)}));"
            )
            mapped_rows.append({"table": table, "raw_value": raw, "target_level": level, "rows": count})
    return statements, mapped_rows, unmapped_rows


def render_sql(statements: Iterable[str], found: Dict[str, Counter], unmapped: Optional[List[dict]] = None) -> str:
    header = [
        "-- BuildSmart: trade -> four skill level data migration",
        "-- Generated by scripts/migrate_trade_to_levels.py",
        f"-- Generated at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        "-- Target levels: " + ", ".join(TRADE_LEVEL_LABELS[lv] for lv in TRADE_LEVELS),
        "--",
        "-- This file was NOT executed by the generator. Review it, back up the",
        "-- database, then run it inside a transaction:",
        "--     psql \"$DATABASE_URL\" -1 -f trade_levels_migration.sql",
        "-- Every UPDATE is idempotent (matched on lower(trim(trade))), so re-running",
        "-- after a partial failure is safe.",
        "",
        "BEGIN;",
        "",
    ]
    if unmapped:
        header.append("-- Values below could not be mapped and are deliberately left untouched.")
        header.append("-- Decide them by hand (correct the value or set trade = NULL) before the")
        header.append("-- API starts rejecting unlisted values:")
        for row in unmapped:
            header.append(
                f"--   {row['table']}.trade = {_sql_literal(row['raw_value'])} ({row['rows']} rows, {row.get('reason', 'no mapping')})"
            )
        header.append("")
    body = list(statements) or ["-- Nothing to update: no legacy trade values were found."]
    footer = [
        "",
        "-- Verification: must return zero rows after the migration.",
    ]
    for table in TARGET_TABLES:
        for level in TRADE_LEVELS:
            footer.append(
                f"-- SELECT count(*) FROM {table} WHERE lower(trim(trade)) = {_sql_literal(level)};"
            )
    footer.append("COMMIT;")
    footer.append("")
    return "\n".join(header + body + footer)


def render_report(found: Dict[str, Counter], mapped: List[dict], unmapped: List[dict], sql_path: Path) -> str:
    lines = [
        "# Trade -> four skill level migration report",
        "",
        f"- Generated at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        f"- SQL file: `{sql_path}`",
        "- Execution policy: **generated only, not executed**",
        "",
        "## Target levels",
        "",
        "| stored value | label |",
        "|---|---|",
    ]
    for level in TRADE_LEVELS:
        lines.append(f"| `{level}` | {TRADE_LEVEL_LABELS[level]} |")

    lines += ["", "## Rows to rewrite", ""]
    if mapped:
        lines += ["| table | current value | new level | rows |", "|---|---|---|---|"]
        for row in mapped:
            lines.append(
                f"| {row['table']} | `{row['raw_value']}` | `{row['target_level']}` | {row['rows']} |"
            )
    else:
        lines.append("No rows to rewrite (offline mode does not read the database).")

    lines += ["", "## Unmapped values (manual decision required)", ""]
    if unmapped:
        lines += ["| table | current value | rows | reason |", "|---|---|---|---|"]
        for row in unmapped:
            lines.append(f"| {row['table']} | `{row['raw_value']}` | {row['rows']} | {row.get('reason', 'no mapping')} |")
        lines += [
            "",
            "These values match no level alias and no MIGRATION_MAP entry. Add them to",
            "`app/trade_levels.py` (LEVEL_ALIASES or MIGRATION_MAP) and regenerate, or",
            "clean them up manually before switching the API to strict validation.",
        ]
    else:
        lines.append("None - every current value resolves to a level.")

    lines += ["", "## Totals per table", ""]
    if found:
        lines += ["| table | distinct values | rows |", "|---|---|---|"]
        for table, counter in found.items():
            lines.append(f"| {table} | {len(counter)} | {sum(counter.values())} |")
    else:
        lines.append("Offline mode - no database statistics collected.")
    lines.append("")
    return "\n".join(lines)


def write_csv(path: Path, rows: List[dict]) -> None:
    """Write the mapping table with a fixed column set (mapped + unmapped rows)."""
    fieldnames = ["table", "raw_value", "target_level", "rows", "reason", "note"]
    with path.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames, restval="")
        writer.writeheader()
        for row in rows:
            writer.writerow({key: row.get(key, "") for key in fieldnames})


def execute_sql(sql_path: Path) -> None:
    """Apply the generated statements. Only reachable with --execute."""
    from sqlalchemy import text

    from app.database import engine

    content = sql_path.read_text(encoding="utf-8")
    statements = [
        line.strip()
        for line in content.splitlines()
        if line.strip().upper().startswith("UPDATE ")
    ]
    if not statements:
        print("Nothing to execute - the SQL file contains no UPDATE statements.")
        return
    with engine.begin() as conn:
        for statement in statements:
            conn.execute(text(statement))
    print(f"Executed {len(statements)} UPDATE statement(s) from {sql_path}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--offline",
        action="store_true",
        help="Do not read the database; emit UPDATEs for the full static mapping table.",
    )
    parser.add_argument(
        "--execute",
        action="store_true",
        help="Apply the generated SQL (disabled by default; back up the database first).",
    )
    parser.add_argument(
        "--out",
        default=str(BACKEND_DIR / "migrations"),
        help="Output directory for the generated SQL and report.",
    )
    args = parser.parse_args()

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    found = read_distinct_values(offline=args.offline)
    statements, mapped, unmapped = build_update_statements(found, offline=args.offline)

    sql_path = out_dir / "trade_levels_migration.sql"
    report_path = out_dir / "trade_levels_migration.md"
    csv_path = out_dir / "trade_levels_migration.csv"

    sql_path.write_text(render_sql(statements, found, unmapped), encoding="utf-8")
    report_path.write_text(render_report(found, mapped, unmapped, sql_path), encoding="utf-8")
    write_csv(csv_path, mapped + unmapped)

    print(f"SQL      : {sql_path}")
    print(f"Report   : {report_path}")
    print(f"CSV      : {csv_path}")
    print(f"Statements: {len(statements)}")
    print(f"Unmapped  : {len(unmapped)} value(s)")

    if unmapped:
        print("\nUnmapped values (fix app/trade_levels.py and regenerate):")
        for row in unmapped:
            print(f"  - {row['table']}.trade = {row['raw_value']!r} ({row['rows']} rows)")

    if not args.execute:
        print("\nGenerated only - no database write performed. Re-run with --execute to apply.")
        return 0

    execute_sql(sql_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
