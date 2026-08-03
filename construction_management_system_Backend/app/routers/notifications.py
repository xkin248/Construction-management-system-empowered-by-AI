from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect
from sqlalchemy.orm import Session
from typing import List, Dict, Any
from datetime import datetime

from app.database import get_db
from app.models import Supervisor, Notification
from app.schemas import (
    NotificationOut, NotificationSettingOut,
    NotificationSettingUpdate, UnreadCountResponse
)
from app.routers.auth import cu
from app.notification_service import get_or_create_settings

router = APIRouter(tags=["🔔 Notifications"])

active_connections: Dict[int, List[WebSocket]] = {}


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


@router.delete("/notifications/{notification_id}")
def delete_notification(
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
    
    db.delete(notification)
    db.commit()
    return {"status": "ok", "message": "Notification deleted"}


@router.get("/notifications/settings", response_model=NotificationSettingOut)
def get_notification_settings(
    db: Session = Depends(get_db),
    current_user: Supervisor = Depends(cu)
):
    return get_or_create_settings(db, current_user.supervisor_id)


@router.put("/notifications/settings", response_model=NotificationSettingOut)
def update_notification_settings(
    settings_update: NotificationSettingUpdate,
    db: Session = Depends(get_db),
    current_user: Supervisor = Depends(cu)
):
    settings = get_or_create_settings(db, current_user.supervisor_id)
    
    for field, value in settings_update.model_dump().items():
        if hasattr(settings, field):
            setattr(settings, field, value)
    
    db.commit()
    db.refresh(settings)
    return settings


@router.websocket("/ws/notifications")
async def websocket_endpoint(
    websocket: WebSocket,
    token: str,
    db: Session = Depends(get_db)
):
    await websocket.accept()
    
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
