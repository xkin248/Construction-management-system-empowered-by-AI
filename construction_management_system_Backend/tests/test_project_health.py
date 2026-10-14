"""Tests for GET /api/ai/projects/{pid}/health — the newly exposed
compute_project_progress() project health score.

Covers auth enforcement, payload shape, the deterministic rule-based fallback
(Gemini not configured in tests) and 404 handling. Everything runs on the
in-memory SQLite DB provided by conftest; Supabase is never touched.
"""
from datetime import date, datetime, timedelta

from app.models import AttendanceLog, Project, Supervisor, Task, Worker
from app.routers.auth import mk_tok

SUP_EMAIL = "health.sup@test.com"


# ── seed helpers ────────────────────────────────────────────────────────────

def make_supervisor(db, email=SUP_EMAIL):
    s = Supervisor(
        full_name="Health Test Supervisor",
        email=email,
        password_hash="not-used-in-tests",
        role="site_supervisor",
    )
    db.add(s)
    db.commit()
    db.refresh(s)
    return s


def auth_headers(email=SUP_EMAIL):
    return {"Authorization": f"Bearer {mk_tok(email, 'supervisor', m=30)}"}


def make_project(db, name="Health Proj", progress=0.0, status="in_progress"):
    p = Project(
        project_name=name,
        location_address="9 Jalan Health",
        status=status,
        progress=progress,
    )
    db.add(p)
    db.commit()
    db.refresh(p)
    return p


def make_task(db, project_id, status="pending", name="Task", worker_id=None, due=None):
    t = Task(
        task_name=name,
        project_id=project_id,
        status=status,
        priority="medium",
        assigned_worker_id=worker_id,
        due_date=due,
    )
    db.add(t)
    db.commit()
    db.refresh(t)
    return t


def make_worker(db, name, project_id, trade="General"):
    w = Worker(name=name, trade=trade, project_id=project_id)
    db.add(w)
    db.commit()
    db.refresh(w)
    return w


def make_attendance(db, worker, project_id, status="checked_in", when=None):
    log = AttendanceLog(
        worker_id=worker.worker_id,
        project_id=project_id,
        status=status,
        check_in_time=when or datetime.now(),
    )
    db.add(log)
    db.commit()
    db.refresh(log)
    return log


# ── tests ───────────────────────────────────────────────────────────────────

def test_health_requires_auth(client):
    """No bearer token -> 401 (endpoint is behind cu / site-supervisor auth)."""
    resp = client.get("/api/ai/projects/1/health")
    assert resp.status_code == 401, resp.text


def test_health_payload_shape_and_rule_based_score(client, db, monkeypatch):
    # Force the deterministic rule-based path: if Gemini happens to be reachable
    # in the test environment the refined score would make the maths flaky.
    monkeypatch.setattr("app.ai_service.get_gemini_model", lambda: None)

    make_supervisor(db)
    p = make_project(db, "Health Proj", progress=50.0)
    w1 = make_worker(db, "Ali", p.project_id, trade="electric")
    w2 = make_worker(db, "Bob", p.project_id, trade="mason")

    # 2 completed, 1 in progress, 1 pending + overdue -> completion 50%.
    make_task(db, p.project_id, status="completed", name="Done 1", worker_id=w1.worker_id)
    make_task(db, p.project_id, status="completed", name="Done 2", worker_id=w2.worker_id)
    make_task(db, p.project_id, status="in_progress", name="Active", worker_id=w1.worker_id)
    make_task(
        db, p.project_id, status="pending", name="Late",
        worker_id=w2.worker_id, due=date.today() - timedelta(days=3),
    )
    # Only one of two workers checked in today -> attendance 50%.
    make_attendance(db, w1, p.project_id)

    resp = client.get(f"/api/ai/projects/{p.project_id}/health", headers=auth_headers())
    assert resp.status_code == 200, resp.text
    body = resp.json()

    # ── identity + score contract ──
    assert body["project_id"] == p.project_id
    assert body["project_name"] == "Health Proj"
    assert isinstance(body["health_score"], int)
    assert 0 <= body["health_score"] <= 100
    assert body["risk_level"] in {"low", "medium", "high", "critical"}
    assert isinstance(body["ai_insights"], str) and body["ai_insights"]
    assert isinstance(body["recommendations"], list)
    assert isinstance(body["generated_at"], str)

    # ── metrics mirror the seeded data ──
    m = body["metrics"]
    assert m["total_tasks"] == 4
    assert m["completed"] == 2
    assert m["in_progress"] == 1
    assert m["pending"] == 1
    assert m["overdue"] == 1
    assert m["task_completion_pct"] == 50
    assert m["attendance_pct"] == 50
    assert m["total_workers"] == 2
    assert m["on_site_today"] == 1

    # Rule-based score (no Gemini in tests):
    #   tasks 50%*0.4 = 20 | attendance 50%*0.3 = 15 | overdue -5 -> 15
    #   all 4 tasks assigned -> +10  =>  60
    assert body["health_score"] == 60
    assert body["risk_level"] == "medium"

    # ── per-task / per-worker breakdowns are exposed for the UI ──
    assert len(body["tasks"]) == 4
    assert {t["status"] for t in body["tasks"]} == {"completed", "in_progress", "pending"}
    assert sum(1 for t in body["tasks"] if t["is_overdue"]) == 1
    assert len(body["worker_metrics"]) == 2
    assert {w["name"] for w in body["worker_metrics"]} == {"Ali", "Bob"}


def test_health_risk_level_tracks_score(client, db, monkeypatch):
    """A project with every signal bad must not be reported as low risk."""
    monkeypatch.setattr("app.ai_service.get_gemini_model", lambda: None)

    make_supervisor(db)
    p = make_project(db, "Bad Proj")
    w = make_worker(db, "Solo", p.project_id)
    # 4 overdue, unassigned, still-pending tasks + nobody on site.
    for i in range(4):
        make_task(
            db, p.project_id, status="pending", name=f"Late {i}",
            due=date.today() - timedelta(days=10),
        )

    resp = client.get(f"/api/ai/projects/{p.project_id}/health", headers=auth_headers())
    assert resp.status_code == 200, resp.text
    body = resp.json()

    # Unassigned tasks score 0 on the assignment band; attendance 0%.
    assert body["metrics"]["unassigned"] == 4
    assert body["metrics"]["attendance_pct"] == 0
    assert body["health_score"] < 40
    assert body["risk_level"] in {"high", "critical"}
    assert body["recommendations"]  # must suggest corrective actions


def test_health_unknown_project_404(client, db):
    make_supervisor(db)
    resp = client.get("/api/ai/projects/999999/health", headers=auth_headers())
    assert resp.status_code == 404, resp.text
