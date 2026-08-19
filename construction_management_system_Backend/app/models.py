from sqlalchemy import Column, Integer, String, Float, DateTime, Date, Text, Boolean, ForeignKey, UniqueConstraint, func
from sqlalchemy.orm import relationship
from app.database import Base

class Supervisor(Base):
    __tablename__ = "supervisors"
    supervisor_id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    full_name = Column(String(100), nullable=False)
    email = Column(String(100), unique=True, nullable=False)
    password_hash = Column(String(255), nullable=False)
    phone = Column(String(50), nullable=True)
    role = Column(String(50), default="site_supervisor")
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    projects = relationship("Project", back_populates="supervisor")
    reports = relationship("DailyReport", back_populates="submitter")

class Project(Base):
    __tablename__ = "projects"
    project_id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    project_name = Column(String(200), nullable=False)
    location_address = Column(String(500), nullable=False)
    start_date = Column(Date, nullable=True)
    end_date = Column(Date, nullable=True)
    status = Column(String(50), default="planning")
    progress = Column(Float, default=0.0)
    supervisor_id = Column(Integer, ForeignKey("supervisors.supervisor_id"), nullable=True)
    # ✅ GPS geofence (used for check-in)
    center_lat = Column(Float, nullable=False, server_default="3.1390")
    center_lng = Column(Float, nullable=False, server_default="101.6869")
    fence_radius = Column(Float, nullable=False, server_default="5000.0")  # unit: meters
    supervisor = relationship("Supervisor", back_populates="projects")
    workers = relationship("Worker", back_populates="project")
    tasks = relationship("Task", back_populates="project")
    issues = relationship("Issue", back_populates="project")
    reports = relationship("DailyReport", back_populates="project")

class Worker(Base):
    __tablename__ = "workers"
    worker_id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    name = Column(String(100), nullable=False)
    ic_number = Column(String(50), unique=True, nullable=True)
    phone = Column(String(50), nullable=True)
    trade = Column(String(100), nullable=True)
    project_id = Column(Integer, ForeignKey("projects.project_id"), nullable=True)
    has_safety_training = Column(Boolean, nullable=False, server_default="0")
    is_safety_officer = Column(Boolean, nullable=False, server_default="0")
    email = Column(String(100), unique=True, nullable=True)
    password_hash = Column(String(255), nullable=True)
    role = Column(String(50), default="worker")
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    project = relationship("Project", back_populates="workers")
    tasks = relationship("Task", back_populates="assigned_worker")
    task_links = relationship("TaskWorker", back_populates="worker", cascade="all, delete-orphan")
    attendance_logs = relationship("AttendanceLog", back_populates="worker")

class AttendanceLog(Base):
    __tablename__ = "attendance_logs"
    attendance_id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    worker_id = Column(Integer, ForeignKey("workers.worker_id"), nullable=False)
    project_id = Column(Integer, ForeignKey("projects.project_id"), nullable=False)
    check_in_time = Column(DateTime(timezone=True), server_default=func.now())
    check_out_time = Column(DateTime(timezone=True), nullable=True)
    # Precise location at check-in/check-out
    in_lat = Column(Float, nullable=True)
    in_lng = Column(Float, nullable=True)
    out_lat = Column(Float, nullable=True)
    out_lng = Column(Float, nullable=True)
    in_distance_m = Column(Float, nullable=True)   # distance from center at check-in
    out_distance_m = Column(Float, nullable=True)  # distance from center at check-out
    # ✅ Status: checked_in=on site / checked_out=checked out normally / left_early=auto-cancelled after leaving fence / absent=absent / rejected=check-in rejected
    status = Column(String(50), default="checked_in")
    last_heartbeat_time = Column(DateTime(timezone=True), nullable=True)  # last location report
    last_heartbeat_lat = Column(Float, nullable=True)
    last_heartbeat_lng = Column(Float, nullable=True)
    out_of_fence_count = Column(Integer, nullable=False, server_default="0")  # consecutive times outside the fence
    device_info = Column(String(500), nullable=True)   # Device make/model/OS info
    device_type = Column(String(50), nullable=True)    # android / ios / web / windows
    device_id = Column(String(255), nullable=True)     # Unique device identifier
    ip_address = Column(String(100), nullable=True)    # Client IP address at check-in
    worker = relationship("Worker", back_populates="attendance_logs")

