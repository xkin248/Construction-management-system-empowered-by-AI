from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import date, datetime

from app.database import get_db
from app.models import Worker, AttendanceLog, Project
from app.worker_pool import get_project_workers
from app.schemas import WorkerCreate, WorkerOut, WorkerWithStatus
from app.schemas import CurrentUser
from app.routers.auth import project_for_user, require_any_authorized, require_site_supervisor

router = APIRouter(tags=["👷 Workers"])


def _today_start():
    t = date.today()
    return datetime(t.year, t.month, t.day)


def _with_status(w: Worker, db: Session) -> WorkerWithStatus:
    a = db.query(AttendanceLog).filter(
        AttendanceLog.worker_id == w.worker_id,
        AttendanceLog.check_in_time >= _today_start(),
    ).order_by(AttendanceLog.attendance_id.desc()).first()

    status = "absent"
    hours = None
    if a and a.status in ("checked_in", "checked_out"):
        # Late = checked in after the project's configured late threshold (default 07:30).
        status = "present"
        if a.check_in_time and a.check_in_time.strftime("%H:%M") > "07:30":
            status = "late"
        if a.check_in_time and a.check_out_time:
            hours = round((a.check_out_time - a.check_in_time).total_seconds() / 3600, 1)

    out = WorkerWithStatus.model_validate(w)
    out.today_status = status
    out.check_in_time = a.check_in_time if a else None
    out.check_out_time = a.check_out_time if a else None
    out.hours_today = hours
    return out


@router.get("/workers", response_model=List[WorkerWithStatus])
def list_workers(
    project_id: Optional[int] = None,
    user: CurrentUser = Depends(require_site_supervisor),
    db: Session = Depends(get_db),
):
    if project_id:
        project_for_user(db, user, project_id, supervisor_only=True)
        workers = get_project_workers(db, project_id)
    else:
        workers = db.query(Worker).join(Project).filter(
            Project.supervisor_id == user.id
        ).order_by(Worker.worker_id.desc()).all()
    return [_with_status(w, db) for w in workers]


@router.post("/workers", response_model=WorkerOut)
def create_worker(
    d: WorkerCreate,
    user: CurrentUser = Depends(require_site_supervisor),
    db: Session = Depends(get_db),
):
    if d.project_id:
        project_for_user(db, user, d.project_id, supervisor_only=True)
    data = d.model_dump()
    # Auto-assign project when none was chosen: fall back to the first project.
    if data.get("project_id") is None:
        first_p = db.query(Project).filter(
            Project.supervisor_id == user.id
        ).order_by(Project.project_id.asc()).first()
        data["project_id"] = first_p.project_id if first_p else None
    w = Worker(**data)
    db.add(w)
    db.commit()
    db.refresh(w)
    return w


@router.get("/workers/{wid}", response_model=WorkerWithStatus)
def get_worker(
    wid: int,
    user: CurrentUser = Depends(require_any_authorized),
    db: Session = Depends(get_db),
):
    w = db.query(Worker).get(wid)
    if not w:
        raise HTTPException(404, "Worker does not exist")
    if user.user_type == "worker":
        if user.id != w.worker_id:
            raise HTTPException(403, "You may only view your own worker profile")
    elif w.project_id is None:
        raise HTTPException(403, "This worker is not assigned to one of your projects")
    else:
        project_for_user(db, user, w.project_id, supervisor_only=True)
    return _with_status(w, db)


@router.put("/workers/{wid}", response_model=WorkerOut)
def update_worker(
    wid: int,
    d: WorkerCreate,
    user: CurrentUser = Depends(require_site_supervisor),
    db: Session = Depends(get_db),
):
    w = db.query(Worker).get(wid)
    if not w:
        raise HTTPException(404, "Worker does not exist")
    if w.project_id is None:
        raise HTTPException(403, "This worker is not assigned to one of your projects")
    project_for_user(db, user, w.project_id, supervisor_only=True)
    if d.project_id:
        project_for_user(db, user, d.project_id, supervisor_only=True)
    for k, v in d.model_dump().items():
        setattr(w, k, v)
    db.commit()
    db.refresh(w)
    return w


@router.delete("/workers/{wid}")
def delete_worker(
    wid: int,
    user: CurrentUser = Depends(require_site_supervisor),
    db: Session = Depends(get_db),
):
    w = db.query(Worker).get(wid)
    if not w:
        raise HTTPException(404, "Worker does not exist")
    if w.project_id is None:
        raise HTTPException(403, "This worker is not assigned to one of your projects")
    project_for_user(db, user, w.project_id, supervisor_only=True)
    db.delete(w)
    db.commit()
    return {"status": "ok", "msg": "Deleted successfully"}
