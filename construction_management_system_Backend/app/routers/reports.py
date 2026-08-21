from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List

from app.database import get_db
from app.models import DailyReport
from app.schemas import DailyReportCreate, DailyReportOut
from app.routers.auth import cu

router = APIRouter(tags=["📝 Daily Reports"])

@router.get("/projects/{pid}/reports", response_model=List[DailyReportOut])
def list_reports(pid: int, db: Session = Depends(get_db)):
    return db.query(DailyReport).filter(DailyReport.project_id == pid)\
        .order_by(DailyReport.report_date.desc()).all()

@router.post("/daily-reports", response_model=DailyReportOut)
def create_report(d: DailyReportCreate, db: Session = Depends(get_db)):
    # Only one submission per project per day
    ex = db.query(DailyReport).filter(
        DailyReport.project_id == d.project_id,
        DailyReport.report_date == d.report_date
    ).first()
    if ex: raise HTTPException(400, "A daily report has already been submitted for this project today")
    r = DailyReport(**d.model_dump())
    db.add(r); db.commit(); db.refresh(r); return r