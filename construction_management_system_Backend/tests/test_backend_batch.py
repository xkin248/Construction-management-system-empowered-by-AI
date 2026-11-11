"""Backend batch tests: task deletion status recalc, GET /projects derived
status, and auto-assign same_project_only filtering.

All tests run against an in-memory SQLite database; the production Supabase
engine configured in .env is never touched.
"""
from app.models import Project, Supervisor, Task, Worker
from app import ai_service
from app.ai_service import auto_assign_tasks
from app.routers.auth import mk_tok


# ── seed helpers ────────────────────────────────────────────────────────────

def make_project(db, name="Project A", status="planning", progress=0.0):
    supervisor = db.query(Supervisor).filter(Supervisor.email == "batch@example.com").first()
    if supervisor is None:
        supervisor = Supervisor(
            full_name="Batch Supervisor",
            email="batch@example.com",
            password_hash="x",
            role="site_supervisor",
        )
        db.add(supervisor)
        db.flush()
    p = Project(
        project_name=name,
        location_address="123 Jalan Test",
        status=status,
        progress=progress,
        supervisor_id=supervisor.supervisor_id,
    )
    db.add(p)
    db.commit()
    db.refresh(p)
    return p


def supervisor_headers():
    return {"Authorization": f"Bearer {mk_tok('batch@example.com', 'supervisor')}"}


def make_task(db, project_id, status="pending", name="Task"):
    t = Task(task_name=name, project_id=project_id, status=status, priority="medium")
    db.add(t)
    db.commit()
    db.refresh(t)
    return t


def make_worker(db, name, trade, project_id=None):
    w = Worker(name=name, trade=trade, project_id=project_id)
    db.add(w)
    db.commit()
    db.refresh(w)
    return w


# ── 1. DELETE /tasks/{task_id} recalcs project progress/status ─────────────

def test_delete_task_recalcs_project_status(client, db):
    # Stale DB: project stored as "planning" although it already has tasks
    # (simulates the historical "has tasks but shows planning" bug).
    p = make_project(db, "Old Data", status="planning")
    t1 = make_task(db, p.project_id, status="completed", name="Done 1")
    t2 = make_task(db, p.project_id, status="completed", name="Done 2")
    t3 = make_task(db, p.project_id, status="pending", name="Still pending")

    resp = client.delete(f"/api/tasks/{t3.task_id}", headers=supervisor_headers())
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["status"] == "ok"
    assert body["project_id"] == p.project_id

    db.expire_all()
    p = db.get(Project, p.project_id)
    # Both remaining tasks completed -> project must move to completed.
    assert p.status == "completed"
    assert p.progress == 100.0


def test_delete_task_last_task_returns_to_planning(client, db):
    p = make_project(db, "Solo", status="in_progress", progress=50.0)
    t = make_task(db, p.project_id, status="pending", name="Only task")

    resp = client.delete(f"/api/tasks/{t.task_id}", headers=supervisor_headers())
    assert resp.status_code == 200, resp.text

    db.expire_all()
    p = db.get(Project, p.project_id)
    assert p.status == "planning"
    assert p.progress == 0.0
    assert db.query(Task).filter(Task.project_id == p.project_id).count() == 0


def test_delete_task_not_found(client, db):
    # Seed the authenticated supervisor even though the requested task ID is absent.
    make_project(db)
    resp = client.delete("/api/tasks/99999", headers=supervisor_headers())
    assert resp.status_code == 404


# ── 2. GET /projects (list & detail) derive status from tasks ──────────────

def test_projects_list_derives_status(client, db):
    p_planning = make_project(db, "Empty", status="planning")
    p_stale = make_project(db, "Has tasks stale", status="planning")  # stored planning
    make_task(db, p_stale.project_id, status="in_progress", name="Active")
    p_done = make_project(db, "All done", status="in_progress")  # stored in_progress
    make_task(db, p_done.project_id, status="completed", name="Closed 1")
    make_task(db, p_done.project_id, status="completed", name="Closed 2")

    resp = client.get("/api/projects", headers=supervisor_headers())
    assert resp.status_code == 200, resp.text
    rows = {r["project_id"]: r for r in resp.json()}

    assert rows[p_planning.project_id]["status"] == "planning"   # no tasks
    assert rows[p_stale.project_id]["status"] == "in_progress"   # has active task
    assert rows[p_done.project_id]["status"] == "completed"      # all tasks completed

    # Read path must NOT persist the derived value back into the DB.
    db.expire_all()
    raw = db.get(Project, p_stale.project_id)
    assert raw.status == "planning"


