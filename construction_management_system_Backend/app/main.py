from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
import logging
import os

from app.database import engine, Base, SessionLocal, settings
from app import models
from app.db_migrate import (
    ensure_settings_columns, ensure_fcm_columns, ensure_attendance_columns,
    ensure_task_timestamp_columns, ensure_task_progress_columns,
    ensure_ai_decision_log_table, ensure_ai_decision_log_indexes,
    ensure_task_progress_log_audit_columns,
)

logger = logging.getLogger("buildsmart.startup")

# Database bootstrap runs at import time, i.e. BEFORE uvicorn binds the port.
# It must never abort the process: when the database is unreachable the raised
# OperationalError would kill the import, uvicorn would exit with status 1 and
# the platform (Render) would report "Deploy failed" / never pass the port
# scan. Keep the API booting instead and surface the state on /health.
DB_READY = False
DB_BOOTSTRAP_ERROR = ""


def _bootstrap_database() -> None:
    """Create tables / run light migrations / seed settings, without crashing boot."""
    global DB_READY, DB_BOOTSTRAP_ERROR
    try:
        Base.metadata.create_all(bind=engine)
        # Existing SQLite databases don't get new columns via create_all — patch them.
        ensure_settings_columns(engine)
        ensure_fcm_columns(engine)
        ensure_attendance_columns(engine)
        ensure_task_timestamp_columns(engine)
        ensure_task_progress_columns(engine)
        ensure_ai_decision_log_table(engine)
        # Composite (project_id, created_at, stage) index for decision-log analytics.
        ensure_ai_decision_log_indexes(engine)
        # Reopen audit columns (who / when / from -> to / why).
        ensure_task_progress_log_audit_columns(engine)
        # Ensure the single-row settings table exists with default values on startup.
        with SessionLocal() as db:
            if db.query(models.Settings).count() == 0:
                db.add(models.Settings(id=1))
                db.commit()
        DB_READY = True
        DB_BOOTSTRAP_ERROR = ""
        logger.info("Database bootstrap completed.")
    except Exception as exc:  # startup must not crash the whole service
        DB_READY = False
        DB_BOOTSTRAP_ERROR = f"{type(exc).__name__}: {exc}".splitlines()[0]
        logger.error(
            "Database bootstrap FAILED - the API will boot but data endpoints "
            "cannot work. Check that DATABASE_URL points to a reachable, "
            "existing database. Cause: %s", DB_BOOTSTRAP_ERROR,
        )


_bootstrap_database()

# Semantic-model self-check. The joblib artefacts are scikit-learn pickles, and a
# version skew used to be swallowed at request time (silent fallback to keyword
# rules). Loading them once at boot turns "the classifier never actually ran" into
# an explicit startup log line, and /health keeps reporting the outcome.
try:
    from app import ai_service as _ai_service
    _ai_service.log_model_status()
except Exception as _exc:  # never block boot on the model check
    logger.error(
        "Semantic model self-check FAILED: %s",
        f"{type(_exc).__name__}: {_exc}".splitlines()[0],
    )

app = FastAPI(title="Construction Management System API", version="1.0.0")
app.add_middleware(
    CORSMiddleware, allow_origins=["*"], allow_credentials=True,
    allow_methods=["*"], allow_headers=["*"],
)


@app.on_event("startup")
def _start_background_sweeper():
    """Kick off the time-driven notification sweeps (task overdue / daily
    report reminder). Disable with ENABLE_NOTIFY_SCHEDULER=0."""
    try:
        from app.scheduler import start_scheduler

        start_scheduler()
    except Exception as exc:  # never block boot on the sweeper
        logger.error(
            "notification scheduler failed to start: %s",
            f"{type(exc).__name__}: {exc}".splitlines()[0],
        )


@app.on_event("shutdown")
def _stop_background_sweeper():
    try:
        from app.scheduler import stop_scheduler

        stop_scheduler()
    except Exception:
        pass

# ✅ Mount backend static HTML → accessible at /html/index.html
_STATIC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "static_html")
os.makedirs(_STATIC, exist_ok=True)
app.mount("/html", StaticFiles(directory=_STATIC, html=True), name="static_html")

@app.get("/")
def root():
    return {
        "status": "✅ BuildSmart API is running",
        "version": "1.0.0",
        "docs": "/docs",
    }

@app.get("/health")
def health():
    # Expose the semantic-model state: a silently degraded classifier (missing or
    # version-skewed artefact) is otherwise indistinguishable from a healthy API.
    try:
        models = _ai_service.model_status()
    except Exception as exc:  # health must still answer
        models = {"all_loaded": False, "error": f"{type(exc).__name__}: {exc}"}
    return {
        "status": "ok",
        "database": "ok" if DB_READY else "unavailable",
        "database_error": DB_BOOTSTRAP_ERROR or None,
        "models": models,
        "models_ok": bool(models.get("all_loaded"))
        and not models.get("version_mismatch"),
    }

# ✅ Register routers
from app.routers.auth import router as ar;       app.include_router(ar, prefix="/api")
from app.routers.projects import router as pr;   app.include_router(pr, prefix="/api")
from app.routers.attendance import router as atr;app.include_router(atr, prefix="/api")
from app.routers.reports import router as rr;    app.include_router(rr, prefix="/api")
from app.routers.ai_task import router as air;   app.include_router(air, prefix="/api")
from app.routers.workers import router as wr;    app.include_router(wr, prefix="/api")
from app.routers.issues import router as isr;    app.include_router(isr, prefix="/api")
from app.routers.settings_router import router as ser; app.include_router(ser, prefix="/api")
from app.routers.safety import router as sr; app.include_router(sr, prefix="/api")
from app.routers.files import router as fr; app.include_router(fr, prefix="/api")
from app.routers.ai import router as ai_r; app.include_router(ai_r, prefix="/api")
from app.routers.notifications import router as notif_r; app.include_router(notif_r, prefix="/api")
