"""Guards for the model-artefact / runtime alignment.

The two joblib bundles are scikit-learn pickles. When they were built under a
different scikit-learn / numpy pair than the one pinned in ``requirements.txt``,
``joblib.load`` raised inside a bare ``except`` and the trade pipeline silently
fell back to the keyword layer, so the trained classifier shipped but never ran.

These tests lock in the three properties that fix that:

* both artefacts load in the current environment and are not degraded;
* the versions recorded inside each artefact match ``requirements.txt`` (checked
  against the pins, not against the locally installed wheels, so the guard holds
  on a developer machine with a newer scikit-learn);
* a missing / broken / version-skewed artefact is reported loudly (warning +
  ``MODEL_STATUS``) instead of disappearing into a silent fallback.
"""

import logging
import re
from pathlib import Path

import pytest

from app import ai_service

BACKEND_ROOT = Path(__file__).resolve().parent.parent
REQUIREMENTS = BACKEND_ROOT / "requirements.txt"
ARTIFACT_NAMES = ("trade_matcher", "trade_classifier")


def _pinned_versions():
    """Parse ``library==version`` pins out of requirements.txt."""
    pins = {}
    for line in REQUIREMENTS.read_text(encoding="utf-8").splitlines():
        match = re.match(r"\s*([A-Za-z0-9_.\-]+)\s*==\s*([^\s;#]+)", line)
        if match:
            pins[match.group(1).lower()] = match.group(2)
    return pins


@pytest.fixture()
def fresh_models():
    """Force a real reload for each test, and forget the result afterwards."""
    ai_service.reset_model_cache()
    yield ai_service
    ai_service.reset_model_cache()


def test_requirements_pin_the_pickle_libraries():
    pins = _pinned_versions()
    # Without these pins the alignment check below would silently pass on nothing.
    for library in ("scikit-learn", "numpy", "joblib"):
        assert library in pins, f"requirements.txt must pin {library}"


def test_both_artefacts_load_without_degrading(fresh_models):
    status = fresh_models.model_status()

    assert status["degraded"] == [], f"degraded artefacts: {status['degraded']}"
    for name in ARTIFACT_NAMES:
        entry = status["artifacts"][name]
        assert entry["loaded"] is True, entry
        assert entry["state"] in ("loaded", "version_mismatch"), entry
        assert entry["path"] and Path(entry["path"]).exists()

    assert fresh_models._load_trade_matcher() is not None
    assert fresh_models._load_trade_classifier() is not None


def test_artefacts_record_the_pinned_build_versions(fresh_models):
    pins = _pinned_versions()
    status = fresh_models.model_status()

    for name in ARTIFACT_NAMES:
        built = status["artifacts"][name]["built_with"]
        assert built, f"{name} carries no build metadata"
        for library in ("scikit-learn", "numpy", "joblib"):
            assert built.get(library) == pins[library], (
                f"{name} was built with {library} {built.get(library)}, "
                f"requirements.txt pins {pins[library]}"
            )


def test_trainer_writes_build_metadata():
    """The retraining script must stamp versions, or the guard has nothing to read."""
    payload_meta = ai_service._artifact_build_info({"meta": {"scikit-learn": "1.5.2"}})
    assert payload_meta["scikit-learn"] == "1.5.2"


def test_pickle_version_stamp_is_read_as_fallback():
    class FakeEstimator:
        _sklearn_version = "1.5.2"

    bundle = {"vectorizer": FakeEstimator()}  # no meta block, old artefact
    info = ai_service._artifact_build_info(bundle)
    assert info["scikit-learn"] == "1.5.2"
    assert info["source"] == "pickle_stamp"


def test_version_skew_is_flagged_not_swallowed(fresh_models, monkeypatch, caplog):
    """A newer local scikit-learn must surface as a warning, not a silent pass."""
    fake_bundle = {"model": object(), "classes": ["carpenter"],
                   "meta": {"scikit-learn": "0.0.1", "numpy": "0.0.1"}}
    monkeypatch.setattr(ai_service.joblib, "load", lambda path: fake_bundle)
    caplog.set_level(logging.WARNING, logger="app.ai_service")

    loaded = fresh_models._load_trade_classifier()
    entry = fresh_models.MODEL_STATUS["trade_classifier"]

    assert loaded is fake_bundle            # still usable ...
    assert entry["loaded"] is True
    assert entry["state"] == "version_mismatch"   # ... but not silently
    assert "scikit-learn" in (entry["error"] or "")
    assert any("scikit-learn" in record.getMessage() for record in caplog.records)


def test_missing_artefact_marks_degraded(fresh_models, monkeypatch, caplog):
    monkeypatch.setitem(ai_service.MODEL_ARTIFACTS, "trade_classifier", "does_not_exist.joblib")
    caplog.set_level(logging.WARNING, logger="app.ai_service")

    assert fresh_models._load_trade_classifier() is None
    entry = fresh_models.MODEL_STATUS["trade_classifier"]

    assert entry["state"] == "missing"
    assert entry["loaded"] is False
    assert "not found" in entry["error"].lower()
    assert any("MISSING" in record.getMessage() for record in caplog.records)


def test_broken_artefact_degrades_with_warning(fresh_models, monkeypatch, caplog):
    def boom(path):
        raise ValueError("corrupt pickle")

    monkeypatch.setattr(ai_service.joblib, "load", boom)
    caplog.set_level(logging.WARNING, logger="app.ai_service")

    assert fresh_models._load_trade_classifier() is None
    entry = fresh_models.MODEL_STATUS["trade_classifier"]

    assert entry["state"] == "failed"
    assert entry["loaded"] is False
    assert "ValueError" in entry["error"]
    assert any("falls back to keyword rules" in record.getMessage()
               for record in caplog.records)


def test_startup_self_check_screams_when_degraded(fresh_models, monkeypatch, caplog):
    """app.main calls log_model_status() at boot: degradation must be an ERROR."""
    monkeypatch.setitem(ai_service.MODEL_ARTIFACTS, "trade_classifier", "does_not_exist.joblib")
    monkeypatch.setitem(ai_service.MODEL_ARTIFACTS, "trade_matcher", "does_not_exist.joblib")
    caplog.set_level(logging.ERROR, logger="app.ai_service")

    status = fresh_models.log_model_status()

    assert set(status["degraded"]) == set(ARTIFACT_NAMES)
    errors = [record.getMessage() for record in caplog.records if record.levelno >= logging.ERROR]
    assert any("DEGRADED" in message for message in errors), errors


def test_startup_self_check_is_quiet_when_healthy(fresh_models, caplog):
    caplog.set_level(logging.ERROR, logger="app.ai_service")

    status = fresh_models.log_model_status()

    assert status["all_loaded"] is True
    assert [r for r in caplog.records if r.levelno >= logging.ERROR] == []
