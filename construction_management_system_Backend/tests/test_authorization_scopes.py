"""Regression tests for project-scoped role authorization."""

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.database import get_db
from app.models import Project, Supervisor, Task, Worker
from app.routers.ai_task import router as tasks_router
from app.routers.auth import mk_tok
from app.routers.common_task import router as common_task_router
from app.routers.projects import router as projects_router
from app.routers.settings_router import router as settings_router
from app.routers.safety import router as safety_router
from app.routers.workers import router as workers_router


@pytest.fixture()
def api(session_factory):
    app = FastAPI(title="authorization scope test")

    def override_get_db():
        session = session_factory()
        try:
            yield session
        finally:
            session.close()

    app.dependency_overrides[get_db] = override_get_db
    app.include_router(projects_router, prefix="/api")
    app.include_router(workers_router, prefix="/api")
    app.include_router(tasks_router, prefix="/api")
    app.include_router(settings_router, prefix="/api")
    app.include_router(safety_router, prefix="/api")
    app.include_router(common_task_router, prefix="/api")
    return TestClient(app)


@pytest.fixture()
def scoped(db):
    alpha = Supervisor(full_name="Alpha", email="alpha@example.com", password_hash="x", role="site_supervisor")
    beta = Supervisor(full_name="Beta", email="beta@example.com", password_hash="x", role="site_supervisor")
    db.add_all([alpha, beta])
    db.flush()
    project_a = Project(project_name="Alpha Site", location_address="A", supervisor_id=alpha.supervisor_id)
    project_b = Project(project_name="Beta Site", location_address="B", supervisor_id=beta.supervisor_id)
    db.add_all([project_a, project_b])
    db.flush()
    worker = Worker(name="Ali", email="ali@example.com", password_hash="x", role="worker", project_id=project_a.project_id)
    db.add(worker)
    db.flush()
    own_task = Task(task_name="Own task", project_id=project_a.project_id, assigned_worker_id=worker.worker_id)
    other_task = Task(task_name="Other task", project_id=project_a.project_id)
    db.add_all([own_task, other_task])
    db.commit()
    return {
        "alpha": {"Authorization": f"Bearer {mk_tok('alpha@example.com', 'supervisor')}"},
        "beta": {"Authorization": f"Bearer {mk_tok('beta@example.com', 'supervisor')}"},
        "worker": {"Authorization": f"Bearer {mk_tok('ali@example.com', 'worker')}"},
        "project_a": project_a.project_id,
        "project_b": project_b.project_id,
        "worker_id": worker.worker_id,
        "own_task": own_task.task_id,
        "other_task": other_task.task_id,
    }


def test_management_endpoints_require_login(api):
    assert api.get("/api/projects").status_code == 401
    assert api.get("/api/workers").status_code == 401
    assert api.get("/api/settings").status_code == 401


def test_supervisor_cannot_access_another_supervisors_project(api, scoped):
    assert api.get(f"/api/projects/{scoped['project_b']}", headers=scoped["alpha"]).status_code == 403
    assert api.get(f"/api/projects/{scoped['project_b']}/tasks", headers=scoped["alpha"]).status_code == 403
    assert api.delete(f"/api/projects/{scoped['project_b']}", headers=scoped["alpha"]).status_code == 403


def test_worker_only_reads_and_updates_an_assigned_task(api, scoped):
    assert api.get(f"/api/tasks/{scoped['own_task']}", headers=scoped["worker"]).status_code == 200
    assert api.get(f"/api/tasks/{scoped['other_task']}", headers=scoped["worker"]).status_code == 403
    assert api.put(
        f"/api/tasks/{scoped['own_task']}",
        json={"priority": "high"},
        headers=scoped["worker"],
    ).status_code == 403


def test_worker_cannot_access_supervisor_management_endpoints(api, scoped):
    assert api.get("/api/workers", headers=scoped["worker"]).status_code == 403
    assert api.get("/api/settings", headers=scoped["worker"]).status_code == 403


def test_worker_safety_report_uses_authenticated_identity(api, scoped):
    denied = api.post(
        "/api/safety/report",
        params={
            "incident_type": "unsafe_act",
            "worker_id": 999,
            "project_id": scoped["project_a"],
            "gps_lat": 3.139,
            "gps_lng": 101.6869,
        },
        headers=scoped["worker"],
    )
    assert denied.status_code == 403

    created = api.post(
        "/api/safety/report",
        params={
            "incident_type": "unsafe_act",
            "worker_id": scoped["worker_id"],
            "project_id": scoped["project_a"],
            "gps_lat": 3.139,
            "gps_lng": 101.6869,
        },
        headers=scoped["worker"],
    )
    assert created.status_code == 200, created.text
    assert created.json()["incident_type"] == "unsafe_act"


def test_supervisor_dashboard_gets_three_common_task_summaries(api, scoped):
    """The default all-project dashboard scope must not fail validation."""
    response = api.get("/api/common-tasks/today", headers=scoped["alpha"])

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["project_id"] is None
    assert [item["task_kind"] for item in body["tasks"]] == [
        "briefing",
        "toolbox",
        "housekeeping",
    ]
    assert all(item["project_count"] == 1 for item in body["tasks"])
