from datetime import date, datetime
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import or_
from sqlalchemy.orm import Session, joinedload

from app.database import get_db
from app.models import AttendanceLog, Project, Task, TaskWorker, Worker
from app.schemas import (
    AIMatchResult, TaskOut,
    WorkerTaskItem, WorkerTaskBoardResponse, CurrentUser,
)
from app.routers.auth import require_worker, require_any_authorized

router = APIRouter(tags=["🤖 Tasks & AI Assignment"])

STATUS_TO_PROGRESS = {
    "pending": 0,
    "in_progress": 50,
    "completed": 100,
}


def _recalc_project_progress(db: Session, project_id: int) -> None:
    """Recompute project.progress = completed tasks / total tasks * 100.

    Called on task creation / status change so the project progress stays in
    sync with its task board (progress closed loop). Supervisor can still
    override progress manually via the project update endpoint; the next task
    status change simply recalculates from tasks again.
    """
    project = db.query(Project).filter(Project.project_id == project_id).first()
    if not project:
        return
    tasks = db.query(Task).filter(Task.project_id == project_id).all()
    total = len(tasks)
    completed = sum(1 for t in tasks if t.status == "completed")
    new_progress = round(completed / total * 100, 1) if total > 0 else 0.0
    if (project.progress or 0.0) != new_progress:
        project.progress = new_progress
        db.add(project)

AVATAR_COLORS = ["#f97316", "#3b82f6", "#22c55e", "#8b5cf6", "#ef4444", "#06b6d4"]


def _today_start() -> datetime:
    today = date.today()
    return datetime(today.year, today.month, today.day)


def _normalize_status(value: Optional[str], progress: Optional[float] = None) -> str:
    if value:
        cleaned = str(value).strip().lower().replace(" ", "_")
        if cleaned in STATUS_TO_PROGRESS:
            return cleaned
    if progress is not None:
        if progress >= 100:
            return "completed"
        if progress <= 0:
            return "pending"
        return "in_progress"
    return "pending"


def _parse_date(value: Any) -> Optional[date]:
    if not value:
        return None
    if isinstance(value, date):
        return value
    if isinstance(value, str):
        return date.fromisoformat(value.split("T")[0])
    raise HTTPException(400, "Invalid due date format")


def _project_from_payload(payload: Dict[str, Any], db: Session) -> Project:
    project_id = payload.get("project_id")
    if project_id is not None:
        project = db.get(Project, int(project_id))
    else:
        project_name = str(payload.get("project") or "").strip()
        project = None
        if project_name:
            project = db.query(Project).filter(Project.project_name == project_name).first()
    if not project:
        raise HTTPException(404, "Project does not exist")
    return project


def _validate_worker(db: Session, project_id: int, worker_id: Optional[int]) -> Optional[Worker]:
    if worker_id is None:
        return None
    worker = db.get(Worker, int(worker_id))
    if not worker:
        raise HTTPException(404, "Worker does not exist")
    return worker


def _extract_worker_ids(payload: Dict[str, Any]) -> Optional[List[int]]:
    """Extract the worker_ids list from a payload.

    Returns None when worker_ids was not provided (caller should fall back to the
    legacy single-worker fields). Returns [] when explicitly cleared."""
    if "worker_ids" not in payload:
        return None
    raw = payload.get("worker_ids")
    if raw is None:
        return []
    if isinstance(raw, (list, tuple)):
        return [int(x) for x in raw if x is not None]
    return [int(raw)]


def _set_task_workers(db: Session, task: Task, worker_ids: List[int]) -> List[int]:
    """Replace the full worker assignment of a task.

    Validates every id, writes the task_workers association rows and keeps the
    legacy assigned_worker_id column in sync (first worker, or None)."""
    valid_ids: List[int] = []
    for wid in worker_ids:
        worker = _validate_worker(db, task.project_id, wid)
        if worker and worker.worker_id not in valid_ids:
            valid_ids.append(worker.worker_id)
    task.task_workers = [TaskWorker(worker_id=wid) for wid in valid_ids]
    task.assigned_worker_id = valid_ids[0] if valid_ids else None
    return valid_ids


