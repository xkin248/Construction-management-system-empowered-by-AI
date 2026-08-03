from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from pydantic_settings import BaseSettings
from dotenv import load_dotenv
import os

try: load_dotenv()
except Exception: pass

class Settings(BaseSettings):
    DATABASE_URL: str = os.getenv("DATABASE_URL", "sqlite:///./construction_management.db")
    SECRET_KEY: str = os.getenv("SECRET_KEY", "fyp-construction-2026-final-key")
    ALGORITHM: str = os.getenv("ALGORITHM", "HS256")
    ACCESS_TOKEN_EXPIRE_MINUTES: int = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "10080"))
    # GPS geofence rules
    FENCE_LEAVE_TOLERANCE_MIN: int = 10  # Auto-cancel check-in if outside the fence for more than 10 minutes
    HEARTBEAT_INTERVAL_MIN: int = 15     # Frontend location report interval
    class Config: env_file = ".env"; extra = "ignore"

settings = Settings()
connect_args = {"check_same_thread": False} if settings.DATABASE_URL.startswith("sqlite") else {}
engine = create_engine(settings.DATABASE_URL, connect_args=connect_args, pool_pre_ping=True)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

def get_db():
    db = SessionLocal()
    try: yield db
    finally: db.close()