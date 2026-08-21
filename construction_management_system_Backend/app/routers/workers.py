from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import date, datetime

from app.database import get_db
from app.models import Worker, AttendanceLog, Project
from app.worker_pool import get_project_workers
from app.schemas import WorkerCreate, WorkerOut, WorkerWithStatus

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
def list_workers(project_id: Optional[int] = None, db: Session = Depends(get_db)):
    if project_id:
        workers = get_project_workers(db, project_id)
    else:
        workers = db.query(Worker).order_by(Worker.worker_id.desc()).all()
    return [_with_status(w, db) for w in workers]


@router.post("/workers", response_model=WorkerOut)
def create_worker(d: WorkerCreate, db: Session = Depends(get_db)):
    if d.project_id and not db.query(Project).get(d.project_id):
        raise HTTPException(404, "Project does not exist")
    data = d.model_dump()
    # Auto-assign project when none was chosen: fall back to the first project.
    if data.get("project_id") is None:
        first_p = db.query(Project).order_by(Project.project_id.asc()).first()
        data["project_id"] = first_p.project_id if first_p else None
    w = Worker(**data)
    db.add(w)
    db.commit()
    db.refresh(w)
    return w


@router.get("/workers/{wid}", response_model=WorkerWithStatus)
def get_worker(wid: int, db: Session = Depends(get_db)):
    w = db.query(Worker).get(wid)
    if not w:
        raise HTTPException(404, "Worker does not exist")
    return _with_status(w, db)


@router.put("/workers/{wid}", response_model=WorkerOut)
def update_worker(wid: int, d: WorkerCreate, db: Session = Depends(get_db)):
    w = db.query(Worker).get(wid)
    if not w:
        raise HTTPException(404, "Worker does not exist")
    for k, v in d.model_dump().items():
        setattr(w, k, v)
    db.commit()
    db.refresh(w)
    return w


@router.delete("/workers/{wid}")
def delete_worker(wid: int, db: Session = Depends(get_db)):
    w = db.query(Worker).get(wid)
    if not w:
        raise HTTPException(404, "Worker does not exist")
    db.delete(w)
    db.commit()
    return {"status": "ok", "msg": "Deleted successfully"}
