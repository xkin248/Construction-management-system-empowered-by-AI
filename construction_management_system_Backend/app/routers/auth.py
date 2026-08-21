from fastapi import APIRouter, Depends, HTTPException, status, Request
from fastapi.security import OAuth2PasswordRequestForm, OAuth2PasswordBearer
from sqlalchemy.orm import Session
from jose import jwt
from datetime import datetime, timedelta
import hashlib

try:
    from passlib.context import CryptContext
    pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto", bcrypt__rounds=4)
    _BC = True
except Exception:
    _BC = False
    class _F:
        def hash(self, r): return "sha256$"+hashlib.sha256(r.encode()).hexdigest()
        def verify(self, r, h): return h.startswith("sha256$") and h=="sha256$"+hashlib.sha256(r.encode()).hexdigest()
    pwd_context = _F()

from app.database import get_db, settings
from app.models import Supervisor, Worker
from app.schemas import (
    SupervisorCreate, SupervisorOut,
    WorkerAuthCreate, WorkerAuthOut,
    CurrentUser,
)

router = APIRouter(prefix="/auth", tags=["🔐 Auth"])
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login", auto_error=False)

# ────────────────── Password Helpers ──────────────────
def hpw(r):
    if not _BC: return pwd_context.hash(r)
    try: return pwd_context.hash(r)
    except: return "sha256$"+hashlib.sha256(r.encode()).hexdigest()
def vpw(r, h):
    try:
        if h.startswith("sha256$"): return h=="sha256$"+hashlib.sha256(r.encode()).hexdigest()
        return pwd_context.verify(r, h)
    except: return False
