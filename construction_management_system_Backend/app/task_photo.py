"""Persistence for the photo a worker must submit to finish a task.

Completion evidence follows the same rules as the attendance selfie (see
``attendance_photo.py``): camera capture on the device, base64 upload, magic
byte sniffing, size cap and a directory outside the code tree. The two flows
stay apart on disk (``uploads/task_completion`` vs ``uploads/attendance``) so
retention or review policies can differ, and because a task photo is owned by
the task — not by a worker or a supervisor row.

The path stored on ``Task.completion_photo_path`` is always relative to
``UPLOAD_DIR`` so it can be replayed through an authenticated endpoint.
"""

import base64
import binascii
import os
import uuid
from datetime import datetime
from typing import Optional, Tuple

from app import storage_service
from app.attendance_photo import (
    MAX_PHOTO_BYTES,
    PhotoError,
    _sniff_extension,
    _strip_data_url,
)

# Sub-directory of the storage root holding task completion evidence.
TASK_PHOTO_SUBDIR = "task_completion"


def save_task_photo(
    photo_base64: str,
    *,
    task_id: int,
    worker_id: Optional[int] = None,
    taken_at: Optional[datetime] = None,
) -> str:
    """Validate and persist one task-completion photo.

    Returns the path relative to ``UPLOAD_DIR`` (forward slashes only).
    """
    raw = _strip_data_url(photo_base64 or "")
    if not raw:
        raise PhotoError("Empty photo payload")

    # Reject on the encoded length before decoding: an oversized payload must
    # never be materialised in memory.
    if len(raw) > MAX_PHOTO_BYTES * 2:
        raise PhotoError(
            f"Photo is too large (limit {MAX_PHOTO_BYTES // (1024 * 1024)}MB)"
        )

    try:
        data = base64.b64decode(raw, validate=True)
    except (binascii.Error, ValueError):
        raise PhotoError("Photo payload is not valid base64")

    if not data:
        raise PhotoError("Empty photo payload")
    if len(data) > MAX_PHOTO_BYTES:
        raise PhotoError(
            f"Photo is too large (limit {MAX_PHOTO_BYTES // (1024 * 1024)}MB)"
        )

    ext = _sniff_extension(data)
    if ext is None:
        raise PhotoError("Photo must be a JPEG or PNG image")

    stamp = taken_at or datetime.now()
    worker_part = f"w{int(worker_id)}" if worker_id else "w0"
    rel_dir = "/".join(
        [TASK_PHOTO_SUBDIR, str(int(task_id)), worker_part, f"{stamp.year}{stamp.month:02d}"]
    )
    filename = f"done_{stamp.strftime('%Y%m%d%H%M%S')}_{uuid.uuid4().hex[:8]}.{ext}"
    rel_path = f"{rel_dir}/{filename}"

    # Key only on the task row; bytes go to Supabase Storage or uploads/.
    return storage_service.save_object(rel_path, data)


def resolve_task_photo_path(rel_path: str) -> str:
    """Absolute path of a locally stored completion photo.

    Kept for callers that need the file on disk; the API read path is
    :func:`open_task_photo`, which also serves objects held in the bucket.
    """
    try:
        target = storage_service.local_abs_path(
            rel_path, root_subdir=TASK_PHOTO_SUBDIR
        )
    except storage_service.StorageError:
        raise PhotoError("Invalid photo path")
    if not os.path.isfile(target):
        raise PhotoError("Photo not found")
    return target


def open_task_photo(rel_path: str) -> Tuple[str, str]:
    """Resolve a stored completion photo for reading.

    Returns ``("local", absolute_path)`` for evidence written before the switch
    or ``("url", signed_url)`` for an object in the bucket. The router has
    already checked that the caller may review this task's evidence.
    """
    try:
        return storage_service.open_source(
            rel_path, root_subdir=TASK_PHOTO_SUBDIR
        )
    except storage_service.StorageError:
        raise PhotoError("Photo not found")


def delete_task_photo(rel_path: Optional[str]) -> bool:
    """Remove a previously stored completion photo (best effort).

    Used when a task's evidence is replaced ("keep only the latest submission")
    or dropped on reopen. Both backends are cleaned, and every failure is
    swallowed: a missing object or a flaky bucket must never break the database
    transaction that is replacing it.
    """
    if not rel_path:
        return False
    try:
        # Confine deletion to uploads/task_completion the same way reads are.
        storage_service.local_abs_path(rel_path, root_subdir=TASK_PHOTO_SUBDIR)
    except storage_service.StorageError:
        return False
    return storage_service.delete_object(rel_path)


def task_photo_url(task_id: int, rel_path: Optional[str]) -> Optional[str]:
    """API URL a client can GET to review the completion photo (None if absent)."""
    if not rel_path:
        return None
    return f"/tasks/{int(task_id)}/completion-photo"
