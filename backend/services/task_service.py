from sqlalchemy.orm import Session
from sqlalchemy import and_, or_, func
from datetime import datetime
from models import Task, Worker, TaskStatus, TaskPriority
from services.ai_service import AIService


class TaskService:
    """Service for task-related operations"""
    
    @staticmethod
    def create_task(db: Session, title: str, description: str, project_id: int,
                   priority: str = 'MEDIUM', estimated_hours: float = 0,
                   required_skills: list = None, due_date: datetime = None) -> Task:
        """Create a new task"""
        task = Task(
            title=title,
            description=description,
            project_id=project_id,
            priority=TaskPriority[priority],
            estimated_hours=estimated_hours,
            due_date=due_date,
        )
        
        if required_skills:
            import json
            task.required_skills = json.dumps(required_skills)
        
        db.add(task)
        db.commit()
        db.refresh(task)
        return task
    
    @staticmethod
    def get_tasks(db: Session, project_id: int = None, status: str = None,
                 priority: str = None, assigned_worker_id: int = None) -> list:
        """Get tasks with optional filtering"""
        query = db.query(Task)
        
        if project_id:
            query = query.filter(Task.project_id == project_id)
        
        if status:
            query = query.filter(Task.status == TaskStatus[status])
        
        if priority:
            query = query.filter(Task.priority == TaskPriority[priority])
        
        if assigned_worker_id:
            query = query.filter(Task.assigned_worker_id == assigned_worker_id)
        
        return query.order_by(Task.created_at.desc()).all()
    
    @staticmethod
    def get_task_by_id(db: Session, task_id: int) -> Task:
        """Get a specific task by ID"""
        return db.query(Task).filter(Task.id == task_id).first()
    
    @staticmethod
    def assign_task(db: Session, task_id: int, worker_id: int) -> Task:
        """Assign a task to a worker and calculate AI match score"""
        task = TaskService.get_task_by_id(db, task_id)
        worker = db.query(Worker).filter(Worker.id == worker_id).first()
        
        if not task or not worker:
            return None
        
        task.assigned_worker_id = worker_id
        
        # Calculate AI match score
        import json
        required_skills = json.loads(task.required_skills) if task.required_skills else []
        worker_skills = json.loads(worker.skills) if worker.skills else []
        
        match_score = AIService.calculate_worker_task_match(
            worker_skills=worker_skills,
            required_skills=required_skills,
            worker_rating=worker.rating,
            task_priority=task.priority.value,
        )
        
        task.ai_match_score = match_score
        db.commit()
        db.refresh(task)
        return task
    
    @staticmethod
    def update_task_progress(db: Session, task_id: int, progress: float,
                            hours_logged: float = None) -> Task:
        """Update task progress"""
        task = TaskService.get_task_by_id(db, task_id)
        if not task:
            return None
        
        task.progress = min(progress, 100.0)  # Cap at 100%
        
        if hours_logged:
            task.hours_logged += hours_logged
        
        # Auto-complete if progress reaches 100%
        if task.progress >= 100:
            task.status = TaskStatus.COMPLETED
        elif task.progress > 0:
            task.status = TaskStatus.IN_PROGRESS
        
        db.commit()
        db.refresh(task)
        return task
    
    @staticmethod
    def get_task_stats(db: Session, project_id: int = None) -> dict:
        """Get task statistics"""
        query = db.query(Task)
        
        if project_id:
            query = query.filter(Task.project_id == project_id)
        
        total = query.count()
        in_progress = query.filter(Task.status == TaskStatus.IN_PROGRESS).count()
        completed = query.filter(Task.status == TaskStatus.COMPLETED).count()
        pending = query.filter(Task.status == TaskStatus.PENDING).count()
        
        avg_progress = db.query(func.avg(Task.progress)).scalar() or 0
        
        return {
            'total': total,
            'in_progress': in_progress,
            'completed': completed,
            'pending': pending,
            'average_progress': round(avg_progress, 2),
        }
    
    @staticmethod
    def get_overdue_tasks(db: Session, project_id: int = None) -> list:
        """Get overdue tasks"""
        query = db.query(Task).filter(
            and_(
                Task.due_date < datetime.utcnow(),
                Task.status != TaskStatus.COMPLETED
            )
        )
        
        if project_id:
            query = query.filter(Task.project_id == project_id)
        
        return query.order_by(Task.due_date.asc()).all()
