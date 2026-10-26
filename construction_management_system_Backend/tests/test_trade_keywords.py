"""Guards for the tuned trade keyword tables.

The tuning itself lives in ``reports/trade_matcher_tuning.md``; these tests only
lock in the invariants that the tuning must never break:

* the two copies of the seed table (production ``ai_service`` and the training
  script) stay identical, otherwise retraining silently diverges from serving;
* the weak multi-word terms that caused the wrong-trade misses stay narrowed;
* a handful of representative task texts keep resolving to the intended trade.
"""

import pytest

from app import ai_service
from scripts import build_trade_matcher

CANONICAL_TRADES = (
    "carpenter", "electrical", "plumbing", "masonry", "painting", "welding",
    "hvac", "roofing", "tiling", "drywall", "glazing", "flooring",
    "equipment", "laborer", "insulation", "supervision",
)


def test_seed_tables_are_identical():
    assert ai_service.SEED_KEYWORDS == build_trade_matcher.SEED_KEYWORDS


def test_both_tables_cover_every_canonical_trade():
    for table_name in ("TASK_KEYWORDS", "SEED_KEYWORDS"):
        table = getattr(ai_service, table_name)
        assert set(table) == set(CANONICAL_TRADES), table_name
        for trade, words in table.items():
            assert words, f"{table_name}[{trade}] is empty"
            assert all(w == w.lower() for w in words), f"{table_name}[{trade}] must be lowercase"
            assert len(set(words)) == len(words), f"{table_name}[{trade}] has duplicates"


@pytest.mark.parametrize(
    "trade, term",
    [
        ("tiling", "terrazzo"),
        ("welding", "ironworker"),
        ("laborer", "sign"),
        ("laborer", "wall"),
        ("laborer", "water"),
        ("plumbing", "water"),
    ],
)
def test_ambiguous_terms_stay_out_of_the_rule_layer(trade, term):
    assert term not in ai_service.TASK_KEYWORDS[trade]


@pytest.mark.parametrize(
    "trade, term",
    [
        ("masonry", "terrazzo"),
        ("masonry", "terrazzo"),
        ("masonry", "post tension"),
        ("hvac", "boiler"),
        ("insulation", "asbestos"),
        ("plumbing", "sewage"),
        ("laborer", "detailer"),
        ("carpenter", "marquetry"),
        ("electrical", "wirer"),
    ],
)
def test_missing_vocabulary_was_added(trade, term):
    assert term in ai_service.TASK_KEYWORDS[trade]
    assert term in ai_service.SEED_KEYWORDS[trade]


@pytest.mark.parametrize(
    "task_text, expected_trade",
    [
        ("terrazzo mechanic", "masonry"),
        ("terrazzo polisher", "masonry"),
        ("auto detailer", "laborer"),
        ("shrub and tree planter", "laborer"),
        ("boiler operator", "hvac"),
        ("sewage disposal plant operator", "plumbing"),
        ("marquetry worker", "carpenter"),
        ("house wirer", "electrical"),
    ],
)
def test_representative_tasks_resolve_to_expected_trade(tmp_path, monkeypatch, task_text, expected_trade):
    # Keep the pipeline offline: no Gemini call during tests.
    monkeypatch.setattr(ai_service, "get_gemini_model", lambda: None)
    decision = ai_service.resolve_trade_decision(task_text)
    assert expected_trade in decision["detected_trades"], decision
