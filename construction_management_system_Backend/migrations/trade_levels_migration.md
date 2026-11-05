# Trade -> four skill level migration report

- Generated at: 2026-11-04 13:38:19
- SQL file: `C:\Users\asus\Documents\construction_management_system\construction_management_system_Backend\migrations\trade_levels_migration.sql`
- Execution policy: **generated only, not executed**

## Target levels

| stored value | label |
|---|---|
| `general worker` | General Worker |
| `semi skilled worker` | Semi Skilled Worker |
| `skilled worker` | Skilled Worker |
| `foreman` | Foreman |

## Rows to rewrite

| table | current value | new level | rows |
|---|---|---|---|
| workers | `Electrical` | `skilled worker` | 1 |
| workers | `electrician` | `skilled worker` | 2 |
| workers | `scaffolder` | `semi skilled worker` | 1 |
| workers | `welder` | `skilled worker` | 1 |
| tasks | `(NULL)` | `(left as NULL)` | 2 |
| tasks | `electrical` | `skilled worker` | 1 |
| tasks | `plumbing` | `skilled worker` | 1 |

## Unmapped values (manual decision required)

| table | current value | rows | reason |
|---|---|---|---|
| workers | `426788` | 1 | manual review |

These values match no level alias and no MIGRATION_MAP entry. Add them to
`app/trade_levels.py` (LEVEL_ALIASES or MIGRATION_MAP) and regenerate, or
clean them up manually before switching the API to strict validation.

## Totals per table

| table | distinct values | rows |
|---|---|---|
| workers | 5 | 6 |
| tasks | 3 | 4 |
