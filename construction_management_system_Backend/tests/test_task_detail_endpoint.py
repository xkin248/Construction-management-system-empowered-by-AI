"""Tests for GET /api/tasks/{task_id} — the endpoint behind the worker detail page.

The worker task board previously had no way to open a task, so the whole
start → progress → complete flow was unreachable. The detail page loads one
fresh task record and relies on this endpoint returning a concrete ``progress``
(including the status-derived fallback) plus 404 for unknown ids.
"""
from app.models import Project, Task


def make_project(db, name="Project A"):
    p = Project(project_name=name, location_address="123 Jalan Test")
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
    p = make_project(db)
    t = make_task(db, p.project_id, status="pending", name="Worker App Test Task")

    resp = client.get(f"/api/tasks/{t.task_id}")
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["task_id"] == t.task_id
    assert body["task_name"] == "Worker App Test Task"
    assert body["progress"] == 0  # pending derives 0

    client.put(f"/api/tasks/{t.task_id}", json={"status": "in_progress"})
    resp = client.get(f"/api/tasks/{t.task_id}")
    assert resp.status_code == 200
    assert resp.json()["progress"] == 50  # in_progress derives 50


def test_get_single_task_404_for_unknown_id(client):
    resp = client.get("/api/tasks/999999")
    assert resp.status_code == 404
