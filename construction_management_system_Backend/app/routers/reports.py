from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List

from app.database import get_db
from app.models import DailyReport
from app.schemas import DailyReportCreate, DailyReportOut, CurrentUser
from app.routers.auth import cu

router = APIRouter(tags=["📝 Daily Reports"])


def _require_supervisor(current_user: CurrentUser) -> int:
    """Daily reports are supervisor-only; return the supervisor id or 403."""
    if current_user.user_type != "supervisor" or not current_user.supervisor_id:
        raise HTTPException(403, "Only supervisors can manage daily reports")
    return current_user.supervisor_id


@router.get("/projects/{pid}/reports", response_model=List[DailyReportOut])
def list_reports(
    pid: int,
    db: Session = Depends(get_db),
    current_user: CurrentUser = Depends(cu)
):
    """Only return reports submitted by the current supervisor (private)."""
    sid = _require_supervisor(current_user)
    return db.query(DailyReport).filter(
        DailyReport.project_id == pid,
        DailyReport.submitted_by == sid
    ).order_by(DailyReport.report_date.desc()).all()


@router.post("/daily-reports", response_model=DailyReportOut)
def create_report(
    d: DailyReportCreate,
    db: Session = Depends(get_db),
    current_user: CurrentUser = Depends(cu)
):
    sid = _require_supervisor(current_user)
    # Only one submission per project per day
    ex = db.query(DailyReport).filter(
        DailyReport.project_id == d.project_id,
        DailyReport.report_date == d.report_date
    ).first()
    if ex:
        raise HTTPException(400, "A daily report has already been submitted for this project today")
    # Always attribute the report to the authenticated supervisor; ignore any
    # client-supplied submitted_by so reports stay private to their creator.
    data = d.model_dump(exclude={"submitted_by"})
    r = DailyReport(**data, submitted_by=sid)
    db.add(r)
    db.commit()
    db.refresh(r)
    return r
