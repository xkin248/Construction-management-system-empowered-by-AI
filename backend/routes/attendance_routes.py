from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from datetime import datetime, date
from database import get_db
from services.attendance_service import AttendanceService
from pydantic import BaseModel

router = APIRouter(prefix="/api/attendance", tags=["attendance"])


class CheckInRequest(BaseModel):
    worker_id: int
    project_id: int
    location: str = None
    method: str = "Geofence"


class CheckOutRequest(BaseModel):
    worker_id: int
    project_id: int


class MarkAbsentRequest(BaseModel):
    worker_id: int
    project_id: int


@router.post("/check-in")
def check_in_worker(request: CheckInRequest, db: Session = Depends(get_db)):
    """Check in a worker"""
    try:
        record = AttendanceService.check_in_worker(
            db, request.worker_id, request.project_id, request.location, request.method
        )
        return {
            'success': True,
            'data': record.to_dict(),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/check-out")
def check_out_worker(request: CheckOutRequest, db: Session = Depends(get_db)):
    """Check out a worker"""
    try:
        record = AttendanceService.check_out_worker(db, request.worker_id, request.project_id)
        if not record:
            raise HTTPException(status_code=404, detail="No check-in record found for today")
        
        return {
            'success': True,
            'data': record.to_dict(),
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/mark-absent")
def mark_absent(request: MarkAbsentRequest, db: Session = Depends(get_db)):
    """Mark worker as absent"""
    try:
        record = AttendanceService.mark_absent(db, request.worker_id, request.project_id)
        return {
            'success': True,
            'data': record.to_dict(),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/for-date")
def get_attendance_for_date(date_str: str = None, project_id: int = None, db: Session = Depends(get_db)):
    """Get attendance records for a specific date"""
    try:
        if not date_str:
            record_date = date.today()
        else:
            record_date = datetime.fromisoformat(date_str).date()
        
        records = AttendanceService.get_attendance_for_date(db, record_date, project_id)
        return {
            'success': True,
            'data': [r.to_dict() for r in records],
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/stats")
def get_attendance_stats(date_str: str = None, project_id: int = None, db: Session = Depends(get_db)):
    """Get attendance statistics for a date"""
    try:
        if not date_str:
            record_date = date.today()
        else:
            record_date = datetime.fromisoformat(date_str).date()
        
        stats = AttendanceService.get_attendance_stats(db, record_date, project_id)
        return {
            'success': True,
            'data': stats,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/worker/{worker_id}/history")
def get_worker_attendance_history(worker_id: int, days: int = 30, db: Session = Depends(get_db)):
    """Get worker attendance history"""
    try:
        records = AttendanceService.get_worker_attendance_history(db, worker_id, days)
        return {
            'success': True,
            'data': [r.to_dict() for r in records],
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/weekly-data")
def get_weekly_attendance_data(project_id: int = None, db: Session = Depends(get_db)):
    """Get weekly attendance trend data"""
    try:
        data = AttendanceService.get_weekly_attendance_data(db, project_id)
        return {
            'success': True,
            'data': data,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/worker/{worker_id}/hours")
def get_worker_total_hours(worker_id: int, start_date: str = None, end_date: str = None, db: Session = Depends(get_db)):
    """Get total hours worked by a worker"""
    try:
        start = None
        end = None
        
        if start_date:
            start = datetime.fromisoformat(start_date).date()
        if end_date:
            end = datetime.fromisoformat(end_date).date()
        
        hours = AttendanceService.get_total_hours_worked(db, worker_id, start, end)
        return {
            'success': True,
            'data': {'total_hours': hours},
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
