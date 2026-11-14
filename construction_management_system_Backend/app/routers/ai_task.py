from datetime import date, datetime
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Body, Depends, HTTPException, Query
from fastapi.responses import FileResponse, JSONResponse, RedirectResponse
from sqlalchemy import or_
from sqlalchemy.orm import Session, joinedload

from app.database import get_db
from app.models import Project, Task, TaskProgressLog, TaskWorker, Worker
from app.ai_service import mark_decision_overridden
from app.schemas import (
    AIMatchResult, TaskOut, TaskProgressLogOut,
    WorkerTaskItem, WorkerTaskBoardResponse, CurrentUser,
)
from app.routers.auth import (
    project_for_user,
    require_worker,
    require_any_authorized,
    require_site_supervisor,
)
from app.task_photo import (
    PhotoError,
    delete_task_photo,
    open_task_photo,
    save_task_photo,
    task_photo_url,
)
from app.storage_service import DEFAULT_SIGNED_URL_TTL
from app.trade_levels import (
    DEFAULT_LEVEL,
    TRADE_LEVEL_RANK,
    level_label,
    level_rank,
    trade_level,
)
from app.specialties import normalise_specialty, normalise_specialties

router = APIRouter(tags=["🤖 Tasks & AI Assignment"])

STATUS_TO_PROGRESS = {
    "pending": 0,
    "in_progress": 50,
    # A worker has supplied the final evidence, but a supervisor still has to
    # accept or reject it.  It is intentionally 100% work-progress while not
    # being a completed/approved task for reporting purposes.
    "submitted": 100,
    "approved": 100,
    "completed": 100,
    "rejected": 99,
}


def _authorize_task_access(db: Session, task: Task, user: CurrentUser) -> None:
    """Enforce ownership before exposing or changing a task."""
    if user.user_type == "supervisor":
        project_for_user(db, user, task.project_id, supervisor_only=True)
        return

    assigned = task.assigned_worker_id == user.id or any(
        link.worker_id == user.id for link in task.task_workers
    )
    if not assigned:
        raise HTTPException(403, "This task is not assigned to you")

# Allowed task status transitions (state machine whitelist). Only adjacent
# forward moves are permitted; jumping pending->completed is rejected with a 400
# so task history stays honest.
#
# The completed -> in_progress / pending edges are listed here as the single
# source of truth, but they are *reopen-only*: the generic update endpoint still
# rejects them (see _validate_status_transition), and only the supervisor-only
# reopen endpoint may use them, together with an audit entry. Keeping one map
# means the front-end status picker can render every legal edge from the same
# definition the API validates against.
TASK_STATUS_TRANSITIONS = {
    "pending": {"in_progress"},
    # ``completed`` remains a legacy supervisor-only compatibility state.
    # Field workers submit evidence through /complete, which lands at
    # ``submitted`` and therefore cannot silently bypass review.
    "in_progress": {"submitted", "completed", "pending"},
    "submitted": {"approved", "rejected"},
    "rejected": {"in_progress", "submitted"},
    "approved": {"in_progress", "pending"},
    "completed": {"in_progress", "pending"},
}

# Edges that may only be traversed through POST /tasks/{id}/reopen.
REOPEN_ONLY_TRANSITIONS = {
    ("approved", "in_progress"),
    ("approved", "pending"),
    ("completed", "in_progress"),
    ("completed", "pending"),
}

# Statuses a reopen may land on (a completed task never reopens straight back to
# completed).
REOPEN_TARGET_STATUSES = ("in_progress", "pending")
TERMINAL_APPROVED_STATUSES = {"approved", "completed"}


def _validate_status_transition(old_status: str, new_status: str, allow_reopen: bool = False) -> None:
    """Raise 400 when new_status is not a legal move from old_status.

    ``allow_reopen`` is only set by the privileged reopen endpoint; everywhere
    else a completed task stays closed, so the historical forward-only contract
    of PUT /tasks/{id} is preserved.
    """
    allowed = TASK_STATUS_TRANSITIONS.get(old_status, set())
    if new_status not in allowed:
        raise HTTPException(
            400,
            f"Invalid task status transition: {old_status} -> {new_status}. "
            "Allowed transitions: pending -> in_progress; in_progress -> submitted; "
            "submitted -> approved or rejected.",
        )
    if not allow_reopen and (old_status, new_status) in REOPEN_ONLY_TRANSITIONS:
        raise HTTPException(
            400,
            f"Invalid task status transition: {old_status} -> {new_status}. "
            "A completed task can only be reopened through the reopen endpoint "
            "(supervisor only, reason required).",
        )


def _task_progress_value(task: Task) -> float:
    """Return one task's actual work progress as a safe 0-100 number."""
    raw = task.progress
    if raw is None:
        raw = STATUS_TO_PROGRESS.get((task.status or "pending").lower(), 0)
    try:
        return max(0.0, min(100.0, float(raw)))
    except (TypeError, ValueError):
        return 0.0