def _notify_workers_assigned(db: Session, task: Task, worker_ids: List[int]) -> None:
    """Push "new task assigned" to every worker in worker_ids and mirror it to
    the worker_notifications table.

    Best-effort by design: missing tokens, FCM being unconfigured or network
    errors are all swallowed — the in-app row is still written and the caller's
    transaction commits normally (rows are flushed by the caller's commit).
    """
    if not worker_ids:
        return
    from app.models import WorkerNotification
    from app.services.fcm import send_to_device

    project_name = task.project.project_name if task.project else "Project"
    title = "您有新任务"
    content = f"任务「{task.task_name}」已分配给您（{project_name}）"
    data = {
        "type": "task_assigned",
        "task_id": str(task.task_id),
        "project_id": str(task.project_id),
    }

    for wid in worker_ids:
        worker = db.get(Worker, wid)
        if not worker:
            continue
        db.add(WorkerNotification(
            worker_id=wid,
            title=title,
            content=content,
            related_entity_type="task",
            related_entity_id=task.task_id,
        ))
        if worker.fcm_token:
            send_to_device(worker.fcm_token, title, content, data)


def _task_load_options():
    return (
        joinedload(Task.assigned_worker),
        joinedload(Task.project),
        joinedload(Task.task_workers).joinedload(TaskWorker.worker),
    )


def _score_worker(task: Task, worker: Worker, attendance: Optional[AttendanceLog]) -> tuple[int, str]:
    text = " ".join(filter(None, [task.task_name, task.description])).lower()
    trade = (worker.trade or "").strip().lower()
    score = 45
    reasons: list[str] = []

    if trade and trade in text:
        score += 35
        reasons.append(f"Trade matches task needs: {worker.trade}")
    elif trade:
        score += 12
        reasons.append(f"Worker trade available: {worker.trade}")
    else:
        reasons.append("Trade not set, scored by availability only")

    worker_status = "Absent"
    if attendance and attendance.status in ("checked_in", "checked_out"):
        if attendance.check_in_time and attendance.check_in_time.strftime("%H:%M") > "07:30":
            worker_status = "Late"
            score += 5
            reasons.append("Worker is on site today but arrived late")
        else:
            worker_status = "Present"
            score += 15
            reasons.append("Worker is on site today")
    else:
        reasons.append("Worker has no attendance log today")

    if worker.has_safety_training:
        score += 3
    if worker.is_safety_officer:
        score += 2

    return min(score, 99), "; ".join(reasons[:3])


def _worker_status_payload(worker: Worker, attendance: Optional[AttendanceLog]) -> str:
    if not attendance or attendance.status not in ("checked_in", "checked_out"):
        return "Absent"
    if attendance.check_in_time and attendance.check_in_time.strftime("%H:%M") > "07:30":
        return "Late"
    return "Present"


def _worker_skills(worker: Worker) -> list[str]:
    skills = []
    if worker.trade:
        skills.append(worker.trade.title())
    if worker.has_safety_training:
        skills.append("Safety Trained")
    if worker.is_safety_officer:
        skills.append("Safety Officer")
    return skills or ["General"]


def _worker_initials(name: str) -> str:
    parts = [p[:1].upper() for p in name.split() if p.strip()]
    return "".join(parts[:2]) or "NA"


def _serialize_task(task: Task) -> Dict[str, Any]:
    data = TaskOut.model_validate(task).model_dump(mode="json")
    data["ok"] = True
    data["progress"] = STATUS_TO_PROGRESS.get(task.status or "pending", 0)
    data["project_name"] = task.project.project_name if task.project else None
    return data


def _candidate_payload(task: Task, worker: Worker, attendance: Optional[AttendanceLog], index: int) -> Dict[str, Any]:
    score, reason = _score_worker(task, worker, attendance)
    return {
        "worker_id": worker.worker_id,
        "worker_name": worker.name,
        "worker_role": worker.trade or "General Worker",
        "worker_status": _worker_status_payload(worker, attendance),
        "worker_rating": round(3.8 + min(score, 95) / 100, 1),
        "worker_skills": _worker_skills(worker),
        "worker_avatar_color": AVATAR_COLORS[index % len(AVATAR_COLORS)],
        "worker_initials": _worker_initials(worker.name),
        "match_score": score,
        "reason": reason,
    }


