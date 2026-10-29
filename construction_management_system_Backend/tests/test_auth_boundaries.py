"""Role-boundary tests.

The app has exactly two account types (``worker`` and ``site_supervisor``) and
no admin back office. The rules that matter:

* supervisor-only endpoints reject a worker token with 403
* worker-only endpoints reject a supervisor token with 403
* every protected endpoint rejects a missing token with 401

These were previously untested — the suite exercised happy paths only.
"""
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.database import get_db
from app.models import Project, Supervisor, Worker
from app.routers.ai_task import router as ai_task_router
from app.routers.attendance import router as attendance_router
from app.routers.auth import mk_tok


@pytest.fixture()
def api(session_factory):
    app = FastAPI(title="test")

    def override_get_db():
        session = session_factory()
        try:
            yield session
        finally:
            session.close()

    app.dependency_overrides[get_db] = override_get_db
    app.include_router(attendance_router, prefix="/api")
    app.include_router(ai_task_router, prefix="/api")
    return TestClient(app)


@pytest.fixture()
def seeded(db):
    sup = Supervisor(
        full_name="Boss", email="boss@buildsmart.com", password_hash="x", role="site_supervisor"
    )
    db.add(sup)
    db.commit()
    db.refresh(sup)
    project = Project(
        project_name="Project A",
        location_address="123 Jalan Test",
        supervisor_id=sup.supervisor_id,
    )
    db.add(project)
    db.commit()
    db.refresh(project)
    worker = Worker(
        name="Ali", email="ali@site.com", password_hash="x", role="worker",
        project_id=project.project_id,
    )
    db.add(worker)
    db.commit()
    db.refresh(worker)
    return {"supervisor": sup, "worker": worker, "project": project}


def worker_headers():
    return {"Authorization": f"Bearer {mk_tok('ali@site.com', 'worker')}"}


def supervisor_headers():
    return {"Authorization": f"Bearer {mk_tok('boss@buildsmart.com', 'supervisor')}"}


# ── supervisor-only endpoints ───────────────────────────────────────────────

def test_worker_cannot_reopen_task(api, seeded):
    resp = api.post("/api/tasks/1/reopen", json={"reason": "x"}, headers=worker_headers())
    assert resp.status_code == 403, resp.text


def test_worker_cannot_view_supervisor_attendance(api, seeded):
    resp = api.get("/api/attendance/supervisor/today", headers=worker_headers())
    assert resp.status_code == 403, resp.text


def test_supervisor_passes_role_gate_on_supervisor_endpoint(api, seeded):
    """Sanity check that the 403s above come from the role gate, not a broken
    token: the supervisor reaches the handler (200 with an empty summary)."""
    resp = api.get("/api/attendance/supervisor/today", headers=supervisor_headers())
    assert resp.status_code == 200, resp.text


# ── worker-only endpoints ───────────────────────────────────────────────────

def test_supervisor_cannot_use_worker_check_in(api, seeded):
    resp = api.post(
        "/api/attendance/worker/check-in",
        json={"project_id": seeded["project"].project_id, "lat": 3.139, "lng": 101.6869},
        headers=supervisor_headers(),
    )
    assert resp.status_code == 403, resp.text


def test_worker_can_use_worker_check_in(api, seeded):
    resp = api.post(
        "/api/attendance/worker/check-in",
        json={"project_id": seeded["project"].project_id, "lat": 3.139, "lng": 101.6869},
        headers=worker_headers(),
    )
    assert resp.status_code == 200, resp.text


# ── missing credentials ─────────────────────────────────────────────────────

@pytest.mark.parametrize(
    "method,path",
    [
        ("post", "/api/tasks/1/reopen"),
        ("get", "/api/attendance/supervisor/today"),
        ("post", "/api/attendance/worker/check-in"),
    ],
)
def test_missing_token_is_rejected(api, seeded, method, path):
    resp = getattr(api, method)(path, **({"json": {}} if method == "post" else {}))
    assert resp.status_code == 401, resp.text


def test_garbage_token_is_rejected(api, seeded):
    resp = api.get(
        "/api/attendance/supervisor/today",
        headers={"Authorization": "Bearer not-a-real-token"},
    )
    assert resp.status_code == 401, resp.text