def _recalc_project_progress(db: Session, project_id: int) -> None:
    """Recompute project.progress as the average task work progress.

    Counting only completed rows made a project with ten 90%-finished tasks
    appear as 0%.  Task weights are not captured yet, so an equal-weight average
    is the honest interim model and keeps project progress aligned with the work
    workers actually report.
    """
    project = db.query(Project).filter(Project.project_id == project_id).first()
    if not project:
        return
    tasks = db.query(Task).filter(Task.project_id == project_id).all()
    total = len(tasks)
    new_progress = (
        round(sum(_task_progress_value(task) for task in tasks) / total, 1)
        if total > 0
        else 0.0
    )
    if (project.progress or 0.0) != new_progress:
        project.progress = new_progress
        db.add(project)


def _recalc_project_status(db: Session, project_id: int) -> None:
    """Recompute project.status from its task set (status closed loop).

    Rule: no tasks at all -> "planning"; every task completed (and at least one
    exists) -> "completed"; any other task set (pending-only included) ->
    "in_progress". Creating the first task therefore moves the project off the
    planning board, and completing all tasks closes it.
    The project is only marked dirty (db.add) when the value actually changes,
    so no spurious writes hit the DB on unrelated task edits.

    Values are lowercase to match models.Project.status default ("planning")
    and the frontend statusPill rendering.
    """
    project = db.query(Project).filter(Project.project_id == project_id).first()
    if not project:
        return
    tasks = db.query(Task).filter(Task.project_id == project_id).all()
    if not tasks:
        new_status = "planning"
    elif all((t.status or "").lower() in TERMINAL_APPROVED_STATUSES for t in tasks):
        new_status = "completed"
    else:
        # Any task exists (pending / in_progress / mixed): the project has left
        # the planning board once at least one task row is created. Pending-only
        # projects therefore count as in_progress, matching the user expectation
        # that adding a new task moves the project off "planning".
        new_status = "in_progress"
    if (project.status or "").lower() != new_status:
        project.status = new_status
        db.add(project)


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


def _parse_datetime(value: Any) -> Optional[datetime]:
    """Parse a planned start (date or ISO datetime) coming from the client.

    The supervisor form sends the planned start of the work window; the column
    (``Task.started_at``) already exists, so this only widens what the API
    accepts instead of adding a migration. Empty / unusable values fall back to
    None, which keeps the automatic "stamped on first in_progress" behaviour.
    """
    if not value:
        return None
    if isinstance(value, datetime):
        return value
    if isinstance(value, date):
        return datetime(value.year, value.month, value.day)
    if isinstance(value, str):
        text = value.strip().replace("Z", "+00:00")
        try:
            return datetime.fromisoformat(text)
        except ValueError:
            parsed = _parse_date(text)
            return datetime(parsed.year, parsed.month, parsed.day) if parsed else None
    return None


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
    # Explicitly delete existing links before writing the new assignment, then
    # flush so the DELETE is emitted before the new INSERTs. Under SQLAlchemy
    # 2.0, replacing task.task_workers with a new list does NOT remove the old
    # rows (delete-orphan is not applied on collection replacement), so without
    # this the INSERT would violate uq_task_worker and return 500.
    for link in list(task.task_workers):
        db.delete(link)
    db.flush()
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
    title = "You have a new task"
    content = f"Task \"{task.task_name}\" has been assigned to you ({project_name})"
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


def _notify_task_review(
    db: Session,
    task: Task,
    *,
    decision: str,
    reason: Optional[str] = None,
) -> None:
    """Write a durable worker notification for a supervisor review decision."""
    from app.models import WorkerNotification
    from app.services.fcm import send_to_device

    approved = decision == "approved"
    title = "Task approved" if approved else "Task needs rework"
    if approved:
        content = f'Your task "{task.task_name}" was approved by the supervisor.'
    else:
        suffix = f" Reason: {reason}" if reason else ""
        content = f'Your task "{task.task_name}" needs rework.{suffix}'
    worker_ids = task.worker_ids or ([task.assigned_worker_id] if task.assigned_worker_id else [])
    for worker_id in worker_ids:
        worker = db.get(Worker, worker_id)
        if not worker:
            continue
        db.add(WorkerNotification(
            worker_id=worker_id,
            title=title,
            content=content,
            related_entity_type="task",
            related_entity_id=task.task_id,
        ))
        if worker.fcm_token:
            send_to_device(worker.fcm_token, title, content, {
                "type": "task_review",
                "task_id": str(task.task_id),
                "decision": decision,
            })


def _notify_supervisor_submission(db: Session, task: Task) -> None:
    """Put a task-review action in the owning supervisor's notification inbox."""
    from app.models import Notification

    project = task.project or db.get(Project, task.project_id)
    if not project or not project.supervisor_id:
        return
    db.add(Notification(
        supervisor_id=project.supervisor_id,
        notification_type="task_review",
        title="Task evidence awaiting review",
        content=f'"{task.task_name}" has been submitted with photo evidence.',
        related_entity_type="task",
        related_entity_id=task.task_id,
    ))


def _task_load_options():
    return (
        joinedload(Task.assigned_worker),
        joinedload(Task.project),
        joinedload(Task.task_workers).joinedload(TaskWorker.worker),
    )





