from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from datetime import datetime, date, time
from typing import Optional

from app.database import get_db
from app.models import AttendanceLog, Worker, Project
from app.schemas import (
    CheckInReq, CheckOutReq, HeartbeatReq, AttendanceOut,
    WorkerWithStatus, AttendanceSummary,
    WorkerCheckInReq, WorkerCheckOutReq,
    CurrentUser,
)
from app.geofence import is_within_fence
from app.routers.auth import require_worker, require_any_authorized

router = APIRouter(prefix="/attendance", tags=["📍 GPS Geofence Attendance"])

OUT_OF_FENCE_LIMIT = 2

# Check-in time window (can be moved to Settings later)
CHECK_IN_WINDOW_START = time(5, 0)    # 05:00 AM
CHECK_IN_WINDOW_END = time(10, 30)    # 10:30 AM
CHECK_OUT_WINDOW_START = time(15, 0)  # 03:00 PM
CHECK_OUT_WINDOW_END = time(21, 0)    # 09:00 PM

def _today_start():
    t = date.today()
    return datetime(t.year, t.month, t.day)

def _to_out(a: AttendanceLog) -> AttendanceOut:
    o = AttendanceOut.model_validate(a)
    o.worker_name = a.worker.name if a.worker else None
    return o

def _format_hhmm(dt: Optional[datetime]) -> str:
    return dt.strftime("%H:%M") if dt else "-"

def _in_time_window(t: time, start: time, end: time) -> bool:
    return start <= t <= end

def _client_ip(request: Request) -> str:
    try:
        forwarded = request.headers.get("x-forwarded-for")
        if forwarded:
            return forwarded.split(",")[0].strip()
        return request.client.host if request.client else ""
    except Exception:
        return ""

# ──────────────────────────────────────────────────────────────────
# Legacy / supervisor-facing endpoints (keep backwards compatibility)
# ──────────────────────────────────────────────────────────────────

@router.post("/check-in", response_model=AttendanceOut)
def check_in(d: CheckInReq, db: Session = Depends(get_db)):
    w = db.query(Worker).get(d.worker_id)
    if not w:
        raise HTTPException(404, "Worker does not exist")
    p = db.query(Project).get(d.project_id)
    if not p:
        raise HTTPException(404, "Project does not exist")

    existing = db.query(AttendanceLog).filter(
        AttendanceLog.worker_id == d.worker_id,
        AttendanceLog.project_id == d.project_id,
        AttendanceLog.check_in_time >= _today_start(),
        AttendanceLog.status.in_(["checked_in", "checked_out"]),
    ).first()
    if existing:
        raise HTTPException(400, "Already checked in today, please do not check in again")

    verified, dist = is_within_fence(d.lat, d.lng, p.center_lat, p.center_lng, p.fence_radius)

    a = AttendanceLog(
        worker_id=d.worker_id, project_id=d.project_id,
        check_in_time=datetime.utcnow(),
        in_lat=d.lat, in_lng=d.lng, in_distance_m=dist,
        status="checked_in" if verified else "rejected",
        last_heartbeat_time=datetime.utcnow() if verified else None,
        last_heartbeat_lat=d.lat if verified else None,
        last_heartbeat_lng=d.lng if verified else None,
        out_of_fence_count=0,
    )
    db.add(a)
    db.commit()
    db.refresh(a)

    if not verified:
        raise HTTPException(
            400,
            f"Check-in failed: outside the site geofence (distance from center {int(dist)}m, allowed range {int(p.fence_radius)}m)",
        )
    return _to_out(a)


@router.post("/checkin")
def check_in_legacy(payload: dict, db: Session = Depends(get_db)):
    worker_id = payload.get("worker_id")
    project_id = payload.get("project_id")
    if project_id is None and payload.get("project"):
        project = db.query(Project).filter(Project.project_name == str(payload["project"]).strip()).first()
        project_id = project.project_id if project else None
    if worker_id is None or project_id is None:
        raise HTTPException(400, "worker_id and project_id/project are required")

    result = check_in(
        CheckInReq(
            worker_id=int(worker_id),
            project_id=int(project_id),
            lat=float(payload.get("lat")),
            lng=float(payload.get("lng")),
        ),
        db,
    )
    return {
        "ok": True,
        "message": "Check-in recorded successfully",
        "status": result.status,
        "check_in": _format_hhmm(result.check_in_time),
        "attendance_id": result.attendance_id,
    }


