from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
from geopy.distance import great_circle
from datetime import datetime, date

from app.database import get_db
from app.models import Issue, Worker, Project, DailyReport
from app.worker_pool import get_project_workers
from app.schemas import IssueCreate, IssueOut

router = APIRouter(tags=["🚨 Safety Incidents"])
INCIDENT = {"snake":"🐍 Snake sighting","fire":"🔥 Fire","fall":"⚠️ Fall","electrical":"⚡ Electric shock","general":"🔧 Other"}
PRIORITY = {"snake":"critical","fire":"critical","fall":"high","electrical":"high","general":"medium"}

def _dist(a,b,c,d): return great_circle((a,b),(c,d)).meters

@router.post("/safety/report", response_model=IssueOut)
def report(
    incident_type: str, worker_id: int, project_id: int,
    gps_lat: float, gps_lng: float,
    image_path: str = None, description: str = None,
    db: Session = Depends(get_db)
):
    w = db.query(Worker).get(worker_id); p = db.query(Project).get(project_id)
    if not w or not p: raise HTTPException(404, "Does not exist")
    if incident_type not in INCIDENT: raise HTTPException(400, "Invalid type")
    is_safe = incident_type != "general"
    issue = Issue(
        title=f"🚨 {INCIDENT[incident_type]}",
        description=description or "Auto-reported",
        project_id=project_id, reported_by=worker_id,
        priority=PRIORITY[incident_type], status="open",
        image_path=image_path, incident_type=incident_type,
        is_safety_incident=is_safe, gps_lat=gps_lat, gps_lng=gps_lng,
    )
    db.add(issue); db.flush()
    # Auto-assign to the nearest safety officer (project pool = bound or attended)
    officers = [
        w for w in get_project_workers(db, project_id)
        if w.is_safety_officer or w.has_safety_training
    ]
    if officers:
        officers.sort(key=lambda o: _dist(p.center_lat,p.center_lng,gps_lat,gps_lng))
        issue.handled_by = officers[0].worker_id
    db.commit(); db.refresh(issue); return issue

@router.post("/safety/resolve/{iid}", response_model=IssueOut)
def resolve(iid: int, worker_id: int, note: str, db: Session = Depends(get_db)):
    i = db.query(Issue).get(iid)
    if not i: raise HTTPException(404, "Does not exist")
    i.status="resolved"; i.handled_at=datetime.utcnow()
    i.description += f"\n✅ Resolved: {note}"
    # Auto-log to the daily report
    t = date.today()
    r = db.query(DailyReport).filter(DailyReport.project_id==i.project_id, DailyReport.report_date==t).first()
    if r: r.issues_encountered = (r.issues_encountered or "") + f"\n🚨 {INCIDENT[i.incident_type]}：{note}"
    db.commit(); db.refresh(i); return i

@router.get("/safety/my-tasks/{wid}", response_model=List[IssueOut])
def my_tasks(wid: int, db: Session = Depends(get_db)):
    return db.query(Issue).filter(Issue.handled_by==wid, Issue.status.in_(["open","in_progress"])).all()