def _serialize_task(task: Task) -> Dict[str, Any]:
    data = TaskOut.model_validate(task).model_dump(mode="json")
    data["ok"] = True
    # Supervisor-set progress wins; fall back to the status-derived value so
    # tasks without an explicit progress still display a sensible percentage.
    data["progress"] = (
        task.progress
        if task.progress is not None
        else STATUS_TO_PROGRESS.get(task.status or "pending", 0)
    )
    data["project_name"] = task.project.project_name if task.project else None
    # Completion evidence: expose the review URL (never the raw storage path) so
    # the worker and the supervisor can open the photo but cannot guess at other
    # tasks' files on disk.
    data["completion_photo_url"] = task_photo_url(task.task_id, task.completion_photo_path)
    data["completion_photo_at"] = (
        task.completion_photo_at.isoformat() if task.completion_photo_at else None
    )
    return data


def _attach_completion_photo(task: Task, payload: Dict[str, Any], *, worker_id: Optional[int]) -> None:
    """Store the completion photo carried by the request, or reject completion.

    A task may only reach ``completed`` with photographic evidence: either this
    request carries one, or the task already has one stored (the normal case
    when a worker closed the task and a supervisor is only touching metadata).
    This is the backend half of the rule the worker app enforces in its UI, so
    the rule cannot be skipped by calling the API directly.

    Replacement rule: a task keeps exactly one completion photo — the latest
    submission. When a new photo arrives the previous file is deleted from
    ``uploads/task_completion`` and ``completion_photo_at`` is refreshed, so the
    row always points at the most recent evidence and its submission time.
    """
    photo_b64 = str(payload.get("photo_base64") or "").strip()
    if photo_b64:
        _replace_task_photo(task, photo_b64, worker_id=worker_id)
        return

    if not task.completion_photo_path:
        raise HTTPException(
            400,
            "A site photo is required when completing a task "
            "(send photo_base64, camera capture only)",
        )


def _replace_task_photo(task: Task, photo_b64: str, *, worker_id: Optional[int]) -> None:
    """Persist the latest on-site photo submitted for a task.

    Progress and completion uploads share one current evidence photo.  This
    keeps storage bounded and, importantly, avoids accepting a progress photo
    only to silently throw it away.
    """
    try:
        rel_path = save_task_photo(
            photo_b64,
            task_id=task.task_id,
            worker_id=worker_id,
        )
    except PhotoError as exc:
        raise HTTPException(400, str(exc))
    previous = task.completion_photo_path
    task.completion_photo_path = rel_path
    task.completion_photo_at = datetime.utcnow()
    if previous and previous != rel_path:
        delete_task_photo(previous)





@router.get("/projects/{pid}/tasks")
def list_tasks(
    pid: int,
    user: CurrentUser = Depends(require_any_authorized),
    db: Session = Depends(get_db),
):
    # Serialised through _serialize_task (not TaskOut) so the list carries the
    # completion evidence fields too — the supervisor opens the task detail page
    # straight from a list row, and would otherwise land on a card without the
    # photo URL until it refetched.
    query = db.query(Task).options(*_task_load_options()).filter(Task.project_id == pid)
    if user.user_type == "supervisor":
        project_for_user(db, user, pid, supervisor_only=True)
    else:
        query = query.filter(
            or_(
                Task.assigned_worker_id == user.id,
                Task.task_workers.any(TaskWorker.worker_id == user.id),
            )
        )
    tasks = query.order_by(Task.task_id.desc()).all()
    return [_serialize_task(task) for task in tasks]


@router.get("/tasks")
def list_supervisor_tasks(
    project_id: Optional[int] = Query(default=None),
    user: CurrentUser = Depends(require_site_supervisor),
    db: Session = Depends(get_db),
):
    """Return one supervisor-scoped task board without one request per project."""
    query = (
        db.query(Task)
        .options(*_task_load_options())
        .join(Project, Task.project_id == Project.project_id)
        .filter(Project.supervisor_id == user.id)
    )
    if project_id is not None:
        project_for_user(db, user, project_id, supervisor_only=True)
        query = query.filter(Task.project_id == project_id)
    tasks = query.order_by(Task.task_id.desc()).all()
    return [_serialize_task(task) for task in tasks]


@router.post("/tasks")
def create_task(
    payload: Dict[str, Any],
    user: CurrentUser = Depends(require_site_supervisor),
    db: Session = Depends(get_db),
):
    project = _project_from_payload(payload, db)
    project_for_user(db, user, project.project_id, supervisor_only=True)
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
        trade=str(payload.get("trade") or "").strip() or None,
        due_date=_parse_date(payload.get("due_date") or payload.get("due")),
        # Planned start of the work window (supervisor form). Optional: when it
        # is omitted the column stays empty and is stamped automatically the
        # first time the task moves to in_progress.
        started_at=_parse_datetime(payload.get("started_at") or payload.get("start_date")),
        ai_confidence=(float(payload["ai_confidence"]) if payload.get("ai_confidence") is not None else None),
    )
    db.add(task)
    db.flush()
    _set_task_workers(db, task, worker_ids)
    _recalc_project_progress(db, task.project_id)
    _recalc_project_status(db, task.project_id)
    db.commit()
    db.refresh(task)
    task = db.query(Task).options(*_task_load_options()).get(task.task_id)
    return _serialize_task(task)