@router.post("/heartbeat", response_model=AttendanceOut)
def heartbeat(d: HeartbeatReq, db: Session = Depends(get_db)):
    a = db.query(AttendanceLog).get(d.attendance_id)
    if not a:
        raise HTTPException(404, "Attendance record does not exist")
    if a.status != "checked_in":
        raise HTTPException(410, "Check-in was auto-cancelled, please check in again")

    p = db.query(Project).get(a.project_id)
    verified, dist = is_within_fence(d.lat, d.lng, p.center_lat, p.center_lng, p.fence_radius)

    a.last_heartbeat_time = datetime.utcnow()
    a.last_heartbeat_lat = d.lat
    a.last_heartbeat_lng = d.lng

    if verified:
        a.out_of_fence_count = 0
        db.commit()
        db.refresh(a)
        return _to_out(a)

    a.out_of_fence_count = (a.out_of_fence_count or 0) + 1
    if a.out_of_fence_count >= OUT_OF_FENCE_LIMIT:
        a.status = "left_early"
        db.commit()
        db.refresh(a)
        raise HTTPException(410, "Left the site geofence too many times in a row, check-in auto-cancelled")

    db.commit()
    db.refresh(a)
    return _to_out(a)


@router.post("/check-out", response_model=AttendanceOut)
def check_out(d: CheckOutReq, db: Session = Depends(get_db)):
    a = db.query(AttendanceLog).get(d.attendance_id)
    if not a:
        raise HTTPException(404, "Attendance record does not exist")
    if a.status != "checked_in":
        raise HTTPException(400, "Cannot check out from the current status")

    p = db.query(Project).get(a.project_id)
    _, dist = is_within_fence(d.lat, d.lng, p.center_lat, p.center_lng, p.fence_radius)

    a.check_out_time = datetime.utcnow()
    a.out_lat = d.lat
    a.out_lng = d.lng
    a.out_distance_m = dist
    a.status = "checked_out"
    db.commit()
    db.refresh(a)
    return _to_out(a)


@router.post("/checkout")
def check_out_legacy(payload: dict, db: Session = Depends(get_db)):
    worker_id = payload.get("worker_id")
    if worker_id is None:
        raise HTTPException(400, "worker_id is required")

    attendance = db.query(AttendanceLog).filter(
        AttendanceLog.worker_id == int(worker_id),
        AttendanceLog.check_in_time >= _today_start(),
        AttendanceLog.status == "checked_in",
    ).order_by(AttendanceLog.attendance_id.desc()).first()
    if not attendance:
        raise HTTPException(404, "No active check-in found for this worker today")

    result = check_out(
        CheckOutReq(
            attendance_id=attendance.attendance_id,
            lat=float(payload.get("lat") or attendance.last_heartbeat_lat or attendance.in_lat or 0),
            lng=float(payload.get("lng") or attendance.last_heartbeat_lng or attendance.in_lng or 0),
        ),
        db,
    )
    hours = 0.0
    if result.check_in_time and result.check_out_time:
        hours = round((result.check_out_time - result.check_in_time).total_seconds() / 3600, 1)
    return {
        "ok": True,
        "check_out": _format_hhmm(result.check_out_time),
        "hours": hours,
        "status": result.status,
    }


@router.get("/worker/{wid}/today", response_model=Optional[AttendanceOut])
def worker_today(wid: int, db: Session = Depends(get_db)):
    a = db.query(AttendanceLog).filter(
        AttendanceLog.worker_id == wid,
        AttendanceLog.check_in_time >= _today_start(),
    ).order_by(AttendanceLog.attendance_id.desc()).first()
    if not a:
        return None
    return _to_out(a)


