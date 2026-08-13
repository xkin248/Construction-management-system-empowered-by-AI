"""Shared helper for building a unified project worker pool.

A worker belongs to a project's pool if either:
  1. Worker.project_id == project_id (explicit binding), OR
  2. The worker has at least one AttendanceLog for this project.

The result is deduplicated by worker_id, so a worker bound to the project
who also clocked in only appears once.
"""
from typing import List
from sqlalchemy.orm import Session

from app.models import Worker, AttendanceLog


def get_project_workers(db: Session, project_id: int) -> List[Worker]:
    bound_ids = {
        w.worker_id
        for w in db.query(Worker.worker_id).filter(
            Worker.project_id == project_id
        ).all()
    }
    attended_ids = {
        row[0]
        for row in db.query(AttendanceLog.worker_id).filter(
            AttendanceLog.project_id == project_id
        ).all()
    }

    ids = bound_ids | attended_ids
    if not ids:
        return []

    return (
        db.query(Worker)
        .filter(Worker.worker_id.in_(ids))
        .order_by(Worker.worker_id.desc())
        .all()
    )
