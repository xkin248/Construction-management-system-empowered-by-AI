"""Unified object storage for evidence photos (Supabase Storage + local fallback).

Both the attendance selfie and the task-completion photo go through this module
so the two flows share one contract:

* the database only ever stores a **relative object key** (``attendance/...``,
  ``task_completion/...``). Image bytes and public URLs are never persisted, so
  rotating a signed link or switching backend needs no data migration;
* when ``SUPABASE_URL`` and ``SUPABASE_SECRET_KEY`` are present the object is
  uploaded to the private bucket named by ``SUPABASE_STORAGE_BUCKET`` and reads
  are served as short-lived signed URLs;
* when the environment is incomplete — or a single upload fails — the same key
  is written under ``uploads/`` on local disk. That directory is also where rows
  created before the switch already live, so a half-configured deployment or a
  half-migrated bucket degrades to "readable" instead of "lost".

Only the standard library is used (``urllib.request``) on purpose: pushing image
bytes over the Supabase Storage REST API does not justify a new runtime
dependency that production would then have to keep patched.

The bucket must stay private. Reads are authorised by the caller (the existing
``/attendance/photos/...`` and ``/tasks/{id}/completion-photo`` endpoints) and
only then handed a short-lived signed URL; no object is ever publicly readable.
"""

import json
import logging
import os
import urllib.error
import urllib.parse
import urllib.request
from typing import Dict, Optional, Tuple

from app.file_service import UPLOAD_DIR

# Configuration is read from the process environment. ``app.database`` already
# calls ``load_dotenv()`` during startup, but this module must also work when it
# is imported on its own (scripts, tests, workers), so it loads the backend's
# .env itself. ``override=False`` keeps real deployment variables authoritative.
try:  # pragma: no cover - depends on the presence of python-dotenv
    from dotenv import load_dotenv

    _BACKEND_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    load_dotenv(os.path.join(_BACKEND_ROOT, ".env"), override=False)
except Exception:  # python-dotenv missing is not fatal: env vars still work
    pass

logger = logging.getLogger(__name__)

# Bucket name used when SUPABASE_STORAGE_BUCKET is not set. It matches the
# bucket created for this project in the Supabase dashboard.
DEFAULT_BUCKET = "buildsmart-photos"

# Signed links are short-lived: the client fetches the image immediately after
# the authorised endpoint redirects to it.
DEFAULT_SIGNED_URL_TTL = 600

_UPLOAD_TIMEOUT = 20.0
_READ_TIMEOUT = 20.0
_SIGN_TIMEOUT = 10.0
_PROBE_TIMEOUT = 8.0

_EXT_CONTENT_TYPES = {
    "jpg": "image/jpeg",
    "jpeg": "image/jpeg",
    "png": "image/png",
}


class StorageError(RuntimeError):
    """Raised when an object key is invalid or the object cannot be found."""


# --------------------------------------------------------------------------- #
# Configuration
# --------------------------------------------------------------------------- #
def _env(name: str) -> str:
    return (os.environ.get(name) or "").strip()


def supabase_url() -> str:
    """Base project URL without the trailing slash ('' when unconfigured)."""
    return _env("SUPABASE_URL").rstrip("/")


def supabase_secret() -> str:
    """Service-role / secret key. Never logged, never returned to clients."""
    return _env("SUPABASE_SECRET_KEY")


def bucket_name() -> str:
    """Target bucket, defaulting to the project bucket."""
    return _env("SUPABASE_STORAGE_BUCKET") or DEFAULT_BUCKET


def remote_enabled() -> bool:
    """True when Supabase is configured and local mode was not requested.

    ``STORAGE_BACKEND=local`` is deliberately an explicit opt-out for local
    development, device tests and offline demos.  It prevents a checked-in
    ``.env`` from sending test selfies to the real bucket while preserving the
    existing production default (Supabase when its credentials are present).
    """
    if _env("STORAGE_BACKEND").lower() == "local":
        return False
    return bool(supabase_url() and supabase_secret())


def backend_name() -> str:
    """Where new objects are written: ``supabase`` or ``local``."""
    return "supabase" if remote_enabled() else "local"


def status() -> Dict[str, object]:
    """Non-sensitive description of the storage configuration (for /health)."""
    configured = remote_enabled()
    return {
        "backend": backend_name(),
        "bucket": bucket_name() if configured else None,
        "project_host": urllib.parse.urlsplit(supabase_url()).hostname if configured else None,
        "local_root": os.path.abspath(UPLOAD_DIR),
        "signed_url_ttl_seconds": DEFAULT_SIGNED_URL_TTL,
    }


def content_type_for(key: str) -> str:
    """Content type inferred from the extension of an object key."""
    name = (key or "").replace("\\", "/").rsplit("/", 1)[-1]
    ext = name.rsplit(".", 1)[-1].lower() if "." in name else ""
    return _EXT_CONTENT_TYPES.get(ext, "application/octet-stream")


