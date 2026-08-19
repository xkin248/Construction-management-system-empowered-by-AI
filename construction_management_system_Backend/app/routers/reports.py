import io
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
from typing import List
from openpyxl import Workbook

from app.database import get_db
from app.models import DailyReport, Task, AttendanceLog, Project
from app.schemas import DailyReportCreate, DailyReportOut
from app.routers.auth import cu

router = APIRouter(tags=["📝 Daily Reports"])

@router.get("/projects/{pid}/reports", response_model=List[DailyReportOut])
def list_reports(pid: int, db: Session = Depends(get_db)):
    return db.query(DailyReport).filter(DailyReport.project_id == pid)\
        .order_by(DailyReport.report_date.desc()).all()

@router.post("/daily-reports", response_model=DailyReportOut)
def create_report(d: DailyReportCreate, db: Session = Depends(get_db)):
    # Only one submission per project per day
    ex = db.query(DailyReport).filter(
        DailyReport.project_id == d.project_id,
        DailyReport.report_date == d.report_date
    ).first()
    if ex: raise HTTPException(400, "A daily report has already been submitted for this project today")
    r = DailyReport(**d.model_dump())
    db.add(r); db.commit(); db.refresh(r); return r

@router.get("/reports/export/{project_id}")
def export_report(
    project_id: int,
    type: str = "tasks",
    db: Session = Depends(get_db),
    current_user=Depends(cu),
):
    """Export project data as an .xlsx file stream.

    type: tasks | attendance | daily_reports
    """
    project = db.query(Project).get(project_id)
    if not project:
        raise HTTPException(404, "Project does not exist")

    wb = Workbook()
    ws = wb.active

    if type == "tasks":
        ws.title = "Tasks"
        headers = ["任务ID", "任务名称", "描述", "负责人", "优先级", "状态", "截止日期"]
        ws.append(headers)
        tasks = db.query(Task).filter(Task.project_id == project_id).all()
        for t in tasks:
            ws.append([
                t.task_id,
                t.task_name,
                t.description or "",
                t.assigned_worker.name if t.assigned_worker else "",
                t.priority or "medium",
                t.status or "pending",
                t.due_date.isoformat() if t.due_date else "",
            ])
        filename = f"tasks_{project_id}.xlsx"
    elif type == "attendance":
        ws.title = "Attendance"
        headers = ["考勤ID", "工人", "项目ID", "签到时间", "签退时间", "状态", "设备类型", "进围栏距离(m)", "出围栏距离(m)"]
        ws.append(headers)
        logs = db.query(AttendanceLog).filter(
            AttendanceLog.project_id == project_id
        ).order_by(AttendanceLog.check_in_time.desc()).all()
        for a in logs:
            ws.append([
                a.attendance_id,
                a.worker.name if a.worker else "",
                a.project_id,
                a.check_in_time.strftime("%Y-%m-%d %H:%M:%S") if a.check_in_time else "",
                a.check_out_time.strftime("%Y-%m-%d %H:%M:%S") if a.check_out_time else "",
                a.status or "",
                a.device_type or "",
                a.in_distance_m if a.in_distance_m is not None else "",
                a.out_distance_m if a.out_distance_m is not None else "",
            ])
        filename = f"attendance_{project_id}.xlsx"
    elif type == "daily_reports":
        ws.title = "Daily Reports"
        headers = ["日报ID", "报告日期", "天气", "工作进度", "遇到的问题", "使用材料", "人力数量", "提交人"]
        ws.append(headers)
        reports = db.query(DailyReport).filter(
            DailyReport.project_id == project_id
        ).order_by(DailyReport.report_date.desc()).all()
        for r in reports:
            ws.append([
                r.report_id,
                r.report_date.isoformat() if r.report_date else "",
                r.weather or "",
                r.work_progress or "",
                r.issues_encountered or "",
                r.materials_used or "",
                r.manpower_count if r.manpower_count is not None else 0,
                r.submitter.full_name if r.submitter else "",
            ])
        filename = f"daily_reports_{project_id}.xlsx"
    else:
        raise HTTPException(400, "type must be one of: tasks, attendance, daily_reports")

    output = io.BytesIO()
    wb.save(output)
    output.seek(0)

    return StreamingResponse(
        output,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )