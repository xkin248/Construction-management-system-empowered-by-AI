from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
from datetime import date, datetime, time as dtime

from app.database import get_db
from app.models import Project, Worker, Task, Issue, DailyReport, AttendanceLog
from app.schemas import ProjectCreate, ProjectOut, DashboardKPI
from app.schemas import CurrentUser
from app.routers.auth import (
    project_for_user,
    require_any_authorized,
    require_site_supervisor,
)

router = APIRouter(tags=["🏗️ Project Management"])


def _derived_project_status(project) -> str:
    """Derive project.status from its task set (read-only, never persisted).

    Mirrors ai_task._recalc_project_status so list/detail responses never show
    a stale "planning" column for a project that already has tasks:
    - no tasks -> "planning"
    - tasks all completed -> "completed"
    - any other task set (pending-only / in_progress / mixed) -> "in_progress"
    """
    tasks = list(project.tasks or [])
    if not tasks:
        return "planning"
    if all(t.status == "completed" for t in tasks):
        return "completed"
    return "in_progress"


@router.get("/projects", response_model=List[ProjectOut])
def lp(user: CurrentUser = Depends(require_any_authorized), db=Depends(get_db)):
    query = db.query(Project)
    if user.user_type == "supervisor":
        query = query.filter(Project.supervisor_id == user.id)
    else:
        worker = db.get(Worker, user.id)
        if not worker or worker.project_id is None:
            return []
        query = query.filter(Project.project_id == worker.project_id)
    projects = query.order_by(Project.project_id.desc()).all()
    # Dynamically compute progress: projects with tasks show task completion rate; projects without tasks keep the manual value (not persisted)
    for p in projects:
        total = len(p.tasks)
        if total > 0:
            done = sum(1 for t in p.tasks if t.status == "completed")
            p.progress = round(done / total * 100, 1)
        p.status = _derived_project_status(p)  # read-derived, not written back
    return projects

@router.post("/projects", response_model=ProjectOut)
def cp(
    d: ProjectCreate,
    user: CurrentUser = Depends(require_site_supervisor),
    db=Depends(get_db),
):
    p = Project(project_name=d.project_name.strip(), location_address=d.location_address.strip(),
                start_date=d.start_date, end_date=d.end_date,
                status=(d.status or "planning").strip().lower(),
                progress=min(max(d.progress or 0.0, 0.0), 100.0),
                # The authenticated supervisor owns new projects; accepting a
                # client-supplied id would allow cross-account project writes.
                supervisor_id=user.id,
                center_lat=d.center_lat, center_lng=d.center_lng,
                fence_radius=max(d.fence_radius or 5000.0, 50.0))
    db.add(p); db.commit(); db.refresh(p); return p

@router.get("/projects/{pid}", response_model=ProjectOut)
def gp(pid: int, user: CurrentUser = Depends(require_any_authorized), db=Depends(get_db)):
    p = project_for_user(db, user, pid)
    p.status = _derived_project_status(p)  # read-derived, not written back
    return p

@router.put("/projects/{pid}", response_model=ProjectOut)
def up(
    pid: int,
    d: ProjectCreate,
    user: CurrentUser = Depends(require_site_supervisor),
    db=Depends(get_db),
):
    p = project_for_user(db, user, pid, supervisor_only=True)
    p.project_name=d.project_name.strip(); p.location_address=d.location_address.strip()
    p.start_date=d.start_date; p.end_date=d.end_date
    p.status=(d.status or p.status).strip().lower()
    p.progress=min(max(d.progress or p.progress, 0.0), 100.0)
    # Project ownership is immutable through this endpoint.  Transfer requires
    # a future audited administrator workflow, not a client-provided id.
    p.center_lat=d.center_lat; p.center_lng=d.center_lng
    p.fence_radius=max(d.fence_radius or p.fence_radius, 50.0)
    db.commit(); db.refresh(p); return p

@router.delete("/projects/{pid}")
def dp(
    pid: int,
    user: CurrentUser = Depends(require_site_supervisor),
    db=Depends(get_db),
):
    p = project_for_user(db, user, pid, supervisor_only=True)
    db.delete(p); db.commit(); return {"status":"ok","msg":"Deleted successfully"}

@router.get("/dashboard/kpi", response_model=DashboardKPI)
def kpi(user: CurrentUser = Depends(require_site_supervisor), db=Depends(get_db)):
    t = date.today()
    start = datetime.combine(t, dtime.min)
    project_ids = [pid for (pid,) in db.query(Project.project_id).filter(
        Project.supervisor_id == user.id
    ).all()]
    return DashboardKPI(
        total_projects=len(project_ids),
        ongoing_projects=db.query(Project).filter(Project.supervisor_id == user.id, Project.status=="in_progress").count(),
        completed_projects=db.query(Project).filter(Project.supervisor_id == user.id, Project.status=="completed").count(),
        total_workers=db.query(Worker).filter(Worker.project_id.in_(project_ids)).count(),
        today_attendance=db.query(AttendanceLog).filter(AttendanceLog.project_id.in_(project_ids), AttendanceLog.check_in_time>=start).count(),
        pending_tasks=db.query(Task).filter(Task.project_id.in_(project_ids), Task.status.in_(["pending","in_progress"])).count(),
        open_issues=db.query(Issue).filter(Issue.project_id.in_(project_ids), Issue.status.in_(["open","in_progress"])).count(),
        today_reports=db.query(DailyReport).filter(DailyReport.project_id.in_(project_ids), DailyReport.report_date==t).count(),
        completed_tasks=db.query(Task).filter(Task.project_id.in_(project_ids), Task.status=="completed").count(),
        in_progress_tasks=db.query(Task).filter(Task.project_id.in_(project_ids), Task.status=="in_progress").count(),
    )
