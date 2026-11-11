"""Tests for GET /api/tasks/{task_id} — the endpoint behind the worker detail page.

The worker task board previously had no way to open a task, so the whole
start → progress → complete flow was unreachable. The detail page loads one
fresh task record and relies on this endpoint returning a concrete ``progress``
(including the status-derived fallback) plus 404 for unknown ids.
"""
from app.models import Project, Supervisor, Task
from app.routers.auth import mk_tok


def supervisor_headers(db):
    supervisor = Supervisor(
        full_name="Task Test Supervisor",
        email="task-test@example.com",
        password_hash="x",
        role="site_supervisor",
    )
    db.add(supervisor)
    db.commit()
    return {"Authorization": f"Bearer {mk_tok(supervisor.email, 'supervisor')}"}, supervisor


def make_project(db, supervisor_id, name="Project A"):
    p = Project(
        project_name=name,
        location_address="123 Jalan Test",
        supervisor_id=supervisor_id,
    )
    db.add(p)
    db.commit()
    db.refresh(p)
    return p


def make_task(db, project_id, status="pending", name="Task"):
    t = Task(task_name=name, project_id=project_id, status=status, priority="medium")
    db.add(t)
    db.commit()
    db.refresh(t)
    return t


def test_get_single_task_returns_detail_with_progress(client, db):
    headers, supervisor = supervisor_headers(db)
    p = make_project(db, supervisor.supervisor_id)
    t = make_task(db, p.project_id, status="pending", name="Worker App Test Task")

    resp = client.get(f"/api/tasks/{t.task_id}", headers=headers)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["task_id"] == t.task_id
    assert body["task_name"] == "Worker App Test Task"
    assert body["progress"] == 0  # pending derives 0

    client.put(f"/api/tasks/{t.task_id}", json={"status": "in_progress"}, headers=headers)
    resp = client.get(f"/api/tasks/{t.task_id}", headers=headers)
    assert resp.status_code == 200
    assert resp.json()["progress"] == 50  # in_progress derives 50


def test_get_single_task_404_for_unknown_id(client, db):
    headers, _ = supervisor_headers(db)
    resp = client.get("/api/tasks/999999", headers=headers)
    assert resp.status_code == 404
