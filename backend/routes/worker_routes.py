from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from database import get_db
from services.worker_service import WorkerService
from pydantic import BaseModel

router = APIRouter(prefix="/api/workers", tags=["workers"])


class CreateWorkerRequest(BaseModel):
    name: str
    role: str
    email: str
    phone: str = None
    hourly_rate: float = 0
    skills: list = None
    certifications: list = None


class AssignWorkerRequest(BaseModel):
    worker_id: int
    project_id: int


class UpdateRatingRequest(BaseModel):
    worker_id: int
    rating: float


@router.post("/create")
def create_worker(request: CreateWorkerRequest, db: Session = Depends(get_db)):
    """Create a new worker"""
    try:
        worker = WorkerService.create_worker(
            db=db,
            name=request.name,
            role=request.role,
            email=request.email,
            phone=request.phone,
            hourly_rate=request.hourly_rate,
            skills=request.skills,
            certifications=request.certifications,
        )
        return {
            'success': True,
            'data': worker.to_dict(),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/list")
def get_workers(project_id: int = None, status: str = None, db: Session = Depends(get_db)):
    """Get workers with optional filtering"""
    try:
        workers = WorkerService.get_workers(db, project_id, status)
        return {
            'success': True,
            'data': [w.to_dict() for w in workers],
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/{worker_id}")
def get_worker(worker_id: int, db: Session = Depends(get_db)):
    """Get a specific worker"""
    try:
        worker = WorkerService.get_worker_by_id(db, worker_id)
        if not worker:
            raise HTTPException(status_code=404, detail="Worker not found")
        
        return {
            'success': True,
            'data': worker.to_dict(),
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/{worker_id}/details")
def get_worker_details(worker_id: int, db: Session = Depends(get_db)):
    """Get detailed worker information"""
    try:
        details = WorkerService.get_worker_details(db, worker_id)
        if not details:
            raise HTTPException(status_code=404, detail="Worker not found")
        
        return {
            'success': True,
            'data': details,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/assign-to-project")
def assign_worker_to_project(request: AssignWorkerRequest, db: Session = Depends(get_db)):
    """Assign a worker to a project"""
    try:
        assignment = WorkerService.assign_worker_to_project(db, request.worker_id, request.project_id)
        return {
            'success': True,
            'data': {
                'worker_id': assignment.worker_id,
                'project_id': assignment.project_id,
                'assigned_date': assignment.assigned_date.isoformat(),
            },
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.put("/update-rating")
def update_worker_rating(request: UpdateRatingRequest, db: Session = Depends(get_db)):
    """Update worker rating"""
    try:
        worker = WorkerService.update_worker_rating(db, request.worker_id, request.rating)
        if not worker:
            raise HTTPException(status_code=404, detail="Worker not found")
        
        return {
            'success': True,
            'data': worker.to_dict(),
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/by-skills")
def get_workers_by_skills(skills: list = None, project_id: int = None, db: Session = Depends(get_db)):
    """Get workers by required skills"""
    try:
        workers = WorkerService.get_workers_by_skills(db, skills or [], project_id)
        return {
            'success': True,
            'data': [w.to_dict() for w in workers],
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/{worker_id}/availability")
def get_worker_availability(worker_id: int, date_str: str = None, db: Session = Depends(get_db)):
    """Check worker availability"""
    try:
        from datetime import datetime
        check_date = None
        if date_str:
            check_date = datetime.fromisoformat(date_str).date()
        
        availability = WorkerService.get_worker_availability(db, worker_id, check_date)
        return {
            'success': True,
            'data': availability,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/{worker_id}/statistics")
def get_worker_statistics(worker_id: int, db: Session = Depends(get_db)):
    """Get worker statistics"""
    try:
        stats = WorkerService.get_worker_statistics(db, worker_id)
        if not stats:
            raise HTTPException(status_code=404, detail="Worker not found")
        
        return {
            'success': True,
            'data': stats,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
