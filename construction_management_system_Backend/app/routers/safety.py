from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
from geopy.distance import great_circle
from datetime import datetime, date

from app.database import get_db
from app.models import Issue, Worker, Project, DailyReport
from app.worker_pool import get_project_workers
from app.schemas import IssueCreate, IssueOut, CurrentUser
from app.routers.auth import project_for_user, require_site_supervisor, require_worker

router = APIRouter(tags=["🚨 Safety Incidents"])
INCIDENT = {"snake":"🐍 Snake sighting","fire":"🔥 Fire","fall":"⚠️ Fall","electrical":"⚡ Electric shock","general":"🔧 Other"}
PRIORITY = {"snake":"critical","fire":"critical","fall":"high","electrical":"high","general":"medium"}

def _dist(a,b,c,d): return great_circle((a,b),(c,d)).meters

# These are the values emitted by the current worker app. Keep the earlier
# incident categories too so existing records and clients remain compatible.
INCIDENT.update({
    "unsafe_act": "Unsafe act",
    "unsafe_condition": "Unsafe condition",
    "near_miss": "Near miss",
    "equipment_defect": "Equipment defect",
    "other": "Other",
})
PRIORITY.update({
    "unsafe_act": "high",
    "unsafe_condition": "high",
    "near_miss": "high",
    "equipment_defect": "high",
    "other": "medium",
})

@router.post("/safety/report", response_model=IssueOut)
def report(
    incident_type: str, worker_id: int, project_id: int,
    gps_lat: float, gps_lng: float,
    image_path: str = None, description: str = None,
    user: CurrentUser = Depends(require_worker),
    db: Session = Depends(get_db)
):
    if worker_id != user.id:
        raise HTTPException(403, "Workers may only report safety incidents for themselves")
    w = db.query(Worker).get(worker_id); p = db.query(Project).get(project_id)
    if not w or not p: raise HTTPException(404, "Does not exist")
    project_for_user(db, user, project_id)
    if incident_type not in INCIDENT: raise HTTPException(400, "Invalid type")
    is_safe = incident_type != "general"
    issue = Issue(
        title=f"🚨 {INCIDENT[incident_type]}",
        # ``reported_by`` is a legacy FK to supervisors, so a worker id cannot
        # be stored there. Preserve the worker identity in the incident text
        # until the schema gains a proper worker reporter column.
        description=f"Reported by worker {w.worker_id} ({w.name})\n{description or 'Auto-reported'}",
        project_id=project_id, reported_by=None,
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
    db.commit(); db.refresh(issue)

    # Best-effort fan-out: supervisor feed (safety incidents only) + the
    # auto-assigned safety officer's own inbox.
    try:
        from app.models import WorkerNotification
        from app.notification_service import notify_safety_incident

        if is_safe and p.supervisor_id:
            notify_safety_incident(
                db, p.supervisor_id, issue.title, p.project_name, issue.issue_id
            )
        if issue.handled_by:
            db.add(WorkerNotification(
                worker_id=issue.handled_by,
                title=f"Safety incident assigned: {INCIDENT[incident_type]}",
                content=f"{issue.title} on project {p.project_name}",
                related_entity_type="issue",
                related_entity_id=issue.issue_id,
            ))
            db.commit()
    except Exception:
        db.rollback()

    db.refresh(issue)
    return issue

@router.post("/safety/resolve/{iid}", response_model=IssueOut)
def resolve(
    iid: int,
    worker_id: int,
    note: str,
    user: CurrentUser = Depends(require_site_supervisor),
    db: Session = Depends(get_db),
):
    i = db.query(Issue).get(iid)
    if not i: raise HTTPException(404, "Does not exist")
    project_for_user(db, user, i.project_id, supervisor_only=True)
    i.status="resolved"; i.handled_at=datetime.utcnow()
    i.description += f"\n✅ Resolved: {note}"
    # Auto-log to the daily report
    t = date.today()
    r = db.query(DailyReport).filter(DailyReport.project_id==i.project_id, DailyReport.report_date==t).first()
    if r: r.issues_encountered = (r.issues_encountered or "") + f"\n🚨 {INCIDENT[i.incident_type]}：{note}"
    db.commit(); db.refresh(i); return i
