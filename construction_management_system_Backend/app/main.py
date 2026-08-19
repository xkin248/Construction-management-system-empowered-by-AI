from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
import os

from app.database import engine, Base, SessionLocal, settings
from app import models
from app.db_migrate import ensure_settings_columns
Base.metadata.create_all(bind=engine)
# Existing SQLite databases don't get new columns via create_all — patch them.
ensure_settings_columns(engine)
# Ensure the single-row settings table exists with default values on startup.
with SessionLocal() as db:
    if db.query(models.Settings).count() == 0:
        db.add(models.Settings(id=1))
        db.commit()

app = FastAPI(title="Construction Management System API", version="1.0.0")
app.add_middleware(
    CORSMiddleware, allow_origins=["*"], allow_credentials=True,
    allow_methods=["*"], allow_headers=["*"],
)

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
    return {"status": "ok"}

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
