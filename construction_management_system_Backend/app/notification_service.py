import asyncio
from typing import Optional, List
from datetime import datetime
from sqlalchemy.orm import Session

from app.models import Notification, NotificationSetting, Supervisor, WorkerNotificationSetting


def _push_websocket(supervisor_id: int, notification: Notification) -> None:
    """Best-effort delivery to a supervisor that currently has the
    ``/ws/notifications`` socket open. The in-app row is already committed at
    this point, so any failure here must stay silent."""
    try:
        from app.routers import notifications as notif_router

        loop = notif_router.get_event_loop_ref()
        if loop is None or not loop.is_running():
            return
        payload = {
            "notification_id": notification.notification_id,
            "notification_type": notification.notification_type,
            "title": notification.title,
            "content": notification.content,
            "related_entity_type": notification.related_entity_type,
            "related_entity_id": notification.related_entity_id,
        }
        asyncio.run_coroutine_threadsafe(
            notif_router.notify_user(supervisor_id, payload), loop
        )
    except Exception:
        pass


def get_or_create_worker_settings(db: Session, worker_id: int) -> WorkerNotificationSetting:
    """Worker-scoped counterpart of ``get_or_create_settings``."""
    settings = db.query(WorkerNotificationSetting).filter(
        WorkerNotificationSetting.worker_id == worker_id
    ).first()

    if not settings:
        settings = WorkerNotificationSetting(worker_id=worker_id)
        db.add(settings)
        db.commit()
        db.refresh(settings)

    return settings


def send_notification(
    db: Session,
    supervisor_id: int,
    notification_type: str,
    title: str,
    content: str,
    related_entity_type: Optional[str] = None,
    related_entity_id: Optional[int] = None
) -> Notification:
    settings = get_or_create_settings(db, supervisor_id)
    
    type_field = f"notif_{notification_type.lower()}"
    if hasattr(settings, type_field) and not getattr(settings, type_field):
        return None

    notification = Notification(
        supervisor_id=supervisor_id,
        notification_type=notification_type,
        title=title,
        content=content,
        related_entity_type=related_entity_type,
        related_entity_id=related_entity_id
    )
    db.add(notification)
    db.commit()
    db.refresh(notification)
    _push_websocket(supervisor_id, notification)
    return notification


def get_or_create_settings(db: Session, supervisor_id: int) -> NotificationSetting:
    settings = db.query(NotificationSetting).filter(
        NotificationSetting.supervisor_id == supervisor_id
    ).first()
    
    if not settings:
        settings = NotificationSetting(supervisor_id=supervisor_id)
        db.add(settings)
        db.commit()
        db.refresh(settings)
    
    return settings


def notify_task_assigned(
    db: Session,
    supervisor_id: int,
    task_name: str,
    worker_name: str,
    task_id: Optional[int] = None,
):
    return send_notification(
        db=db,
        supervisor_id=supervisor_id,
        notification_type="task_assigned",
        title="New task assigned",
        content=f"Task \"{task_name}\" has been assigned to {worker_name}",
        related_entity_type="task",
        related_entity_id=task_id,
    )


def notify_task_overdue(
    db: Session,
    supervisor_id: int,
    task_name: str,
    project_name: str,
    days_overdue: int = 0,
    task_id: Optional[int] = None,
):
    suffix = f" ({days_overdue} day(s) overdue)" if days_overdue > 0 else ""
    return send_notification(
        db=db,
        supervisor_id=supervisor_id,
        notification_type="task_overdue",
        title="Task overdue",
        content=f"Task \"{task_name}\" on project \"{project_name}\" is past its due date{suffix}",
        related_entity_type="task",
        related_entity_id=task_id,
    )


def notify_issue_created(
    db: Session,
    supervisor_id: int,
    issue_title: str,
    project_name: str,
    issue_id: Optional[int] = None,
):
    return send_notification(
        db=db,
        supervisor_id=supervisor_id,
        notification_type="issue",
        title="New issue reported",
        content=f"Project \"{project_name}\" has a new issue: {issue_title}",
        related_entity_type="issue",
        related_entity_id=issue_id,
    )


def notify_safety_incident(
    db: Session,
    supervisor_id: int,
    incident_title: str,
    project_name: str,
    issue_id: Optional[int] = None,
):
    return send_notification(
        db=db,
        supervisor_id=supervisor_id,
        notification_type="safety",
        title="Safety incident reported",
        content=f"A safety incident occurred on project \"{project_name}\": {incident_title}",
        related_entity_type="issue",
        related_entity_id=issue_id,
    )


def notify_attendance_alert(
    db: Session,
    supervisor_id: int,
    worker_name: str,
    status: str,
    worker_id: Optional[int] = None,
):
    return send_notification(
        db=db,
        supervisor_id=supervisor_id,
        notification_type="attendance",
        title="Attendance alert",
        content=f"{worker_name} {status}",
        related_entity_type="worker",
        related_entity_id=worker_id,
    )


def notify_daily_report_reminder(
    db: Session,
    supervisor_id: int,
    project_name: str,
    project_id: Optional[int] = None,
):
    return send_notification(
        db=db,
        supervisor_id=supervisor_id,
        notification_type="daily_report",
        title="Daily report reminder",
        content=f"Please remember to submit today's daily report for project \"{project_name}\"",
        related_entity_type="project",
        related_entity_id=project_id,
    )
