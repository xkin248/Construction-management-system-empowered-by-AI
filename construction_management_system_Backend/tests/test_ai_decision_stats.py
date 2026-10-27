"""Tests for the AI decision-log consumer side (``app/ai_stats.py`` + report CLI).

Covers the aggregates behind ``GET /api/ai/decision-log/stats`` and
``scripts/trade_decision_report.py``:

* empty table / empty time window -> valid zeroed structure (never an error),
* source, trade, skip-reason, LLM trigger-vs-adoption, override and
  low-confidence ratios,
* project / stage / time filters,
* supervisor-only auth plus input validation on the endpoint,
* the Markdown renderer and the override-sample CSV export.
"""
import csv
import datetime as dt

import pytest

from app import ai_service
from app.ai_stats import (
    DEFAULT_LOW_CONFIDENCE_THRESHOLD,
    build_decision_stats,
    empty_stats,
    fetch_override_samples,
)
from app.models import AIDecisionLog, Project, Supervisor, Worker
from app.routers.auth import mk_tok
from scripts.trade_decision_report import (
    _parse_dt,
    export_overrides_csv,
    main,
    render_report,
)

BASE_TIME = dt.datetime(2026, 9, 1, 9, 0, 0)


def make_project(db, name="Site A"):
    project = Project(project_name=name, location_address="KL", status="active", progress=0)
    db.add(project)
    db.commit()
    db.refresh(project)
    return project


def add_log(db, *, project_id=None, source="rule", trade="electrical", confidence=0.9,
            llm_used=False, skip_reason=None, overridden=False, override_trade=None,
            elapsed_ms=120, stage="auto_assign", created_at=BASE_TIME, task_id=None,
            task_text="Install wiring"):
    row = AIDecisionLog(
        stage=stage,
        task_id=task_id,
        project_id=project_id,
        task_text=task_text,
        final_trade=trade,
        source=source,
        confidence=confidence,
        elapsed_ms=elapsed_ms,
        llm_used=llm_used,
        skip_reason=skip_reason,
        was_overridden=overridden,
        override_trade=override_trade,
        created_at=created_at,
    )
    db.add(row)
    return row


@pytest.fixture()
def seeded(db):
    """Eight rows: 5 decided (1 overridden, 1 low confidence), 3 skips, 2 LLM calls."""
    project = make_project(db)
    pid = project.project_id
    add_log(db, project_id=pid, source="rule", trade="electrical", confidence=0.9, elapsed_ms=100)
    add_log(db, project_id=pid, source="classifier", trade="electrical", confidence=0.8, elapsed_ms=180)
    add_log(db, project_id=pid, source="classifier", trade="plumbing", confidence=0.7, elapsed_ms=200,
            overridden=True, override_trade="electrical")
    add_log(db, project_id=pid, source="semantic", trade="tiling", confidence=0.3, elapsed_ms=150)
    add_log(db, project_id=pid, source="llm", trade="flooring", confidence=0.86, elapsed_ms=900,
            llm_used=True)
    add_log(db, project_id=pid, source="skip", trade=None, confidence=0.0, elapsed_ms=90,
            skip_reason="no trade identified from task text")
    add_log(db, project_id=pid, source="skip", trade=None, confidence=0.0, elapsed_ms=95,
            skip_reason="no trade identified from task text")
    add_log(db, project_id=pid, source="llm", trade=None, confidence=0.4, elapsed_ms=1100,
            llm_used=True, skip_reason="no trade identified from task text")
    db.commit()
    return pid


# ── empty / missing data ───────────────────────────────────────────────────

def test_empty_table_returns_zeroed_structure(db):
    stats = build_decision_stats(db)
    assert stats["total_decisions"] == 0
    assert stats["decided"] == 0
    assert stats["skip_count"] == 0
    assert stats["by_source"] == []
    assert stats["by_final_trade"] == []
    assert stats["skip_reasons"] == {"total": 0, "share": None, "top": []}
    assert stats["llm"]["triggered"] == 0
    assert stats["llm"]["adoption_rate"] is None
    assert stats["overrides"]["override_rate"] is None
    assert stats["elapsed_ms"]["avg"] is None
    assert stats["low_confidence"]["count"] == 0
    assert stats["first_log_at"] is None and stats["last_log_at"] is None


def test_empty_stats_payload_matches_build_key_set(db):
    assert set(empty_stats()) == set(build_decision_stats(db))
    assert set(empty_stats()["llm"]) == set(build_decision_stats(db)["llm"])
    assert set(empty_stats()["skip_reasons"]) == set(build_decision_stats(db)["skip_reasons"])


