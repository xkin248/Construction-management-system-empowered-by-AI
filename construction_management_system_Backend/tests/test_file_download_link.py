"""Tests for the short-lived signed file download links.

The Flutter client cannot attach ``Authorization`` on two paths (browser download
navigation on Web, ``Image.network`` previews), so ``/files/{id}/download``
answered 401 there. The fix keeps the authenticated endpoint intact and adds:

* ``GET /api/files/{id}/download-link`` (supervisor auth) -> mint a signed URL,
* ``GET /api/files/download?token=...``            -> serve the bytes.

These tests pin the token scope, the expiry, the idempotent behaviour of the
endpoint and the fact that the old authenticated path still works.
"""
import datetime as dt
import os

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from jose import jwt
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.database import Base, get_db, settings
from app.file_tokens import (
    DEFAULT_DOWNLOAD_TOKEN_TTL,
    DOWNLOAD_TOKEN_SCOPE,
    MAX_DOWNLOAD_TOKEN_TTL,
    MIN_DOWNLOAD_TOKEN_TTL,
    clamp_ttl,
    create_download_token,
    decode_download_token,
)
from app.models import File as DBFile, Project, Supervisor, Worker
from app.routers.auth import mk_tok
from app.routers.files import router as files_router


# ── fixtures ────────────────────────────────────────────────────────────────

@pytest.fixture()
def engine():
    eng = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.create_all(eng)
    yield eng
    Base.metadata.drop_all(eng)
    eng.dispose()


@pytest.fixture()
def session_factory(engine):
    return sessionmaker(autocommit=False, autoflush=False, bind=engine)


@pytest.fixture()
def db(session_factory):
    s = session_factory()
    yield s
    s.close()


@pytest.fixture()
def client(engine, session_factory):
    app = FastAPI(title="test-files")
    app.include_router(files_router, prefix="/api")

    def override_get_db():
        session = session_factory()
        try:
            yield session
        finally:
            session.close()

    app.dependency_overrides[get_db] = override_get_db
    return TestClient(app)


def make_supervisor(db, email="boss@buildsmart.com", name="Boss"):
    s = Supervisor(full_name=name, email=email, password_hash="x", role="site_supervisor")
    db.add(s)
    db.commit()
    db.refresh(s)
    return s


