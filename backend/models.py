from sqlalchemy import Column, Integer, String, Float, DateTime, Enum, ForeignKey, Boolean, Text
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import relationship
from datetime import datetime
import enum

Base = declarative_base()


class ProjectStatus(enum.Enum):
    ON_TRACK = "On Track"
    AT_RISK = "At Risk"
    DELAYED = "Delayed"


class TaskStatus(enum.Enum):
    IN_PROGRESS = "In Progress"
    COMPLETED = "Completed"
    PENDING = "Pending"


class TaskPriority(enum.Enum):
    HIGH = "High"
    MEDIUM = "Medium"
    LOW = "Low"


class AttendanceStatus(enum.Enum):
    PRESENT = "Present"
    LATE = "Late"
    ABSENT = "Absent"


class Project(Base):
    __tablename__ = "projects"
    
    id = Column(Integer, primary_key=True)
    name = Column(String(255), nullable=False)
    location = Column(String(255))
    description = Column(Text)
    progress = Column(Float, default=0.0)
    status = Column(Enum(ProjectStatus), default=ProjectStatus.ON_TRACK)
    total_budget = Column(Float)
    amount_spent = Column(Float, default=0.0)
    start_date = Column(DateTime, default=datetime.utcnow)
    end_date = Column(DateTime)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Relationships
    tasks = relationship("Task", back_populates="project")
    workers = relationship("ProjectWorker", back_populates="project")
    
    def to_dict(self):
        return {
            'id': self.id,
            'name': self.name,
            'location': self.location,
            'description': self.description,
            'progress': self.progress,
            'status': self.status.value if self.status else None,
            'total_budget': self.total_budget,
            'amount_spent': self.amount_spent,
            'start_date': self.start_date.isoformat() if self.start_date else None,
            'end_date': self.end_date.isoformat() if self.end_date else None,
        }


class Worker(Base):
    __tablename__ = "workers"
    
    id = Column(Integer, primary_key=True)
    name = Column(String(255), nullable=False)
    role = Column(String(255))
    email = Column(String(255), unique=True)
    phone = Column(String(20))
    rating = Column(Float, default=4.0)
    hours_logged = Column(Integer, default=0)
    tasks_completed = Column(Integer, default=0)
    status = Column(String(50), default="Active")  # Active, Inactive, On Leave
    hourly_rate = Column(Float)
    certifications = Column(Text)  # JSON string of certifications
    skills = Column(Text)  # JSON string of skills
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Relationships
    tasks = relationship("Task", back_populates="assigned_worker")
    attendance_records = relationship("AttendanceRecord", back_populates="worker")
    project_assignments = relationship("ProjectWorker", back_populates="worker")
    
    def to_dict(self):
        return {
            'id': self.id,
            'name': self.name,
            'role': self.role,
            'email': self.email,
            'phone': self.phone,
            'rating': self.rating,
            'hours_logged': self.hours_logged,
            'tasks_completed': self.tasks_completed,
            'status': self.status,
            'hourly_rate': self.hourly_rate,
        }


class ProjectWorker(Base):
    __tablename__ = "project_workers"
    
    id = Column(Integer, primary_key=True)
    project_id = Column(Integer, ForeignKey('projects.id'))
    worker_id = Column(Integer, ForeignKey('workers.id'))
    assigned_date = Column(DateTime, default=datetime.utcnow)
    
    # Relationships
    project = relationship("Project", back_populates="workers")
    worker = relationship("Worker", back_populates="project_assignments")


class Task(Base):
    __tablename__ = "tasks"
    
    id = Column(Integer, primary_key=True)
    title = Column(String(255), nullable=False)
    description = Column(Text)
    project_id = Column(Integer, ForeignKey('projects.id'))
    assigned_worker_id = Column(Integer, ForeignKey('workers.id'))
    priority = Column(Enum(TaskPriority), default=TaskPriority.MEDIUM)
    status = Column(Enum(TaskStatus), default=TaskStatus.PENDING)
    progress = Column(Float, default=0.0)
    hours_logged = Column(Float, default=0.0)
    estimated_hours = Column(Float)
    required_skills = Column(Text)  # JSON string
    ai_match_score = Column(Float, default=0.0)  # AI matching percentage
    due_date = Column(DateTime)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Relationships
    project = relationship("Project", back_populates="tasks")
    assigned_worker = relationship("Worker", back_populates="tasks")
    
    def to_dict(self):
        return {
            'id': self.id,
            'title': self.title,
            'description': self.description,
            'project_id': self.project_id,
            'priority': self.priority.value if self.priority else None,
            'status': self.status.value if self.status else None,
            'progress': self.progress,
            'hours_logged': self.hours_logged,
            'estimated_hours': self.estimated_hours,
            'ai_match_score': self.ai_match_score,
            'due_date': self.due_date.isoformat() if self.due_date else None,
        }


class AttendanceRecord(Base):
    __tablename__ = "attendance_records"
    
    id = Column(Integer, primary_key=True)
    worker_id = Column(Integer, ForeignKey('workers.id'))
    project_id = Column(Integer, ForeignKey('projects.id'))
    date = Column(DateTime, default=datetime.utcnow)
    check_in_time = Column(DateTime)
    check_out_time = Column(DateTime)
    status = Column(Enum(AttendanceStatus), default=AttendanceStatus.ABSENT)
    hours_worked = Column(Float, default=0.0)
    location = Column(String(255))  # GPS coordinates or location name
    method = Column(String(50), default="Geofence")  # Geofence, Manual, RFID, etc.
    
    # Relationships
    worker = relationship("Worker", back_populates="attendance_records")
    
    def to_dict(self):
        return {
            'id': self.id,
            'worker_id': self.worker_id,
            'project_id': self.project_id,
            'date': self.date.isoformat() if self.date else None,
            'check_in_time': self.check_in_time.isoformat() if self.check_in_time else None,
            'check_out_time': self.check_out_time.isoformat() if self.check_out_time else None,
            'status': self.status.value if self.status else None,
            'hours_worked': self.hours_worked,
            'location': self.location,
            'method': self.method,
        }


class DashboardMetrics(Base):
    __tablename__ = "dashboard_metrics"
    
    id = Column(Integer, primary_key=True)
    project_id = Column(Integer, ForeignKey('projects.id'))
    date = Column(DateTime, default=datetime.utcnow)
    workers_on_site = Column(Integer, default=0)
    active_tasks = Column(Integer, default=0)
    productivity_percentage = Column(Float, default=0.0)
    alerts_count = Column(Integer, default=0)
    
    def to_dict(self):
        return {
            'id': self.id,
            'project_id': self.project_id,
            'date': self.date.isoformat() if self.date else None,
            'workers_on_site': self.workers_on_site,
            'active_tasks': self.active_tasks,
            'productivity_percentage': self.productivity_percentage,
            'alerts_count': self.alerts_count,
        }
