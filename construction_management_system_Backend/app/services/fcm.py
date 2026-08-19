"""FCM push notification service (Firebase Admin SDK, free tier).

Credential resolution order:
  1. ``FIREBASE_SERVICE_ACCOUNT_JSON`` env var — raw JSON content of the
     service account file (preferred on Render / cloud deploys).
  2. ``FIREBASE_SERVICE_ACCOUNT_FILE`` env var — explicit path to the JSON file.
  3. Local file ``<repo_root>/construction_management_system_Flutter/firebase-service-account.json``
     (dev machine, file is gitignored).
  4. Nothing found → FCM stays disabled and ``send_to_device`` returns False
     without raising; the caller simply falls back to database-only logging.

Every public function is defensive: any exception (missing credentials, invalid
token, network error) is swallowed so push failures never break the main flow.
"""
import json
import os
from pathlib import Path
from typing import Any, Dict, Optional

_APP = None
_AVAILABLE: Optional[bool] = None

# <repo_root>/construction_management_system_Flutter/firebase-service-account.json
# services -> app -> Backend -> repo root
_REPO_ROOT = Path(__file__).resolve().parents[3]
_LOCAL_CRED_FILE = _REPO_ROOT / "construction_management_system_Flutter" / "firebase-service-account.json"


def _locate_credentials() -> Optional[str]:
    """Return the service-account JSON as a string, or None when unavailable."""
    env_content = os.environ.get("FIREBASE_SERVICE_ACCOUNT_JSON")
    if env_content and env_content.strip():
        return env_content

    env_path = os.environ.get("FIREBASE_SERVICE_ACCOUNT_FILE")
    if env_path and Path(env_path).exists():
        return str(Path(env_path).resolve())

    if _LOCAL_CRED_FILE.exists():
        return str(_LOCAL_CRED_FILE)

    return None


def init_firebase() -> bool:
    """Initialize the Firebase Admin app once. Safe to call repeatedly."""
    global _APP, _AVAILABLE
    if _AVAILABLE is not None:
        return _AVAILABLE

    cred_source = _locate_credentials()
    if not cred_source:
        _AVAILABLE = False
        return False

    try:
        import firebase_admin
        from firebase_admin import credentials

        if not firebase_admin._apps:
            try:
                # cred_source may be raw JSON content or a file path.
                cred = credentials.Certificate(json.loads(cred_source))
            except json.JSONDecodeError:
                cred = credentials.Certificate(cred_source)
            _APP = firebase_admin.initialize_app(cred)
        else:
            _APP = list(firebase_admin._apps.values())[0]
        _AVAILABLE = True
    except Exception:
        _AVAILABLE = False
    return _AVAILABLE


def send_to_device(token: str, title: str, body: str, data: Optional[Dict[str, Any]] = None) -> bool:
    """Send one FCM push to a single device token.

    Returns True when the message was accepted by Firebase; False on any error
    (missing token / credentials / invalid token / network). Never raises.
    """
    if not token or not token.strip():
        return False
    if not init_firebase():
        return False

    try:
        from firebase_admin import messaging

        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in (data or {}).items()},
            token=token.strip(),
        )
        messaging.send(message)
        return True
    except Exception:
        return False


def is_available() -> bool:
    """Whether FCM is initialized (and usable) in this process."""
    if _AVAILABLE is None:
        init_firebase()
    return bool(_AVAILABLE)
