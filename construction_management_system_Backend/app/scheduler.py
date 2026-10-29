"""Background notification sweeper.

The notification *feed* (in-app rows + WebSocket/FCM push) is written by
``app.notification_service`` at the moment a business event happens, e.g. a
safety incident is reported or a worker checks in outside the geofence.  Two
notification types have no such trigger because they are *time* driven:

* ``task_overdue``     - a task's ``due_date`` has passed and it is not completed
* ``daily_report``     - the supervisor has not filed today's daily report

This module owns those two.  A single daemon thread wakes up every
``NOTIFY_SWEEP_INTERVAL_SECONDS`` (default 30 min), scans once, and writes at
most one notification per subject per day, so the feed never floods.

Environment switches:

* ``ENABLE_NOTIFY_SCHEDULER=0``  -> do not start the thread (tests, CI)
* ``NOTIFY_SWEEP_INTERVAL_SECONDS=<n>`` -> sweep period
* ``NOTIFY_SWEEP_INITIAL_DELAY_SECONDS=<n>`` -> wait before the first sweep
"""

from __future__ import annotations

import logging
import os
import threading
from datetime import date, datetime

logger = logging.getLogger("buildsmart.scheduler")

DEFAULT_INTERVAL_SECONDS = 1800
DEFAULT_INITIAL_DELAY_SECONDS = 120

# Statuses that mean "still owes work". Only "completed" is terminal in this app.
_OPEN_TASK_STATUSES = ("pending", "in_progress")

_stop_event = threading.Event()
_thread: threading.Thread | None = None


def _env_int(name: str, default: int) -> int:
    raw = os.getenv(name)
    if not raw:
        return default
    try:
        return max(1, int(raw))
    except ValueError:
        return default


def _enabled() -> bool:
    return os.getenv("ENABLE_NOTIFY_SCHEDULER", "1").strip().lower() not in (
        "0", "false", "no", "off",
    )


def _utc_day_start() -> datetime:
    now = datetime.utcnow()
    return now.replace(hour=0, minute=0, second=0, microsecond=0)


def _already_notified(db, supervisor_id: int, ntype: str, entity: str, entity_id) -> bool:
    """True when a notification of this type for this subject was already
    written today (dedupe key = type + related entity + calendar day)."""
    from app.models import Notification

    return (
        db.query(Notification)
        .filter(
            Notification.supervisor_id == supervisor_id,
            Notification.notification_type == ntype,
            Notification.related_entity_type == entity,
            Notification.related_entity_id == entity_id,
            Notification.created_at >= _utc_day_start(),
        )
        .count()
        > 0
    )


def sweep_overdue_tasks(db) -> int:
    """Notify supervisors about tasks whose due date has passed."""
    from app.models import Project, Task
    from app.notification_service import notify_task_overdue

    today = date.today()
    sent = 0
    overdue = (
        db.query(Task)
        .filter(
            Task.due_date.isnot(None),
            Task.due_date < today,
            Task.status.in_(_OPEN_TASK_STATUSES),
        )
        .all()
    )
    for task in overdue:
        project = db.query(Project).get(task.project_id)
        if not project or not project.supervisor_id:
            continue
        if _already_notified(db, project.supervisor_id, "task_overdue", "task", task.task_id):
            continue
        days_overdue = (today - task.due_date).days
        result = notify_task_overdue(
            db,
            project.supervisor_id,
            task.task_name,
            project.project_name,
            days_overdue=days_overdue,
            task_id=task.task_id,
        )
        if result is not None:
            sent += 1
            logger.info(
                "task_overdue notification sent: task=%s supervisor=%s (%s day(s))",
                task.task_id, project.supervisor_id, days_overdue,
            )
    return sent


def sweep_daily_report_reminders(db) -> int:
    """Remind supervisors who have not filed today's daily report.

    ``notif_daily_report`` defaults to OFF in ``NotificationSetting``, so this
    sweep is a no-op until the supervisor opts in.
    """
    from app.models import DailyReport, Project
    from app.notification_service import notify_daily_report_reminder

    today = date.today()
    sent = 0
    projects = (
        db.query(Project)
        .filter(Project.supervisor_id.isnot(None))
        .all()
    )
    for project in projects:
        filed = (
            db.query(DailyReport)
            .filter(
                DailyReport.project_id == project.project_id,
                DailyReport.report_date == today,
            )
            .count()
        )
        if filed:
            continue
        if _already_notified(
            db, project.supervisor_id, "daily_report", "project", project.project_id
        ):
            continue
        result = notify_daily_report_reminder(
            db, project.supervisor_id, project.project_name, project.project_id
        )
        if result is not None:
            sent += 1
    return sent


def run_sweep() -> dict:
    """Run one sweep. Imported lazily so the module stays cheap to import."""
    from app.database import SessionLocal

    stats = {"overdue": 0, "daily_report": 0, "error": ""}
    db = SessionLocal()
    try:
        stats["overdue"] = sweep_overdue_tasks(db)
        stats["daily_report"] = sweep_daily_report_reminders(db)
    except Exception as exc:  # a bad sweep must never kill the thread
        db.rollback()
        stats["error"] = f"{type(exc).__name__}: {exc}".splitlines()[0]
        logger.error("notification sweep failed: %s", stats["error"])
    finally:
        db.close()
    return stats


def _runner(initial_delay: int, interval: int) -> None:
    if _stop_event.wait(initial_delay):
        return
    while True:
        run_sweep()
        if _stop_event.wait(interval):
            return


def start_scheduler() -> bool:
    """Start the sweeper once. Returns True when the thread is running."""
    global _thread
    if not _enabled():
        logger.info("notification scheduler disabled by ENABLE_NOTIFY_SCHEDULER")
        return False
    if _thread and _thread.is_alive():
        return True
    initial = _env_int("NOTIFY_SWEEP_INITIAL_DELAY_SECONDS", DEFAULT_INITIAL_DELAY_SECONDS)
    interval = _env_int("NOTIFY_SWEEP_INTERVAL_SECONDS", DEFAULT_INTERVAL_SECONDS)
    _stop_event.clear()
    _thread = threading.Thread(
        target=_runner, args=(initial, interval), name="buildsmart-notify-sweeper", daemon=True
    )
    _thread.start()
    logger.info(
        "notification scheduler started (first sweep in %ss, then every %ss)", initial, interval
    )
    return True


def stop_scheduler() -> None:
    _stop_event.set()
