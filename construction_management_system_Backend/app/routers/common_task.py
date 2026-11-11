"""Daily common tasks and the toolbox talk.

Two routers live here because the flows are different even though they share the
same tab on the phone:

* ``router`` (``/common-tasks``) — the three jobs every site repeats daily
  (morning briefing, toolbox talk, housekeeping). The day's checklist is created
  lazily on first read (see :mod:`app.common_task_service`), so it shows up
  without a background scheduler, and it can only be closed with a photo.
* ``toolbox_router`` (``/toolbox``) — tools signed out and brought back. Several
  tools share one photo per hand-over, and whatever is still out is a single
  query away, which is the whole reason the paper toolbox register was replaced.

Every photo is stored through :mod:`app.common_photo` (Supabase Storage, local
disk as fallback) and every read is authenticated: the caller may only see the
evidence of their own project.
"""

from datetime import date, datetime, timedelta
from typing import Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import FileResponse, JSONResponse, RedirectResponse
from sqlalchemy.orm import Session

from app.attendance_photo import PhotoError
from app.common_photo import (
    COMMON_TASK_SUBDIR,
    TOOLBOX_SUBDIR,
    delete_common_photo,
    open_common_task_photo,
    open_toolbox_photo,
    save_common_task_photo,
    save_toolbox_photo,
)
from app.common_task_service import (
    COMMON_TASK_KINDS,
    ensure_daily_instances,
    serialize_instance,
)
from app.database import get_db
from app.models import CommonTaskInstance, Project, ToolboxIssue, Worker
from app.routers.auth import require_any_authorized, require_worker
from app.schemas import (
    CommonTaskCompleteIn,
    CommonTaskOut,
    ToolboxIssueOut,
    ToolboxReturnIn,
    ToolboxTakeIn,
)
from app.storage_service import DEFAULT_SIGNED_URL_TTL

router = APIRouter(prefix="/common-tasks", tags=["🧹 Common Tasks"])
toolbox_router = APIRouter(prefix="/toolbox", tags=["🧰 Toolbox"])

_PHOTO_MEDIA_TYPES = {"jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png"}


# ────────────────── Permission helpers ──────────────────
def _worker_project(db: Session, user) -> int:
    """The project the caller works on (worker side)."""
    worker = db.query(Worker).filter(Worker.worker_id == user.worker_id).first()
    if not worker:
        raise HTTPException(404, "Worker account does not exist")
    if not worker.project_id:
        raise HTTPException(
            400,
            "You are not assigned to a project yet, so there are no daily tasks",
        )
    return int(worker.project_id)


def _resolve_project(db: Session, user, project_id: Optional[int]) -> int:
    """Which project the caller is acting on, after checking they may.

    A worker is pinned to their own project (passing another one is refused
    rather than silently ignored). A supervisor must name a project they own.
    """
    if user.user_type == "worker":
        own = _worker_project(db, user)
        if project_id and int(project_id) != own:
            raise HTTPException(403, "This project is not yours")
        return own

    if not project_id:
        raise HTTPException(400, "project_id is required")
    project = (
        db.query(Project).filter(Project.project_id == int(project_id)).first()
    )
    if not project:
        raise HTTPException(404, "Project not found")
    if project.supervisor_id != user.supervisor_id:
        raise HTTPException(403, "This project is not assigned to you")
    return int(project.project_id)


def _supervisor_daily_summary(db: Session, supervisor_id: int, day: date) -> List[Dict[str, object]]:
    """Summarise the three daily jobs across a supervisor's projects.

    The dashboard's default scope is "All projects".  A daily job is still
    created and completed per project; this helper only supplies the compact
    three-row overview needed by that dashboard scope.  Selecting a project
    continues to return that project's actual task instances.
    """
    projects = (
        db.query(Project)
        .filter(Project.supervisor_id == supervisor_id)
        .order_by(Project.project_id)
        .all()
    )
    if not projects:
        return []

    rows_by_kind: Dict[str, List[CommonTaskInstance]] = {
        kind: [] for kind in COMMON_TASK_KINDS
    }
    for project in projects:
        for instance in ensure_daily_instances(db, project.project_id, day):
            rows_by_kind.setdefault(instance.task_kind, []).append(instance)

    summary: List[Dict[str, object]] = []
    for kind in COMMON_TASK_KINDS:
        instances = rows_by_kind.get(kind, [])
        done_count = sum(1 for item in instances if (item.status or '').lower() == 'done')
        total = len(instances)
        status = 'done' if total and done_count == total else (
            'in_progress' if done_count else 'pending'
        )
        summary.append({
            'project_id': None,
            'task_kind': kind,
            'work_date': day.isoformat(),
            'status': status,
            'project_count': total,
            'completed_project_count': done_count,
        })
    return summary