def mk_tok(sub, user_type, m=None):
    exp = datetime.utcnow()+timedelta(minutes=m or settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    return jwt.encode(
        {"sub": sub, "user_type": user_type, "exp": exp},
        settings.SECRET_KEY, algorithm=settings.ALGORITHM,
    )

# ────────────────── Role Configuration ──────────────────
REGISTER_ALLOWED_ROLES = {"worker"}
LOGIN_ALLOWED_ROLES = {"worker", "site_supervisor"}

# ────────────────── Unified Current User Dependency ──────────────────
def cu(t=Depends(oauth2_scheme), db=Depends(get_db)) -> CurrentUser:
    if not t:
        raise HTTPException(401, "Please log in first")
    try:
        payload = jwt.decode(t, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        email = payload.get("sub")
        user_type = payload.get("user_type", "supervisor")
    except Exception:
        raise HTTPException(401, "Login session has expired")
    if not email:
        raise HTTPException(401, "Login session has expired")

    if user_type == "worker":
        u = db.query(Worker).filter(Worker.email == email).first()
        if not u:
            raise HTTPException(401, "Worker account does not exist")
        if (u.role or "worker") not in LOGIN_ALLOWED_ROLES:
            raise HTTPException(403, "This role is not allowed to log in")
        return CurrentUser(
            user_type="worker",
            id=u.worker_id,
            email=u.email or "",
            name=u.name,
            role=u.role or "worker",
            phone=u.phone,
            worker_id=u.worker_id,
        )
    else:
        u = db.query(Supervisor).filter(Supervisor.email == email).first()
        if not u:
            raise HTTPException(401, "User does not exist")
        if (u.role or "site_supervisor") not in LOGIN_ALLOWED_ROLES:
            raise HTTPException(403, "This role is not allowed to log in")
        return CurrentUser(
            user_type="supervisor",
            id=u.supervisor_id,
            email=u.email,
            name=u.full_name,
            role=u.role or "site_supervisor",
            phone=u.phone,
            supervisor_id=u.supervisor_id,
        )

# ────────────────── Role-Based Permission Dependencies ──────────────────
def require_worker(user: CurrentUser = Depends(cu)) -> CurrentUser:
    if user.role != "worker":
        raise HTTPException(403, "This feature is only available to Worker accounts")
    return user

def require_site_supervisor(user: CurrentUser = Depends(cu)) -> CurrentUser:
    if user.role != "site_supervisor":
        raise HTTPException(403, "This feature is only available to Site Supervisor accounts")
    return user

def require_any_authorized(user: CurrentUser = Depends(cu)) -> CurrentUser:
    if user.role not in LOGIN_ALLOWED_ROLES:
        raise HTTPException(403, "Unauthorized role")
    return user

async def get_current_user_ws(token: str, db: Session):
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        email = payload.get("sub")
        user_type = payload.get("user_type", "supervisor")
    except Exception:
        raise HTTPException(status_code=401, detail="Login session has expired")

    if user_type == "worker":
        u = db.query(Worker).filter(Worker.email == email).first()
        if not u:
            raise HTTPException(status_code=401, detail="Worker account does not exist")
        return CurrentUser(
            user_type="worker", id=u.worker_id, email=u.email or "",
            name=u.name, role=u.role or "worker", phone=u.phone,
        )
    else:
        u = db.query(Supervisor).filter(Supervisor.email == email).first()
        if not u:
            raise HTTPException(status_code=401, detail="User does not exist")
        return CurrentUser(
            user_type="supervisor", id=u.supervisor_id, email=u.email,
            name=u.full_name, role=u.role or "site_supervisor", phone=u.phone,
        )

# ────────────────── Worker ONLY Registration ──────────────────
@router.post("/register/worker", response_model=WorkerAuthOut)
def register_worker(d: WorkerAuthCreate, db=Depends(get_db)):
    """Register a new Worker account. This endpoint is ONLY for the 'worker' role.
    Site supervisors or other roles CANNOT register via this endpoint."""
    try:
        role_normalized = (d.role or "worker").strip().lower()
        if role_normalized not in REGISTER_ALLOWED_ROLES:
            raise HTTPException(
                403,
                f"Registration is only available for the 'worker' role. "
                f"Role '{role_normalized}' cannot be registered via this API.",
            )
        d.role = role_normalized

        email_lower = d.email.strip().lower()
        if db.query(Worker).filter(Worker.email == email_lower).first():
            raise HTTPException(400, "This email is already registered as a worker")
        if db.query(Supervisor).filter(Supervisor.email == email_lower).first():
            raise HTTPException(400, "This email is already registered as a supervisor")

        # Auto-assign project: keep the provided one if bound at registration,
        # otherwise fall back to the first available project.
        project_id = d.project_id
        if project_id is None:
            first_p = db.query(Project).order_by(Project.project_id.asc()).first()
            project_id = first_p.project_id if first_p else None

        w = Worker(
            name=d.name.strip(),
            email=email_lower,
            password_hash=hpw(d.password),
            phone=d.phone,
            ic_number=d.ic_number,
            trade=d.trade,
            project_id=project_id,
            role=d.role,
            has_safety_training=False,
            is_safety_officer=False,
        )
        db.add(w)
        db.commit()
        db.refresh(w)
        return w
    except HTTPException:
        raise
    except Exception as ex:
        db.rollback()
        raise HTTPException(500, f"Worker registration failed: {ex}")

# ────────────────── Legacy /register endpoint ──────────────────
@router.post("/register", response_model=SupervisorOut)
def reg(d: SupervisorCreate, db=Depends(get_db)):
    """Legacy registration endpoint — now BLOCKED for all roles.
    Only the /auth/register/worker endpoint allows registration (worker only)."""
    role_normalized = (d.role or "site_supervisor").strip().lower()
    raise HTTPException(
        403,
        f"Direct registration is disabled for role '{role_normalized}'. "
        f"Registration is only available for the 'worker' role via /auth/register/worker. "
        f"Site supervisors must be invited by an admin.",
    )

# ────────────────── Unified Login (Worker + Site Supervisor) ──────────────────
@router.post("/login")
def login(f: OAuth2PasswordRequestForm=Depends(), db=Depends(get_db)):
    """Login endpoint — ONLY allows 'worker' and 'site_supervisor' roles.
    Other roles are rejected. The system auto-detects the account type."""
    try:
        e = f.username.strip().lower()

        sup = db.query(Supervisor).filter(Supervisor.email == e).first()
        wrk = db.query(Worker).filter(Worker.email == e).first()

        user_obj = None
        user_type = None

        if sup and vpw(f.password, sup.password_hash):
            user_obj = sup
            user_type = "supervisor"
        elif wrk and wrk.password_hash and vpw(f.password, wrk.password_hash):
            user_obj = wrk
            user_type = "worker"

        if not user_obj:
            raise HTTPException(401, "Incorrect email or password")

        role = (user_obj.role or ("site_supervisor" if user_type == "supervisor" else "worker")).strip().lower()

        if role not in LOGIN_ALLOWED_ROLES:
            raise HTTPException(
                403,
                f"Role '{role}' is not allowed to log in. "
                f"Only 'worker' and 'site_supervisor' can access the system.",
            )

        token = mk_tok(e, user_type)

        if user_type == "supervisor":
            return {
                "access_token": token,
                "token_type": "bearer",
                "expires_in": settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
                "user_type": "supervisor",
                "user": {
                    "supervisor_id": user_obj.supervisor_id,
                    "id": user_obj.supervisor_id,
                    "full_name": user_obj.full_name,
                    "name": user_obj.full_name,
                    "email": user_obj.email,
                    "phone": user_obj.phone,
                    "role": role,
                },
            }
        else:
            return {
                "access_token": token,
                "token_type": "bearer",
                "expires_in": settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
                "user_type": "worker",
                "user": {
                    "worker_id": user_obj.worker_id,
                    "id": user_obj.worker_id,
                    "name": user_obj.name,
                    "full_name": user_obj.name,
                    "email": user_obj.email,
                    "phone": user_obj.phone,
                    "role": role,
                    "trade": user_obj.trade,
                    "ic_number": user_obj.ic_number,
                    "project_id": user_obj.project_id,
                },
            }
    except HTTPException:
        raise
    except Exception as ex:
        raise HTTPException(500, f"Login failed: {ex}")

# ────────────────── /me — returns profile for any authorized user ──────────────────
@router.get("/me")
def me(user: CurrentUser = Depends(cu)):
    return {
        "user_type": user.user_type,
        "id": user.id,
        "name": user.name,
        "full_name": user.name,
        "email": user.email,
        "phone": user.phone,
        "role": user.role,
        "supervisor_id": user.id if user.user_type == "supervisor" else None,
        "worker_id": user.id if user.user_type == "worker" else None,
    }
