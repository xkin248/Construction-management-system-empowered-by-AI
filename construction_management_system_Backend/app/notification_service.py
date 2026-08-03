from typing import Optional, List
from datetime import datetime
from sqlalchemy.orm import Session

from app.models import Notification, NotificationSetting, Supervisor


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


def notify_task_assigned(db: Session, supervisor_id: int, task_name: str, worker_name: str):
    return send_notification(
        db=db,
        supervisor_id=supervisor_id,
        notification_type="task_assigned",
        title="新任务已分配",
        content=f"任务「{task_name}」已分配给 {worker_name}",
        related_entity_type="task"
    )


def notify_issue_created(db: Session, supervisor_id: int, issue_title: str, project_name: str):
    return send_notification(
        db=db,
        supervisor_id=supervisor_id,
        notification_type="issue",
        title="新问题报告",
        content=f"项目「{project_name}」有新问题：{issue_title}",
        related_entity_type="issue"
    )


def notify_safety_incident(db: Session, supervisor_id: int, incident_title: str, project_name: str):
    return send_notification(
        db=db,
        supervisor_id=supervisor_id,
        notification_type="safety",
        title="⚠️ 安全事件报告",
        content=f"项目「{project_name}」发生安全事件：{incident_title}",
        related_entity_type="issue"
    )


def notify_attendance_alert(db: Session, supervisor_id: int, worker_name: str, status: str):
    return send_notification(
        db=db,
        supervisor_id=supervisor_id,
        notification_type="attendance",
        title="考勤异常提醒",
        content=f"{worker_name} {status}",
        related_entity_type="worker"
    )


def notify_daily_report_reminder(db: Session, supervisor_id: int, project_name: str):
    return send_notification(
        db=db,
        supervisor_id=supervisor_id,
        notification_type="daily_report",
        title="日报提交提醒",
        content=f"请记得提交项目「{project_name}」的今日日报",
        related_entity_type="project"
    )