def make_file(db, tmp_path, name="site-plan.pdf", content=b"PDF-BYTES", project_id=None,
              uploaded_by=1):
    path = tmp_path / name
    path.write_bytes(content)
    row = DBFile(
        original_name=name,
        stored_name=name,
        file_path=str(path),
        file_size=len(content),
        mime_type="application/pdf",
        file_category="documents",
        project_id=project_id,
        uploaded_by=uploaded_by,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


def auth(email="boss@buildsmart.com", user_type="supervisor"):
    return {"Authorization": f"Bearer {mk_tok(email, user_type)}"}


# ── token primitives ────────────────────────────────────────────────────────

def test_clamp_ttl_bounds():
    assert clamp_ttl(None) == DEFAULT_DOWNLOAD_TOKEN_TTL
    assert clamp_ttl(1) == MIN_DOWNLOAD_TOKEN_TTL
    assert clamp_ttl(999999) == MAX_DOWNLOAD_TOKEN_TTL
    assert clamp_ttl("abc") == DEFAULT_DOWNLOAD_TOKEN_TTL
    assert clamp_ttl(120) == 120


def test_token_roundtrip_carries_scope_and_file_id():
    token = create_download_token(42, 60)
    assert decode_download_token(token) == 42
    payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
    assert payload["scope"] == DOWNLOAD_TOKEN_SCOPE
    assert payload["file_id"] == 42


def test_token_rejects_foreign_scope():
    """A login JWT must not be replayable as a download token."""
    login_token = mk_tok("boss@buildsmart.com", "supervisor")
    from fastapi import HTTPException
    with pytest.raises(HTTPException) as exc:
        decode_download_token(login_token)
    assert exc.value.status_code == 401


def test_token_rejects_garbage_and_empty():
    from fastapi import HTTPException
    for bad in ("", "not-a-jwt", "a.b.c"):
        with pytest.raises(HTTPException) as exc:
            decode_download_token(bad)
        assert exc.value.status_code == 401


def test_token_rejects_expired():
    from fastapi import HTTPException
    expired = jwt.encode(
        {"scope": DOWNLOAD_TOKEN_SCOPE, "file_id": 7,
         "exp": dt.datetime.utcnow() - dt.timedelta(seconds=5)},
        settings.SECRET_KEY, algorithm=settings.ALGORITHM,
    )
    with pytest.raises(HTTPException) as exc:
        decode_download_token(expired)
    assert exc.value.status_code == 401


# ── endpoints ───────────────────────────────────────────────────────────────

def test_download_link_returns_url_that_serves_bytes(client, db, tmp_path):
    make_supervisor(db)
    row = make_file(db, tmp_path, content=b"REAL-CONTENT")

    resp = client.get(f"/api/files/{row.file_id}/download-link", headers=auth())
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["file_id"] == row.file_id
    assert body["filename"] == "site-plan.pdf"
    assert body["expires_in"] == DEFAULT_DOWNLOAD_TOKEN_TTL
    assert body["path"].startswith("/api/files/download?token=")

    # The signed path is fetched exactly as a browser would: no headers at all.
    plain = TestClient(client.app)
    got = plain.get(f"/api/files/download?token={body['path'].split('token=')[1]}")
    assert got.status_code == 200, got.text
    assert got.content == b"REAL-CONTENT"


def test_download_link_honours_ttl_param(client, db, tmp_path):
    make_supervisor(db)
    row = make_file(db, tmp_path)
    resp = client.get(f"/api/files/{row.file_id}/download-link?ttl=60", headers=auth())
    assert resp.status_code == 200, resp.text
    assert resp.json()["expires_in"] == 60

    # Out-of-range ttl is a 422 from FastAPI validation.
    assert client.get(
        f"/api/files/{row.file_id}/download-link?ttl=5", headers=auth()
    ).status_code == 422


def test_download_link_requires_login(client, db, tmp_path):
    """Minting a link needs the same auth as downloading: no privilege widening."""
    row = make_file(db, tmp_path)
    db.add(Worker(name="Ali", trade="electrician", email="ali@site.com",
                  password_hash="x", role="worker"))
    db.commit()

    assert client.get(f"/api/files/{row.file_id}/download-link").status_code == 401
    # A logged-in worker keeps the access it already had on /download.
    assert client.get(
        f"/api/files/{row.file_id}/download-link", headers=auth("ali@site.com", "worker")
    ).status_code == 200


def test_download_link_missing_file(client, db):
    make_supervisor(db)
    assert client.get("/api/files/999999/download-link", headers=auth()).status_code == 404


def test_token_download_unknown_file_is_401(client, db):
    token = create_download_token(999999, 60)
    resp = client.get(f"/api/files/download?token={token}")
    # Signature is valid but the row is gone: 404 keeps the link debuggable.
    assert resp.status_code == 404


def test_token_download_requires_token_param(client, db):
    assert client.get("/api/files/download").status_code == 422


def test_authenticated_download_still_works(client, db, tmp_path):
    """The original Bearer endpoint is preserved for header-capable clients."""
    make_supervisor(db)
    row = make_file(db, tmp_path, content=b"HEADER-PATH")
    ok = client.get(f"/api/files/{row.file_id}/download", headers=auth())
    assert ok.status_code == 200
    assert ok.content == b"HEADER-PATH"
    assert client.get(f"/api/files/{row.file_id}/download").status_code == 401


def test_download_link_scoped_to_one_file(client, db, tmp_path):
    """A token minted for file A must not download file B."""
    make_supervisor(db)
    a = make_file(db, tmp_path, name="a.pdf", content=b"A")
    b = make_file(db, tmp_path, name="b.pdf", content=b"B")

    token_a = client.get(f"/api/files/{a.file_id}/download-link", headers=auth()).json()["path"]
    token_a = token_a.split("token=")[1]
    got = client.get(f"/api/files/download?token={token_a}")
    assert got.status_code == 200
    assert got.content == b"A"  # never B, the token only encodes a.file_id
    assert decode_download_token(token_a) == a.file_id
    assert b.file_id != a.file_id