class Task(Base):
    __tablename__ = "tasks"
    task_id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    task_name = Column(String(200), nullable=False)
    description = Column(Text, nullable=True)
    assigned_worker_id = Column(Integer, ForeignKey("workers.worker_id"), nullable=True)
    project_id = Column(Integer, ForeignKey("projects.project_id"), nullable=False)
    priority = Column(String(50), default="medium")
    status = Column(String(50), default="pending")
    due_date = Column(Date, nullable=True)
    ai_confidence = Column(Float, nullable=True)
    assigned_worker = relationship("Worker", back_populates="tasks")
    task_workers = relationship("TaskWorker", back_populates="task", cascade="all, delete-orphan")
    project = relationship("Project", back_populates="tasks")

    @property
    def assigned_workers(self) -> list:
        """Derived list of {worker_id, name, trade} for the task_workers links."""
        result = []
        for link in self.task_workers:
            if link.worker:
                result.append({
                    "worker_id": link.worker.worker_id,
                    "name": link.worker.name,
                    "trade": link.worker.trade,
                })
        return result

    @property
    def worker_ids(self) -> list:
        return [link.worker_id for link in self.task_workers]

class Issue(Base):
    __tablename__ = "issues"
    issue_id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    title = Column(String(200), nullable=False)
    description = Column(Text, nullable=False)
    project_id = Column(Integer, ForeignKey("projects.project_id"), nullable=False)
    reported_by = Column(Integer, ForeignKey("supervisors.supervisor_id"), nullable=True)
    status = Column(String(50), default="open")
    priority = Column(String(50), default="medium")
    image_path = Column(String(500), nullable=True)
    incident_type = Column(String(50), nullable=False, server_default="general")
    is_safety_incident = Column(Boolean, nullable=False, server_default="0")
    gps_lat = Column(Float, nullable=True)
    gps_lng = Column(Float, nullable=True)
    handled_by = Column(Integer, ForeignKey("workers.worker_id"), nullable=True)
    handled_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    resolved_at = Column(DateTime(timezone=True), nullable=True)
    project = relationship("Project", back_populates="issues")