def _may_view_project_photo(db: Session, user, project_id: Optional[int]) -> bool:
    """Read-only variant of :func:`_resolve_project` (no 400 on missing project)."""
    if user.user_type == "worker":
        try:
            own = _worker_project(db, user)
        except HTTPException:
            return False
        return project_id is None or int(project_id) == own
    if not project_id:
        return False
    project = db.query(Project).filter(Project.project_id == int(project_id)).first()
    return bool(project and project.supervisor_id == user.supervisor_id)


def _iso(value: Optional[datetime]) -> Optional[str]:
    if not value:
        return None
    return (value.replace(tzinfo=None) if value.tzinfo else value).isoformat()


def _photo_response(source_kind: str, target: str, redirect: bool):
    """Stream a local file, or hand the client a short-lived signed URL."""
    if source_kind == "local":
        ext = target.rsplit(".", 1)[-1].lower()
        return FileResponse(
            target, media_type=_PHOTO_MEDIA_TYPES.get(ext, "application/octet-stream")
        )
    if redirect:
        return RedirectResponse(target, status_code=307)
    return JSONResponse({"url": target, "expires_in": DEFAULT_SIGNED_URL_TTL})


# ────────────────── Common tasks ──────────────────
@router.get("/today", response_model=Dict[str, object])
def today_tasks(
    project_id: Optional[int] = Query(None),
    work_date: Optional[date] = Query(None),
    user=Depends(require_any_authorized),
    db: Session = Depends(get_db),
):
    """Today's checklist for the caller's project.

    Opening this endpoint IS what creates the day's rows, so the three common
    tasks always exist without a scheduler running anywhere.
    """
    day = work_date or date.today()
    # Supervisors open their dashboard in an all-project scope by default.  It
    # should show a useful three-row overview instead of failing because no
    # individual project was selected yet.
    if user.user_type != "worker" and not project_id:
        return {
            "project_id": None,
            "work_date": day.isoformat(),
            "tasks": _supervisor_daily_summary(db, user.supervisor_id, day),
        }

    pid = _resolve_project(db, user, project_id)
    instances = ensure_daily_instances(db, pid, day)
    return {
        "project_id": pid,
        "work_date": day.isoformat(),
        "tasks": [serialize_instance(db, inst) for inst in instances],
    }


@router.get("", response_model=List[CommonTaskOut])
def list_common_tasks(
    project_id: Optional[int] = Query(None),
    days: int = Query(7, ge=1, le=90),
    user=Depends(require_any_authorized),
    db: Session = Depends(get_db),
):
    """Recent history (default: the last ``days`` days, today included)."""
    pid = _resolve_project(db, user, project_id)
    today = date.today()
    ensure_daily_instances(db, pid, today)
    since = today - timedelta(days=days - 1)
    rows = (
        db.query(CommonTaskInstance)
        .filter(
            CommonTaskInstance.project_id == pid,
            CommonTaskInstance.work_date >= since,
            CommonTaskInstance.work_date <= today,
        )
        .order_by(CommonTaskInstance.work_date.desc())
        .all()
    )
    order = {k: i for i, k in enumerate(COMMON_TASK_KINDS)}
    rows.sort(key=lambda r: (r.work_date, order.get(r.task_kind, 99)), reverse=True)
    return [serialize_instance(db, r) for r in rows]


@router.post("/{instance_id}/complete", response_model=CommonTaskOut)
def complete_common_task(
    instance_id: int,
    payload: CommonTaskCompleteIn,
    user=Depends(require_worker),
    db: Session = Depends(get_db),
):
    """Close one daily task with a photo. The photo is required, never optional.

    Re-submitting replaces the previous evidence (one photo per instance, the
    latest one) — the same rule the task-completion flow uses.
    """
    instance = (
        db.query(CommonTaskInstance)
        .filter(CommonTaskInstance.instance_id == instance_id)
        .first()
    )
    if not instance:
        raise HTTPException(404, "Common task not found")

    _resolve_project(db, user, instance.project_id)

    photo_b64 = (payload.photo_base64 or "").strip()
    if not photo_b64:
        raise HTTPException(
            400,
            "A site photo is required to complete this task "
            "(send photo_base64, camera capture only)",
        )

    try:
        rel_path = save_common_task_photo(
            photo_b64,
            project_id=instance.project_id,
            task_kind=instance.task_kind,
            worker_id=user.worker_id,
        )
    except PhotoError as exc:
        raise HTTPException(400, str(exc))

    previous = instance.photo_path
    instance.photo_path = rel_path
    instance.status = "done"
    instance.completed_at = datetime.utcnow()
    instance.completed_by = user.worker_id
    db.commit()
    db.refresh(instance)

    if previous and previous != rel_path:
        # Keep storage tidy: the row holds one photo, so the old object goes.
        delete_common_photo(previous, root_subdir=COMMON_TASK_SUBDIR)

    return serialize_instance(db, instance)


