from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import datetime

from app.database import get_db
from app.models import Issue, Project
from app.schemas import IssueCreate, IssueOut

router = APIRouter(tags=["\u26a0\ufe0f Issues"])


@router.get("/issues", response_model=List[IssueOut])
def list_issues(project_id: Optional[int] = None, status: Optional[str] = None, db: Session = Depends(get_db)):
    q = db.query(Issue)
    if project_id:
        q = q.filter(Issue.project_id == project_id)
    if status:
        q = q.filter(Issue.status == status)
    return q.order_by(Issue.issue_id.desc()).all()


@router.post("/issues", response_model=IssueOut)
def create_issue(d: IssueCreate, db: Session = Depends(get_db)):
    if not db.query(Project).get(d.project_id):
        raise HTTPException(404, "Project does not exist")
    issue = Issue(**d.model_dump())
    db.add(issue)
    db.commit()
    db.refresh(issue)
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
