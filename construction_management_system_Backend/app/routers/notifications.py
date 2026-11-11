import asyncio
from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect
from sqlalchemy.orm import Session
from typing import List, Dict, Any, Optional
from datetime import datetime

from app.database import get_db
from app.models import Supervisor, Worker, Notification, WorkerNotification
from app.schemas import (
    NotificationOut, NotificationSettingOut,
    NotificationSettingUpdate, UnreadCountResponse
)
from app.routers.auth import cu, require_any_authorized
from app.notification_service import get_or_create_settings, get_or_create_worker_settings

router = APIRouter(tags=["🔔 Notifications"])

active_connections: Dict[int, List[WebSocket]] = {}

# Event loop captured by the first websocket handshake, so synchronous callers
# (notification_service) can schedule pushes onto it with
# ``asyncio.run_coroutine_threadsafe``.
_main_loop: Optional[Any] = None


def get_event_loop_ref():
    """Return the captured loop (None until the first socket connects)."""
    return _main_loop


# ───────────── FCM device token registration ─────────────
@router.post("/notifications/register-token")
def register_fcm_token(
    payload: Dict[str, Any],
    db: Session = Depends(get_db),
    _: Any = Depends(require_any_authorized),
):
    """Store (or replace) the caller's FCM device token for push delivery.

    Payload: {"user_id": int, "user_type": "worker"|"supervisor", "token": str}
    Token is persisted on the users/workers row (nullable column, added by
    db_migrate.ensure_fcm_columns on old databases).
    """
    token = str(payload.get("token") or "").strip()
    if not token:
        raise HTTPException(400, "token is required")

    user_type = str(payload.get("user_type") or "worker").strip().lower()
    user_id = payload.get("user_id")
    if user_id is None:
        raise HTTPException(400, "user_id is required")

    if user_type == "worker":
        user = db.query(Worker).filter(Worker.worker_id == int(user_id)).first()
    else:
        user = db.query(Supervisor).filter(Supervisor.supervisor_id == int(user_id)).first()

    if not user:
        raise HTTPException(404, "User does not exist")

    user.fcm_token = token
    db.commit()
    return {"ok": True, "user_type": user_type, "user_id": int(user_id)}


# ───────────── Worker notifications (task assignment etc.) ─────────────
@router.get("/notifications/worker/{worker_id}")
def list_worker_notifications(
    worker_id: int,
    unread_only: bool = False,
    limit: int = 50,
    db: Session = Depends(get_db),
    _: Any = Depends(require_any_authorized),
):
    """List in-app notifications for a worker (mirror of FCM pushes)."""
    query = db.query(WorkerNotification).filter(
        WorkerNotification.worker_id == worker_id
    )
    if unread_only:
        query = query.filter(WorkerNotification.is_read == False)  # noqa: E712
    rows = query.order_by(WorkerNotification.created_at.desc()).limit(limit).all()
    return [
        {
            "notification_id": r.notification_id,
            "worker_id": r.worker_id,
            "title": r.title,
            "content": r.content,
            "related_entity_type": r.related_entity_type,
            "related_entity_id": r.related_entity_id,
            "is_read": bool(r.is_read),
            "created_at": r.created_at.isoformat() if r.created_at else None,
        }
        for r in rows
    ]


@router.get("/notifications/worker/{worker_id}/unread-count")
def worker_unread_count(
    worker_id: int,
    db: Session = Depends(get_db),
    _: Any = Depends(require_any_authorized),
):
    count = db.query(WorkerNotification).filter(
        WorkerNotification.worker_id == worker_id,
        WorkerNotification.is_read == False,  # noqa: E712
    ).count()
    return {"count": count}


@router.put("/notifications/worker/{worker_id}/read-all")
def worker_mark_all_read(
    worker_id: int,
    db: Session = Depends(get_db),
    _: Any = Depends(require_any_authorized),
):
    db.query(WorkerNotification).filter(
        WorkerNotification.worker_id == worker_id,
        WorkerNotification.is_read == False,  # noqa: E712
    ).update({"is_read": True, "read_at": datetime.utcnow()})
    db.commit()
    return {"status": "ok"}


@router.get("/notifications", response_model=List[NotificationOut])
def list_notifications(
    unread_only: bool = False,
    limit: int = 50,
    db: Session = Depends(get_db),
    current_user: Supervisor = Depends(cu)
):
    query = db.query(Notification).filter(
        Notification.supervisor_id == current_user.supervisor_id
    )
    
    if unread_only:
        query = query.filter(Notification.is_read == False)
    
    return query.order_by(Notification.created_at.desc()).limit(limit).all()


