from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
from datetime import date

from app.database import get_db
from app.models import Project, Worker, Task, Issue, DailyReport, AttendanceLog
from app.schemas import ProjectCreate, ProjectOut, DashboardKPI

router = APIRouter(tags=["🏗️ Project Management"])

@router.get("/projects", response_model=List[ProjectOut])
def lp(db=Depends(get_db)):
    return db.query(Project).order_by(Project.project_id.desc()).all()

@router.post("/projects", response_model=ProjectOut)
def cp(d: ProjectCreate, db=Depends(get_db)):
    p = Project(project_name=d.project_name.strip(), location_address=d.location_address.strip(),
                start_date=d.start_date, end_date=d.end_date,
                status=(d.status or "planning").strip().lower(),
                progress=min(max(d.progress or 0.0, 0.0), 100.0),
                supervisor_id=d.supervisor_id,
                center_lat=d.center_lat, center_lng=d.center_lng,
                fence_radius=max(d.fence_radius or 500.0, 50.0))
    db.add(p); db.commit(); db.refresh(p); return p

@router.get("/projects/{pid}", response_model=ProjectOut)
def gp(pid:int, db=Depends(get_db)):
    p = db.query(Project).get(pid)
    if not p: raise HTTPException(404,"Project does not exist"); return p

@router.put("/projects/{pid}", response_model=ProjectOut)
def up(pid:int, d:ProjectCreate, db=Depends(get_db)):
    p = db.query(Project).get(pid)
    if not p: raise HTTPException(404,"Project does not exist")
    p.project_name=d.project_name.strip(); p.location_address=d.location_address.strip()
    p.start_date=d.start_date; p.end_date=d.end_date
    p.status=(d.status or p.status).strip().lower()
    p.progress=min(max(d.progress or p.progress, 0.0), 100.0)
    p.supervisor_id=d.supervisor_id or p.supervisor_id
    p.center_lat=d.center_lat; p.center_lng=d.center_lng
    p.fence_radius=max(d.fence_radius or p.fence_radius, 50.0)
    db.commit(); db.refresh(p); return p

@router.delete("/projects/{pid}")
def dp(pid:int, db=Depends(get_db)):
    p = db.query(Project).get(pid)
    if not p: raise HTTPException(404,"Project does not exist")
    db.delete(p); db.commit(); return {"status":"ok","msg":"Deleted successfully"}

@router.get("/dashboard/kpi", response_model=DashboardKPI)
def kpi(db=Depends(get_db)):
    t = date.today()
    return DashboardKPI(
        total_projects=db.query(Project).count(),
        ongoing_projects=db.query(Project).filter(Project.status=="in_progress").count(),
        completed_projects=db.query(Project).filter(Project.status=="completed").count(),
        total_workers=db.query(Worker).count(),
        today_attendance=db.query(AttendanceLog).filter(AttendanceLog.check_in_time>=t).count(),
        pending_tasks=db.query(Task).filter(Task.status.in_(["pending","in_progress"])).count(),
        open_issues=db.query(Issue).filter(Issue.status.in_(["open","in_progress"])).count(),
        today_reports=db.query(DailyReport).filter(DailyReport.report_date==t).count(),
    )