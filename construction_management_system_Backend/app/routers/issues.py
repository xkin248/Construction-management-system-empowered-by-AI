from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import datetime

from app.database import get_db
from app.models import Issue, Project, Worker, WorkerNotification
from app.schemas import IssueCreate, IssueOut, CurrentUser
from app.routers.auth import cu
from app.notification_service import notify_issue_created

router = APIRouter(tags=["⚠️ Issues"])


@router.get("/issues", response_model=List[IssueOut])
def list_issues(project_id: Optional[int] = None, status: Optional[str] = None, db: Session = Depends(get_db)):
    q = db.query(Issue)
    if project_id:
        q = q.filter(Issue.project_id == project_id)
    if status:
        q = q.filter(Issue.status == status)
    return q.order_by(Issue.issue_id.desc()).all()


@router.post("/issues", response_model=IssueOut)
def create_issue(
    d: IssueCreate,
    db: Session = Depends(get_db),
    current_user: CurrentUser = Depends(cu)
):
    project = db.query(Project).get(d.project_id)
    if not project:
        raise HTTPException(404, "Project does not exist")
    issue = Issue(**d.model_dump())
    db.add(issue)
    db.commit()
    db.refresh(issue)

    # Broadcast the issue to every worker so it shows up in each worker's
    # notifications list (WorkerNotification mirrors in-app notifications).
    workers = db.query(Worker).all()
    for w in workers:
        db.add(WorkerNotification(
            worker_id=w.worker_id,
            title="New issue reported",
            content=f"Project \"{project.project_name}\" has a new issue: {issue.title}",
            related_entity_type="issue",
            related_entity_id=issue.issue_id,
        ))
    db.commit()

    # Keep the reporting supervisor's own notification feed in sync too.
    if current_user.user_type == "supervisor" and current_user.supervisor_id:
        try:
            notify_issue_created(
                db, current_user.supervisor_id, issue.title, project.project_name
            )
        except Exception:
            # Best-effort: the in-app notification must never block the issue.
            db.rollback()

    return issue


@router.put("/issues/{iid}/resolve", response_model=IssueOut)
def resolve_issue(iid: int, db: Session = Depends(get_db)):
    issue = db.query(Issue).get(iid)
    if not issue:
        raise HTTPException(404, "Issue does not exist")
    issue.status = "resolved"
    issue.resolved_at = datetime.utcnow()
    db.commit()
    db.refresh(issue)
    return issue