@router.get("/notifications/unread-count", response_model=UnreadCountResponse)
def get_unread_count(
    db: Session = Depends(get_db),
    current_user: Supervisor = Depends(cu)
):
    count = db.query(Notification).filter(
        Notification.supervisor_id == current_user.supervisor_id,
        Notification.is_read == False
    ).count()
    return UnreadCountResponse(count=count)


# NOTE: the static "/notifications/settings" routes MUST be declared before the
# dynamic "/notifications/{notification_id}" route. FastAPI matches routes in
# registration order, so declaring the dynamic one first makes
# GET /notifications/settings resolve to get_notification(notification_id="settings")
# and fail with 422 instead of returning the settings payload.
@router.get("/notifications/settings")
def get_notification_settings(
    db: Session = Depends(get_db),
    current_user=Depends(cu)
):
    """Notification preferences of the logged-in account.

    Workers get their own row (``worker_notification_settings``); supervisors
    keep the original site-level row. Returning the same field set for both
    keeps the Flutter settings dialog role-agnostic.
    """
    return _settings_payload(db, current_user)


@router.put("/notifications/settings")
def update_notification_settings(
    settings_update: NotificationSettingUpdate,
    db: Session = Depends(get_db),
    current_user=Depends(cu)
):
    settings = (
        get_or_create_worker_settings(db, current_user.worker_id)
        if current_user.user_type == "worker"
        else get_or_create_settings(db, current_user.supervisor_id)
    )

    for field, value in settings_update.model_dump().items():
        if hasattr(settings, field):
            setattr(settings, field, value)

    db.commit()
    db.refresh(settings)
    return _settings_payload(db, current_user, settings=settings)


def _settings_payload(db: Session, current_user, settings=None) -> Dict[str, Any]:
    is_worker = current_user.user_type == "worker"
    if settings is None:
        settings = (
            get_or_create_worker_settings(db, current_user.worker_id)
            if is_worker
            else get_or_create_settings(db, current_user.supervisor_id)
        )
    payload = {
        field: bool(getattr(settings, field))
        for field in NotificationSettingUpdate.model_fields.keys()
    }
    payload.update({
        "setting_id": settings.setting_id,
        "scope": "worker" if is_worker else "supervisor",
    })
    return payload


@router.get("/notifications/{notification_id}", response_model=NotificationOut)
def get_notification(
    notification_id: int,
    db: Session = Depends(get_db),
    current_user: Supervisor = Depends(cu)
):
    notification = db.query(Notification).filter(
        Notification.notification_id == notification_id,
        Notification.supervisor_id == current_user.supervisor_id
    ).first()
    
    if not notification:
        raise HTTPException(status_code=404, detail="Notification not found")
    return notification


@router.put("/notifications/{notification_id}/read", response_model=NotificationOut)
def mark_read(
    notification_id: int,
    db: Session = Depends(get_db),
    current_user: Supervisor = Depends(cu)
):
    notification = db.query(Notification).filter(
        Notification.notification_id == notification_id,
        Notification.supervisor_id == current_user.supervisor_id
    ).first()
    
    if not notification:
        raise HTTPException(status_code=404, detail="Notification not found")
    
    notification.is_read = True
    notification.read_at = datetime.utcnow()
    db.commit()
    db.refresh(notification)
    return notification


@router.put("/notifications/read-all")
def mark_all_read(
    db: Session = Depends(get_db),
    current_user: Supervisor = Depends(cu)
):
    db.query(Notification).filter(
        Notification.supervisor_id == current_user.supervisor_id,
        Notification.is_read == False
    ).update({
        "is_read": True,
        "read_at": datetime.utcnow()
    })
    db.commit()
    return {"status": "ok", "message": "All notifications marked as read"}


@router.websocket("/ws/notifications")
async def websocket_endpoint(
    websocket: WebSocket,
    token: str,
    db: Session = Depends(get_db)
):
    await websocket.accept()

    global _main_loop
    _main_loop = asyncio.get_running_loop()

    from app.routers.auth import get_current_user_ws
    try:
        current_user = await get_current_user_ws(token, db)
    except Exception:
        await websocket.close()
        return
    
    user_id = current_user.supervisor_id
    if user_id not in active_connections:
        active_connections[user_id] = []
    active_connections[user_id].append(websocket)
    
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        active_connections[user_id].remove(websocket)
        if not active_connections[user_id]:
            del active_connections[user_id]


async def notify_user(user_id: int, message: Dict[str, Any]):
    if user_id in active_connections:
        for websocket in active_connections[user_id]:
            try:
                await websocket.send_json(message)
            except Exception:
                pass
