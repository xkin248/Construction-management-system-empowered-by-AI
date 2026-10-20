"""Regression tests for GET/PUT /api/notifications/settings.

Two defects are covered:

1. ``/notifications/settings`` used to be swallowed by the dynamic route
   ``/notifications/{notification_id}`` and answered 422 ("settings" parsed as
   an int id), which made the Flutter settings dialog save button look dead.
2. The endpoint only ever resolved a ``supervisor_id`` row, so a worker account
   crashed with 500 on its own settings.

The tests mount the real router and override the ``cu`` dependency, so no JWT
or production database is involved.
"""
import os
import sys

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

BACKEND_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if BACKEND_ROOT not in sys.path:
    sys.path.insert(0, BACKEND_ROOT)

from app.database import Base, get_db  # noqa: E402
from app import models  # noqa: E402,F401  (register every table)
from app.routers.auth import cu  # noqa: E402
from app.routers.notifications import router as notifications_router  # noqa: E402
from app.schemas import CurrentUser  # noqa: E402


@pytest.fixture()
def session_factory():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    yield sessionmaker(autocommit=False, autoflush=False, bind=engine)
    Base.metadata.drop_all(engine)
    engine.dispose()


def _client(session_factory, current_user):
    app = FastAPI(title="test")
    app.include_router(notifications_router, prefix="/api")

    def override_get_db():
        session = session_factory()
        try:
            yield session
        finally:
            session.close()

    app.dependency_overrides[get_db] = override_get_db
    app.dependency_overrides[cu] = lambda: current_user
    return TestClient(app)


def _seed_worker(session_factory):
    session = session_factory()
    session.add(models.Worker(name="test1", role="worker", email="worker@example.com"))
    session.commit()
    worker = session.query(models.Worker).first()
    worker_id = worker.worker_id
    session.close()
    return worker_id


def _seed_supervisor(session_factory):
    session = session_factory()
    session.add(
        models.Supervisor(
            full_name="sup", email="sup@example.com", password_hash="x"
        )
    )
    session.commit()
    sup = session.query(models.Supervisor).first()
    sup_id = sup.supervisor_id
    session.close()
    return sup_id


def test_worker_settings_route_is_not_swallowed_by_dynamic_route(session_factory):
    worker_id = _seed_worker(session_factory)
    client = _client(
        session_factory,
        CurrentUser(
            user_type="worker",
            id=worker_id,
            email="worker@example.com",
            name="test1",
            role="worker",
            worker_id=worker_id,
        ),
    )

    res = client.get("/api/notifications/settings")
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["scope"] == "worker"
    assert body["setting_id"] > 0
    assert body["notif_attendance"] is True


def test_worker_can_update_own_settings(session_factory):
    worker_id = _seed_worker(session_factory)
    client = _client(
        session_factory,
        CurrentUser(
            user_type="worker",
            id=worker_id,
            email="worker@example.com",
            name="test1",
            role="worker",
            worker_id=worker_id,
        ),
    )

    payload = {
        "notif_attendance": False,
        "notif_task_overdue": True,
        "notif_task_assigned": False,
        "notif_issue": True,
        "notif_safety": True,
        "notif_daily_report": True,
        "notif_email": False,
        "notif_push": True,
    }
    res = client.put("/api/notifications/settings", json=payload)
    assert res.status_code == 200, res.text
    assert res.json()["notif_daily_report"] is True

    # A single row per worker is reused, so the second read reflects the write.
    res = client.get("/api/notifications/settings")
    assert res.status_code == 200
    body = res.json()
    assert body["notif_attendance"] is False
    assert body["notif_push"] is True

    session = session_factory()
    assert session.query(models.WorkerNotificationSetting).count() == 1
    session.close()


def test_supervisor_settings_stay_on_supervisor_scope(session_factory):
    sup_id = _seed_supervisor(session_factory)
    client = _client(
        session_factory,
        CurrentUser(
            user_type="supervisor",
            id=sup_id,
            email="sup@example.com",
            name="sup",
            role="supervisor",
            supervisor_id=sup_id,
        ),
    )

    res = client.get("/api/notifications/settings")
    assert res.status_code == 200, res.text
    assert res.json()["scope"] == "supervisor"
