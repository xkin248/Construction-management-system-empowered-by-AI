from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from datetime import datetime
from database import get_db
from services.task_service import TaskService
from pydantic import BaseModel

router = APIRouter(prefix="/api/tasks", tags=["tasks"])


class CreateTaskRequest(BaseModel):
    title: str
    description: str
    project_id: int
    priority: str = "MEDIUM"
    estimated_hours: float = 0
    required_skills: list = None
    due_date: str = None


class AssignTaskRequest(BaseModel):
    task_id: int
    worker_id: int


class UpdateProgressRequest(BaseModel):
    task_id: int
    progress: float
    hours_logged: float = None


@router.post("/create")
def create_task(request: CreateTaskRequest, db: Session = Depends(get_db)):
    """Create a new task"""
    try:
        due_date = None
        if request.due_date:
            due_date = datetime.fromisoformat(request.due_date)
        
        task = TaskService.create_task(
            db=db,
            title=request.title,
            description=request.description,
            project_id=request.project_id,
            priority=request.priority,
            estimated_hours=request.estimated_hours,
            required_skills=request.required_skills,
            due_date=due_date,
        )
        
        return {
            'success': True,
            'data': task.to_dict(),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/list")
def get_tasks(project_id: int = None, status: str = None, priority: str = None,
             assigned_worker_id: int = None, db: Session = Depends(get_db)):
    """Get tasks with optional filtering"""
    try:
        tasks = TaskService.get_tasks(db, project_id, status, priority, assigned_worker_id)
        return {
            'success': True,
            'data': [t.to_dict() for t in tasks],
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/{task_id}")
def get_task(task_id: int, db: Session = Depends(get_db)):
    """Get a specific task"""
    try:
        task = TaskService.get_task_by_id(db, task_id)
        if not task:
            raise HTTPException(status_code=404, detail="Task not found")
        
        return {
            'success': True,
            'data': task.to_dict(),
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/assign")
def assign_task(request: AssignTaskRequest, db: Session = Depends(get_db)):
    """Assign a task to a worker"""
    try:
        task = TaskService.assign_task(db, request.task_id, request.worker_id)
        if not task:
            raise HTTPException(status_code=404, detail="Task or worker not found")
        
        return {
            'success': True,
            'data': task.to_dict(),
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.put("/update-progress")
def update_task_progress(request: UpdateProgressRequest, db: Session = Depends(get_db)):
    """Update task progress"""
    try:
        task = TaskService.update_task_progress(db, request.task_id, request.progress, request.hours_logged)
        if not task:
            raise HTTPException(status_code=404, detail="Task not found")
        
        return {
            'success': True,
            'data': task.to_dict(),
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/stats/summary")
def get_task_stats(project_id: int = None, db: Session = Depends(get_db)):
    """Get task statistics"""
    try:
        stats = TaskService.get_task_stats(db, project_id)
        return {
            'success': True,
            'data': stats,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/overdue-tasks")
def get_overdue_tasks(project_id: int = None, db: Session = Depends(get_db)):
    """Get overdue tasks"""
    try:
        tasks = TaskService.get_overdue_tasks(db, project_id)
        return {
            'success': True,
            'data': [t.to_dict() for t in tasks],
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
