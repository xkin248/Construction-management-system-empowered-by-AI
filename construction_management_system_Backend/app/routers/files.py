from fastapi import APIRouter, Depends, HTTPException, Query, Request, UploadFile
from fastapi.responses import FileResponse, RedirectResponse
from sqlalchemy.orm import Session, joinedload
from typing import List, Optional
from urllib.parse import quote
import os

from app.database import get_db
from app.models import File as DBFile, Project, Supervisor
from app.schemas import FileOut, FileUpdate
from app.file_service import (
    save_upload_file, create_thumbnail, delete_file,
    UPLOAD_DIR, THUMBNAIL_DIR
)
from app.file_tokens import clamp_ttl, create_download_token, decode_download_token
from app.routers.auth import cu
from app import storage_service
from app.storage_service import StorageError

router = APIRouter(tags=["📁 File Management"])

# Documents must not share the evidence-photo bucket: that bucket can safely
# restrict uploads to images, while project documents need PDFs, office files
# and text checklists. The bucket is private; reads still use signed URLs.
FILE_STORAGE_BUCKET = os.getenv("SUPABASE_FILE_BUCKET", "buildsmart-files")

def _storage_keys(file: DBFile) -> list[str]:
    """Return compatible bucket keys for a legacy or current file record."""
    raw = (file.file_path or "").replace("\\", "/").lstrip("./")
    keys = [raw]
    if raw.startswith("uploads/"):
        keys.append(raw[len("uploads/"):])
    return [key for index, key in enumerate(keys) if key and key not in keys[:index]]


def _file_source(file: DBFile) -> tuple[str, str]:
    """Resolve a file from the local development disk or Supabase Storage."""
    if file.file_path and os.path.isfile(file.file_path):
        return "local", file.file_path
    for key in _storage_keys(file):
        try:
            return storage_service.open_source(key, bucket=FILE_STORAGE_BUCKET)
        except StorageError:
            continue
    raise HTTPException(status_code=404, detail="File content is unavailable")


def _file_response(file: DBFile):
    source_type, source = _file_source(file)
    if source_type == "local":
        return FileResponse(
            path=source,
            filename=file.original_name,
            media_type=file.mime_type,
        )
    # The signed Supabase URL is short-lived. Redirecting prevents Render's
    # ephemeral process from proxying large documents and supports previews.
    return RedirectResponse(url=source, status_code=307)


@router.post("/files/upload", response_model=FileOut)
async def upload_file(
    file: UploadFile,
    file_category: str = "attachment",
    project_id: Optional[int] = None,
    db: Session = Depends(get_db),
    current_user: Supervisor = Depends(cu)
):
    file_path, stored_name, file_size, mime_type = await save_upload_file(file)
    thumbnail_path = create_thumbnail(file_path, stored_name, mime_type)

    # Render's disk is temporary. Retain the short-lived local copy for the
    # thumbnail helper, but make Supabase Storage the durable source of truth.
    with open(file_path, "rb") as uploaded_file:
        content = uploaded_file.read()
    object_key = "files/" + file_path.replace("\\", "/").split("/", 1)[-1]
    stored_path = storage_service.save_object(
        object_key, content, content_type=mime_type, bucket=FILE_STORAGE_BUCKET
    )

    # Infer a meaningful category when the client did not pass an explicit one
    # ("attachment" is the API default). This keeps files visible under the
    # right front-end category chips instead of only appearing in "All".
    if file_category == "attachment" or not file_category:
        if mime_type and mime_type.startswith("image/"):
            file_category = "photos"
        elif mime_type in ("application/pdf", "application/msword", "application/vnd.openxmlformats-officedocument.wordprocessingml.document"):
            file_category = "documents"
        else:
            file_category = "attachment"

    db_file = DBFile(
        original_name=file.filename or "unknown",
        stored_name=stored_name,
        file_path=stored_path,
        file_size=file_size,
        mime_type=mime_type,
        file_category=file_category,
        thumbnail_path=thumbnail_path,
        uploaded_by=current_user.supervisor_id,
        project_id=project_id
    )

    db.add(db_file)
    db.commit()
    db.refresh(db_file)
    return db_file


