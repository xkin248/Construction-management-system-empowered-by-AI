from pydantic import BaseModel, Field, ConfigDict, EmailStr
from typing import Optional, List, Dict, Any
from datetime import date, datetime

# 1. Supervisor
class SupervisorBase(BaseModel):
    full_name: str = Field(..., max_length=100)
    email: EmailStr
    phone: Optional[str] = Field(None, max_length=50)
    role: Optional[str] = "site_supervisor"
class SupervisorCreate(SupervisorBase):
    password: str = Field(..., min_length=6, max_length=100)
class SupervisorOut(SupervisorBase):
    supervisor_id: int; created_at: Optional[datetime] = None
    model_config = ConfigDict(from_attributes=True)

# 2. Project
class ProjectBase(BaseModel):
    project_name: str = Field(..., max_length=200)
    location_address: str = Field(..., max_length=500)
    start_date: Optional[date] = None
    end_date: Optional[date] = None
    status: Optional[str] = "planning"
    progress: Optional[float] = Field(0.0, ge=0, le=100)
    supervisor_id: Optional[int] = None
    center_lat: Optional[float] = 3.1390
    center_lng: Optional[float] = 101.6869
    fence_radius: Optional[float] = 500.0
class ProjectCreate(ProjectBase): pass
class ProjectOut(ProjectBase):
    project_id: int; supervisor: Optional[SupervisorOut] = None
    model_config = ConfigDict(from_attributes=True)

# 3. Worker
class WorkerBase(BaseModel):
    name: str = Field(..., max_length=100)
    ic_number: Optional[str] = Field(None, max_length=50)
    phone: Optional[str] = Field(None, max_length=50)
    trade: Optional[str] = Field(None, max_length=100)
    project_id: Optional[int] = None
    has_safety_training: Optional[bool] = False
    is_safety_officer: Optional[bool] = False
class WorkerCreate(WorkerBase): pass
class WorkerOut(WorkerBase):
    worker_id: int; project: Optional[ProjectOut] = None
    email: Optional[str] = None
    role: Optional[str] = None
    created_at: Optional[datetime] = None
    model_config = ConfigDict(from_attributes=True)

# Worker Auth Schemas
class WorkerAuthBase(BaseModel):
    name: str = Field(..., max_length=100)
    email: EmailStr
    phone: Optional[str] = Field(None, max_length=50)
    ic_number: Optional[str] = Field(None, max_length=50)
    trade: Optional[str] = Field(None, max_length=100)
    project_id: Optional[int] = None
    role: str = "worker"
class WorkerAuthCreate(WorkerAuthBase):
    password: str = Field(..., min_length=6, max_length=100)
class WorkerAuthOut(WorkerAuthBase):
    worker_id: int
    created_at: Optional[datetime] = None
    model_config = ConfigDict(from_attributes=True)

# Unified current user wrapper (can hold either Supervisor or Worker)
class CurrentUser(BaseModel):
    user_type: str    # "supervisor" or "worker"
    id: int
    email: str
    name: str
    role: str
    phone: Optional[str] = None
    model_config = ConfigDict(from_attributes=True)

# 4. Attendance (GPS geofence check-in)
class CheckInReq(BaseModel):
    worker_id: int; project_id: int; lat: float; lng: float
class CheckOutReq(BaseModel):
    attendance_id: int; lat: float; lng: float
class HeartbeatReq(BaseModel):
    attendance_id: int; lat: float; lng: float
class AttendanceOut(BaseModel):
    attendance_id: int; worker_id: int; worker_name: Optional[str] = None
    project_id: int
    check_in_time: Optional[datetime] = None
    check_out_time: Optional[datetime] = None
    in_distance_m: Optional[float] = None
    out_distance_m: Optional[float] = None
    status: str
    out_of_fence_count: int = 0
    last_heartbeat_time: Optional[datetime] = None
    device_info: Optional[str] = None
    device_type: Optional[str] = None
    ip_address: Optional[str] = None
    model_config = ConfigDict(from_attributes=True)

# Worker check-in with device info
class WorkerCheckInReq(BaseModel):
    project_id: int
    lat: float
    lng: float
    device_info: Optional[str] = None
    device_type: Optional[str] = None
    device_id: Optional[str] = None
class WorkerCheckOutReq(BaseModel):
    lat: float
    lng: float
    device_info: Optional[str] = None
    device_type: Optional[str] = None