# --------------------------------------------------------------------------- #
# Object keys and local paths
# --------------------------------------------------------------------------- #
def normalise_key(key: str) -> str:
    """Validate an object key and return it in canonical form.

    Keys come from the database *and* from URL path segments, so the traversal
    guard is mandatory: an absolute path, an empty segment or ``..`` is refused
    rather than resolved.
    """
    cleaned = (key or "").replace("\\", "/").strip("/")
    parts = cleaned.split("/")
    if not cleaned or any(part in ("", ".", "..") for part in parts):
        raise StorageError("Invalid object key")
    if os.path.isabs(cleaned) or ":" in parts[0]:
        raise StorageError("Invalid object key")
    return cleaned


def local_abs_path(key: str, *, root_subdir: Optional[str] = None) -> str:
    """Absolute path this key occupies on local disk.

    ``root_subdir`` restricts the result to one sub-tree of ``uploads/`` (used by
    the attendance and task-photo modules, which must never resolve each other's
    files even if a database value was tampered with).
    """
    cleaned = normalise_key(key)
    base = os.path.abspath(UPLOAD_DIR)
    target = os.path.abspath(os.path.join(base, *cleaned.split("/")))
    if not target.startswith(base + os.sep):
        raise StorageError("Invalid object key")
    if root_subdir:
        root = os.path.abspath(os.path.join(base, root_subdir))
        if not target.startswith(root + os.sep):
            raise StorageError("Invalid object key")
    return target


def local_exists(key: str, *, root_subdir: Optional[str] = None) -> bool:
    try:
        return os.path.isfile(local_abs_path(key, root_subdir=root_subdir))
    except StorageError:
        return False


def read_local(key: str, *, root_subdir: Optional[str] = None) -> bytes:
    path = local_abs_path(key, root_subdir=root_subdir)
    with open(path, "rb") as handle:
        return handle.read()


def _write_local(key: str, data: bytes) -> str:
    path = local_abs_path(key)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(data)
    return path


def _delete_local(key: str) -> bool:
    try:
        path = local_abs_path(key)
    except StorageError:
        return False
    try:
        os.remove(path)
        return True
    except OSError:
        return False


# --------------------------------------------------------------------------- #
# Supabase Storage REST helpers
# --------------------------------------------------------------------------- #
def _auth_headers() -> Dict[str, str]:
    key = supabase_secret()
    return {"apikey": key, "Authorization": f"Bearer {key}"}


def _quote_key(key: str) -> str:
    # Slashes stay literal: the object key is a path inside the bucket.
    return urllib.parse.quote(key, safe="/")


def _object_url(key: str) -> str:
    return (
        f"{supabase_url()}/storage/v1/object/"
        f"{urllib.parse.quote(bucket_name())}/{_quote_key(key)}"
    )


def _http(
    method: str,
    url: str,
    *,
    data: Optional[bytes] = None,
    headers: Optional[Dict[str, str]] = None,
    timeout: float = _READ_TIMEOUT,
) -> Tuple[int, bytes]:
    """Perform one request, returning ``(status, body)``.

    HTTP error statuses are returned instead of raised so callers can decide
    whether a 404 is fatal; transport failures raise :class:`StorageError`.
    """
    request = urllib.request.Request(url, data=data, method=method)
    for name, value in (headers or {}).items():
        request.add_header(name, value)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as exc:
        body = b""
        try:
            body = exc.read()
        except Exception:  # noqa: BLE001 - body of an error response is optional
            body = b""
        return exc.code, body
    except urllib.error.URLError as exc:
        raise StorageError(f"Supabase request failed: {exc.reason}") from exc
    except OSError as exc:  # timeouts surface as OSError subclasses
        raise StorageError(f"Supabase request failed: {exc}") from exc


def upload_object(
    key: str, data: bytes, *, content_type: Optional[str] = None
) -> bool:
    """Upload one object. Returns False (never raises) when it cannot upload."""
    if not remote_enabled():
        return False
    cleaned = normalise_key(key)
    headers = _auth_headers()
    headers["Content-Type"] = content_type or content_type_for(cleaned)
    # Object names carry a uuid suffix, so an upsert can only ever overwrite the
    # exact same file; keeping it on makes a retried upload idempotent.
    headers["x-upsert"] = "true"
    headers["cache-control"] = "max-age=3600"
    try:
        status_code, body = _http(
            "POST", _object_url(cleaned), data=data, headers=headers,
            timeout=_UPLOAD_TIMEOUT,
        )
    except StorageError as exc:
        logger.warning("Supabase upload skipped for %s: %s", cleaned, exc)
        return False
    if 200 <= status_code < 300:
        return True
    logger.warning(
        "Supabase upload failed (%s) for %s: %s",
        status_code, cleaned, body[:200],
    )
    return False


def remote_exists(key: str) -> bool:
    """Whether the object exists in the bucket.

    Probes with a one-byte ranged GET: cheap, and correct for both private and
    public buckets without relying on the newer ``/object/info`` route.
    """
    if not remote_enabled():
        return False
    cleaned = normalise_key(key)
    headers = _auth_headers()
    headers["Range"] = "bytes=0-0"
    url = (
        f"{supabase_url()}/storage/v1/object/authenticated/"
        f"{urllib.parse.quote(bucket_name())}/{_quote_key(cleaned)}"
    )
    try:
        status_code, _ = _http(
            "GET", url, headers=headers, timeout=_PROBE_TIMEOUT
        )
    except StorageError as exc:
        logger.warning("Supabase probe failed for %s: %s", cleaned, exc)
        return False
    return 200 <= status_code < 300