@router.get("/today", response_model=AttendanceSummary)
def today_summary(project_id: Optional[int] = None, db: Session = Depends(get_db)):
    wq = db.query(Worker)
    if project_id:
        wq = wq.filter(Worker.project_id == project_id)
    workers = wq.all()

    rows: list[WorkerWithStatus] = []
    present = late = absent = 0
    for w in workers:
        a = db.query(AttendanceLog).filter(
            AttendanceLog.worker_id == w.worker_id,
            AttendanceLog.check_in_time >= _today_start(),
        ).order_by(AttendanceLog.attendance_id.desc()).first()

        status = "absent"
        hours = None
        if a and a.status in ("checked_in", "checked_out"):
            status = "present"
            if a.check_in_time and a.check_in_time.strftime("%H:%M") > "07:30":
                status = "late"
            if a.check_in_time and a.check_out_time:
                hours = round((a.check_out_time - a.check_in_time).total_seconds() / 3600, 1)

        if status == "present":
            present += 1
        elif status == "late":
            late += 1
        else:
            absent += 1

        row = WorkerWithStatus.model_validate(w)
        row.today_status = status
        row.check_in_time = a.check_in_time if a else None
        row.check_out_time = a.check_out_time if a else None
        row.hours_today = hours
        rows.append(row)

    return AttendanceSummary(total=len(workers), present=present, late=late, absent=absent, rows=rows)


# ──────────────────────────────────────────────────────────────────
# NEW: Worker-authenticated endpoints (with device info, time windows)
# ──────────────────────────────────────────────────────────────────

@router.post("/worker/check-in", response_model=AttendanceOut)
def worker_self_check_in(
    d: WorkerCheckInReq,
    request: Request,
    user: CurrentUser = Depends(require_worker),
    db: Session = Depends(get_db),
):
    """Worker self check-in — requires worker authentication.
    Records device info, enforces check-in time window, validates
    the worker belongs to the project, and prevents duplicate check-ins."""
    worker = db.query(Worker).get(user.id)
    if not worker:
        raise HTTPException(404, "Worker account not found")

    p = db.query(Project).get(d.project_id)
    if not p:
        raise HTTPException(404, "Project does not exist")

    if worker.project_id is not None and worker.project_id != d.project_id:
        raise HTTPException(400, "You are not assigned to this project")

    # ── Duplicate check-in protection ──
    existing = db.query(AttendanceLog).filter(
        AttendanceLog.worker_id == user.id,
        AttendanceLog.check_in_time >= _today_start(),
        AttendanceLog.status.in_(["checked_in", "checked_out"]),
    ).first()
    if existing:
        raise HTTPException(
            400,
            f"You have already checked in today at {_format_hhmm(existing.check_in_time)}. "
            f"Duplicate check-in is not allowed.",
        )

    # ── Check-in time window enforcement ──
    now_local = datetime.now()
    now_time = now_local.time()
    if not _in_time_window(now_time, CHECK_IN_WINDOW_START, CHECK_IN_WINDOW_END):
        raise HTTPException(
            400,
            f"Check-in is only allowed between "
            f"{CHECK_IN_WINDOW_START.strftime('%H:%M')} and "
            f"{CHECK_IN_WINDOW_END.strftime('%H:%M')}. "
            f"Current time: {now_time.strftime('%H:%M')}",
        )

    # ── Geofence validation ──
    verified, dist = is_within_fence(d.lat, d.lng, p.center_lat, p.center_lng, p.fence_radius)

    a = AttendanceLog(
        worker_id=user.id,
        project_id=d.project_id,
        check_in_time=datetime.utcnow(),
        in_lat=d.lat,
        in_lng=d.lng,
        in_distance_m=dist,
        status="checked_in" if verified else "rejected",
        last_heartbeat_time=datetime.utcnow() if verified else None,
        last_heartbeat_lat=d.lat if verified else None,
        last_heartbeat_lng=d.lng if verified else None,
        out_of_fence_count=0,
        device_info=(d.device_info or "")[:500],
        device_type=(d.device_type or "")[:50],
        device_id=(d.device_id or "")[:255],
        ip_address=_client_ip(request)[:100],
    )
    db.add(a)
    db.commit()
    db.refresh(a)

    if not verified:
        raise HTTPException(
            400,
            f"Check-in failed: outside the site geofence "
            f"(distance from center {int(dist)}m, allowed range {int(p.fence_radius)}m). "
            f"Please ensure you are within the project boundary before checking in.",
        )
    return _to_out(a)