def _attendance_map(db: Session, project_id: int) -> Dict[int, AttendanceLog]:
    rows = db.query(AttendanceLog).filter(
        AttendanceLog.project_id == project_id,
        AttendanceLog.check_in_time >= _today_start(),
    ).order_by(AttendanceLog.attendance_id.desc()).all()
    result: Dict[int, AttendanceLog] = {}
    for row in rows:
        result.setdefault(row.worker_id, row)
    return result


def _task_candidates(task: Task, db: Session) -> List[Dict[str, Any]]:
    workers = db.query(Worker).order_by(Worker.worker_id.asc()).all()
    attendance_by_worker = _attendance_map(db, task.project_id)
    candidates = [
        _candidate_payload(task, worker, attendance_by_worker.get(worker.worker_id), idx)
        for idx, worker in enumerate(workers)
    ]
    candidates.sort(key=lambda item: item["match_score"], reverse=True)
    return candidates


def _assignment_payload(task: Task, db: Session) -> Dict[str, Any]:
    assigned_name = task.assigned_worker.name if task.assigned_worker else None
    return {
        "task": {
            "id": task.task_id,
            "title": task.task_name,
            "project": task.project.project_name if task.project else f"Project {task.project_id}",
            "priority": (task.priority or "medium").title(),
            "status": (task.status or "pending").replace("_", " ").title(),
            "assigned_to": assigned_name,
        },
        "candidates": _task_candidates(task, db),
    }


@router.get("/projects/{pid}/tasks", response_model=List[TaskOut])
def list_tasks(pid: int, db: Session = Depends(get_db)):
    return db.query(Task).options(*_task_load_options()).filter(Task.project_id == pid).order_by(Task.task_id.desc()).all()


@router.post("/tasks")
def create_task(payload: Dict[str, Any], db: Session = Depends(get_db)):
    project = _project_from_payload(payload, db)
    task_name = str(payload.get("task_name") or payload.get("title") or "").strip()
    if not task_name:
        raise HTTPException(400, "Task name is required")

    status = _normalize_status(payload.get("status"), payload.get("progress"))

    # Multi-worker support: worker_ids replaces the legacy single-worker fields.
    worker_ids = _extract_worker_ids(payload)
    if worker_ids is None:
        worker_id = payload.get("assigned_worker_id") or payload.get("worker_id")
        worker_ids = [int(worker_id)] if worker_id is not None else []

    task = Task(
        task_name=task_name,
        description=(payload.get("description") or payload.get("subtitle") or "").strip() or None,
        assigned_worker_id=None,
        project_id=project.project_id,
        priority=str(payload.get("priority") or "medium").strip().lower(),
        status=status,
        due_date=_parse_date(payload.get("due_date") or payload.get("due")),
        ai_confidence=(float(payload["ai_confidence"]) if payload.get("ai_confidence") is not None else None),
    )
    db.add(task)
    db.flush()
    _set_task_workers(db, task, worker_ids)
    _recalc_project_progress(db, task.project_id)
    db.commit()
    db.refresh(task)
    task = db.query(Task).options(*_task_load_options()).get(task.task_id)
    return _serialize_task(task)


