import os
import uuid
from pathlib import Path
import aiofiles
from fastapi import FastAPI, UploadFile, File, Form, Header, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(title="Bhromon Media Server", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

MEDIA_ROOT = Path(os.getenv("MEDIA_ROOT", "/data/media"))
UPLOAD_KEY = os.getenv("MEDIA_UPLOAD_KEY", "bhromon_vps_media_2026_sec")
BASE_URL = os.getenv("BASE_URL", "https://bhromon.fun/media")

ALLOWED_EXTENSIONS = {
    ".jpg", ".jpeg", ".png", ".webp", ".gif",
    ".mp4", ".mov", ".m4v", ".webm"
}

MAX_IMAGE_BYTES = 15 * 1024 * 1024       # 15 MB
MAX_VIDEO_BYTES = 120 * 1024 * 1024      # 120 MB

@app.get("/health")
async def health():
    return {"status": "ok", "service": "bhromon-media-server"}

@app.post("/upload")
async def upload_media(
    file: UploadFile = File(...),
    tourId: str = Form(...),
    folder: str = Form("photos"),
    uploaderEmail: str = Form(None),
    x_upload_key: str = Header(None, alias="X-Upload-Key"),
):
    if x_upload_key != UPLOAD_KEY:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing upload authorization key",
        )

    safe_tour_id = "".join(c for c in tourId if c.isalnum() or c in ("-", "_"))
    safe_folder = "".join(c for c in folder if c.isalnum() or c in ("-", "_"))
    if not safe_tour_id or not safe_folder:
        raise HTTPException(status_code=400, detail="Invalid tourId or folder name")

    orig_ext = Path(file.filename or "").suffix.lower()
    if orig_ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file extension: {orig_ext}. Allowed: {list(ALLOWED_EXTENSIONS)}"
        )

    target_dir = MEDIA_ROOT / safe_tour_id / safe_folder
    target_dir.mkdir(parents=True, exist_ok=True)

    file_id = f"{uuid.uuid4().hex}{orig_ext}"
    target_path = target_dir / file_id

    total_bytes = 0
    max_allowed = MAX_VIDEO_BYTES if orig_ext in {".mp4", ".mov", ".m4v", ".webm"} else MAX_IMAGE_BYTES

    async with aiofiles.open(target_path, "wb") as out_file:
        while chunk := await file.read(1024 * 1024):
            total_bytes += len(chunk)
            if total_bytes > max_allowed:
                if target_path.exists():
                    target_path.unlink()
                raise HTTPException(
                    status_code=413,
                    detail=f"File exceeds maximum allowed size ({max_allowed // (1024*1024)} MB)"
                )
            await out_file.write(chunk)

    relative_url_path = f"{safe_tour_id}/{safe_folder}/{file_id}"
    public_url = f"{BASE_URL.rstrip('/')}/{relative_url_path}"

    return {
        "status": "success",
        "url": public_url,
        "filename": file_id,
        "bytes": total_bytes,
        "contentType": file.content_type,
    }

@app.delete("/media/{tourId}/{folder}/{filename}")
async def delete_media(
    tourId: str,
    folder: str,
    filename: str,
    x_upload_key: str = Header(None, alias="X-Upload-Key"),
):
    if x_upload_key != UPLOAD_KEY:
        raise HTTPException(status_code=401, detail="Unauthorized")

    safe_tour_id = "".join(c for c in tourId if c.isalnum() or c in ("-", "_"))
    safe_folder = "".join(c for c in folder if c.isalnum() or c in ("-", "_"))
    safe_file = "".join(c for c in filename if c.isalnum() or c in ("-", "_", "."))

    file_path = MEDIA_ROOT / safe_tour_id / safe_folder / safe_file
    if file_path.exists() and file_path.is_file():
        file_path.unlink()
        return {"status": "deleted", "path": f"{safe_tour_id}/{safe_folder}/{safe_file}"}

    return {"status": "not_found"}