@router.get("/{instance_id}/photo")
def get_common_task_photo(
    instance_id: int,
    redirect: bool = True,
    user=Depends(require_any_authorized),
    db: Session = Depends(get_db),
):
    """Replay the evidence of one daily task (authenticated, project-scoped)."""
    instance = (
        db.query(CommonTaskInstance)
        .filter(CommonTaskInstance.instance_id == instance_id)
        .first()
    )
    if not instance or not instance.photo_path:
        raise HTTPException(404, "Photo not found")
    if not _may_view_project_photo(db, user, instance.project_id):
        raise HTTPException(403, "You are not allowed to view this photo")

    try:
        source_kind, target = open_common_task_photo(instance.photo_path)
    except PhotoError:
        raise HTTPException(404, "Photo not found")
    return _photo_response(source_kind, target, redirect)


# ────────────────── Toolbox: take out / bring back ──────────────────
def _toolbox_out(issue: ToolboxIssue, worker_name: Optional[str] = None) -> Dict[str, object]:
    return {
        "issue_id": issue.issue_id,
        "worker_id": issue.worker_id,
        "worker_name": worker_name,
        "project_id": issue.project_id,
        "tool_name": issue.tool_name,
        "qty": int(issue.qty or 0),
        "status": issue.status or "taken",
        "taken_at": _iso(issue.taken_at),
        "returned_at": _iso(issue.returned_at),
        "take_photo_url": (
            f"/toolbox/issues/{issue.issue_id}/photo?kind=take"
            if issue.take_photo_path
            else None
        ),
        "return_photo_url": (
            f"/toolbox/issues/{issue.issue_id}/photo?kind=return"
            if issue.return_photo_path
            else None
        ),
    }


@toolbox_router.post("/take", response_model=Dict[str, object])
def take_tools(
    payload: ToolboxTakeIn,
    user=Depends(require_worker),
    db: Session = Depends(get_db),
):
    """Sign out one or more tools under a single photo of the tray."""
    pid = _resolve_project(db, user, payload.project_id)

    photo_b64 = (payload.photo_base64 or "").strip()
    if not photo_b64:
        raise HTTPException(
            400, "A photo of the tools is required (send photo_base64)"
        )

    taken_at = datetime.utcnow()
    try:
        rel_path = save_toolbox_photo(
            photo_b64,
            project_id=pid,
            worker_id=user.worker_id,
            kind="take",
            taken_at=taken_at,
        )
    except PhotoError as exc:
        raise HTTPException(400, str(exc))

    created: List[ToolboxIssue] = []
    for item in payload.items:
        issue = ToolboxIssue(
            worker_id=user.worker_id,
            project_id=pid,
            tool_name=item.tool_name.strip(),
            qty=item.qty,
            taken_at=taken_at,
            take_photo_path=rel_path,
            status="taken",
        )
        db.add(issue)
        created.append(issue)
    db.commit()
    for issue in created:
        db.refresh(issue)

    worker = db.query(Worker).filter(Worker.worker_id == user.worker_id).first()
    name = worker.name if worker else None
    return {
        "photo_url": f"/toolbox/issues/{created[0].issue_id}/photo?kind=take",
        "count": len(created),
        "items": [_toolbox_out(i, name) for i in created],
    }


@toolbox_router.post("/return", response_model=Dict[str, object])
def return_tools(
    payload: ToolboxReturnIn,
    user=Depends(require_any_authorized),
    db: Session = Depends(get_db),
):
    """Close one or more open issues with a single photo of the returned tools."""
    ids = list(dict.fromkeys(int(i) for i in payload.issue_ids))
    rows = (
        db.query(ToolboxIssue).filter(ToolboxIssue.issue_id.in_(ids)).all()
    )
    found = {r.issue_id: r for r in rows}
    missing = [i for i in ids if i not in found]
    if missing:
        raise HTTPException(
            404, f"Toolbox issue not found: {', '.join(str(i) for i in missing)}"
        )

    for issue in rows:
        if user.user_type == "worker":
            if issue.worker_id != user.worker_id:
                raise HTTPException(403, "This tool was not taken by you")
        elif not _may_view_project_photo(db, user, issue.project_id):
            raise HTTPException(403, "This tool does not belong to your project")

    photo_b64 = (payload.photo_base64 or "").strip()
    if not photo_b64:
        raise HTTPException(
            400, "A photo of the returned tools is required (send photo_base64)"
        )

    returned_at = datetime.utcnow()
    try:
        rel_path = save_toolbox_photo(
            photo_b64,
            project_id=rows[0].project_id,
            worker_id=rows[0].worker_id,
            kind="return",
            taken_at=returned_at,
        )
    except PhotoError as exc:
        raise HTTPException(400, str(exc))

    opened = [r for r in rows if (r.status or "taken") != "returned"]
    for issue in opened:
        issue.status = "returned"
        issue.returned_at = returned_at
        issue.return_photo_path = rel_path
    if opened:
        db.commit()
        for issue in opened:
            db.refresh(issue)

    names = _worker_names(db, {r.worker_id for r in rows})
    return {
        "photo_url": f"/toolbox/issues/{rows[0].issue_id}/photo?kind=return",
        "returned_count": len(opened),
        "already_returned": len(rows) - len(opened),
        "items": [_toolbox_out(r, names.get(r.worker_id)) for r in rows],
    }