def test_project_detail_derives_status(client, db):
    p = make_project(db, "Detail stale", status="planning")
    make_task(db, p.project_id, status="completed", name="Done")
    make_task(db, p.project_id, status="pending", name="Pending")

    resp = client.get(f"/api/projects/{p.project_id}", headers=supervisor_headers())
    assert resp.status_code == 200, resp.text
    assert resp.json()["status"] == "in_progress"

    db.expire_all()
    assert db.get(Project, p.project_id).status == "planning"  # not written


# ── 3. auto-assign same_project_only filtering ─────────────────────────────

def test_auto_assign_same_project_only_restricts_pool(db):
    p_a = make_project(db, "Proj A")
    p_b = make_project(db, "Proj B")
    w_a = make_worker(db, "Ali", trade="electric", project_id=p_a.project_id)
    w_b = make_worker(db, "Bob", trade="electric", project_id=p_b.project_id)
    t = make_task(db, p_a.project_id, status="pending", name="Install electrical wiring")

    # Default (whole worker pool): Bob from the other project is reachable.
    broad = auto_assign_tasks(
        db, project_id=p_a.project_id, task_ids=[t.task_id],
        dry_run=True, top_k=3, same_project_only=False,
    )
    broad_ids = {s.get("worker_id") for a in broad["assignments"] for s in (a["suggested_workers"] or [])}
    assert w_b.worker_id in broad_ids
    assert w_a.worker_id in broad_ids

    # same_project_only=True: only workers bound to Proj A may appear.
    restricted = auto_assign_tasks(
        db, project_id=p_a.project_id, task_ids=[t.task_id],
        dry_run=True, top_k=3, same_project_only=True,
    )
    restricted_ids = {
        s.get("worker_id")
        for a in restricted["assignments"]
        for s in (a["suggested_workers"] or [])
    }
    assert w_a.worker_id in restricted_ids
    assert restricted_ids == {w_a.worker_id}

    # Safe default: callers that omit the flag must not pull staff from a
    # different project. A supervisor can still deliberately pass False above.
    default_scoped = auto_assign_tasks(
        db, project_id=p_a.project_id, task_ids=[t.task_id], dry_run=True, top_k=3,
    )
    default_ids = {
        s.get("worker_id")
        for assignment in default_scoped["assignments"]
        for s in (assignment["suggested_workers"] or [])
    }
    assert default_ids == {w_a.worker_id}


def test_auto_assign_never_assigns_a_worker_below_the_required_level(db, monkeypatch):
    """A larger top_k must not turn lower-ranked suggestions into assignees."""
    monkeypatch.setattr(ai_service, "get_gemini_model", lambda: None)
    project = make_project(db, "Skill floor")
    foreman = make_worker(db, "Foreman Fara", trade="foreman", project_id=project.project_id)
    skilled = make_worker(db, "Skilled Sam", trade="skilled worker", project_id=project.project_id)
    semi = make_worker(db, "Semi Siti", trade="semi skilled worker", project_id=project.project_id)
    general = make_worker(db, "General Gan", trade="general worker", project_id=project.project_id)
    task = Task(
        task_name="Coordinate workfront",
        description="Inspect completed work and brief the crew.",
        trade="foreman",
        project_id=project.project_id,
        status="pending",
    )
    db.add(task)
    db.commit()

    result = auto_assign_tasks(
        db, project_id=project.project_id, task_ids=[task.task_id],
        dry_run=True, top_k=3, same_project_only=True,
    )

    assignment = result["assignments"][0]
    assert assignment["assigned_worker_ids"] == [foreman.worker_id]
    assert skilled.worker_id not in assignment["assigned_worker_ids"]
    assert semi.worker_id not in assignment["assigned_worker_ids"]
    assert general.worker_id not in assignment["assigned_worker_ids"]


def test_auto_assign_requires_the_task_specialty_when_one_is_set(db, monkeypatch):
    monkeypatch.setattr(ai_service, "get_gemini_model", lambda: None)
    project = make_project(db, "Specialty matching")
    electrician = Worker(
        name="Eli Electrical", trade="skilled worker", specialties=["electrical"],
        project_id=project.project_id,
    )
    plumber = Worker(
        name="Pia Plumbing", trade="skilled worker", specialties=["plumbing"],
        project_id=project.project_id,
    )
    task = Task(
        task_name="Terminate DB cables", trade="skilled worker",
        required_specialty="electrical", project_id=project.project_id, status="pending",
    )
    db.add_all([electrician, plumber, task])
    db.commit()

    result = auto_assign_tasks(
        db, project_id=project.project_id, task_ids=[task.task_id],
        dry_run=True, top_k=3, same_project_only=True,
    )

    assert result["assignments"][0]["assigned_worker_ids"] == [electrician.worker_id]
