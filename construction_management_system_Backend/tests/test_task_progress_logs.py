"""C-batch tests: task progress/completion_note fields, automatic
task_progress_logs timeline entries, and the dual-dialect migration helpers.

All tests run against in-memory SQLite databases; the production Supabase
engine configured in .env is never touched.
"""
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.database import Base
from app.db_migrate import ensure_task_progress_columns
from app.models import Project, Task, TaskProgressLog


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


# ── 1. progress validation & automatic timeline entries ────────────────────

def test_progress_update_writes_log_and_serializes(client, db):
    p = make_project(db)
    t = make_task(db, p.project_id, status="pending")

    resp = client.put(f"/api/tasks/{t.task_id}", json={"progress": 70, "note": "Foundation done"})
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["progress"] == 70

    db.expire_all()
    t = db.get(Task, t.task_id)
    assert t.progress == 70
    assert t.status == "in_progress"  # progress 70 derives in_progress (legal move)

    logs = (
        db.query(TaskProgressLog)
        .filter(TaskProgressLog.task_id == t.task_id)
        .order_by(TaskProgressLog.log_id)
        .all()
    )
    assert len(logs) == 1
    assert logs[0].from_status == "pending"
    assert logs[0].to_status == "in_progress"
    assert logs[0].note == "Foundation done"

    # Pure progress change while staying in_progress: from == to.
    resp = client.put(f"/api/tasks/{t.task_id}", json={"progress": 85})
    assert resp.status_code == 200, resp.text
    db.expire_all()
    logs = (
        db.query(TaskProgressLog)
        .filter(TaskProgressLog.task_id == t.task_id)
        .order_by(TaskProgressLog.log_id)
        .all()
    )
    assert len(logs) == 2
    assert logs[1].from_status == "in_progress"
    assert logs[1].to_status == "in_progress"
    assert logs[1].note is None


def test_progress_out_of_range_rejected(client, db):
    p = make_project(db)
    t = make_task(db, p.project_id)
    assert client.put(f"/api/tasks/{t.task_id}", json={"progress": 101}).status_code == 400
    assert client.put(f"/api/tasks/{t.task_id}", json={"progress": -1}).status_code == 400
    assert client.put(f"/api/tasks/{t.task_id}", json={"progress": "abc"}).status_code == 400


# ── 2. completion requires a non-empty note ────────────────────────────────

def test_completed_requires_note(client, db):
    p = make_project(db)
    t = make_task(db, p.project_id, status="in_progress")

    # Missing / blank note must be rejected with 400.
    assert (
        client.put(f"/api/tasks/{t.task_id}", json={"status": "completed"}).status_code
        == 400
    )
    assert (
        client.put(
            f"/api/tasks/{t.task_id}", json={"status": "completed", "completion_note": "   "}
        ).status_code
        == 400
    )

    resp = client.put(
        f"/api/tasks/{t.task_id}",
        json={"status": "completed", "completion_note": "All walls poured"},
    )
    assert resp.status_code == 200, resp.text
    db.expire_all()
    t = db.get(Task, t.task_id)
    assert t.status == "completed"
    assert t.completion_note == "All walls poured"
    assert t.completed_at is not None
    logs = db.query(TaskProgressLog).filter(TaskProgressLog.task_id == t.task_id).all()
    assert len(logs) == 1
    assert logs[0].from_status == "in_progress"
    assert logs[0].to_status == "completed"
    assert logs[0].note == "All walls poured"


def test_progress_100_completion_bypass_requires_note(client, db):
    """Pulling progress to 100 implies completed -> note is still mandatory."""
    p = make_project(db)
    t = make_task(db, p.project_id, status="in_progress")
    assert (
        client.put(f"/api/tasks/{t.task_id}", json={"progress": 100}).status_code == 400
    )
    resp = client.put(
        f"/api/tasks/{t.task_id}",
        json={"progress": 100, "completion_note": "Final inspection passed"},
    )
    assert resp.status_code == 200, resp.text
    db.expire_all()
    t = db.get(Task, t.task_id)
    assert t.status == "completed"
    assert t.completion_note == "Final inspection passed"


# ── 3. GET /tasks/{id}/logs newest first ───────────────────────────────────

def test_logs_endpoint_newest_first(client, db):
    p = make_project(db)
    t = make_task(db, p.project_id, status="pending")
    client.put(f"/api/tasks/{t.task_id}", json={"status": "in_progress"})
    client.put(f"/api/tasks/{t.task_id}", json={"progress": 60, "note": "60% mark"})
    client.put(
        f"/api/tasks/{t.task_id}",
        json={"status": "completed", "completion_note": "Wrapped up"},
    )

    resp = client.get(f"/api/tasks/{t.task_id}/logs")
    assert resp.status_code == 200, resp.text
    logs = resp.json()
    assert len(logs) == 3
    assert logs[0]["to_status"] == "completed"
    assert logs[0]["note"] == "Wrapped up"
    assert logs[1]["to_status"] == "in_progress"
    assert logs[1]["from_status"] == "in_progress"
    assert logs[2]["to_status"] == "in_progress"

    assert client.get("/api/tasks/999999/logs").status_code == 404


# ── 4. migration: old DB -> ALTER, new DB -> create_all, idempotency ───────

def _old_schema_engine():
    """SQLite DB that mirrors a pre-C database (tasks without the new columns)."""
    eng = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    with eng.begin() as conn:
        conn.execute(text("CREATE TABLE projects (project_id INTEGER PRIMARY KEY, project_name VARCHAR(200) NOT NULL)"))
        conn.execute(text("CREATE TABLE workers (worker_id INTEGER PRIMARY KEY, name VARCHAR(200) NOT NULL, trade VARCHAR(100))"))
        conn.execute(text(
            "CREATE TABLE tasks (task_id INTEGER PRIMARY KEY, task_name VARCHAR(200) NOT NULL, "
            "project_id INTEGER NOT NULL REFERENCES projects(project_id), status VARCHAR(50) DEFAULT 'pending', "
            "started_at DATETIME, completed_at DATETIME)"
        ))
    return eng


def test_migration_old_db_adds_columns_then_idempotent():
    eng = _old_schema_engine()
    try:
        added = ensure_task_progress_columns(eng)
        assert added == ["tasks.progress", "tasks.completion_note"]
        cols = {c["name"] for c in inspect(eng).get_columns("tasks")}
        assert {"progress", "completion_note"} <= cols
        # Running again must be a no-op.
        assert ensure_task_progress_columns(eng) == []
    finally:
        eng.dispose()


def test_migration_new_db_create_all_has_log_table():
    """A fresh database gets task_progress_logs via create_all."""
    eng = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    try:
        Base.metadata.create_all(eng)
        tables = set(inspect(eng).get_table_names())
        assert "task_progress_logs" in tables
        cols = {c["name"] for c in inspect(eng).get_columns("tasks")}
        assert {"progress", "completion_note"} <= cols
    finally:
        eng.dispose()