@toolbox_router.get("/outstanding", response_model=List[ToolboxIssueOut])
def outstanding_tools(
    worker_id: Optional[int] = Query(None),
    project_id: Optional[int] = Query(None),
    user=Depends(require_any_authorized),
    db: Session = Depends(get_db),
):
    """Everything not yet brought back — the replacement for the paper register.

    A worker sees only their own outstanding tools; a supervisor sees every open
    item of a project they own.
    """
    query = db.query(ToolboxIssue).filter(
        ToolboxIssue.status != "returned"
    )

    if user.user_type == "worker":
        query = query.filter(ToolboxIssue.worker_id == user.worker_id)
    else:
        if not project_id:
            raise HTTPException(
                400, "project_id is required to list a project's outstanding tools"
            )
        if not _may_view_project_photo(db, user, project_id):
            raise HTTPException(403, "This project is not assigned to you")
        query = query.filter(ToolboxIssue.project_id == int(project_id))
        if worker_id:
            query = query.filter(ToolboxIssue.worker_id == int(worker_id))

    rows = query.order_by(ToolboxIssue.taken_at.desc()).all()
    names = _worker_names(db, {r.worker_id for r in rows})
    return [_toolbox_out(r, names.get(r.worker_id)) for r in rows]


@toolbox_router.get("/issues", response_model=List[ToolboxIssueOut])
def list_toolbox_issues(
    worker_id: Optional[int] = Query(None),
    project_id: Optional[int] = Query(None),
    status: Optional[str] = Query(None),
    limit: int = Query(100, ge=1, le=500),
    user=Depends(require_any_authorized),
    db: Session = Depends(get_db),
):
    """History of hand-overs (all statuses), for review."""
    query = db.query(ToolboxIssue)

    if user.user_type == "worker":
        query = query.filter(ToolboxIssue.worker_id == user.worker_id)
    else:
        if not project_id:
            raise HTTPException(400, "project_id is required")
        if not _may_view_project_photo(db, user, project_id):
            raise HTTPException(403, "This project is not assigned to you")
        query = query.filter(ToolboxIssue.project_id == int(project_id))
        if worker_id:
            query = query.filter(ToolboxIssue.worker_id == int(worker_id))

    if status:
        query = query.filter(ToolboxIssue.status == status)

    rows = query.order_by(ToolboxIssue.taken_at.desc()).limit(limit).all()
    names = _worker_names(db, {r.worker_id for r in rows})
    return [_toolbox_out(r, names.get(r.worker_id)) for r in rows]


@toolbox_router.get("/issues/{issue_id}/photo")
def get_toolbox_photo(
    issue_id: int,
    kind: str = Query("take"),
    redirect: bool = True,
    user=Depends(require_any_authorized),
    db: Session = Depends(get_db),
):
    """Replay the take-out or return photo of one issue."""
    issue = db.query(ToolboxIssue).filter(ToolboxIssue.issue_id == issue_id).first()
    if not issue:
        raise HTTPException(404, "Toolbox issue not found")

    if user.user_type == "worker":
        if issue.worker_id != user.worker_id:
            raise HTTPException(403, "You are not allowed to view this photo")
    elif not _may_view_project_photo(db, user, issue.project_id):
        raise HTTPException(403, "You are not allowed to view this photo")

    rel_path = issue.return_photo_path if kind == "return" else issue.take_photo_path
    if not rel_path:
        raise HTTPException(404, "Photo not found")

    try:
        source_kind, target = open_toolbox_photo(rel_path)
    except PhotoError:
        raise HTTPException(404, "Photo not found")
    return _photo_response(source_kind, target, redirect)


def _worker_names(db: Session, worker_ids) -> Dict[int, str]:
    """Map worker ids to names so issue lists can show who took the tool."""
    ids = [int(i) for i in worker_ids if i]
    if not ids:
        return {}
    rows = db.query(Worker).filter(Worker.worker_id.in_(ids)).all()
    return {w.worker_id: w.name for w in rows}