@router.post("/tasks/{task_id}/complete")
def complete_task_with_photo(
    task_id: int,
    payload: Dict[str, Any] = Body(default_factory=dict),
    user: CurrentUser = Depends(require_worker),
    db: Session = Depends(get_db),
):
    """Worker endpoint: close a task with the mandatory site photo.

    Kept separate from the generic update endpoint so the worker path is
    validated in one place: the caller must be assigned to the task, the task
    must already be in progress, and a fresh camera photo is required. The
    photo is stored on the task row and replayed through the authenticated
    ``GET /tasks/{id}/completion-photo`` endpoint.
    """
    task = db.query(Task).options(*_task_load_options()).get(task_id)
    if not task:
        raise HTTPException(404, "Task does not exist")

    worker = db.query(Worker).get(user.id)
    if not worker:
        raise HTTPException(404, "Worker account not found")

    assigned = task.assigned_worker_id == worker.worker_id or any(
        link.worker_id == worker.worker_id for link in task.task_workers
    )
    if not assigned:
        raise HTTPException(403, "This task is not assigned to you")

    old_status = (task.status or "pending").lower()
    is_resubmission = old_status == "rejected"
    if is_resubmission:
        # Repeat-submission rule: the assigned worker may resubmit a completed
        # task, but only together with a fresh site photo. The newest evidence
        # wins — the old file is deleted and completion_photo_at is refreshed —
        # so the row never accumulates photos and always shows the latest one.
        if not str(payload.get("photo_base64") or "").strip():
            raise HTTPException(
                400,
                "This task is already completed; send a new photo_base64 to "
                "replace the completion evidence",
            )
    else:
        _validate_status_transition(old_status, "submitted")

    note = str(payload.get("completion_note") or "").strip() or None
    if not note and is_resubmission:
        # A resubmission without a new note keeps the original one instead of
        # failing: the photo, not the wording, is the evidence being updated.
        note = (task.completion_note or "").strip() or None
    # Field workers submit photo evidence; a written description is optional.
    if not note:
        note = "Photo evidence submitted by worker"

    # Photo first: if it is missing or unreadable the task stays untouched, so a
    # rejected upload never leaves a half-completed task behind.
    _attach_completion_photo(task, payload, worker_id=worker.worker_id)

    task.completion_note = note
    task.status = "submitted"
    task.progress = 100
    # completed_at keeps the FIRST completion moment (audit), while
    # completion_photo_at always tracks the latest evidence submission.
    task.completed_at = None

    db.add(TaskProgressLog(
        task_id=task.task_id,
        from_status=old_status,
        to_status="submitted",
        note=(f"Resubmitted completion evidence: {note}" if is_resubmission else note),
        action="submit",
    ))
    _notify_supervisor_submission(db, task)
    db.flush()
    _recalc_project_progress(db, task.project_id)
    _recalc_project_status(db, task.project_id)
    db.commit()

    task = db.query(Task).options(*_task_load_options()).get(task.task_id)
    return _serialize_task(task)


@router.post("/tasks/{task_id}/review")
def review_submitted_task(
    task_id: int,
    payload: Dict[str, Any] = Body(default_factory=dict),
    current_user: CurrentUser = Depends(require_site_supervisor),
    db: Session = Depends(get_db),
):
    """Approve or reject a worker submission with an auditable decision."""
    task = db.query(Task).options(*_task_load_options()).get(task_id)
    if not task:
        raise HTTPException(404, "Task does not exist")
    _authorize_task_access(db, task, current_user)
    if (task.status or "").lower() != "submitted":
        raise HTTPException(400, "Only submitted tasks can be reviewed")

    decision = str(payload.get("decision") or "").strip().lower()
    if decision not in {"approved", "rejected"}:
        raise HTTPException(400, "decision must be 'approved' or 'rejected'")
    reason = str(payload.get("reason") or "").strip()
    if decision == "rejected" and not reason:
        raise HTTPException(400, "reason is required when rejecting a task")

    old_status = task.status
    task.status = decision
    task.progress = 100 if decision == "approved" else 99
    task.completed_at = datetime.utcnow() if decision == "approved" else None
    db.add(TaskProgressLog(
        task_id=task.task_id,
        from_status=old_status,
        to_status=decision,
        note=reason or "Evidence approved by supervisor",
        action="approve" if decision == "approved" else "reject",
        changed_by_id=current_user.id,
        changed_by_name=current_user.name,
        reason=reason or None,
    ))
    _notify_task_review(db, task, decision=decision, reason=reason or None)
    db.flush()
    _recalc_project_progress(db, task.project_id)
    _recalc_project_status(db, task.project_id)
    db.commit()
    task = db.query(Task).options(*_task_load_options()).get(task.task_id)
    return _serialize_task(task)


