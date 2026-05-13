from sqlalchemy.orm import Session
from sqlalchemy import and_, func
from datetime import datetime, date, timedelta
from models import Worker, Task, AttendanceRecord, ProjectWorker, TaskStatus, AttendanceStatus
import json


class WorkerService:
    """Service for worker management operations"""
    
    @staticmethod
    def create_worker(db: Session, name: str, role: str, email: str,
                     phone: str = None, hourly_rate: float = 0,
                     skills: list = None, certifications: list = None) -> Worker:
        """Create a new worker"""
        worker = Worker(
            name=name,
            role=role,
            email=email,
            phone=phone,
            hourly_rate=hourly_rate,
        )
        
        if skills:
            worker.skills = json.dumps(skills)
        if certifications:
            worker.certifications = json.dumps(certifications)
        
        db.add(worker)
        db.commit()
        db.refresh(worker)
        return worker
    
    @staticmethod
    def get_workers(db: Session, project_id: int = None, status: str = None) -> list:
        """Get workers with optional filtering"""
        if project_id:
            # Get workers assigned to a specific project
            query = db.query(Worker).join(ProjectWorker).filter(
                ProjectWorker.project_id == project_id
            )
        else:
            query = db.query(Worker)
        
        if status:
            query = query.filter(Worker.status == status)
        
        return query.all()
    
    @staticmethod
    def get_worker_by_id(db: Session, worker_id: int) -> Worker:
        """Get a specific worker by ID"""
        return db.query(Worker).filter(Worker.id == worker_id).first()
    
    @staticmethod
    def get_worker_details(db: Session, worker_id: int) -> dict:
        """Get detailed worker information"""
        worker = WorkerService.get_worker_by_id(db, worker_id)
        if not worker:
            return None
        
        # Get completed tasks count
        completed_tasks = db.query(func.count(Task.id)).filter(
            and_(
                Task.assigned_worker_id == worker_id,
                Task.status == TaskStatus.COMPLETED
            )
        ).scalar() or 0
        
        # Get total hours worked
        total_hours = db.query(func.sum(AttendanceRecord.hours_worked)).filter(
            AttendanceRecord.worker_id == worker_id
        ).scalar() or 0.0
        
        # Get current projects
        current_projects = db.query(ProjectWorker).filter(
            ProjectWorker.worker_id == worker_id
        ).all()
        
        # Get skills and certifications
        skills = json.loads(worker.skills) if worker.skills else []
        certifications = json.loads(worker.certifications) if worker.certifications else []
        
        return {
            'id': worker.id,
            'name': worker.name,
            'role': worker.role,
            'email': worker.email,
            'phone': worker.phone,
            'rating': worker.rating,
            'hours_logged': total_hours,
            'tasks_completed': completed_tasks,
            'status': worker.status,
            'hourly_rate': worker.hourly_rate,
            'skills': skills,
            'certifications': certifications,
            'current_projects': len(current_projects),
        }
    
    @staticmethod
    def assign_worker_to_project(db: Session, worker_id: int, project_id: int) -> ProjectWorker:
        """Assign a worker to a project"""
        # Check if assignment already exists
        existing = db.query(ProjectWorker).filter(
            and_(
                ProjectWorker.worker_id == worker_id,
                ProjectWorker.project_id == project_id
            )
        ).first()
        
        if existing:
            return existing
        
        assignment = ProjectWorker(
            worker_id=worker_id,
            project_id=project_id,
            assigned_date=datetime.utcnow()
        )
        
        db.add(assignment)
        db.commit()
        db.refresh(assignment)
        return assignment
    
    @staticmethod
    def update_worker_rating(db: Session, worker_id: int, new_rating: float) -> Worker:
        """Update worker rating (calculate average with existing ratings)"""
        worker = WorkerService.get_worker_by_id(db, worker_id)
        if not worker:
            return None
        
        # Calculate rolling average (80% old, 20% new)
        worker.rating = (worker.rating * 0.8) + (new_rating * 0.2)
        worker.rating = round(worker.rating, 1)
        
        db.commit()
        db.refresh(worker)
        return worker
    
    @staticmethod
    def get_workers_by_skills(db: Session, required_skills: list, project_id: int = None) -> list:
        """Get workers who have required skills"""
        workers = WorkerService.get_workers(db, project_id)
        
        matching_workers = []
        for worker in workers:
            worker_skills = json.loads(worker.skills) if worker.skills else []
            
            # Calculate skill match percentage
            matching_skills = len(set(worker_skills) & set(required_skills))
            match_percentage = (matching_skills / len(required_skills) * 100) if required_skills else 0
            
            if match_percentage >= 50:  # At least 50% skill match
                matching_workers.append({
                    'worker': worker,
                    'skill_match': match_percentage,
                    'rating': worker.rating,
                })
        
        # Sort by skill match and rating
        matching_workers.sort(key=lambda x: (x['skill_match'], x['rating']), reverse=True)
        
        return [w['worker'] for w in matching_workers]
    
    @staticmethod
    def get_worker_availability(db: Session, worker_id: int, date_check: date = None) -> dict:
        """Check worker availability for a specific date"""
        if not date_check:
            date_check = date.today()
        
        # Check if worker has check-in/check-out for today
        attendance = db.query(AttendanceRecord).filter(
            and_(
                AttendanceRecord.worker_id == worker_id,
                func.date(AttendanceRecord.date) == date_check
            )
        ).first()
        
        if not attendance:
            return {'available': True, 'status': 'Unknown'}
        
        if attendance.status == AttendanceStatus.ABSENT:
            return {'available': False, 'status': 'Absent'}
        elif attendance.status == AttendanceStatus.LATE:
            return {'available': True, 'status': 'Late'}
        else:
            return {'available': True, 'status': 'Present'}
    
    @staticmethod
    def get_worker_statistics(db: Session, worker_id: int) -> dict:
        """Get comprehensive worker statistics"""
        worker = WorkerService.get_worker_by_id(db, worker_id)
        if not worker:
            return None
        
        # Calculate statistics
        today = date.today()
        start_of_month = today.replace(day=1)
        
        tasks = db.query(Task).filter(Task.assigned_worker_id == worker_id).all()
        completed_tasks = len([t for t in tasks if t.status == TaskStatus.COMPLETED])
        in_progress_tasks = len([t for t in tasks if t.status == TaskStatus.IN_PROGRESS])
        
        total_hours = db.query(func.sum(AttendanceRecord.hours_worked)).filter(
            and_(
                AttendanceRecord.worker_id == worker_id,
                AttendanceRecord.date >= start_of_month
            )
        ).scalar() or 0.0
        
        attendance_records = db.query(AttendanceRecord).filter(
            and_(
                AttendanceRecord.worker_id == worker_id,
                AttendanceRecord.date >= start_of_month
            )
        ).all()
        
        present_days = len([a for a in attendance_records if a.status == AttendanceStatus.PRESENT])
        late_days = len([a for a in attendance_records if a.status == AttendanceStatus.LATE])
        absent_days = len([a for a in attendance_records if a.status == AttendanceStatus.ABSENT])
        
        return {
            'worker_id': worker_id,
            'name': worker.name,
            'role': worker.role,
            'rating': worker.rating,
            'tasks_completed': completed_tasks,
            'tasks_in_progress': in_progress_tasks,
            'hours_this_month': round(total_hours, 2),
            'attendance': {
                'present_days': present_days,
                'late_days': late_days,
                'absent_days': absent_days,
            },
        }
