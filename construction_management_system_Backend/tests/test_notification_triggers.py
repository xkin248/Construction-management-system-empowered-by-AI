"""Notification write-path tests.

The supervisor notification feed used to be read-only in practice: the
``Notification`` table had readers (list / unread-count / mark-read) but the
``notify_*`` helpers in ``app.notification_service`` were never called, and the
``/ws/notifications`` socket had no producer. These tests pin the three
triggers that now exist:

1. a safety incident -> supervisor feed row + worker inbox row for the officer
2. a check-in outside the geofence -> attendance alert for the supervisor
3. the background sweeper -> ``task_overdue`` / ``daily_report`` rows, deduped
   to one per subject per day
"""
import datetime as dt

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.database import get_db
from app.models import (
    DailyReport,
    Notification,
    NotificationSetting,
    Project,
    Supervisor,
    Task,
    Worker,
    WorkerNotification,
)
from app.routers.attendance import router as attendance_router
from app.routers.auth import mk_tok
from app.routers.safety import router as safety_router
from app import scheduler


# ── seed helpers ────────────────────────────────────────────────────────────

def make_supervisor(db, email="boss@buildsmart.com"):
    s = Supervisor(full_name="Boss", email=email, password_hash="x", role="site_supervisor")
    db.add(s)
    db.commit()
    db.refresh(s)
    return s


def make_project(db, supervisor_id, name="Project A", lat=3.1390, lng=101.6869, radius=500.0):
    p = Project(
        project_name=name,
        location_address="123 Jalan Test",
        supervisor_id=supervisor_id,
        center_lat=lat,
        center_lng=lng,
        fence_radius=radius,
    )
    db.add(p)
    db.commit()
    db.refresh(p)
    return p


def make_worker(db, project_id, name="Ali", email="ali@site.com", officer=False):
    w = Worker(
        name=name,
        project_id=project_id,
        email=email,
        password_hash="x",
        role="worker",
        is_safety_officer=officer,
        has_safety_training=officer,
    )
    db.add(w)
    db.commit()
    db.refresh(w)
    return w


@pytest.fixture()
def api(session_factory):
    """Minimal app exposing the two routers under test."""
    app = FastAPI(title="test")

    def override_get_db():
        session = session_factory()
        try:
            yield session
        finally:
            session.close()

    app.dependency_overrides[get_db] = override_get_db
    app.include_router(safety_router, prefix="/api")
    app.include_router(attendance_router, prefix="/api")
    return TestClient(app)


# ── 1. safety incident fan-out ──────────────────────────────────────────────

def test_safety_incident_notifies_supervisor_and_officer(db, api):
    sup = make_supervisor(db)
    project = make_project(db, sup.supervisor_id)
    reporter = make_worker(db, project.project_id, name="Reporter", email="rep@site.com")
    officer = make_worker(db, project.project_id, name="Officer", email="off@site.com", officer=True)

    resp = api.post(
        "/api/safety/report",
        params={
            "incident_type": "fire",
            "worker_id": reporter.worker_id,
            "project_id": project.project_id,
            "gps_lat": project.center_lat,
            "gps_lng": project.center_lng,
            "description": "Smoke near the generator",
        },
    )
    assert resp.status_code == 200, resp.text
    issue_id = resp.json()["issue_id"]

    # Supervisor feed gets exactly one safety row pointing at the incident.
    rows = db.query(Notification).filter(Notification.notification_type == "safety").all()
    assert len(rows) == 1
    assert rows[0].supervisor_id == sup.supervisor_id
    assert rows[0].related_entity_type == "issue"
    assert rows[0].related_entity_id == issue_id

    # The auto-assigned safety officer gets their own inbox row.
    worker_rows = db.query(WorkerNotification).all()
    assert len(worker_rows) == 1
    assert worker_rows[0].worker_id in {officer.worker_id}
    assert worker_rows[0].related_entity_id == issue_id


def test_non_safety_issue_report_does_not_ping_supervisor_feed(db, api):
    """"general" reports are logged as issues but are not safety incidents."""
    sup = make_supervisor(db)
    project = make_project(db, sup.supervisor_id)
    reporter = make_worker(db, project.project_id)

    resp = api.post(
        "/api/safety/report",
        params={
            "incident_type": "general",
            "worker_id": reporter.worker_id,
            "project_id": project.project_id,
            "gps_lat": project.center_lat,
            "gps_lng": project.center_lng,
        },
    )
    assert resp.status_code == 200, resp.text
    assert db.query(Notification).filter(Notification.notification_type == "safety").count() == 0


# ── 2. attendance alert on a geofence rejection ─────────────────────────────

