"""Photo persistence for the daily common tasks and the toolbox hand-over.

Both flows borrow the attendance rules verbatim — camera capture on the device,
base64 upload, magic-byte sniffing, size cap and a storage root outside the code
tree — so a client cannot upload an arbitrary file and call it evidence. What is
new here is only the object layout: evidence is filed under the project (and the
kind of job) instead of under one worker, because the briefing and the
housekeeping log belong to the site, not to whoever happened to press the button.

The value stored on the row is always a key relative to ``UPLOAD_DIR`` (forward
slashes only), so objects can be replayed through an authenticated endpoint while
the backend can still move between local disk and the bucket without migrating
data.
"""

import base64
import binascii
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

# Sub-directories of the storage root. Kept apart from ``attendance`` /
# ``task_completion`` so retention policies can differ and so a key from one flow
# can never be replayed against another (each reader bounds its own subtree).
COMMON_TASK_SUBDIR = "common_task"
TOOLBOX_SUBDIR = "toolbox"


def _decode(photo_base64: str) -> bytes:
    """Validate a base64 photo payload and return the decoded bytes."""
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

    if _sniff_extension(data) is None:
        raise PhotoError("Photo must be a JPEG or PNG image")
    return data


def _store(
    photo_base64: str,
    *,
    subdir: str,
    parts: list,
    prefix: str,
    taken_at: Optional[datetime] = None,
) -> str:
    """Persist one validated photo and return its relative object key."""
    data = _decode(photo_base64)
    ext = _sniff_extension(data)
    stamp = taken_at or datetime.now()
    rel_dir = "/".join([subdir] + [str(p) for p in parts] + [f"{stamp.year}{stamp.month:02d}"])
    filename = (
        f"{prefix}_{stamp.strftime('%Y%m%d%H%M%S')}_{uuid.uuid4().hex[:8]}.{ext}"
    )
    return storage_service.save_object(f"{rel_dir}/{filename}", data)


def save_common_task_photo(
    photo_base64: str,
    *,
    project_id: int,
    task_kind: str,
    worker_id: Optional[int] = None,
    taken_at: Optional[datetime] = None,
) -> str:
    """Evidence for one daily common task (briefing / toolbox / housekeeping)."""
    worker_part = f"w{int(worker_id)}" if worker_id else "w0"
    return _store(
        photo_base64,
        subdir=COMMON_TASK_SUBDIR,
        parts=[int(project_id), str(task_kind or "task").lower(), worker_part],
        prefix="done",
        taken_at=taken_at,
    )


def save_toolbox_photo(
    photo_base64: str,
    *,
    project_id: Optional[int],
    worker_id: int,
    kind: str,
    taken_at: Optional[datetime] = None,
) -> str:
    """Toolbox evidence. ``kind`` is ``take`` or ``return``.

    One photo may back several ``ToolboxIssue`` rows: the whole tray is shot once
    when it leaves the store and once when it comes back.
    """
    return _store(
        photo_base64,
        subdir=TOOLBOX_SUBDIR,
        parts=[int(project_id or 0), f"w{int(worker_id)}"],
        prefix=str(kind or "take").lower(),
        taken_at=taken_at,
    )


def open_common_task_photo(rel_path: str) -> Tuple[str, str]:
    """Resolve a common-task photo for reading (local path or signed URL)."""
    try:
        return storage_service.open_source(rel_path, root_subdir=COMMON_TASK_SUBDIR)
    except storage_service.StorageError:
        raise PhotoError("Photo not found")


def open_toolbox_photo(rel_path: str) -> Tuple[str, str]:
    """Resolve a toolbox photo for reading (local path or signed URL)."""
    try:
        return storage_service.open_source(rel_path, root_subdir=TOOLBOX_SUBDIR)
    except storage_service.StorageError:
        raise PhotoError("Photo not found")


def delete_common_photo(rel_path: Optional[str], *, root_subdir: str) -> bool:
    """Best-effort removal of a replaced photo; never breaks the transaction."""
    if not rel_path:
        return False
    try:
        # Confine deletion to its own subtree exactly as reads are confined.
        storage_service.local_abs_path(rel_path, root_subdir=root_subdir)
    except storage_service.StorageError:
        return False
    return storage_service.delete_object(rel_path)