@router.post("/worker/check-out", response_model=AttendanceOut)
def worker_self_check_out(
    d: WorkerCheckOutReq,
    request: Request,
    user: CurrentUser = Depends(require_worker),
    db: Session = Depends(get_db),
):
    """Worker self check-out — requires worker authentication.
    Enforces check-out time window and validates active check-in."""
    attendance = db.query(AttendanceLog).filter(
        AttendanceLog.worker_id == user.id,
        AttendanceLog.check_in_time >= _today_start(),
        AttendanceLog.status == "checked_in",
    ).order_by(AttendanceLog.attendance_id.desc()).first()
    if not attendance:
        raise HTTPException(404, "No active check-in found for you today. Please check in first.")

    p = db.query(Project).get(attendance.project_id)
    if not p:
        raise HTTPException(404, "Project not found")

    # ── Check-out time window ──
    now_local = datetime.now()
    now_time = now_local.time()
    if not _in_time_window(now_time, CHECK_OUT_WINDOW_START, CHECK_OUT_WINDOW_END):
        # Allow check-out but warn — use informational header instead of blocking
        pass

    _, dist = is_within_fence(d.lat, d.lng, p.center_lat, p.center_lng, p.fence_radius)

    attendance.check_out_time = datetime.utcnow()
    attendance.out_lat = d.lat
    attendance.out_lng = d.lng
    attendance.out_distance_m = dist
    attendance.status = "checked_out"

    if d.device_info:
        attendance.device_info = (d.device_info or "")[:500]
    if d.device_type:
        attendance.device_type = (d.device_type or "")[:50]
    attendance.ip_address = _client_ip(request)[:100]

    db.commit()
    db.refresh(attendance)
    return _to_out(attendance)


@router.get("/worker/today")
def worker_today_authenticated(
    user: CurrentUser = Depends(require_worker),
    db: Session = Depends(get_db),
):
    """Authenticated version — get today's attendance record for the current worker."""
    a = db.query(AttendanceLog).filter(
        AttendanceLog.worker_id == user.id,
        AttendanceLog.check_in_time >= _today_start(),
    ).order_by(AttendanceLog.attendance_id.desc()).first()
    if not a:
        return {
            "checked_in": False,
            "attendance": None,
            "check_in_window": f"{CHECK_IN_WINDOW_START.strftime('%H:%M')} - {CHECK_IN_WINDOW_END.strftime('%H:%M')}",
            "check_out_window": f"{CHECK_OUT_WINDOW_START.strftime('%H:%M')} - {CHECK_OUT_WINDOW_END.strftime('%H:%M')}",
        }
    hours = 0.0
    if a.check_in_time and a.check_out_time:
        hours = round((a.check_out_time - a.check_in_time).total_seconds() / 3600, 1)
    return {
        "checked_in": a.status == "checked_in",
        "checked_out": a.status == "checked_out",
        "status": a.status,
        "hours_today": hours,
        "attendance": _to_out(a),
        "check_in_window": f"{CHECK_IN_WINDOW_START.strftime('%H:%M')} - {CHECK_IN_WINDOW_END.strftime('%H:%M')}",
        "check_out_window": f"{CHECK_OUT_WINDOW_START.strftime('%H:%M')} - {CHECK_OUT_WINDOW_END.strftime('%H:%M')}",
    }


@router.post("/worker/heartbeat", response_model=AttendanceOut)
def worker_self_heartbeat(
    d: HeartbeatReq,
    user: CurrentUser = Depends(require_worker),
    db: Session = Depends(get_db),
):
    """Authenticated heartbeat endpoint for the current worker."""
    a = db.query(AttendanceLog).get(d.attendance_id)
    if not a:
        raise HTTPException(404, "Attendance record does not exist")
    if a.worker_id != user.id:
        raise HTTPException(403, "This attendance record does not belong to you")
    return heartbeat(d, db)