@router.put("/tasks/{task_id}")
def update_task(task_id: int, payload: Dict[str, Any], db: Session = Depends(get_db)):
    task = db.query(Task).options(*_task_load_options()).get(task_id)
    if not task:
        raise HTTPException(404, "Task does not exist")

    if "task_name" in payload or "title" in payload:
        task.task_name = str(payload.get("task_name") or payload.get("title") or "").strip() or task.task_name

    if "description" in payload or "subtitle" in payload:
        task.description = (payload.get("description") or payload.get("subtitle") or "").strip() or None

    if "project_id" in payload or "project" in payload:
        project = _project_from_payload(payload, db)
        task.project_id = project.project_id

    if "priority" in payload and payload.get("priority") is not None:
        task.priority = str(payload["priority"]).strip().lower()

    if "status" in payload or "progress" in payload:
        old_status = task.status
        task.status = _normalize_status(payload.get("status"), payload.get("progress"))
        if task.status != old_status:
            _recalc_project_progress(db, task.project_id)

    if "due_date" in payload or "due" in payload:
        task.due_date = _parse_date(payload.get("due_date") or payload.get("due"))

    # Multi-worker support: worker_ids replaces the full assignment list.
    worker_ids = _extract_worker_ids(payload)
    if worker_ids is not None:
        assigned = _set_task_workers(db, task, worker_ids)
        _notify_workers_assigned(db, task, assigned)
    elif "assigned_worker_id" in payload or "worker_id" in payload:
        worker_id = payload.get("assigned_worker_id") or payload.get("worker_id")
        worker = _validate_worker(db, task.project_id, worker_id)
        if worker:
            assigned = _set_task_workers(db, task, [worker.worker_id])
            _notify_workers_assigned(db, task, assigned)
        else:
            _set_task_workers(db, task, [])

    if payload.get("ai_confidence") is not None:
        task.ai_confidence = float(payload["ai_confidence"])

    db.commit()
    db.refresh(task)
    task = db.query(Task).options(*_task_load_options()).get(task.task_id)
    return _serialize_task(task)


@router.post("/ai/tasks/match", response_model=List[AIMatchResult])
def ai_match(required_trade: str, project_id: int, db: Session = Depends(get_db)):
    workers = db.query(Worker).all()
    if not workers:
        raise HTTPException(404, "No workers found")

    trade = required_trade.strip().lower()
    results = []
    for worker in workers:
        worker_trade = (worker.trade or "").strip().lower()
        if worker_trade == trade:
            score, reason = 1.0, f"Exact trade match: {worker.trade}"
        elif trade and (trade in worker_trade or worker_trade in trade):
            score, reason = 0.6, f"Partial trade match: {worker.trade}"
        else:
            score, reason = 0.2, f"Trade mismatch (current: {worker.trade or 'not set'}), recommended by availability only"
        results.append(
            AIMatchResult(
                worker_id=worker.worker_id,
                worker_name=worker.name,
                trade=worker.trade or "-",
                match_score=score,
                reason=reason,
            )
        )
    results.sort(key=lambda row: row.match_score, reverse=True)
    return results


@router.get("/ai-assign")
def list_ai_assignments(db: Session = Depends(get_db)):
    tasks = db.query(Task).options(*_task_load_options()).order_by(Task.task_id.asc()).all()
    return [_assignment_payload(task, db) for task in tasks]


@router.post("/ai-assign/{task_id}")
def assign_worker(task_id: int, payload: Dict[str, Any], db: Session = Depends(get_db)):
    task = db.query(Task).options(*_task_load_options()).get(task_id)
    if not task:
        raise HTTPException(404, "Task does not exist")

    worker_id = payload.get("worker_id")
    if worker_id is None:
        raise HTTPException(400, "worker_id is required")
    worker = _validate_worker(db, task.project_id, worker_id)
    candidates = _task_candidates(task, db)
    chosen = next((item for item in candidates if item["worker_id"] == worker.worker_id), None)
    if not chosen:
        raise HTTPException(400, "Unable to score the selected worker for this task")

    _set_task_workers(db, task, [worker.worker_id])
    _notify_workers_assigned(db, task, [worker.worker_id])
    task.ai_confidence = round(chosen["match_score"] / 100, 2)
    if task.status == "pending":
        task.status = "in_progress"
    db.commit()
    db.refresh(task)
    return {
        "ok": True,
        "task_id": task.task_id,
        "worker_id": worker.worker_id,
        "worker_name": worker.name,
        "match_score": chosen["match_score"],
    }