class DailyReport(Base):
    __tablename__ = "daily_reports"
    report_id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    project_id = Column(Integer, ForeignKey("projects.project_id"), nullable=False)
    report_date = Column(Date, nullable=False)
    weather = Column(String(100), nullable=True)
    work_progress = Column(Text, nullable=True)
    issues_encountered = Column(Text, nullable=True)
    materials_used = Column(Text, nullable=True)
    manpower_count = Column(Integer, default=0)
    submitted_by = Column(Integer, ForeignKey("supervisors.supervisor_id"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    project = relationship("Project", back_populates="reports")
    submitter = relationship("Supervisor", back_populates="reports")

class Settings(Base):
    # Single-row table (id=1) holding company-wide app settings.
    __tablename__ = "settings"
    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    company_name = Column(String(200), nullable=False, server_default="BuildSmart Construction Sdn Bhd")
    system_language = Column(String(50), nullable=False, server_default="English")
    timezone = Column(String(100), nullable=False, server_default="Asia/Kuala_Lumpur (UTC+8)")
    date_format = Column(String(20), nullable=False, server_default="DD/MM/YYYY")
    work_start = Column(String(20), nullable=False, server_default="07:00 AM")
    work_end = Column(String(20), nullable=False, server_default="05:00 PM")
    late_threshold = Column(String(20), nullable=False, server_default="07:30 AM")
    notif_attendance = Column(Boolean, nullable=False, server_default="1")
    notif_task_overdue = Column(Boolean, nullable=False, server_default="1")
    notif_budget = Column(Boolean, nullable=False, server_default="1")
    notif_safety = Column(Boolean, nullable=False, server_default="1")
    notif_daily_summary = Column(Boolean, nullable=False, server_default="0")
    notif_weekly_report = Column(Boolean, nullable=False, server_default="0")


class File(Base):
    __tablename__ = "files"
    file_id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    original_name = Column(String(500), nullable=False)
    stored_name = Column(String(500), nullable=False)
    file_path = Column(String(1000), nullable=False)
    file_size = Column(Integer, nullable=False)
    mime_type = Column(String(100), nullable=False)
    file_category = Column(String(50), nullable=False, default="attachment")
    thumbnail_path = Column(String(1000), nullable=True)
    uploaded_by = Column(Integer, ForeignKey("supervisors.supervisor_id"), nullable=False)
    project_id = Column(Integer, ForeignKey("projects.project_id"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    uploader = relationship("Supervisor")
    project = relationship("Project")
    links = relationship("FileLink", back_populates="file", cascade="all, delete-orphan")


class FileLink(Base):
    __tablename__ = "file_links"
    link_id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    file_id = Column(Integer, ForeignKey("files.file_id"), nullable=False)
    entity_type = Column(String(50), nullable=False)
    entity_id = Column(Integer, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    file = relationship("File", back_populates="links")


class AIChatSession(Base):
    __tablename__ = "ai_chat_sessions"
    session_id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    supervisor_id = Column(Integer, ForeignKey("supervisors.supervisor_id"), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    supervisor = relationship("Supervisor")
    messages = relationship("AIChatMessage", back_populates="session", cascade="all, delete-orphan")


class AIChatMessage(Base):
    __tablename__ = "ai_chat_messages"
    message_id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    session_id = Column(Integer, ForeignKey("ai_chat_sessions.session_id"), nullable=False)
    role = Column(String(20), nullable=False)
    content = Column(Text, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    tokens_used = Column(Integer, nullable=True)
    session = relationship("AIChatSession", back_populates="messages")


class Notification(Base):
    __tablename__ = "notifications"
    notification_id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    supervisor_id = Column(Integer, ForeignKey("supervisors.supervisor_id"), nullable=False)
    notification_type = Column(String(50), nullable=False)
    title = Column(String(200), nullable=False)
    content = Column(Text, nullable=False)
    related_entity_type = Column(String(50), nullable=True)
    related_entity_id = Column(Integer, nullable=True)
    is_read = Column(Boolean, nullable=False, server_default="0")
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    read_at = Column(DateTime(timezone=True), nullable=True)
    supervisor = relationship("Supervisor")


class NotificationSetting(Base):
    __tablename__ = "notification_settings"
    setting_id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    supervisor_id = Column(Integer, ForeignKey("supervisors.supervisor_id"), nullable=False, unique=True)
    notif_attendance = Column(Boolean, nullable=False, server_default="1")
    notif_task_overdue = Column(Boolean, nullable=False, server_default="1")
    notif_task_assigned = Column(Boolean, nullable=False, server_default="1")
    notif_issue = Column(Boolean, nullable=False, server_default="1")
    notif_safety = Column(Boolean, nullable=False, server_default="1")
    notif_daily_report = Column(Boolean, nullable=False, server_default="0")
    notif_email = Column(Boolean, nullable=False, server_default="0")
    notif_push = Column(Boolean, nullable=False, server_default="0")
    supervisor = relationship("Supervisor")


class TaskWorker(Base):
    """Many-to-many link between Task and Worker (multi-worker assignment).

    Keeps the legacy Task.assigned_worker_id column in sync (first worker) so
    existing front-ends continue to work while the association table holds the
    full list of assigned workers.
    """
    __tablename__ = "task_workers"
    __table_args__ = (
        UniqueConstraint("task_id", "worker_id", name="uq_task_worker"),
    )
    link_id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    task_id = Column(Integer, ForeignKey("tasks.task_id"), nullable=False)
    worker_id = Column(Integer, ForeignKey("workers.worker_id"), nullable=False)
    assigned_at = Column(DateTime(timezone=True), server_default=func.now())
    task = relationship("Task", back_populates="task_workers")
    worker = relationship("Worker", back_populates="task_links")