@router.get("/files", response_model=List[FileOut])
def list_files(
    project_id: Optional[int] = None,
    file_category: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: Supervisor = Depends(cu)
):
    query = db.query(DBFile).options(
        joinedload(DBFile.uploader),
        joinedload(DBFile.project)
    )

    if project_id:
        query = query.filter(DBFile.project_id == project_id)
    if file_category:
        query = query.filter(DBFile.file_category == file_category)

    return query.order_by(DBFile.created_at.desc()).all()


@router.get("/files/{file_id}/download")
def download_file(
    file_id: int,
    db: Session = Depends(get_db),
    current_user: Supervisor = Depends(cu)
):
    file = db.query(DBFile).filter(DBFile.file_id == file_id).first()
    if not file:
        raise HTTPException(status_code=404, detail="File not found")

    return _file_response(file)


def _get_downloadable_file(db: Session, file_id: int) -> DBFile:
    """Fetch a file row whose local or Supabase object can be opened."""
    file = db.query(DBFile).filter(DBFile.file_id == file_id).first()
    if not file:
        raise HTTPException(status_code=404, detail="File not found")
    _file_source(file)
    return file


@router.get("/files/{file_id}/download-link")
def create_file_download_link(
    file_id: int,
    request: Request,
    ttl: int = Query(default=300, ge=30, le=3600),
    db: Session = Depends(get_db),
    current_user: Supervisor = Depends(cu)
):
    """Return a short-lived, file-scoped URL the client can fetch without headers.

    Chosen over "attach the Authorization header on every platform" because the
    two broken call sites live outside Dio: Flutter Web download navigation and
    ``Image.network`` previews. Both can only carry a URL, so the credential has
    to be in the URL itself. The token is scoped to one file and expires in
    ``ttl`` seconds (default 5 minutes), which keeps the exposure window small.

    Auth is the same ``cu`` dependency as ``/download``: minting a link grants
    exactly the access the caller already had, so no privilege is widened.
    """
    file = _get_downloadable_file(db, file_id)
    token = create_download_token(file.file_id, ttl)
    path = f"/api/files/download?token={quote(token)}"
    # Absolute URL derived from the request so the client does not have to guess
    # the host (and so a Render deployment behind a proxy still yields https).
    return {
        "file_id": file.file_id,
        "filename": file.original_name,
        "mime_type": file.mime_type,
        "download_url": str(request.base_url).rstrip("/") + path,
        "path": path,
        "expires_in": clamp_ttl(ttl),
    }


@router.get("/files/download")
def download_file_with_token(
    token: str = Query(...),
    db: Session = Depends(get_db)
):
    """Serve a file for a valid signed link (no Authorization header needed).

    This is the only unauthenticated read path in the router: authorisation is
    delegated to the signed token, which encodes a single ``file_id`` and a
    short expiry, so it cannot be widened into a general-purpose credential.
    """
    file_id = decode_download_token(token)
    file = _get_downloadable_file(db, file_id)
    return _file_response(file)


@router.put("/files/{file_id}", response_model=FileOut)
def update_file(
    file_id: int,
    file_update: FileUpdate,
    db: Session = Depends(get_db),
    current_user: Supervisor = Depends(cu)
):
    file = db.query(DBFile).filter(DBFile.file_id == file_id).first()
    if not file:
        raise HTTPException(status_code=404, detail="File not found")

    if file_update.original_name is not None:
        file.original_name = file_update.original_name
    if file_update.file_category is not None:
        file.file_category = file_update.file_category
    if file_update.project_id is not None:
        if file_update.project_id and not db.query(Project).filter(Project.project_id == file_update.project_id).first():
            raise HTTPException(status_code=404, detail="Project not found")
        file.project_id = file_update.project_id

    db.commit()
    db.refresh(file)
    return file


@router.delete("/files/{file_id}")
def delete_file_endpoint(
    file_id: int,
    db: Session = Depends(get_db),
    current_user: Supervisor = Depends(cu)
):
    file = db.query(DBFile).filter(DBFile.file_id == file_id).first()
    if not file:
        raise HTTPException(status_code=404, detail="File not found")

    # Remove the local-development copy and the durable Storage object.
    delete_file(file.file_path, file.thumbnail_path)
    for key in _storage_keys(file):
        storage_service.delete_object(key, bucket=FILE_STORAGE_BUCKET)
    db.delete(file)
    db.commit()
    return {"status": "ok", "message": "File deleted successfully"}



