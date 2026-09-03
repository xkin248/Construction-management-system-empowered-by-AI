"""Shared pytest fixtures for the BuildSmart backend test suite.

Every fixture uses an in-memory SQLite database (StaticPool) and overrides the
FastAPI dependency (app.database.get_db). The production engine is never
connected: the real app entrypoint (app.main) is NOT imported here because its
module-level Base.metadata.create_all(bind=engine) would hit the Supabase
DATABASE_URL configured in .env.
"""
import os
import sys

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

# Make the backend root importable (repo root is one level above tests/).
BACKEND_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if BACKEND_ROOT not in sys.path:
    sys.path.insert(0, BACKEND_ROOT)

from app.database import Base, get_db  # noqa: E402
from app import models  # noqa: E402,F401  (registers every table on Base)

from app.routers.projects import router as projects_router  # noqa: E402
from app.routers.ai_task import router as ai_task_router  # noqa: E402
from app.routers.ai import router as ai_router  # noqa: E402


@pytest.fixture()
def engine():
    """Function-scoped in-memory SQLite engine -> isolated DB per test."""
    eng = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(eng)
    yield eng
    Base.metadata.drop_all(eng)
    eng.dispose()


@pytest.fixture()
def session_factory(engine):
    return sessionmaker(autocommit=False, autoflush=False, bind=engine)


@pytest.fixture()
def db(session_factory):
    """Direct SQLAlchemy session for seeding / asserting (same engine as client)."""
    session = session_factory()
    yield session
    session.close()


@pytest.fixture()
def client(engine, session_factory):
    """TestClient whose get_db dependency is overridden to the in-memory DB."""
    app = FastAPI(title="test")
    app.include_router(projects_router, prefix="/api")
    app.include_router(ai_task_router, prefix="/api")
    app.include_router(ai_router, prefix="/api")

    def override_get_db():
        session = session_factory()
        try:
            yield session
        finally:
            session.close()

    app.dependency_overrides[get_db] = override_get_db
    return TestClient(app)