def test_empty_time_window_returns_valid_structure(db, seeded):
    stats = build_decision_stats(
        db,
        start=dt.datetime(2026, 1, 1),
        end=dt.datetime(2026, 1, 31, 23, 59),
    )
    assert stats["total_decisions"] == 0
    assert stats["by_source"] == []
    assert stats["filters"]["start"] == "2026-01-01T00:00:00"
    assert stats["filters"]["end"] == "2026-01-31T23:59:00"


def test_low_confidence_threshold_constant_matches_pipeline():
    # The stats module must not drift from the threshold the pipeline uses.
    assert DEFAULT_LOW_CONFIDENCE_THRESHOLD == ai_service.SKIP_CONFIDENCE_THRESHOLD


# ── aggregates ─────────────────────────────────────────────────────────────

def test_source_distribution(db, seeded):
    stats = build_decision_stats(db)
    assert stats["total_decisions"] == 8
    assert stats["decided"] == 5
    assert stats["skip_count"] == 3

    by_source = {item["source"]: item for item in stats["by_source"]}
    assert by_source["skip"]["count"] == 2
    assert by_source["classifier"]["count"] == 2
    assert by_source["rule"]["count"] == 1
    assert by_source["llm"]["count"] == 2
    assert by_source["rule"]["share"] == pytest.approx(0.125)
    # Sorted by count desc.
    assert stats["by_source"][0]["count"] >= stats["by_source"][-1]["count"]


def test_final_trade_distribution_and_share(db, seeded):
    stats = build_decision_stats(db)
    by_trade = {item["final_trade"]: item for item in stats["by_final_trade"]}
    assert by_trade["electrical"]["count"] == 2
    assert by_trade["plumbing"]["count"] == 1
    assert by_trade["electrical"]["share"] == pytest.approx(2 / 5, abs=1e-4)
    assert "None" not in by_trade          # skip rows never leak into the trade table


def test_skip_reason_top_n_limits_and_orders(db, seeded):
    add_log(db, project_id=seeded, source="skip", trade=None, confidence=0.0,
            skip_reason="empty task text", created_at=BASE_TIME)
    db.commit()

    stats = build_decision_stats(db, top_n=1)
    assert stats["skip_reasons"]["total"] == 4
    assert len(stats["skip_reasons"]["top"]) == 1
    assert stats["skip_reasons"]["top"][0]["reason"] == "no trade identified from task text"
    assert stats["skip_reasons"]["top"][0]["count"] == 3
    assert stats["skip_reasons"]["top"][0]["share"] == pytest.approx(3 / 4, abs=1e-4)


def test_llm_trigger_and_adoption_rate(db, seeded):
    stats = build_decision_stats(db)
    assert stats["llm"]["triggered"] == 2
    assert stats["llm"]["adopted"] == 1
    assert stats["llm"]["discarded"] == 1
    assert stats["llm"]["adoption_rate"] == pytest.approx(0.5)
    assert stats["llm"]["trigger_rate"] == pytest.approx(2 / 8, abs=1e-4)


def test_override_count_and_rate(db, seeded):
    stats = build_decision_stats(db)
    assert stats["overrides"]["was_overridden"] == 1
    assert stats["overrides"]["override_rate"] == pytest.approx(1 / 5, abs=1e-4)


def test_low_confidence_share_excludes_skip_rows(db, seeded):
    stats = build_decision_stats(db)
    assert stats["low_confidence"]["threshold"] == DEFAULT_LOW_CONFIDENCE_THRESHOLD
    assert stats["low_confidence"]["count"] == 1          # the 0.3 semantic row
    assert stats["low_confidence"]["share"] == pytest.approx(1 / 5, abs=1e-4)


def test_low_confidence_threshold_is_configurable(db, seeded):
    stats = build_decision_stats(db, low_confidence_threshold=0.75)
    # 0.3 / 0.7 qualify; the 0.8 / 0.86 / 0.9 rows do not.
    assert stats["low_confidence"]["count"] == 2
    assert stats["low_confidence"]["threshold"] == 0.75


def test_elapsed_average_min_max(db, seeded):
    stats = build_decision_stats(db)
    assert stats["elapsed_ms"]["avg"] == pytest.approx((100 + 180 + 200 + 150 + 900 + 90 + 95 + 1100) / 8, abs=0.01)
    assert stats["elapsed_ms"]["min"] == 90
    assert stats["elapsed_ms"]["max"] == 1100


# ── filters ────────────────────────────────────────────────────────────────