def signed_url(
    key: str, *, expires_in: int = DEFAULT_SIGNED_URL_TTL
) -> Optional[str]:
    """Create a short-lived signed download URL, or None when unavailable."""
    if not remote_enabled():
        return None
    cleaned = normalise_key(key)
    url = (
        f"{supabase_url()}/storage/v1/object/sign/"
        f"{urllib.parse.quote(bucket_name())}/{_quote_key(cleaned)}"
    )
    headers = _auth_headers()
    headers["Content-Type"] = "application/json"
    payload = json.dumps({"expiresIn": int(expires_in)}).encode("utf-8")
    try:
        status_code, body = _http(
            "POST", url, data=payload, headers=headers, timeout=_SIGN_TIMEOUT
        )
    except StorageError as exc:
        logger.warning("Supabase sign failed for %s: %s", cleaned, exc)
        return None
    if not 200 <= status_code < 300:
        logger.warning(
            "Supabase sign failed (%s) for %s: %s",
            status_code, cleaned, body[:200],
        )
        return None
    try:
        parsed = json.loads(body or b"{}")
    except (ValueError, TypeError):
        logger.warning("Supabase sign returned unparsable body for %s", cleaned)
        return None
    signed = parsed.get("signedURL") or parsed.get("signedUrl") or ""
    if not signed:
        return None
    if signed.startswith("http://") or signed.startswith("https://"):
        return signed
    if signed.startswith("/storage/v1"):
        return f"{supabase_url()}{signed}"
    return f"{supabase_url()}/storage/v1{signed}"


def read_remote(key: str) -> bytes:
    """Download one object through the authenticated object route."""
    if not remote_enabled():
        raise StorageError("Remote storage is not configured")
    cleaned = normalise_key(key)
    url = (
        f"{supabase_url()}/storage/v1/object/authenticated/"
        f"{urllib.parse.quote(bucket_name())}/{_quote_key(cleaned)}"
    )
    status_code, body = _http("GET", url, headers=_auth_headers())
    if not 200 <= status_code < 300:
        raise StorageError("Object not found")
    return body


# --------------------------------------------------------------------------- #
# Public API used by the photo modules and the routers
# --------------------------------------------------------------------------- #
def save_object(
    key: str, data: bytes, *, content_type: Optional[str] = None
) -> str:
    """Persist one object and return the key to store in the database.

    Supabase is preferred; any upload failure falls back to local disk so a
    check-in or a task completion is never rejected because the bucket is down.
    """
    cleaned = normalise_key(key)
    if remote_enabled():
        try:
            if upload_object(cleaned, data, content_type=content_type):
                return cleaned
        except StorageError as exc:
            logger.warning("Supabase upload errored for %s: %s", cleaned, exc)
        logger.warning("Falling back to local disk for %s", cleaned)
    _write_local(cleaned, data)
    return cleaned


def open_source(
    key: str,
    *,
    root_subdir: Optional[str] = None,
    expires_in: int = DEFAULT_SIGNED_URL_TTL,
) -> Tuple[str, str]:
    """Resolve a key for reading.

    Returns ``("local", absolute_path)`` when a local copy exists — which also
    covers every row written before the switch — otherwise ``("url",
    signed_url)`` for an object living in the bucket. Raises
    :class:`StorageError` when neither holds the object.
    """
    cleaned = normalise_key(key)
    try:
        path = local_abs_path(cleaned, root_subdir=root_subdir)
    except StorageError:
        raise
    if os.path.isfile(path):
        return "local", path
    if remote_enabled() and remote_exists(cleaned):
        url = signed_url(cleaned, expires_in=expires_in)
        if url:
            return "url", url
    raise StorageError("Photo not found")


def read_object(key: str, *, root_subdir: Optional[str] = None) -> bytes:
    """Return the bytes of one object, local copy first, bucket second."""
    cleaned = normalise_key(key)
    if local_exists(cleaned, root_subdir=root_subdir):
        return read_local(cleaned, root_subdir=root_subdir)
    return read_remote(cleaned)


def delete_object(key: str) -> bool:
    """Delete an object from both backends (best effort, never raises)."""
    try:
        cleaned = normalise_key(key)
    except StorageError:
        return False
    removed = _delete_local(cleaned)
    if remote_enabled():
        try:
            status_code, _ = _http(
                "DELETE", _object_url(cleaned), headers=_auth_headers(),
                timeout=_SIGN_TIMEOUT,
            )
            if 200 <= status_code < 300 or status_code == 404:
                removed = removed or 200 <= status_code < 300
        except StorageError as exc:
            logger.warning("Supabase delete failed for %s: %s", cleaned, exc)
    return removed
