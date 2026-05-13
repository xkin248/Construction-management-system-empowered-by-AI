from sqlalchemy.orm import Session
from sqlalchemy import func, and_, or_
from datetime import datetime, timedelta
from models import (
    Project, Task, Worker, AttendanceRecord, TaskStatus, ProjectStatus, AttendanceStatus
)


class DashboardService:
    """Service for dashboard-related operations"""
    
    @staticmethod
    def get_workers_on_site(db: Session, project_id: int = None) -> dict:
        """Get count of workers on site"""
        today = datetime.utcnow().date()
        query = db.query(AttendanceRecord).filter(
            func.date(AttendanceRecord.date) == today
        )
        
        if project_id:
            query = query.filter(AttendanceRecord.project_id == project_id)
        
        total = query.count()
        present = query.filter(
            or_(
                AttendanceRecord.status == AttendanceStatus.PRESENT,
                AttendanceRecord.status == AttendanceStatus.LATE
            )
        ).count()
        
        absent = query.filter(AttendanceRecord.status == AttendanceStatus.ABSENT).count()
        late = query.filter(AttendanceRecord.status == AttendanceStatus.LATE).count()
        
        return {
            'total': total,
            'present': present,
            'absent': absent,
            'late': late,
        }
    
    @staticmethod
    def get_active_tasks(db: Session, project_id: int = None) -> dict:
        """Get count of active tasks"""
        query = db.query(Task).filter(
            Task.status.in_([TaskStatus.IN_PROGRESS, TaskStatus.PENDING])
        )
        
        if project_id:
            query = query.filter(Task.project_id == project_id)
        
        in_progress = query.filter(Task.status == TaskStatus.IN_PROGRESS).count()
        completed = db.query(Task).filter(Task.status == TaskStatus.COMPLETED).count()
        pending = query.filter(Task.status == TaskStatus.PENDING).count()
        
        return {
            'in_progress': in_progress,
            'completed': completed,
            'pending': pending,
            'total_active': in_progress + pending,
        }
    
    @staticmethod
    def get_productivity_percentage(db: Session, project_id: int = None) -> float:
        """Calculate overall productivity percentage"""
        query = db.query(Task)
        
        if project_id:
            query = query.filter(Task.project_id == project_id)
        
        tasks = query.all()
        if not tasks:
            return 0.0
        
        total_progress = sum([t.progress for t in tasks])
        avg_productivity = (total_progress / len(tasks)) if tasks else 0.0
        
        return round(avg_productivity, 2)
    
    @staticmethod
    def get_alerts(db: Session, project_id: int = None) -> dict:
        """Get alerts for dashboard"""
        alerts = []
        
        # Check for overdue tasks
        overdue_tasks = db.query(Task).filter(
            and_(
                Task.due_date < datetime.utcnow(),
                Task.status != TaskStatus.COMPLETED
            )
        ).all()
        
        for task in overdue_tasks:
            alerts.append({
                'type': 'overdue_task',
                'message': f'Task "{task.title}" is overdue',
                'severity': 'high',
                'task_id': task.id,
            })
        
        # Check for absent workers
        today = datetime.utcnow().date()
        absent_records = db.query(AttendanceRecord).filter(
            and_(
                func.date(AttendanceRecord.date) == today,
                AttendanceRecord.status == AttendanceStatus.ABSENT
            )
        ).all()
        
        if len(absent_records) > 0:
            alerts.append({
                'type': 'absent_workers',
                'message': f'{len(absent_records)} workers absent today',
                'severity': 'medium',
                'count': len(absent_records),
            })
        
        # Check for low productivity
        projects = db.query(Project).all() if not project_id else db.query(Project).filter(Project.id == project_id).all()
        
        for project in projects:
            productivity = DashboardService.get_productivity_percentage(db, project.id)
            if productivity < 50:
                alerts.append({
                    'type': 'low_productivity',
                    'message': f'Project "{project.name}" productivity is below 50%',
                    'severity': 'medium',
                    'project_id': project.id,
                    'percentage': productivity,
                })
        
        return {
            'total': len(alerts),
            'alerts': alerts[:5],  # Return top 5 alerts
        }
    
    @staticmethod
    def get_weekly_attendance(db: Session, project_id: int = None) -> list:
        """Get weekly attendance data"""
        days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
        weekly_data = []
        
        for i in range(7):
            date = datetime.utcnow().date() - timedelta(days=6-i)
            
            query = db.query(func.count(AttendanceRecord.id)).filter(
                and_(
                    func.date(AttendanceRecord.date) == date,
                    or_(
                        AttendanceRecord.status == AttendanceStatus.PRESENT,
                        AttendanceRecord.status == AttendanceStatus.LATE
                    )
                )
            )
            
            if project_id:
                query = query.filter(AttendanceRecord.project_id == project_id)
            
            count = query.scalar() or 0
            weekly_data.append({
                'day': days[i],
                'value': count,
            })
        
        return weekly_data
    
    @staticmethod
    def get_task_distribution(db: Session, project_id: int = None) -> list:
        """Get task distribution data"""
        query = db.query(Task)
        
        if project_id:
            query = query.filter(Task.project_id == project_id)
        
        completed = query.filter(Task.status == TaskStatus.COMPLETED).count()
        in_progress = query.filter(Task.status == TaskStatus.IN_PROGRESS).count()
        pending = query.filter(Task.status == TaskStatus.PENDING).count()
        
        return [
            {'name': 'Completed', 'value': completed},
            {'name': 'In Progress', 'value': in_progress},
            {'name': 'Pending', 'value': pending},
        ]
    
    @staticmethod
    def get_dashboard_summary(db: Session, project_id: int = None) -> dict:
        """Get complete dashboard summary"""
        return {
            'workers_on_site': DashboardService.get_workers_on_site(db, project_id),
            'active_tasks': DashboardService.get_active_tasks(db, project_id),
            'productivity': DashboardService.get_productivity_percentage(db, project_id),
            'alerts': DashboardService.get_alerts(db, project_id),
            'weekly_attendance': DashboardService.get_weekly_attendance(db, project_id),
            'task_distribution': DashboardService.get_task_distribution(db, project_id),
        }