def test_project_filter_isolates_rows(db, seeded):
    other = make_project(db, name="Site B")
    add_log(db, project_id=other.project_id, source="rule", trade="painting", confidence=0.9)
    db.commit()

    stats = build_decision_stats(db, project_id=seeded)
    assert stats["total_decisions"] == 8
    assert stats["filters"]["project_id"] == seeded

    stats_other = build_decision_stats(db, project_id=other.project_id)
    assert stats_other["total_decisions"] == 1
    assert stats_other["by_final_trade"][0]["final_trade"] == "painting"


def test_time_range_filter_is_inclusive(db, seeded):
    add_log(db, project_id=seeded, source="rule", trade="painting", confidence=0.9,
            created_at=dt.datetime(2026, 9, 10, 12, 0, 0))
    add_log(db, project_id=seeded, source="rule", trade="painting", confidence=0.9,
            created_at=dt.datetime(2026, 10, 1, 12, 0, 0))
    db.commit()

    stats = build_decision_stats(
        db,
        start=dt.datetime(2026, 9, 10, 12, 0, 0),
        end=dt.datetime(2026, 9, 30, 23, 59, 59),
    )
    assert stats["total_decisions"] == 1
    assert stats["first_log_at"].startswith("2026-09-10")


def test_stage_filter(db, seeded):
    db.add(AIDecisionLog(stage="trade_resolution", project_id=seeded, final_trade="electrical",
                         source="rule", confidence=0.95, elapsed_ms=50, created_at=BASE_TIME))
    db.commit()

    stats = build_decision_stats(db, stage="trade_resolution")
    assert stats["total_decisions"] == 1
    assert stats["filters"]["stage"] == "trade_resolution"


# ── override samples ───────────────────────────────────────────────────────

def test_fetch_override_samples_returns_labelled_pairs(db, seeded):
    samples = fetch_override_samples(db)
    assert len(samples) == 1
    sample = samples[0]
    assert sample["predicted_trade"] == "plumbing"
    assert sample["override_trade"] == "electrical"
    assert sample["source"] == "classifier"
    assert sample["task_text"] == "Install wiring"


def test_fetch_override_samples_respects_limit_and_filters(db, seeded):
    assert fetch_override_samples(db, limit=1)  # does not raise on the single row
    other = make_project(db, name="Site B")
    assert fetch_override_samples(db, project_id=other.project_id) == []


# ── endpoint ───────────────────────────────────────────────────────────────

def _supervisor(db, email="boss@buildsmart.com"):
    sup = Supervisor(full_name="Boss", email=email, password_hash="x", role="site_supervisor")
    db.add(sup)
    db.commit()
    return sup


def _auth(email="boss@buildsmart.com"):
    return {"Authorization": f"Bearer {mk_tok(email, 'supervisor')}"}


def test_stats_endpoint_requires_authentication(client):
    assert client.get("/api/ai/decision-log/stats").status_code == 401


def test_stats_endpoint_rejects_worker_role(client, db):
    db.add(Worker(name="Ali", trade="electrician", email="ali@site.com", password_hash="x",
                  role="worker"))
    db.commit()
    resp = client.get("/api/ai/decision-log/stats",
                      headers={"Authorization": f"Bearer {mk_tok('ali@site.com', 'worker')}"})
    assert resp.status_code == 403


def test_stats_endpoint_returns_payload(client, db, seeded):
    _supervisor(db)
    resp = client.get("/api/ai/decision-log/stats", headers=_auth())
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["total_decisions"] == 8
    assert body["decided"] == 5
    assert body["llm"]["adoption_rate"] == pytest.approx(0.5)
    assert body["overrides"]["was_overridden"] == 1
    assert {item["source"] for item in body["by_source"]} >= {"rule", "classifier", "llm", "skip"}


