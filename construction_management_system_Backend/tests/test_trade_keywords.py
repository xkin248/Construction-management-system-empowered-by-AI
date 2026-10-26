"""Guards for the tuned trade keyword tables.

The tuning itself lives in ``reports/trade_matcher_tuning.md``; these tests only
lock in the invariants that the tuning must never break:

* the two copies of the seed table (production ``ai_service`` and the training
  script) stay identical, otherwise retraining silently diverges from serving;
* the weak multi-word terms that caused the wrong-trade misses stay narrowed;
* a handful of representative task texts keep resolving to the intended trade;
* the frozen pre-v2 snapshot plus the v2 additions equals the live tables, so the
  baseline in ``reports/trade_matcher_validation.md`` stays reproducible;
* the compound-title rules keep their narrow scope (``boiler operator`` is HVAC,
  ``boilermaker`` is welding);
* the supervised classifier artefact loads and answers offline.
"""

import io
import json
from pathlib import Path

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


# ── v2: frozen baseline snapshot + compound-title rules + classifier ─────────

SNAPSHOT = Path(__file__).resolve().parent.parent / "scripts" / "fixtures" / "trade_keywords_pre_v2.json"

# Exactly what the v2 round added on top of the snapshot; the sum must equal the live tables.
ADDED_V2 = {
    "welding": ["solder", "soldering", "brazing", "boilermaker", "sub arc", "arc weld",
                "spot weld", "boiler installer", "boiler mechanic"],
    "laborer": ["material handler", "cargo handler", "package handler", "freight handler"],
    "painting": ["wallpaper", "wallpapering", "decorator"],
    "masonry": ["cement patcher", "furnace mason", "refractory"],
}


def test_snapshot_plus_additions_equals_live_tables():
    """Pins the reported baseline: swapping the snapshot in must reproduce ``before``."""
    snap = json.loads(io.open(SNAPSHOT, encoding="utf-8").read())
    for key, live in (("task_keywords", ai_service.TASK_KEYWORDS),
                      ("seed_keywords", ai_service.SEED_KEYWORDS)):
        rebuilt = {trade: list(words) for trade, words in snap[key].items()}
        for trade, extra in ADDED_V2.items():
            rebuilt[trade] = rebuilt[trade] + extra
        assert rebuilt == live, key
    assert set(snap["task_keywords"]) == set(CANONICAL_TRADES)
    assert set(snap["seed_keywords"]) == set(CANONICAL_TRADES)


@pytest.mark.parametrize(
    "title, expected",
    [
        ("boilermaker", "welding"),
        ("boiler installer", "welding"),
        ("boiler mechanic", "welding"),
        ("assistant boilermaker", "welding"),
        # HVAC keeps the plain operator wording - the rule must not swallow it.
        ("boiler operator", None),
        ("cargo handler", "laborer"),
        ("package handler", "laborer"),
        ("freight handler", "laborer"),
        ("material handler", "laborer"),
        ("wallpaper hanger", "painting"),
        ("wallpaperer", "painting"),
        ("soldering machine setter and setup operator", "welding"),
        ("furnace mason", "masonry"),
        # A bare trade name must not trip the compound rules.
        ("electrician", None),
        ("laborer", None),
    ],
)
def test_compound_title_rules_are_narrow(title, expected):
    assert ai_service._structured_title_trade(title) == expected


def test_classifier_artefact_loads_and_predicts():
    """The shipped artefact must load offline and return a sensible trade."""
    clf = ai_service._load_trade_classifier()
    if clf is None:
        pytest.skip("trade_classifier.joblib not built; run scripts/build_trade_matcher.py")
    scores = ai_service._classifier_trade_scores("install electrical wiring and conduit")
    assert scores, "classifier returned no scores"
    assert "electrical" in scores
    assert max(scores.values()) > 0.0


def test_resolve_trade_decision_reports_known_source(monkeypatch):
    monkeypatch.setattr(ai_service, "get_gemini_model", lambda: None)
    decision = ai_service.resolve_trade_decision("boilermaker")
    assert decision["trade_source"] in ("explicit", "title-rule", "classifier", "rule",
                                       "semantic", "skip")
    assert "welding" in decision["detected_trades"]
