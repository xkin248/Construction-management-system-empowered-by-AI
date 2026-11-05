# ai_decision_log trade -> four skill level migration report

Generated: 2026-11-04 13:37:32
SQL file: `C:\Users\asus\Documents\construction_management_system\construction_management_system_Backend\migrations\ai_log_trade_levels_migration.sql`

Target levels: General Worker, Semi Skilled Worker, Skilled Worker, Foreman

## Columns rewritten

- `ai_decision_log.final_trade`
- `ai_decision_log.override_trade`

## Mapped values

| Column | Stored value | Becomes | Rows | Note |
| --- | --- | --- | --- | --- |
| ai_decision_log.final_trade | electrical | skilled worker | 5 |  |

## Unmapped values (manual decision required)

_None._

## JSON payloads left untouched

| Column | Rows with payload |
| --- | --- |
| ai_decision_log.rule_trades | 0 |
| ai_decision_log.semantic_scores | 5 |

These columns hold JSON keyed by the old 16 group names. They are analytical payloads: `final_trade` / `override_trade` already carry the resolved value, so API reads are unaffected.