# Worker Task Board (AI-assigned tasks for a specific worker)
class WorkerTaskItem(BaseModel):
    task_id: int
    task_name: str
    description: Optional[str] = None
    project_id: int
    project_name: str
    priority: str
    status: str
    due_date: Optional[date] = None
    ai_confidence: Optional[float] = None
    assigned_at: Optional[datetime] = None
    part_section: Optional[str] = None
    work_instructions: Optional[str] = None
class WorkerTaskBoardResponse(BaseModel):
    worker_id: int
    worker_name: str
    last_updated: datetime
    tasks: List[WorkerTaskItem]
    summary: Optional[str] = None
    alert: Optional[str] = None
    ai_generated: bool = True

# 5. Task + AI Match
class TaskBase(BaseModel):
    task_name: str = Field(..., max_length=200)
    description: Optional[str] = None
    assigned_worker_id: Optional[int] = None
    project_id: int
    priority: Optional[str] = "medium"
    status: Optional[str] = "pending"
    due_date: Optional[date] = None
    ai_confidence: Optional[float] = Field(None, ge=0, le=1)
class TaskCreate(TaskBase): pass
class TaskOut(TaskBase):
    task_id: int; assigned_worker: Optional[WorkerOut] = None; project: Optional[ProjectOut] = None
    model_config = ConfigDict(from_attributes=True)
class AIMatchResult(BaseModel):
    worker_id: int; worker_name: str; trade: str; match_score: float; reason: str

# 6. Issue
class IssueBase(BaseModel):
    title: str = Field(..., max_length=200)
    description: str
    project_id: int
    reported_by: Optional[int] = None
    status: Optional[str] = "open"
    priority: Optional[str] = "medium"
    image_path: Optional[str] = None
    incident_type: Optional[str] = "general"
    is_safety_incident: Optional[bool] = False
    gps_lat: Optional[float] = None
    gps_lng: Optional[float] = None
class IssueCreate(IssueBase): pass
class IssueOut(IssueBase):
    issue_id: int; created_at: datetime; handled_at: Optional[datetime] = None
    project: Optional[ProjectOut] = None
    model_config = ConfigDict(from_attributes=True)

# 7. Daily Report
class DailyReportBase(BaseModel):
    project_id: int; report_date: date
    weather: Optional[str] = Field(None, max_length=100)
    work_progress: Optional[str] = None
    issues_encountered: Optional[str] = None
    materials_used: Optional[str] = None
    manpower_count: Optional[int] = 0
    submitted_by: Optional[int] = None
class DailyReportCreate(DailyReportBase): pass
class DailyReportOut(DailyReportBase):
    report_id: int; created_at: datetime
    project: Optional[ProjectOut] = None; submitter: Optional[SupervisorOut] = None
    model_config = ConfigDict(from_attributes=True)

# 8. Dashboard KPI
class DashboardKPI(BaseModel):
    total_projects: int; ongoing_projects: int; completed_projects: int
    total_workers: int; today_attendance: int; pending_tasks: int
    open_issues: int; today_reports: int

# 9. Worker + today's attendance status (for the Workers list/board screen)
class WorkerWithStatus(WorkerOut):
    today_status: str = "absent"           # present / late / absent (derived from today's AttendanceLog)
    check_in_time: Optional[datetime] = None
    check_out_time: Optional[datetime] = None
    hours_today: Optional[float] = None

# 10. Attendance summary (for the supervisor-facing Attendance table, distinct from the
# worker's own GPS check-in flow in /attendance/check-in etc.)
class AttendanceSummary(BaseModel):
    total: int; present: int; late: int; absent: int
    rows: List[WorkerWithStatus]

# 11. Settings (single company-wide row; geofence lives on Project, users on Supervisor)
class SettingsBase(BaseModel):
    company_name: str = "BuildSmart Construction Sdn Bhd"
    system_language: str = "English"
    timezone: str = "Asia/Kuala_Lumpur (UTC+8)"
    date_format: str = "DD/MM/YYYY"
    work_start: str = "07:00 AM"
    work_end: str = "05:00 PM"
    late_threshold: str = "07:30 AM"
    notif_attendance: bool = True
    notif_task_overdue: bool = True
    notif_budget: bool = True
    notif_safety: bool = True
    notif_daily_summary: bool = False
    notif_weekly_report: bool = False
class SettingsUpdate(SettingsBase): pass
class SettingsOut(SettingsBase):
    id: int
    model_config = ConfigDict(from_attributes=True)

