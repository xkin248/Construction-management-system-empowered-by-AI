from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List

from app.database import get_db
from app.models import Settings, Supervisor
from app.schemas import SettingsOut, SettingsUpdate, SupervisorOut, UserInvite, UserRoleUpdate
from app.routers.auth import hpw

router = APIRouter(tags=["\u2699\ufe0f Settings"])


def _get_or_create(db: Session) -> Settings:
    s = db.query(Settings).get(1)
    if not s:
        s = Settings(id=1)
        db.add(s)
        db.commit()
        db.refresh(s)
    return s


def _apply_settings_payload(s: Settings, payload: dict):
    # Accept both the Flutter field names and the legacy HTML names.
    mapping = {
        "notif_overdue": "notif_task_overdue",
        "notif_daily": "notif_daily_summary",
        "notif_weekly": "notif_weekly_report",
    }
    for key, value in payload.items():
        attr = mapping.get(key, key)
        if hasattr(s, attr):
            setattr(s, attr, value)


@router.get("/settings", response_model=SettingsOut)
def get_settings(db: Session = Depends(get_db)):
    return _get_or_create(db)


@router.put("/settings", response_model=SettingsOut)
def update_settings(d: SettingsUpdate, db: Session = Depends(get_db)):
    s = _get_or_create(db)
    _apply_settings_payload(s, d.model_dump())
    db.commit()
    db.refresh(s)
    return s


@router.post("/settings")
def save_settings(payload: dict, db: Session = Depends(get_db)):
    s = _get_or_create(db)
    _apply_settings_payload(s, payload)
    db.commit()
    db.refresh(s)
    return {"ok": True, **SettingsOut.model_validate(s).model_dump(mode="json")}


@router.get("/users", response_model=List[SupervisorOut])
def list_users(db: Session = Depends(get_db)):
    return db.query(Supervisor).order_by(Supervisor.supervisor_id).all()


@router.post("/users", response_model=SupervisorOut)
def invite_user(d: UserInvite, db: Session = Depends(get_db)):
    if db.query(Supervisor).filter(Supervisor.email == d.email).first():
        raise HTTPException(400, "A user with this email already exists")
    u = Supervisor(full_name=d.full_name, email=d.email, role=d.role, password_hash=hpw(d.password))
    db.add(u)
    db.commit()
    db.refresh(u)
    return u


@router.put("/users/{uid}/role", response_model=SupervisorOut)
def update_user_role(uid: int, d: UserRoleUpdate, db: Session = Depends(get_db)):
    u = db.query(Supervisor).get(uid)
    if not u:
        raise HTTPException(404, "User does not exist")
    u.role = d.role
    db.commit()
    db.refresh(u)
    return u
