"""Short-lived signed links for downloading uploaded files.

Background: ``GET /api/files/{id}/download`` requires a Bearer token. Two client
paths cannot attach that header:

* ``Image.network`` previews in Flutter (no header injection point), and
* the browser's own download navigation on Flutter Web (``dart:html`` anchor /
  ``window.open``), which ignores Dio interceptors entirely.

Instead of plumbing headers through every platform, the backend mints a
*scoped* token that embeds only ``file_id`` plus a short expiry, and the client
trades it for a plain URL. The token is signed with the same SECRET_KEY as the
login JWT, so it cannot be forged, and because ``scope`` must equal
``file_download`` a leaked link cannot be replayed as a session token (and a
session token cannot be used as a download link).
"""
from datetime import datetime, timedelta
from typing import Optional

from fastapi import HTTPException
from jose import jwt

from app.database import settings

# Scope marker so a download token can never be mistaken for a login token.
DOWNLOAD_TOKEN_SCOPE = "file_download"

# 5 minutes: long enough for an image preview request or a browser download
# navigation to start, short enough that a link copied out of a log dies fast.
DEFAULT_DOWNLOAD_TOKEN_TTL = 300
MIN_DOWNLOAD_TOKEN_TTL = 30
MAX_DOWNLOAD_TOKEN_TTL = 3600


def clamp_ttl(ttl_seconds: Optional[int]) -> int:
    """Clamp a client-provided TTL into the safe window."""
    if ttl_seconds is None:
        return DEFAULT_DOWNLOAD_TOKEN_TTL
    try:
        value = int(ttl_seconds)
    except (TypeError, ValueError):
        return DEFAULT_DOWNLOAD_TOKEN_TTL
    return max(MIN_DOWNLOAD_TOKEN_TTL, min(MAX_DOWNLOAD_TOKEN_TTL, value))


def create_download_token(file_id: int, ttl_seconds: Optional[int] = None) -> str:
    """Return a signed, file-scoped token valid for ``ttl_seconds``."""
    ttl = clamp_ttl(ttl_seconds)
    payload = {
        "scope": DOWNLOAD_TOKEN_SCOPE,
        "file_id": int(file_id),
        "exp": datetime.utcnow() + timedelta(seconds=ttl),
    }
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def decode_download_token(token: str) -> int:
    """Validate a signed download token and return its ``file_id``.

    Raises 401 for a bad signature, an expired token, a missing scope marker, or
    a token that is not file-scoped. The HTTP status is deliberately uniform so
    the response cannot be used to probe whether a file exists.
    """
    invalid = HTTPException(401, "Download link is invalid or has expired")
    if not token:
        raise invalid
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
    except Exception:
        raise invalid

    if payload.get("scope") != DOWNLOAD_TOKEN_SCOPE:
        raise invalid
    file_id = payload.get("file_id")
    try:
        file_id = int(file_id)
    except (TypeError, ValueError):
        raise invalid
    return file_id
