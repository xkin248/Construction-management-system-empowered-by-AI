"""Tests for the supervisor-only task reopen endpoint.

A task wrongly marked "completed" used to be a dead end: the state machine had
``completed -> {}`` and the generic update endpoint refused every backward move.
``POST /api/tasks/{id}/reopen`` adds one privileged, audited edge back, while
the historical forward-only contract of ``PUT /api/tasks/{id}`` is preserved.
"""
import datetime as dt

import pytest

from app.models import Project, Supervisor, Task, TaskProgressLog, Worker
from app.routers.ai_task import (
    REOPEN_ONLY_TRANSITIONS,
    REOPEN_TARGET_STATUSES,
    TASK_STATUS_TRANSITIONS,
    _validate_status_transition,
)
from app.routers.auth import mk_tok
from fastapi import HTTPException


def make_project(db, name="Project A"):
    p = Project(project_name=name, location_address="123 Jalan Test")
    db.add(p)
    db.commit()
    db.refresh(p)
    return p


def make_completed_task(db, project_id, name="Fix formwork", progress=100):
    t = Task(
        task_name=name,
        project_id=project_id,
        status="completed",
        priority="medium",
        progress=progress,
        completed_at=dt.datetime(2026, 9, 1, 10, 0, 0),
    )
    db.add(t)
    db.commit()
    db.refresh(t)
    return t


def make_supervisor(db, email="boss@buildsmart.com", name="Boss"):
    s = Supervisor(full_name=name, email=email, password_hash="x", role="site_supervisor")
    db.add(s)
    db.commit()
    db.refresh(s)
    return s


def auth(email="boss@buildsmart.com", user_type="supervisor"):
    return {"Authorization": f"Bearer {mk_tok(email, user_type)}"}


# ── state machine definition ────────────────────────────────────────────────

def test_state_machine_declares_reopen_edges_once():
    """The reopen edges live in TASK_STATUS_TRANSITIONS, tagged as reopen-only."""
    assert TASK_STATUS_TRANSITIONS["completed"] == {"in_progress", "pending"}
    assert REOPEN_ONLY_TRANSITIONS == {("completed", "in_progress"), ("completed", "pending")}
    # Every reopen-only edge must be declared in the shared map and vice versa.
    declared = {(src, dst) for src, dsts in TASK_STATUS_TRANSITIONS.items() for dst in dsts}
    assert REOPEN_ONLY_TRANSITIONS <= declared
    assert set(REOPEN_TARGET_STATUSES) == {"in_progress", "pending"}


def test_validator_blocks_reopen_without_opt_in():
    """Default callers (e.g. PUT /tasks/{id}) still cannot reopen."""
    _validate_status_transition("pending", "in_progress")
    _validate_status_transition("in_progress", "completed")
    with pytest.raises(HTTPException) as exc:
        _validate_status_transition("completed", "in_progress")
    assert exc.value.status_code == 400
    assert "reopen" in exc.value.detail.lower()


def test_validator_allows_reopen_with_opt_in():
    _validate_status_transition("completed", "in_progress", allow_reopen=True)
    _validate_status_transition("completed", "pending", allow_reopen=True)
    # Unknown edges are still rejected even with the flag on.
    with pytest.raises(HTTPException):
        _validate_status_transition("pending", "completed", allow_reopen=True)


# ── generic update endpoint keeps refusing backward moves ───────────────────

def test_put_task_still_rejects_backward_status(client, db):
    p = make_project(db)
    t = make_completed_task(db, p.project_id)
    make_supervisor(db)

    for target in ("in_progress", "pending"):
        resp = client.put(
            f"/api/tasks/{t.task_id}",
            json={"status": target, "note": "sneaky revert"},
            headers=auth(),
        )
        assert resp.status_code == 400, resp.text
        assert "reopen" in resp.json()["detail"].lower()

    db.expire_all()
    assert db.get(Task, t.task_id).status == "completed"


# ── happy path ──────────────────────────────────────────────────────────────

