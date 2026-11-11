"""Persistence for the on-site selfie that check-in now requires.

The capture itself always happens on the device (camera only, never the photo
library) so that the picture is proof of presence; this module is the server
side of that contract:

* decode the base64 payload the client posts,
* refuse anything that is not a real JPEG/PNG and anything above the size cap,
* write it under ``uploads/attendance/...`` outside the code tree,
* return the path relative to ``UPLOAD_DIR`` so it can be stored on the
  attendance row and replayed later through the authenticated photo endpoint.

Keeping the photos out of the ``files`` table is intentional: that table is
keyed on ``supervisors.supervisor_id`` (``File.uploaded_by``), so a worker can
never own a row there. Attendance photos are owned by the attendance record
instead, which already knows whether it belongs to a worker or a supervisor.
"""

import base64
import binascii
import os
import re
import uuid
from datetime import datetime
from typing import Optional, Tuple

from app import storage_service

# Sub-directory of the storage root that holds attendance evidence. Keeping it
# separate makes retention / backup policies easy to apply per flow.
ATTENDANCE_PHOTO_SUBDIR = "attendance"

# A 1280px-wide JPEG at quality 60 is well below 1 MB; 6 MB leaves room for
# older devices while still refusing anything abusive.
MAX_PHOTO_BYTES = 6 * 1024 * 1024

_KIND_RE = re.compile(r"^[a-z_]{1,16}$")


class PhotoError(ValueError):
    """Raised when the submitted photo cannot be accepted."""


def _sniff_extension(data: bytes) -> Optional[str]:
    """Return the extension derived from the magic bytes, or None.

    The declared mime type is never trusted on its own: a client could label a
    text file as image/jpeg, and we would happily store it as evidence.
    """
    if data.startswith(b"\xff\xd8\xff"):
        return "jpg"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "png"
    return None


def _strip_data_url(payload: str) -> str:
    """Accept both a bare base64 string and a ``data:image/jpeg;base64,...`` URL."""
    text = payload.strip()
    if text.startswith("data:"):
        comma = text.find(",")
        if comma == -1:
            raise PhotoError("Malformed photo payload")
        header = text[:comma].lower()
        if "base64" not in header:
            raise PhotoError("Photo payload must be base64 encoded")
        text = text[comma + 1:]
    return text


def save_photo(
    photo_base64: str,
    *,
    user_type: str,
    user_id: int,
    project_id: Optional[int],
    kind: str,
    taken_at: Optional[datetime] = None,
) -> str:
    """Validate and persist one attendance photo.

    Returns the path relative to ``UPLOAD_DIR`` (always with forward slashes, so
    it can be put straight into a URL).
    """
    if not _KIND_RE.match(kind or ""):
        raise PhotoError("Invalid photo kind")

    raw = _strip_data_url(photo_base64 or "")
    if not raw:
        raise PhotoError("Empty photo payload")

    # Reject on the encoded length first so an oversized payload never gets
    # decoded into memory.
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
    owner = "worker" if user_type == "worker" else "supervisor"
    owner_id = int(user_id)
    project_part = f"p{int(project_id)}" if project_id else "p0"
    month_part = f"{stamp.year}{stamp.month:02d}"

    rel_dir = "/".join(
        [ATTENDANCE_PHOTO_SUBDIR, owner, str(owner_id), project_part, month_part]
    )
    filename = f"{kind}_{stamp.strftime('%Y%m%d%H%M%S')}_{uuid.uuid4().hex[:8]}.{ext}"
    rel_path = f"{rel_dir}/{filename}"

    # Only the key is persisted on the attendance row. The bytes go to Supabase
    # Storage when it is configured and to uploads/ otherwise (see
    # ``storage_service``), so the same key stays valid either way.
    return storage_service.save_object(rel_path, data)


def resolve_photo_path(rel_path: str) -> str:
    """Absolute path of a locally stored photo.

    Retained for callers that need the bytes on disk (backups, tests). The
    read path used by the API is :func:`open_photo`, which also handles photos
    that live in the bucket.
    """
    try:
        target = storage_service.local_abs_path(
            rel_path, root_subdir=ATTENDANCE_PHOTO_SUBDIR
        )
    except storage_service.StorageError:
        raise PhotoError("Invalid photo path")
    if not os.path.isfile(target):
        raise PhotoError("Photo not found")
    return target


def open_photo(rel_path: str) -> Tuple[str, str]:
    """Resolve a stored photo for reading.

    Returns ``("local", absolute_path)`` when a copy sits on disk — this covers
    every selfie taken before the Supabase switch — or ``("url", signed_url)``
    for an object in the bucket. Authorisation always happens in the router
    before this call, so a signed link is never minted for an unauthorised
    reader.
    """
    try:
        return storage_service.open_source(
            rel_path, root_subdir=ATTENDANCE_PHOTO_SUBDIR
        )
    except storage_service.StorageError:
        raise PhotoError("Photo not found")


def photo_owner(rel_path: str) -> Tuple[Optional[str], Optional[int]]:
    """Extract (owner_type, owner_id) from a stored photo path."""
    parts = (rel_path or "").replace("\\", "/").strip("/").split("/")
    if len(parts) < 3 or parts[0] != ATTENDANCE_PHOTO_SUBDIR:
        return None, None
    try:
        return parts[1], int(parts[2])
    except (IndexError, ValueError):
        return None, None


def photo_url(rel_path: Optional[str]) -> Optional[str]:
    """API URL a client can GET to review the photo (None when no photo)."""
    if not rel_path:
        return None
    return f"/attendance/photos/{rel_path}"