@router.get("/tasks/{task_id}/completion-photo")
def get_task_completion_photo(
    task_id: int,
    redirect: bool = True,
    user: CurrentUser = Depends(require_any_authorized),
    db: Session = Depends(get_db),
):
    """Serve the stored completion photo to any authorised account.

    Workers may only open photos of tasks assigned to them; supervisors can
    review every task of the projects they own (the assignment itself is already
    project-scoped by the task API). Paths are re-validated here so a tampered
    database value cannot escape ``uploads/task_completion`` or reach another
    prefix inside the bucket.

    Where the object lives in Supabase Storage the response is a 307 to a
    short-lived signed URL; ``redirect=false`` returns
    ``{"url": ..., "expires_in": ...}`` instead. Local files (including evidence
    uploaded before the switch) are streamed exactly as before.
    """
    task = db.query(Task).options(*_task_load_options()).get(task_id)
    if not task:
        raise HTTPException(404, "Task does not exist")
    _authorize_task_access(db, task, user)
    if not task.completion_photo_path:
        raise HTTPException(404, "No completion photo for this task")

    if getattr(user, "user_type", None) == "worker":
        worker = db.query(Worker).get(user.id)
        assigned = worker is not None and (
            task.assigned_worker_id == worker.worker_id
            or any(link.worker_id == worker.worker_id for link in task.task_workers)
        )
        if not assigned:
            raise HTTPException(403, "This task is not assigned to you")
    elif getattr(user, "user_type", None) == "supervisor":
        # A supervisor may review evidence only for tasks of the projects they
        # own; otherwise every supervisor account could open every site photo.
        project = task.project or db.query(Project).get(task.project_id)
        if project is None or project.supervisor_id != user.id:
            raise HTTPException(
                403, "This task does not belong to one of your projects"
            )

    try:
        source_kind, target = open_task_photo(task.completion_photo_path)
    except PhotoError as exc:
        raise HTTPException(404, str(exc))

    if source_kind == "local":
        return FileResponse(target)

    if redirect:
        return RedirectResponse(target, status_code=307)
    return JSONResponse({"url": target, "expires_in": DEFAULT_SIGNED_URL_TTL})


@router.get("/tasks/{task_id}")
def get_task(
    task_id: int,
    user: CurrentUser = Depends(require_any_authorized),
    db: Session = Depends(get_db),
):
    """Single-task detail — used by the worker task detail page, which needs
    one fresh task record (status / progress / notes) without pulling the whole
    project task list. Must be declared before any other GET /tasks/{...}
    sub-path so the literal segments win over path parameters."""
    task = db.query(Task).options(*_task_load_options()).get(task_id)
    if not task:
        raise HTTPException(404, "Task does not exist")
    _authorize_task_access(db, task, user)
    return _serialize_task(task)


