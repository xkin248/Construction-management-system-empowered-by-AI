from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from database import get_db
from services.dashboard_service import DashboardService

router = APIRouter(prefix="/api/dashboard", tags=["dashboard"])


@router.get("/summary")
def get_dashboard_summary(project_id: int = None, db: Session = Depends(get_db)):
    """Get dashboard summary with all metrics"""
    try:
        summary = DashboardService.get_dashboard_summary(db, project_id)
        return {
            'success': True,
            'data': summary,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/workers-on-site")
def get_workers_on_site(project_id: int = None, db: Session = Depends(get_db)):
    """Get workers on site count"""
    try:
        data = DashboardService.get_workers_on_site(db, project_id)
        return {
            'success': True,
            'data': data,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/active-tasks")
def get_active_tasks(project_id: int = None, db: Session = Depends(get_db)):
    """Get active tasks count"""
    try:
        data = DashboardService.get_active_tasks(db, project_id)
        return {
            'success': True,
            'data': data,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/productivity")
def get_productivity(project_id: int = None, db: Session = Depends(get_db)):
    """Get productivity percentage"""
    try:
        productivity = DashboardService.get_productivity_percentage(db, project_id)
        return {
            'success': True,
            'data': {'productivity': productivity},
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/alerts")
def get_alerts(project_id: int = None, db: Session = Depends(get_db)):
    """Get dashboard alerts"""
    try:
        alerts = DashboardService.get_alerts(db, project_id)
        return {
            'success': True,
            'data': alerts,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/weekly-attendance")
def get_weekly_attendance(project_id: int = None, db: Session = Depends(get_db)):
    """Get weekly attendance data"""
    try:
        data = DashboardService.get_weekly_attendance(db, project_id)
        return {
            'success': True,
            'data': data,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/task-distribution")
def get_task_distribution(project_id: int = None, db: Session = Depends(get_db)):
    """Get task distribution data"""
    try:
        data = DashboardService.get_task_distribution(db, project_id)
        return {
            'success': True,
            'data': data,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