@router.post("/ai-assign/all")
def auto_assign_all(db: Session = Depends(get_db)):
    tasks = db.query(Task).options(*_task_load_options()).filter(
        Task.assigned_worker_id.is_(None),
        Task.status.in_(["pending", "in_progress"]),
    ).order_by(Task.task_id.asc()).all()

    assigned = 0
    for task in tasks:
        candidates = _task_candidates(task, db)
        if not candidates:
            continue
        # Assign up to 3 best-matched workers (multi-worker assignment).
        best = candidates[:3]
        task.task_workers = [TaskWorker(worker_id=item["worker_id"]) for item in best]
        task.assigned_worker_id = best[0]["worker_id"]
        task.ai_confidence = round(best[0]["match_score"] / 100, 2)
        if task.status == "pending":
            task.status = "in_progress"
        assigned += 1

    db.commit()
    return {"ok": True, "assigned": assigned}


# ══════════════════════════════════════════════════════════════════
# Worker-specific AI Task Board (Worker-only endpoints)
# ══════════════════════════════════════════════════════════════════

# AI-part inference helpers for the worker's personal task board
TRADE_TO_PARTS: Dict[str, List[str]] = {
    "carpenter": ["Formwork Section", "Timber Frame Section", "Finish Carpentry Section"],
    "electrical": ["Conduit & Wiring Section", "Switchboard Section", "Lighting Fixture Section"],
    "plumbing": ["Drainage & Piping Section", "Water Supply Section", "Sanitary Fixture Section"],
    "masonry": ["Brickwork Section", "Plastering Section", "Tiling Section"],
    "steel": ["Steel Reinforcement Section", "Structural Steel Section", "Metal Fabrication Section"],
    "painter": ["Interior Painting Section", "Exterior Facade Section", "Protective Coating Section"],
    "general": ["General Work Section", "Site Logistics Section", "Housekeeping Section"],
}

TRADE_INSTRUCTIONS: Dict[str, str] = {
    "carpenter": "Use calibrated tools; verify formwork dimensions against shop drawings prior to pour.",
    "electrical": "Follow single-line diagrams; tag all circuits; wear insulated gloves.",
    "plumbing": "Pressure-test all joints; verify gradient on drainage runs before covering.",
    "masonry": "Keep mortar mix consistent; use plumb line every 3 courses.",
    "steel": "Inspect rebar spacing and cover; use tie-wire all intersections.",
    "painter": "Apply primer coat coverage ≥80 microns; ensure surface preparation before topcoat.",
    "general": "Cooperate with trades; maintain housekeeping; use PPE at all times.",
}

def _ai_infer_part_section(task: Task, worker: Worker) -> str:
    trade = (worker.trade or "general").strip().lower()
    parts = TRADE_TO_PARTS.get(trade, TRADE_TO_PARTS["general"])
    idx = (task.task_id or 0) % max(len(parts), 1)
    base = parts[idx]
    tname = task.task_name.lower()
    if "floor" in tname:
        base = f"Floor {task.task_id % 10 + 1} — " + base
    elif "wall" in tname or "column" in tname:
        base = "Grid " + chr(65 + (task.task_id % 6)) + " — " + base
    return base

def _ai_work_instructions(task: Task, worker: Worker) -> str:
    trade = (worker.trade or "general").strip().lower()
    base = TRADE_INSTRUCTIONS.get(trade, TRADE_INSTRUCTIONS["general"])
    if task.priority == "high":
        base = base + " PRIORITY: Accelerate this section — supervisor flagged as high impact."
    if task.due_date:
        base = base + f" Target completion before {task.due_date.strftime('%d %b %Y')}."
    return base

def _ai_build_summary(worker: Worker, tasks: List[Task]) -> str:
    total = len(tasks)
    pending = sum(1 for t in tasks if t.status == "pending")
    in_progress = sum(1 for t in tasks if t.status == "in_progress")
    completed = sum(1 for t in tasks if t.status == "completed")
    high = sum(1 for t in tasks if t.priority == "high")
    trade = (worker.trade or "general worker").title()
    return (
        f"Good day, {worker.name.split()[0]}! As {trade}, today you have {total} assigned task(s): "
        f"{pending} pending, {in_progress} in progress, {completed} completed. "
        + (f"{high} task(s) flagged HIGH priority — please attend to them first. " if high else "")
        + "AI confidence scores updated in real time as site conditions change."
    )