def test_check_in_outside_geofence_alerts_supervisor(db, api):
    sup = make_supervisor(db)
    project = make_project(db, sup.supervisor_id, radius=100.0)
    worker = make_worker(db, project.project_id)

    headers = {"Authorization": f"Bearer {mk_tok('ali@site.com', 'worker')}"}
    resp = api.post(
        "/api/attendance/worker/check-in",
        json={"project_id": project.project_id, "lat": 0.0, "lng": 0.0},
        headers=headers,
    )
    assert resp.status_code == 400, resp.text
    assert "geofence" in resp.json()["detail"]

    rows = db.query(Notification).filter(Notification.notification_type == "attendance").all()
    assert len(rows) == 1
    assert rows[0].supervisor_id == sup.supervisor_id
    assert worker.name in rows[0].content
    assert rows[0].related_entity_id == worker.worker_id


def test_check_in_inside_geofence_sends_no_alert(db, api):
    sup = make_supervisor(db)
    project = make_project(db, sup.supervisor_id, radius=5000.0)
    make_worker(db, project.project_id)

    headers = {"Authorization": f"Bearer {mk_tok('ali@site.com', 'worker')}"}
    resp = api.post(
        "/api/attendance/worker/check-in",
        json={
            "project_id": project.project_id,
            "lat": project.center_lat,
            "lng": project.center_lng,
        },
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    assert db.query(Notification).filter(Notification.notification_type == "attendance").count() == 0


# ── 3. sweeper: overdue tasks ───────────────────────────────────────────────

def test_sweeper_flags_overdue_task_once_per_day(db):
    sup = make_supervisor(db)
    project = make_project(db, sup.supervisor_id)
    task = Task(
        task_name="Pour slab",
        project_id=project.project_id,
        status="pending",
        priority="high",
        due_date=dt.date.today() - dt.timedelta(days=3),
    )
    db.add(task)
    db.commit()

    assert scheduler.sweep_overdue_tasks(db) == 1
    rows = db.query(Notification).filter(Notification.notification_type == "task_overdue").all()
    assert len(rows) == 1
    assert rows[0].related_entity_id == task.task_id
    assert "3 day(s) overdue" in rows[0].content

    # Second sweep on the same day must not duplicate the alert.
    assert scheduler.sweep_overdue_tasks(db) == 0
    assert db.query(Notification).filter(Notification.notification_type == "task_overdue").count() == 1


def test_sweeper_ignores_completed_and_future_tasks(db):
    sup = make_supervisor(db)
    project = make_project(db, sup.supervisor_id)
    db.add_all([
        Task(
            task_name="Done already",
            project_id=project.project_id,
            status="completed",
            due_date=dt.date.today() - dt.timedelta(days=5),
        ),
        Task(
            task_name="Due next week",
            project_id=project.project_id,
            status="pending",
            due_date=dt.date.today() + dt.timedelta(days=7),
        ),
    ])
    db.commit()

    assert scheduler.sweep_overdue_tasks(db) == 0
    assert db.query(Notification).count() == 0


# ── 4. sweeper: daily report reminder (opt-in) ──────────────────────────────

def test_daily_report_reminder_respects_opt_in_flag(db):
    sup = make_supervisor(db)
    make_project(db, sup.supervisor_id)

    # Default notif_daily_report = 0 -> the helper short-circuits (and creates
    # the settings row on first access).
    assert scheduler.sweep_daily_report_reminders(db) == 0
    assert db.query(Notification).count() == 0

    settings_row = (
        db.query(NotificationSetting)
        .filter(NotificationSetting.supervisor_id == sup.supervisor_id)
        .one()
    )
    settings_row.notif_daily_report = True
    db.commit()

    assert scheduler.sweep_daily_report_reminders(db) == 1
    rows = db.query(Notification).filter(Notification.notification_type == "daily_report").all()
    assert len(rows) == 1
    assert rows[0].related_entity_type == "project"

    # Deduped within the same day.
    assert scheduler.sweep_daily_report_reminders(db) == 0


def test_daily_report_reminder_skipped_when_report_exists(db):
    sup = make_supervisor(db)
    project = make_project(db, sup.supervisor_id)
    db.add(NotificationSetting(supervisor_id=sup.supervisor_id, notif_daily_report=True))
    db.add(DailyReport(project_id=project.project_id, report_date=dt.date.today()))
    db.commit()

    assert scheduler.sweep_daily_report_reminders(db) == 0
    assert db.query(Notification).count() == 0


# ── 5. settings switch actually suppresses the write ────────────────────────

def test_disabled_switch_suppresses_notification(db):
    sup = make_supervisor(db)
    project = make_project(db, sup.supervisor_id)
    task = Task(
        task_name="Pump test",
        project_id=project.project_id,
        status="pending",
        due_date=dt.date.today() - dt.timedelta(days=1),
    )
    db.add(task)
    db.add(NotificationSetting(supervisor_id=sup.supervisor_id, notif_task_overdue=False))
    db.commit()

    assert scheduler.sweep_overdue_tasks(db) == 0
    assert db.query(Notification).count() == 0
