import os
import uuid
from datetime import datetime
from typing import Optional, Tuple
from PIL import Image
from fastapi import UploadFile, HTTPException

# Configuration
UPLOAD_DIR = "uploads"
THUMBNAIL_DIR = "thumbnails"
MAX_FILE_SIZE = 50 * 1024 * 1024
ALLOWED_MIME_TYPES = {
    "image/jpeg", "image/png", "image/gif", "image/webp",
    "application/pdf",
    "application/msword", "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/vnd.ms-excel", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "text/plain"
}
IMAGE_MIME_TYPES = {"image/jpeg", "image/png", "image/gif", "image/webp"}
THUMBNAIL_SIZE = (200, 200)


def ensure_upload_dirs():
    os.makedirs(UPLOAD_DIR, exist_ok=True)
    os.makedirs(THUMBNAIL_DIR, exist_ok=True)


def get_date_path() -> str:
    now = datetime.now()
    return os.path.join(str(now.year), f"{now.month:02d}", f"{now.day:02d}")


def generate_unique_filename(original_name: str) -> Tuple[str, str]:
    ext = os.path.splitext(original_name)[1]
    unique_name = f"{uuid.uuid4().hex}{ext}"
    return unique_name, ext


async def save_upload_file(file: UploadFile) -> Tuple[str, str, int, str]:
    ensure_upload_dirs()

    if file.size is None or file.size > MAX_FILE_SIZE:
        raise HTTPException(status_code=400, detail=f"File size exceeds maximum limit of {MAX_FILE_SIZE // (1024*1024)}MB")

    content_type = file.content_type or "application/octet-stream"
    if content_type not in ALLOWED_MIME_TYPES:
        raise HTTPException(status_code=400, detail=f"File type {content_type} not allowed")

    date_path = get_date_path()
    full_upload_dir = os.path.join(UPLOAD_DIR, date_path)
    os.makedirs(full_upload_dir, exist_ok=True)

    original_name = file.filename or "unknown"
    stored_name, ext = generate_unique_filename(original_name)
    file_path = os.path.join(full_upload_dir, stored_name)

    content = await file.read()
    with open(file_path, "wb") as f:
        f.write(content)

    file_size = len(content)

    return file_path, stored_name, file_size, content_type


def create_thumbnail(file_path: str, stored_name: str, mime_type: str) -> Optional[str]:
    if mime_type not in IMAGE_MIME_TYPES:
        return None

    try:
        ensure_upload_dirs()
        date_path = get_date_path()
        full_thumb_dir = os.path.join(THUMBNAIL_DIR, date_path)
        os.makedirs(full_thumb_dir, exist_ok=True)

        name_without_ext = os.path.splitext(stored_name)[0]
        thumb_name = f"{name_without_ext}_thumb.jpg"
        thumb_path = os.path.join(full_thumb_dir, thumb_name)

        with Image.open(file_path) as img:
            img.thumbnail(THUMBNAIL_SIZE)
            if img.mode in ("RGBA", "P"):
                img = img.convert("RGB")
            img.save(thumb_path, "JPEG", quality=85)

        return thumb_path
    except Exception:
        return None


def delete_file(file_path: str, thumbnail_path: Optional[str] = None):
    if file_path and os.path.exists(file_path):
        os.remove(file_path)
    if thumbnail_path and os.path.exists(thumbnail_path):
        os.remove(thumbnail_path)