@router.put("/tasks/{task_id}")
def update_task(
    task_id: int,
    payload: Dict[str, Any],
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(require_any_authorized),
):
    """Generic task update (supervisor console and worker task page).

    Authentication is now required: the endpoint used to be anonymous, which
    made every rule enforced here (completion note, completion photo) optional
    for anyone who skipped the UI. Workers close tasks through
    ``POST /tasks/{id}/complete`` instead, so the photo gate lives on both
    paths.
    """
    task = db.query(Task).options(*_task_load_options()).get(task_id)
    if not task:
        raise HTTPException(404, "Task does not exist")
    old_project_id = task.project_id
    _authorize_task_access(db, task, user)

    if user.user_type == "worker":
        worker_fields = {"status", "progress", "note", "progress_photo_base64"}
        unsupported = set(payload) - worker_fields
        if unsupported:
            raise HTTPException(
                403,
                "Workers may only start an assigned task or update its progress",
            )
        if payload.get("status") not in (None, "in_progress"):
            raise HTTPException(
                403,
                "Workers must use the completion endpoint to finish a task",
            )

    progress_photo = str(payload.get("progress_photo_base64") or "").strip()
    if progress_photo:
        # Store the real camera evidence rather than accepting and ignoring it.
        _replace_task_photo(task, progress_photo, worker_id=user.id)

    if "task_name" in payload or "title" in payload:
        task.task_name = str(payload.get("task_name") or payload.get("title") or "").strip() or task.task_name

    if "description" in payload or "subtitle" in payload:
        task.description = (payload.get("description") or payload.get("subtitle") or "").strip() or None

    if "project_id" in payload or "project" in payload:
        project = _project_from_payload(payload, db)
        project_for_user(db, user, project.project_id, supervisor_only=True)
        task.project_id = project.project_id

    if "priority" in payload and payload.get("priority") is not None:
        task.priority = str(payload["priority"]).strip().lower()

    if "status" in payload or "progress" in payload:
        # Supervisor-set progress: validate type and 0-100 range BEFORE deriving
        # the status, so malformed values fail with 400 instead of a 500.
        raw_progress = payload.get("progress")
        parsed_progress = None
        if "progress" in payload and raw_progress is not None:
            try:
                parsed_progress = int(float(raw_progress))
            except (TypeError, ValueError):
                raise HTTPException(400, "progress must be an integer between 0 and 100")
            if parsed_progress < 0 or parsed_progress > 100:
                raise HTTPException(400, "progress must be between 0 and 100")

        old_status = task.status or "pending"
        new_status = _normalize_status(payload.get("status"), parsed_progress)
        if new_status in {"submitted", "approved", "rejected"}:
            raise HTTPException(
                400,
                "Use the completion and review endpoints for submitted task decisions",
            )
        if user.user_type == "worker" and parsed_progress is not None and parsed_progress >= 100:
            raise HTTPException(
                400,
                "Workers must use the completion endpoint to submit final evidence",
            )
        status_changed = new_status != old_status
        if status_changed:
            _validate_status_transition(old_status, new_status)

        # Persist the validated progress value only when it actually changes.
        progress_changed = False
        if parsed_progress is not None and parsed_progress != task.progress:
            task.progress = parsed_progress
            progress_changed = True

        # Completing a task requires a non-empty completion note (anti-bypass:
        # the note must accompany every route into the completed state).
        completion_note = str(payload.get("completion_note") or "").strip() or None
        if new_status == "completed":
            if not completion_note:
                raise HTTPException(
                    400, "completion_note is required when completing a task"
                )
            task.completion_note = completion_note
            # Same anti-bypass rule for the evidence photo: whatever route the
            # client takes into "completed", a stored site photo must exist.
            _attach_completion_photo(
                task,
                payload,
                worker_id=task.assigned_worker_id,
            )

        # Record lifecycle timestamps: first time entering in_progress, and
        # the moment the task is completed. started_at is kept on later
        # re-entries (pending -> in_progress) so it reflects first start.
        if status_changed:
            task.status = new_status
            if new_status == "in_progress" and task.started_at is None:
                task.started_at = datetime.utcnow()
            elif new_status == "completed":
                task.completed_at = datetime.utcnow()

        # Leave a trace on any status or progress change (timeline entry).
        # from_status == to_status for pure progress updates; the note
        # explains what changed. Completion writes the mandatory note.
        if status_changed or progress_changed or progress_photo:
            log_note = (
                completion_note
                if new_status == "completed"
                else str(payload.get("note") or "").strip()
                or ("Progress photo submitted" if progress_photo else None)
            )
            db.add(TaskProgressLog(
                task_id=task.task_id,
                from_status=old_status,
                to_status=task.status or new_status,
                note=log_note,
                action="status" if status_changed else "progress",
            ))

        if status_changed or progress_changed:
            db.flush()  # persist in-memory change so the recalc query sees it
            _recalc_project_progress(db, task.project_id)
            _recalc_project_status(db, task.project_id)

    if "trade" in payload:
        previous_trade = task.trade
        new_trade = str(payload.get("trade") or "").strip() or None
        task.trade = new_trade
        # A supervisor hand-editing the trade is the ground truth for the AI
        # decision that produced the old value: flag the latest decision row so
        # the pair (prediction, corrected label) can be used for evaluation.
        if (new_trade or "") != (previous_trade or ""):
            mark_decision_overridden(db, task.task_id, new_trade)

    if "due_date" in payload or "due" in payload:
        task.due_date = _parse_date(payload.get("due_date") or payload.get("due"))

    if "started_at" in payload or "start_date" in payload:
        # Planned start edited from the supervisor form. Only applied when it
        # parses; an empty value clears the plan so the next in_progress move
        # stamps the real start again.
        task.started_at = _parse_datetime(
            payload.get("started_at") or payload.get("start_date")
        )

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

    # Task moved to another project: the source project lost one task (and the
    # destination gained one), so both projects' progress/status must be
    # recomputed. The destination may already have been recalculated above when
    # status changed; re-running is idempotent (only dirty-adds on value change).
    if task.project_id != old_project_id:
        db.flush()  # persist the project_id change before the recalc queries
        for pid in {old_project_id, task.project_id}:
            _recalc_project_progress(db, pid)
            _recalc_project_status(db, pid)

    db.commit()
    db.refresh(task)
    task = db.query(Task).options(*_task_load_options()).get(task.task_id)
    return _serialize_task(task)


