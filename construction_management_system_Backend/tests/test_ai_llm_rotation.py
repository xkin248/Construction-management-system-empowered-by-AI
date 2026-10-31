"""Gemini rotation / degradation reporting.

The LLM layer must stay *useful* under partial outages: a per-model 429 quota, a
transient 503 or a single slow candidate should not disable the whole feature,
because the next candidate can still answer. Only deployment-level errors
(401/403: bad or missing key) justify giving up on the first failure.

The tests also pin the *latency* contract: when the provider is down for us, the
caller must fall back to the rule layer in milliseconds instead of waiting for a
full rotation on every request.
"""
import time
import urllib.error

import pytest

from app import ai_service


@pytest.fixture(autouse=True)
def _reset_llm_state(monkeypatch):
    monkeypatch.setattr(ai_service, "_ACTIVE_MODEL", None)
    monkeypatch.setattr(ai_service, "_LAST_LLM_ERROR", None)
    monkeypatch.setattr(ai_service, "_MODEL_COOLDOWN", {})
    monkeypatch.setattr(ai_service, "_LLM_CIRCUIT_OPEN_UNTIL", 0.0)


def _http_error(code: int) -> urllib.error.HTTPError:
    return urllib.error.HTTPError("https://example.invalid", code, "boom", {}, None)


def _live_candidates():
    return [m for m in ai_service.GEMINI_MODEL_CANDIDATES if m not in ai_service._RETIRED_MODELS]


def test_quota_error_rotates_to_next_candidate(monkeypatch):
    candidates = _live_candidates()
    assert len(candidates) >= 2, "rotation test needs at least two live candidates"
    calls = []

    def fake_request(model, prompt, **kwargs):
        calls.append(model)
        if model == candidates[0]:
            raise _http_error(429)
        return "ok"

    monkeypatch.setattr(ai_service, "_gemini_request", fake_request)

    assert ai_service._gemini_text("ping") == "ok"
    assert calls[:2] == candidates[:2]
    assert ai_service._ACTIVE_MODEL == candidates[1]
    # A success wipes the recorded failure: the layer is healthy again.
    status = ai_service.llm_status()
    assert status["last_error"] is None
    assert status["circuit"]["open"] is False
    # The quota-throttled model is benched, not dropped.
    assert candidates[0] in status["cooldown"]


def test_timeout_on_one_model_does_not_disable_the_layer(monkeypatch):
    candidates = _live_candidates()

    def fake_request(model, prompt, **kwargs):
        if model == candidates[0]:
            raise TimeoutError("The read operation timed out")
        return "answer"

    monkeypatch.setattr(ai_service, "_gemini_request", fake_request)

    assert ai_service._gemini_text("ping") == "answer"
    assert ai_service._ACTIVE_MODEL == candidates[1]


def test_full_outage_opens_the_circuit_and_stops_retrying(monkeypatch):
    calls = []

    def failing_request(model, prompt, **kwargs):
        calls.append(model)
        raise _http_error(503)

    monkeypatch.setattr(ai_service, "_gemini_request", failing_request)

    assert ai_service._gemini_text("ping") is None
    first_pass = len(calls)
    assert first_pass == len(_live_candidates())
    assert ai_service.llm_status()["circuit"]["open"] is True
    assert ai_service.llm_status()["last_error"]["code"] == 503

    # While the circuit is open the LLM layer is skipped entirely: a second call
    # costs no network round-trip at all.
    started = time.monotonic()
    assert ai_service._gemini_text("ping") is None
    assert len(calls) == first_pass
    assert time.monotonic() - started < 0.5


def test_budget_exhaustion_does_not_hang(monkeypatch):
    """A candidate that hangs until the deadline must not exceed the budget."""

    def slow_request(model, prompt, **kwargs):
        time.sleep(kwargs.get("timeout", 0.05))
        raise TimeoutError("timeout")

    monkeypatch.setattr(ai_service, "_gemini_request", slow_request)

    started = time.monotonic()
    assert ai_service._gemini_text("ping", timeout=0.2) is None
    assert time.monotonic() - started < ai_service._LLM_TOTAL_BUDGET_SECONDS
    assert ai_service.llm_status()["last_error"] is not None


def test_auth_error_stops_immediately_and_is_reported(monkeypatch):
    calls = []

    def fake_request(model, prompt, **kwargs):
        calls.append(model)
        raise _http_error(403)

    monkeypatch.setattr(ai_service, "_gemini_request", fake_request)

    assert ai_service._gemini_text("ping") is None
    assert len(calls) == 1, "a bad key must not be retried across every candidate"
    status = ai_service.llm_status()
    assert status["last_error"]["code"] == 403
    assert status["enabled"] is True


def test_retired_model_is_never_retried(monkeypatch):
    gone = _live_candidates()[0]
    calls = []

    def fake_request(model, prompt, **kwargs):
        calls.append(model)
        if model == gone:
            raise _http_error(404)
        return "ok"

    monkeypatch.setattr(ai_service, "_RETIRED_MODELS", set())
    monkeypatch.setattr(ai_service, "_gemini_request", fake_request)
    try:
        assert ai_service._gemini_text("ping") == "ok"
        assert gone in ai_service._RETIRED_MODELS
        assert gone not in ai_service.llm_status()["candidates"]
    finally:
        ai_service._RETIRED_MODELS.discard(gone)


def test_status_never_leaks_the_key(monkeypatch):
    monkeypatch.setattr(ai_service, "GEMINI_API_KEY", "secret-key-value")
    payload = ai_service.llm_status()
    assert "secret-key-value" not in repr(payload)
