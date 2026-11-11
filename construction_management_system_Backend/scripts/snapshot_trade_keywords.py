"""Freeze the pre-round vocabulary so the "before" column stays reproducible.

This round added thirteen terms to the keyword tables. Once they are in the source,
the old pipeline can no longer be reproduced from it, so the exact pre-round tables
are written to ``scripts/fixtures/trade_keywords_pre_v2.json``:

* ``before`` in ``eval_trade_validation.py`` is scored with this snapshot;
* ``final`` is scored with the live tables;
* the difference between the two is exactly the vocabulary added this round, which
  ``tests/test_trade_keywords.py`` pins so the snapshot cannot silently drift.

Run once, and re-run only if the snapshot itself needs to be regenerated (it never
should: the snapshot is history).
"""
from __future__ import annotations

import io
import json
import sys
from pathlib import Path

BACKEND = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND))

from app import ai_service  # noqa: E402

# The vocabulary introduced in the v2 round (see reports/trade_matcher_validation.md).
ADDED_V2 = {
    "welding": ["solder", "soldering", "brazing", "boilermaker", "sub arc", "arc weld",
                "spot weld", "boiler installer", "boiler mechanic"],
    "laborer": ["material handler", "cargo handler", "package handler", "freight handler"],
    "painting": ["wallpaper", "wallpapering", "decorator"],
    "masonry": ["cement patcher", "furnace mason", "refractory"],
}


def strip_added(table: dict) -> dict:
    return {trade: [w for w in words if w not in ADDED_V2.get(trade, ())]
            for trade, words in table.items()}


def main() -> int:
    snapshot = {
        "task_keywords": strip_added(ai_service.TASK_KEYWORDS),
        "seed_keywords": strip_added(ai_service.SEED_KEYWORDS),
    }
    out = BACKEND / "scripts" / "fixtures" / "trade_keywords_pre_v2.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    io.open(out, "w", encoding="utf-8", newline="\n").write(
        json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n"
    )
    print("snapshot:", out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