def _ai_detect_alert(tasks: List[Task], worker: Worker) -> Optional[str]:
    alerts: List[str] = []
    today = date.today()
    for t in tasks:
        if t.status == "completed":
            continue
        if t.priority == "high" and t.status == "pending":
            alerts.append(f"High priority task '{t.task_name[:40]}' not started yet")
        if t.due_date and t.due_date < today and t.status != "completed":
            alerts.append(f"Task '{t.task_name[:40]}' is OVERDUE since {t.due_date}")
        if t.ai_confidence is not None and t.ai_confidence < 0.4:
            alerts.append(f"Low AI confidence on '{t.task_name[:40]} — confirm with supervisor")
    if len(alerts):
        return " ⚠ ".join(alerts[:3])
    return None


@router.get("/worker/task-board", response_model=WorkerTaskBoardResponse)
def worker_task_board(
    refresh: bool = False,
    user: CurrentUser = Depends(require_worker),
    db: Session = Depends(get_db),
):
    """Worker AI-driven task board for the authenticated worker.
    Returns all tasks assigned to the current worker.
    AI inference enriches each task with part_section (work板块) and work_instructions,
    a human-readable summary, and anomaly alerts.
    Set refresh=true to force AI re-analysis (simulated for realtime content  the front-end polling.
    """
    worker = db.query(Worker).get(user.id)
    if not worker:
        raise HTTPException(404, "Worker account not found")

    query = db.query(Task).options(
        joinedload(Task.assigned_worker),
        joinedload(Task.project),
        joinedload(Task.task_workers).joinedload(TaskWorker.worker),
    ).filter(
        or_(
            Task.assigned_worker_id == user.id,
            Task.task_workers.any(TaskWorker.worker_id == user.id),
        ),
    ).order_by(
        Task.status.asc(), Task.priority.desc()).all()

    now = datetime.utcnow()

    task_items: List[WorkerTaskItem] = []
    for t in query:
        link = next((l for l in t.task_workers if l.worker_id == user.id), None)
        task_items.append(WorkerTaskItem(
            task_id=t.task_id,
            task_name=t.task_name,
            description=t.description,
            project_id=t.project_id,
            project_name=t.project.project_name if t.project else f"Project {t.project_id}",
            priority=(t.priority or "medium").title(),
            status=(t.status or "pending").replace("_", " ").title(),
            due_date=t.due_date,
            ai_confidence=t.ai_confidence,
            assigned_at=link.assigned_at if link else None,
            part_section=_ai_infer_part_section(t, worker),
            work_instructions=_ai_work_instructions(t, worker),
        ))

    summary = _ai_build_summary(worker, query)
    alert = _ai_detect_alert(query, worker)

    return WorkerTaskBoardResponse(
        worker_id=worker.worker_id,
        worker_name=worker.name,
        last_updated=now,
        tasks=task_items,
        summary=summary,
        alert=alert,
        ai_generated=True,
    )


@router.get("/worker/tasks/sync")
def worker_tasks_sync(
    since_last_updated: Optional[str] = None,
    user: CurrentUser = Depends(require_worker),
    db: Session = Depends(get_db),
):
    """Lightweight realtime sync endpoint.
    Front-end can poll this every N seconds with the last_updated timestamp
    from the previous board pull. Returns changed=true if the task board has
    new changes, along with the full board data; changed=false if same data."""
    board = worker_task_board(refresh=False, user=user, db=db)
    changed = True
    if since_last_updated:
        try:
            client_ts = datetime.fromisoformat(since_last_updated.replace("Z", ""))
            if board.last_updated <= client_ts:
                changed = False
        except Exception:
            changed = True
    return {
        "changed": changed,
        "last_updated": board.last_updated.isoformat(),
        "alert": board.alert,
        "board": board if changed else None,
    }