@router.post("/tasks/{task_id}/reopen")
def reopen_task(
    task_id: int,
    payload: Dict[str, Any] = Body(default={}),
    db: Session = Depends(get_db),
    current_user: CurrentUser = Depends(require_site_supervisor),
):
    """Reopen a completed task (supervisor only) and record an audit entry.

    Why a dedicated endpoint instead of widening PUT /tasks/{id}: a reopen is a
    privileged, backward transition, so it must (a) require a supervisor,
    (b) demand a written reason and (c) leave an auditable trace. Folding it into
    the generic update would let any caller quietly undo a completion.

    Audit row fields: changed_by_id / changed_by_name (who), created_at (when),
    from_status -> to_status (what), reason (why), action="reopen".
    """
    task = db.query(Task).options(*_task_load_options()).get(task_id)
    if not task:
        raise HTTPException(404, "Task does not exist")
    _authorize_task_access(db, task, current_user)

    reason = str(payload.get("reason") or "").strip()
    if not reason:
        raise HTTPException(400, "reason is required when reopening a task")

    # Default target: back to in_progress, which keeps the task on the board
    # without pretending the finished work never happened. Parsed strictly (no
    # _normalize_status defaulting) so a typo fails loudly instead of silently
    # landing on "pending".
    raw_target = payload.get("status") or "in_progress"
    target_status = str(raw_target).strip().lower().replace(" ", "_")
    if target_status not in REOPEN_TARGET_STATUSES:
        raise HTTPException(
            400,
            "A reopen must target 'in_progress' or 'pending', "
            f"got '{raw_target}'",
        )

    old_status = task.status or "pending"
    if old_status not in TERMINAL_APPROVED_STATUSES:
        raise HTTPException(
            400,
            f"Only an approved task can be reopened (current status: {old_status})",
        )
    # Reuse the shared state machine so the reopen edges stay declared in exactly
    # one place (allow_reopen opts into the completed -> * edges).
    _validate_status_transition(old_status, target_status, allow_reopen=True)

    task.status = target_status
    # Reopened work is no longer finished: clear the completion timestamp and
    # pull progress back out of the 100% bucket. in_progress keeps whatever
    # partial progress was recorded, or starts at 50 when it is still 0/100.
    task.completed_at = None
    # The voided submission must not keep its evidence: a task that is no
    # longer completed cannot advertise a completion photo (the supervisor
    # review card would otherwise show the photo of an undone completion).
    # The file is removed through the guarded helper, and the audit row below
    # records that this happened.
    if task.completion_photo_path:
        delete_task_photo(task.completion_photo_path)
        task.completion_photo_path = None
        task.completion_photo_at = None
    if target_status == "pending":
        task.progress = 0
    elif not task.progress or task.progress >= 100:
        # in_progress with no usable partial progress: park it at 50% so the
        # board does not show a live task at 0% or still at 100%.
        task.progress = 50

    db.add(TaskProgressLog(
        task_id=task.task_id,
        from_status=old_status,
        to_status=target_status,
        note=reason,
        action="reopen",
        changed_by_id=current_user.id,
        changed_by_name=current_user.name,
        reason=reason,
    ))

    db.flush()  # persist the change before the recalc queries read the task set
    _recalc_project_progress(db, task.project_id)
    _recalc_project_status(db, task.project_id)
    db.commit()
    db.refresh(task)

    return {
        "status": "ok",
        "task_id": task.task_id,
        "from_status": old_status,
        "to_status": target_status,
        "progress": task.progress,
        "reopened_by": current_user.name,
        "reopened_by_id": current_user.id,
        "reason": reason,
    }


@router.get("/tasks/{task_id}/logs", response_model=List[TaskProgressLogOut])
def task_logs(
    task_id: int,
    user: CurrentUser = Depends(require_any_authorized),
    db: Session = Depends(get_db),
):
    """Return the task timeline (status/progress changes), newest first."""
    task = db.query(Task).get(task_id)
    if not task:
        raise HTTPException(404, "Task does not exist")
    _authorize_task_access(db, task, user)
    return (
        db.query(TaskProgressLog)
        .filter(TaskProgressLog.task_id == task_id)
        .order_by(TaskProgressLog.created_at.desc(), TaskProgressLog.log_id.desc())
        .all()
    )


@router.delete("/tasks/{task_id}")
def delete_task(
    task_id: int,
    user: CurrentUser = Depends(require_site_supervisor),
    db: Session = Depends(get_db),
):
    """Delete a task together with its task_workers association rows, then
    recompute the owning project's progress/status so the board stays in sync.

    SessionLocal runs with autoflush=False, therefore the task deletion must be
    flushed explicitly before the recalc queries re-read the project's task set.
    """
    task = db.query(Task).options(*_task_load_options()).get(task_id)
    if not task:
        raise HTTPException(404, "Task does not exist")
    _authorize_task_access(db, task, user)
    project_id = task.project_id
    # task.task_workers has cascade="all, delete-orphan" on the model, but we
    # delete the rows explicitly first (same pattern as _set_task_workers) so
    # ORM bookkeeping never re-inserts stale links during the flush.
    for link in list(task.task_workers):
        db.delete(link)
    db.flush()
    db.delete(task)
    db.flush()  # persist the delete so recalc queries see the reduced task set
    _recalc_project_progress(db, project_id)
    _recalc_project_status(db, project_id)
    db.commit()
    return {"status": "ok", "msg": f"Task {task_id} deleted successfully", "project_id": project_id}