def test_stats_endpoint_supports_filters(client, db, seeded):
    _supervisor(db)
    resp = client.get(
        "/api/ai/decision-log/stats",
        params={"project_id": seeded, "stage": "auto_assign",
                "start": "2026-09-01T00:00:00", "end": "2026-09-30T23:59:59", "top_n": 2},
        headers=_auth(),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["total_decisions"] == 8
    assert body["filters"]["project_id"] == seeded
    assert len(body["by_final_trade"]) <= 2


def test_stats_endpoint_empty_table_is_200(client, db):
    _supervisor(db)
    resp = client.get("/api/ai/decision-log/stats", headers=_auth())
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["total_decisions"] == 0
    assert body["by_source"] == []
    assert body["llm"]["adoption_rate"] is None


def test_stats_endpoint_404_for_unknown_project(client, db):
    _supervisor(db)
    resp = client.get("/api/ai/decision-log/stats", params={"project_id": 987654}, headers=_auth())
    assert resp.status_code == 404


def test_stats_endpoint_400_for_inverted_range(client, db):
    _supervisor(db)
    resp = client.get(
        "/api/ai/decision-log/stats",
        params={"start": "2026-10-01T00:00:00", "end": "2026-09-01T00:00:00"},
        headers=_auth(),
    )
    assert resp.status_code == 400


# ── report CLI ─────────────────────────────────────────────────────────────

def test_parse_dt_accepts_date_and_timestamp():
    assert _parse_dt("2026-09-01") == dt.datetime(2026, 9, 1, 0, 0, 0)
    assert _parse_dt("2026-09-01", end_of_day=True).time() == dt.time.max
    assert _parse_dt("2026-09-01T08:30:00") == dt.datetime(2026, 9, 1, 8, 30)
    assert _parse_dt(None) is None
    with pytest.raises(SystemExit):
        _parse_dt("not-a-date")


def test_render_report_on_empty_stats_keeps_all_sections():
    report = render_report(empty_stats())
    for heading in ("## 1. 总览", "## 2. 判定来源分布", "## 3. 判定工种分布",
                    "## 4. 跳过原因", "## 5. LLM 兜底效果", "## 6. 人工改派",
                    "## 7. 耗时与低置信占比", "## 8. 改派样本", "## 9. 字段含义与报表用途"):
        assert heading in report
    assert "没有任何决策日志" in report
    assert "total_decisions" in report


def test_render_report_summarises_numbers(db, seeded):
    stats = build_decision_stats(db)
    samples = fetch_override_samples(db)
    report = render_report(stats, samples, override_csv="reports/x.csv")

    assert "| 总判定数 | 8 |" in report
    assert "| 得出工种的判定数（decided） | 5 |" in report
    assert "| 采纳率（采纳 / 触发） | 50.00% |" in report
    assert "| 改派率（改派 / 已判定） | 20.00% |" in report
    assert "plumbing" in report and "electrical" in report
    assert "reports/x.csv" in report


def test_render_report_escapes_pipes_in_free_text():
    stats = empty_stats()
    samples = [{"log_id": 1, "task_text": "fix | pipe\nnow", "predicted_trade": "plumbing",
                "override_trade": "electrical", "source": "rule", "confidence": 0.4}]
    report = render_report(stats, samples)
    assert "fix \\| pipe now" in report


def test_export_overrides_csv(tmp_path, db, seeded):
    samples = fetch_override_samples(db)
    path = tmp_path / "overrides.csv"
    export_overrides_csv(samples, str(path))

    with open(path, encoding="utf-8-sig", newline="") as fh:
        rows = list(csv.DictReader(fh))
    assert len(rows) == 1
    assert rows[0]["predicted_trade"] == "plumbing"
    assert rows[0]["override_trade"] == "electrical"
    assert rows[0]["task_text"] == "Install wiring"


def test_cli_writes_report_and_csv(tmp_path, db, seeded, monkeypatch):
    from app import database

    monkeypatch.setattr(database, "SessionLocal", lambda: db)
    out = tmp_path / "report.md"
    csv_out = tmp_path / "samples.csv"

    code = main(["--project-id", str(seeded), "--since", "2026-09-01",
                 "--until", "2026-09-30", "--output", str(out),
                 "--export-overrides", str(csv_out)])
    assert code == 0
    text = out.read_text(encoding="utf-8")
    assert "AI 决策日志统计报表" in text
    assert "| 总判定数 | 8 |" in text
    assert csv_out.exists()
    assert "override_trade" in csv_out.read_text(encoding="utf-8-sig")


def test_cli_survives_missing_table(tmp_path, db, monkeypatch):
    """An un-migrated deployment must still get a renderable report, not a traceback."""
    from sqlalchemy.exc import ProgrammingError
    from app import database
    from scripts import trade_decision_report as report_mod

    monkeypatch.setattr(database, "SessionLocal", lambda: db)

    def boom(*args, **kwargs):
        raise ProgrammingError("SELECT ...", {}, Exception("no such table: ai_decision_log"))

    monkeypatch.setattr(report_mod, "build_decision_stats", boom)
    out = tmp_path / "report.md"

    code = report_mod.main(["--output", str(out)])
    assert code == 0
    text = out.read_text(encoding="utf-8")
    assert "| 总判定数 | 0 |" in text
    assert "没有任何决策日志" in text
