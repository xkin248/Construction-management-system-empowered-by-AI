from fastapi import APIRouter, Depends, HTTPException, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session, joinedload
from typing import List, Optional
import os

from app.database import get_db
from app.models import File as DBFile, Project, Supervisor
from app.schemas import FileOut, FileUpdate
from app.file_service import (
    save_upload_file, create_thumbnail, delete_file,
    UPLOAD_DIR, THUMBNAIL_DIR
)
from app.routers.auth import cu

router = APIRouter(tags=["📁 File Management"])


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

    db_file = DBFile(
        original_name=file.filename or "unknown",
        stored_name=stored_name,
        file_path=file_path,
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

    if not os.path.exists(file.file_path):
        raise HTTPException(status_code=404, detail="File not found on disk")

    return FileResponse(
        path=file.file_path,
        filename=file.original_name,
        media_type=file.mime_type
    )


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

    delete_file(file.file_path, file.thumbnail_path)
    db.delete(file)
    db.commit()
    return {"status": "ok", "message": "File deleted successfully"}