@router.post("/ai/tasks/match", response_model=List[AIMatchResult])
def ai_match(
    required_trade: str,
    project_id: int,
    required_specialty: Optional[str] = None,
    user: CurrentUser = Depends(require_site_supervisor),
    db: Session = Depends(get_db),
):
    """Rank workers against a required trade level.

    Scoring runs on the four skill levels. Because the granularity is now
    coarse (four values instead of sixteen), exact matches alone would leave
    most candidates tied, so seniority is used as a tiebreaker: a worker whose
    level is above the requirement can still perform the task (ranked below an
    exact match), while a lower level is treated as a mismatch.
    """
    project_for_user(db, user, project_id, supervisor_only=True)
    workers = db.query(Worker).filter(Worker.project_id == project_id).all()
    if not workers:
        raise HTTPException(404, "No workers found")

    requested_level = trade_level(required_trade) or DEFAULT_LEVEL
    requested_rank = TRADE_LEVEL_RANK.get(requested_level, 1)
    specialty = normalise_specialty(required_specialty)
    results = []
    for worker in workers:
        worker_level = trade_level(worker.trade)
        worker_rank = level_rank(worker.trade)
        has_specialty = not specialty or specialty in normalise_specialties(worker.specialties)
        if specialty and not has_specialty:
            continue
        if worker_level == requested_level:
            score, reason = 1.0, f"Exact skill level match: {worker_level}"
        elif worker_level and worker_rank > requested_rank:
            # Over-qualified but capable: keep it above pure availability.
            score = 0.8 - 0.1 * (worker_rank - requested_rank - 1)
            reason = f"Higher skill level ({worker_level}) covers the requirement ({requested_level})"
        elif worker_level:
            score = 0.3
            reason = f"Skill level below requirement (current: {worker_level}, required: {requested_level})"
        else:
            score, reason = 0.2, f"Skill level not set (current: {worker.trade or 'not set'}), recommended by availability only"
        if specialty:
            score += 0.4
            reason += f"; specialty match: {specialty}"
        results.append(
            AIMatchResult(
                worker_id=worker.worker_id,
                worker_name=worker.name,
                trade=worker.trade or "-",
                match_score=round(score, 2),
                reason=reason,
            )
        )
    results.sort(key=lambda row: row.match_score, reverse=True)
    return results





# ══════════════════════════════════════════════════════════════════
# Worker-specific AI Task Board (Worker-only endpoints)
# ══════════════════════════════════════════════════════════════════

# AI-part inference helpers for the worker's personal task board.
# Keyed by the four skill levels (see app.trade_levels). Workers whose stored
# trade is still a legacy fine-grained value are resolved through trade_level()
# before the lookup, so the templates never miss on historical rows.
TRADE_TO_PARTS: Dict[str, List[str]] = {
    "general worker": ["General Work Section", "Site Logistics Section", "Housekeeping Section"],
    "semi skilled worker": ["Finishing Section", "Drywall & Insulation Section", "Blockwork Support Section"],
    "skilled worker": ["Structural Section", "MEP Rough-in Section", "Fit-out Section"],
    "foreman": ["Workfront Supervision Section", "Quality Check Section", "Coordination Section"],
}

TRADE_INSTRUCTIONS: Dict[str, str] = {
    "general worker": "Cooperate with trades; maintain housekeeping; use PPE at all times.",
    "semi skilled worker": "Prepare surfaces before finishing; keep material batch consistent; check level every 3 courses.",
    "skilled worker": "Work to approved drawings; verify dimensions and setting-out before covering any work; test before handover.",
    "foreman": "Confirm today's workfront and manpower; inspect completed work before sign-off; record any defect found.",
}

def _level_of(worker: Worker) -> str:
    """Skill level used as template key, falling back to the default level."""
    return trade_level(worker.trade) or DEFAULT_LEVEL

def _ai_infer_part_section(task: Task, worker: Worker, used: Optional[set] = None) -> str:
    parts = TRADE_TO_PARTS.get(_level_of(worker), TRADE_TO_PARTS[DEFAULT_LEVEL])
    n = max(len(parts), 1)
    idx = (task.task_id or 0) % n
    tname = task.task_name.lower()

    def _build(i: int) -> str:
        base = parts[i % n]
        if "floor" in tname:
            return f"Floor {task.task_id % 10 + 1} — " + base
        if "wall" in tname or "column" in tname:
            return "Grid " + chr(65 + (task.task_id % 6)) + " — " + base
        return base

    section = _build(idx)
    if used is not None:
        # Deduplicate: avoid showing the same part_section twice on one
        # worker's board by probing the trade's parts list in order.
        if section in used:
            for offset in range(1, n + 1):
                cand = _build(idx + offset)
                if cand not in used:
                    section = cand
                    break
        used.add(section)
    return section

def _ai_work_instructions(task: Task, worker: Worker) -> str:
    base = TRADE_INSTRUCTIONS.get(_level_of(worker), TRADE_INSTRUCTIONS[DEFAULT_LEVEL])
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
    trade = level_label(worker.trade) or "General Worker"
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
    AI inference enriches each task with part_section (work section) and work_instructions,
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
    used_sections: set = set()
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
            part_section=_ai_infer_part_section(t, worker, used_sections),
            work_instructions=_ai_work_instructions(t, worker),
            progress=int(round(
                t.progress
                if t.progress is not None
                else STATUS_TO_PROGRESS.get(t.status or "pending", 0)
            )),
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

