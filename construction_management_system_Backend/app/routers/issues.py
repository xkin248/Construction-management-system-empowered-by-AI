from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import datetime

from app.database import get_db
from app.models import Issue, Project, Worker, WorkerNotification
from app.schemas import IssueCreate, IssueOut, CurrentUser
from app.routers.auth import (
    cu,
    project_for_user,
    require_any_authorized,
    require_site_supervisor,
)
from app.notification_service import notify_issue_created
from app.worker_pool import get_project_workers

router = APIRouter(tags=["⚠️ Issues"])


@router.get("/issues", response_model=List[IssueOut])
def list_issues(
    project_id: Optional[int] = None,
    status: Optional[str] = None,
    current_user: CurrentUser = Depends(require_any_authorized),
    db: Session = Depends(get_db),
):
    q = db.query(Issue)
    if project_id:
        project_for_user(db, current_user, project_id)
        q = q.filter(Issue.project_id == project_id)
    elif current_user.user_type == "supervisor":
        q = q.join(Project).filter(Project.supervisor_id == current_user.id)
    else:
        worker = db.get(Worker, current_user.id)
        if not worker or worker.project_id is None:
            return []
        q = q.filter(Issue.project_id == worker.project_id)
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
    project_for_user(db, current_user, project.project_id)
    data = d.model_dump()
    data["reported_by"] = current_user.id if current_user.user_type == "supervisor" else None
    issue = Issue(**data)
    db.add(issue)
    db.commit()
    db.refresh(issue)

    # Broadcast the issue to every worker so it shows up in each worker's
    # notifications list (WorkerNotification mirrors in-app notifications).
    workers = get_project_workers(db, project.project_id)
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
def resolve_issue(
    iid: int,
    current_user: CurrentUser = Depends(require_site_supervisor),
    db: Session = Depends(get_db),
):
    issue = db.query(Issue).get(iid)
    if not issue:
        raise HTTPException(404, "Issue does not exist")
    project_for_user(db, current_user, issue.project_id, supervisor_only=True)
    issue.status = "resolved"
    issue.resolved_at = datetime.utcnow()
    db.commit()
    db.refresh(issue)
    return issue