# 12. Users & Roles (thin wrapper over Supervisor for the settings screen)
class UserInvite(BaseModel):
    full_name: str; email: EmailStr; role: str = "site_supervisor"
    password: str = Field(..., min_length=6, max_length=100)
class UserRoleUpdate(BaseModel):
    role: str


# 13. File Management
class FileBase(BaseModel):
    original_name: str = Field(..., max_length=500)
    file_category: str = Field("attachment", max_length=50)
    project_id: Optional[int] = None

class FileCreate(FileBase):
    pass

class FileUpdate(BaseModel):
    original_name: Optional[str] = Field(None, max_length=500)
    file_category: Optional[str] = Field(None, max_length=50)
    project_id: Optional[int] = None

class FileOut(FileBase):
    file_id: int
    stored_name: str
    file_path: str
    file_size: int
    mime_type: str
    thumbnail_path: Optional[str] = None
    uploaded_by: int
    created_at: datetime
    updated_at: datetime
    model_config = ConfigDict(from_attributes=True)

class FileLinkBase(BaseModel):
    file_id: int
    entity_type: str = Field(..., max_length=50)
    entity_id: int

class FileLinkCreate(FileLinkBase):
    pass

class FileLinkOut(FileLinkBase):
    link_id: int
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)


# 14. AI Chat
class AIChatMessageBase(BaseModel):
    role: str = Field(..., max_length=20)
    content: str

class AIChatMessageCreate(AIChatMessageBase):
    pass

class AIChatMessageOut(AIChatMessageBase):
    message_id: int
    session_id: int
    created_at: datetime
    tokens_used: Optional[int] = None
    model_config = ConfigDict(from_attributes=True)

class AIChatSessionBase(BaseModel):
    pass

class AIChatSessionCreate(AIChatSessionBase):
    pass

class AIChatSessionOut(AIChatSessionBase):
    session_id: int
    supervisor_id: int
    created_at: datetime
    updated_at: datetime
    messages: List[AIChatMessageOut] = []
    model_config = ConfigDict(from_attributes=True)

class AIChatRequest(BaseModel):
    message: str
    session_id: Optional[int] = None

class AITaskAnalysisRequest(BaseModel):
    task_id: Optional[int] = None
    task_name: Optional[str] = None
    description: Optional[str] = None
    project_id: int

class AITaskAnalysisResponse(BaseModel):
    suggested_workers: List[Dict[str, Any]]
    estimated_duration: Optional[str] = None
    priority_suggestion: Optional[str] = None
    safety_notes: Optional[str] = None

class AIAutoAssignRequest(BaseModel):
    project_id: int
    task_ids: Optional[List[int]] = None
    dry_run: bool = True
    top_k: int = 3

class AIAutoAssignItem(BaseModel):
    task_id: int
    task_name: str
    assigned_worker_id: Optional[int] = None
    suggested_workers: List[Dict[str, Any]] = []
    ai_used: bool = False

class AIAutoAssignResponse(BaseModel):
    project_id: int
    dry_run: bool
    assignments: List[AIAutoAssignItem]

class AIDailyReportRequest(BaseModel):
    project_id: int
    report_date: date

class AISafetyAnalysisRequest(BaseModel):
    issue_description: str
    project_id: Optional[int] = None


# 15. Notifications
class NotificationBase(BaseModel):
    notification_type: str = Field(..., max_length=50)
    title: str = Field(..., max_length=200)
    content: str
    related_entity_type: Optional[str] = Field(None, max_length=50)
    related_entity_id: Optional[int] = None

class NotificationCreate(NotificationBase):
    supervisor_id: int

class NotificationUpdate(BaseModel):
    is_read: Optional[bool] = None

class NotificationOut(NotificationBase):
    notification_id: int
    supervisor_id: int
    is_read: bool
    created_at: datetime
    read_at: Optional[datetime] = None
    model_config = ConfigDict(from_attributes=True)

class NotificationSettingBase(BaseModel):
    notif_attendance: bool = True
    notif_task_overdue: bool = True
    notif_task_assigned: bool = True
    notif_issue: bool = True
    notif_safety: bool = True
    notif_daily_report: bool = False
    notif_email: bool = False
    notif_push: bool = False

class NotificationSettingUpdate(NotificationSettingBase):
    pass

class NotificationSettingOut(NotificationSettingBase):
    setting_id: int
    supervisor_id: int
    model_config = ConfigDict(from_attributes=True)

class UnreadCountResponse(BaseModel):
    count: int