def test_reopen_completed_task_writes_audit_and_reverts_progress(client, db):
    p = make_project(db)
    t = make_completed_task(db, p.project_id, progress=100)
    sup = make_supervisor(db, name="Alice Tan")

    resp = client.post(
        f"/api/tasks/{t.task_id}/reopen",
        json={"reason": "Client rejected the plastering finish"},
        headers=auth(),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["status"] == "ok"
    assert body["from_status"] == "completed"
    assert body["to_status"] == "in_progress"
    assert body["reopened_by"] == "Alice Tan"
    assert body["reopened_by_id"] == sup.supervisor_id

    db.expire_all()
    task = db.get(Task, t.task_id)
    assert task.status == "in_progress"
    assert task.completed_at is None
    assert task.progress == 50  # no usable partial progress -> parked mid-way

    log = (
        db.query(TaskProgressLog)
        .filter(TaskProgressLog.task_id == t.task_id)
        .order_by(TaskProgressLog.log_id.desc())
        .first()
    )
    assert log.action == "reopen"
    assert (log.from_status, log.to_status) == ("completed", "in_progress")
    assert log.reason == "Client rejected the plastering finish"
    assert log.note == "Client rejected the plastering finish"
    assert log.changed_by_id == sup.supervisor_id
    assert log.changed_by_name == "Alice Tan"
    assert log.created_at is not None


def test_reopen_to_pending_resets_progress_and_is_visible_in_logs(client, db):
    p = make_project(db)
    t = make_completed_task(db, p.project_id)
    make_supervisor(db)

    resp = client.post(
        f"/api/tasks/{t.task_id}/reopen",
        json={"reason": "Wrong task marked done", "status": "pending"},
        headers=auth(),
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["to_status"] == "pending"

    db.expire_all()
    task = db.get(Task, t.task_id)
    assert task.status == "pending"
    assert task.progress == 0
    assert task.completed_at is None

    # The audit fields are exposed by the timeline endpoint the front-end reads.
    logs = client.get(f"/api/tasks/{t.task_id}/logs").json()
    assert logs[0]["action"] == "reopen"
    assert logs[0]["changed_by_name"] == "Boss"
    assert logs[0]["reason"] == "Wrong task marked done"
    assert logs[0]["to_status"] == "pending"


def test_reopen_keeps_partial_progress_when_present(client, db):
    p = make_project(db)
    t = make_completed_task(db, p.project_id, progress=70)
    make_supervisor(db)

    resp = client.post(
        f"/api/tasks/{t.task_id}/reopen",
        json={"reason": "Snag list still open"},
        headers=auth(),
    )
    assert resp.status_code == 200, resp.text
    db.expire_all()
    assert db.get(Task, t.task_id).progress == 70


def test_reopen_recomputes_project_progress(client, db):
    p = make_project(db)
    t = make_completed_task(db, p.project_id)
    make_supervisor(db)

    db.refresh(p)
    before = p.progress
    resp = client.post(
        f"/api/tasks/{t.task_id}/reopen",
        json={"reason": "Recheck site"},
        headers=auth(),
    )
    assert resp.status_code == 200, resp.text

    db.expire_all()
    project = db.get(Project, p.project_id)
    # Single task went completed -> in_progress, so the project can no longer be
    # reported as fully done.
    assert project.progress < 100
    assert project.progress != before or before < 100


# ── guards ──────────────────────────────────────────────────────────────────

def test_reopen_requires_reason(client, db):
    p = make_project(db)
    t = make_completed_task(db, p.project_id)
    make_supervisor(db)

    for payload in ({}, {"reason": ""}, {"reason": "   "}):
        resp = client.post(f"/api/tasks/{t.task_id}/reopen", json=payload, headers=auth())
        assert resp.status_code == 400, resp.text
        assert "reason" in resp.json()["detail"].lower()

    db.expire_all()
    assert db.get(Task, t.task_id).status == "completed"


def test_reopen_rejects_unknown_target_status(client, db):
    p = make_project(db)
    t = make_completed_task(db, p.project_id)
    make_supervisor(db)

    resp = client.post(
        f"/api/tasks/{t.task_id}/reopen",
        json={"reason": "typo", "status": "blocked"},
        headers=auth(),
    )
    assert resp.status_code == 400, resp.text
    assert "in_progress" in resp.json()["detail"]


def test_reopen_rejects_non_completed_task(client, db):
    p = make_project(db)
    t = Task(task_name="Ongoing", project_id=p.project_id, status="in_progress", priority="low")
    db.add(t)
    db.commit()
    make_supervisor(db)

    resp = client.post(
        f"/api/tasks/{t.task_id}/reopen",
        json={"reason": "not applicable"},
        headers=auth(),
    )
    assert resp.status_code == 400, resp.text
    assert "Only a completed task" in resp.json()["detail"]


def test_reopen_unknown_task_returns_404(client, db):
    make_supervisor(db)
    resp = client.post(
        "/api/tasks/999999/reopen",
        json={"reason": "ghost"},
        headers=auth(),
    )
    assert resp.status_code == 404


def test_reopen_forbidden_for_worker(client, db):
    p = make_project(db)
    t = make_completed_task(db, p.project_id)
    db.add(Worker(name="Ali", trade="electrician", email="ali@site.com",
                  password_hash="x", role="worker", project_id=p.project_id))
    db.commit()

    resp = client.post(
        f"/api/tasks/{t.task_id}/reopen",
        json={"reason": "I want it back"},
        headers=auth("ali@site.com", "worker"),
    )
    assert resp.status_code == 403, resp.text

    db.expire_all()
    assert db.get(Task, t.task_id).status == "completed"
    assert db.query(TaskProgressLog).filter(TaskProgressLog.task_id == t.task_id).count() == 0


def test_reopen_requires_authentication(client, db):
    p = make_project(db)
    t = make_completed_task(db, p.project_id)
    resp = client.post(f"/api/tasks/{t.task_id}/reopen", json={"reason": "anonymous"})
    assert resp.status_code == 401
