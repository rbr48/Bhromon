"""Bhromon media server.

Files are stored at MEDIA_ROOT/{tourId}/{folder}/{objectId}{ext} and served by
nginx under /media/. Every upload and delete needs a Firebase ID token from an
active member of the tour. A delete is allowed for the file's uploader, or for
a tour owner or admin. Ownership is recorded in a metadata file kept outside the
public tree.

LEGACY_UPLOAD_KEY is a transition aid for app builds that predate token auth.
It is unset by default and should be removed once those builds are gone.
"""

import os
import re
import json
import secrets
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import aiofiles
from fastapi import FastAPI, File, Form, Header, HTTPException, UploadFile, status
from fastapi.concurrency import run_in_threadpool
from fastapi.middleware.cors import CORSMiddleware

MEDIA_ROOT = Path(os.getenv("MEDIA_ROOT", "/data/media"))
META_ROOT = Path(os.getenv("MEDIA_META_ROOT", "/data/media-meta"))
BASE_URL = os.getenv("BASE_URL", "https://bhromon.fun/media")
FIREBASE_CREDENTIALS = os.getenv("FIREBASE_CREDENTIALS", "")
LEGACY_UPLOAD_KEY = os.getenv("LEGACY_UPLOAD_KEY", "")
ALLOWED_ORIGINS = [
    origin.strip()
    for origin in os.getenv(
        "CORS_ORIGINS",
        "https://app.bhromon.fun,https://bhromon-ff801.web.app,"
        "https://bhromon-ff801.firebaseapp.com",
    ).split(",")
    if origin.strip()
]

ALLOWED_FOLDERS = frozenset({"posts", "reels", "covers", "stories", "channels"})
ALLOWED_EXTENSIONS = frozenset({
    ".jpg", ".jpeg", ".png", ".webp", ".gif", ".heic", ".heif",
    ".mp4", ".mov", ".m4v", ".webm", ".3gp", ".mkv",
})
VIDEO_EXTENSIONS = frozenset({".mp4", ".mov", ".m4v", ".webm", ".3gp", ".mkv"})

MAX_IMAGE_BYTES = 15 * 1024 * 1024  # 15 MB
MAX_VIDEO_BYTES = 120 * 1024 * 1024  # 120 MB

TOUR_ID_PATTERN = re.compile(r"[A-Za-z0-9_-]{1,64}")
OBJECT_ID_PATTERN = re.compile(r"[0-9a-f]{32}")
FILENAME_PATTERN = re.compile(
    r"([0-9a-f]{32})\.(jpg|jpeg|png|webp|gif|heic|heif|mp4|mov|m4v|webm|3gp|mkv)"
)

app = FastAPI(title="Bhromon Media Server", version="2.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=False,
    allow_methods=["GET", "POST", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Upload-Key"],
)


@dataclass(frozen=True)
class Caller:
    """Who is calling. The legacy key has no identity, so its email is empty."""

    email: str
    legacy: bool = False


class FirebaseBackend:
    """Checks ID tokens and tour memberships with the Firebase Admin SDK."""

    def __init__(self) -> None:
        self._db = None

    def _client(self):
        if self._db is None:
            import firebase_admin
            from firebase_admin import credentials, firestore

            if not firebase_admin._apps:
                cred = (
                    credentials.Certificate(FIREBASE_CREDENTIALS)
                    if FIREBASE_CREDENTIALS
                    else credentials.ApplicationDefault()
                )
                firebase_admin.initialize_app(cred)
            self._db = firestore.client()
        return self._db

    def email_for_token(self, token: str) -> str:
        from firebase_admin import auth

        decoded = auth.verify_id_token(token)
        email = (decoded.get("email") or "").strip().lower()
        if not email:
            raise ValueError("The token has no email address.")
        return email

    def role_for(self, tour_id: str, email: str) -> Optional[str]:
        """The caller's role in the tour, or None when they are not an active member."""
        db = self._client()
        member = db.collection("memberships").document(f"{tour_id}__{email}").get()
        if member.exists:
            data = member.to_dict() or {}
            if data.get("status") != "active":
                return None
            role = str(data.get("role", "member")).lower()
            return role if role in {"owner", "admin", "member"} else "member"
        tour = db.collection("tours").document(tour_id).get()
        if tour.exists and str((tour.to_dict() or {}).get("ownerEmail", "")).lower() == email:
            return "owner"
        return None


backend = FirebaseBackend()


def authenticate(authorization: Optional[str], legacy_key: Optional[str]) -> Caller:
    """Identifies the caller from a Firebase ID token, or from the legacy key if enabled."""
    if authorization and authorization.lower().startswith("bearer "):
        token = authorization[7:].strip()
        try:
            return Caller(email=backend.email_for_token(token))
        except Exception:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Sign in again to upload or delete media.",
            )
    if LEGACY_UPLOAD_KEY and legacy_key and secrets.compare_digest(legacy_key, LEGACY_UPLOAD_KEY):
        return Caller(email="", legacy=True)
    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Missing or invalid authorization.",
    )


def require_member(tour_id: str, caller: Caller) -> str:
    """The caller's role in the tour. Raises 403 when they are not an active member."""
    if caller.legacy:
        return "legacy"
    role = backend.role_for(tour_id, caller.email)
    if role is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not an active member of this tour.",
        )
    return role


def check_tour_id(tour_id: str) -> None:
    if not TOUR_ID_PATTERN.fullmatch(tour_id):
        raise HTTPException(status_code=400, detail="Invalid tour id.")


def check_folder(folder: str) -> None:
    if folder not in ALLOWED_FOLDERS:
        raise HTTPException(
            status_code=400,
            detail=f"Unknown folder. Allowed: {sorted(ALLOWED_FOLDERS)}",
        )


def extension_of(filename: Optional[str]) -> str:
    ext = Path(filename or "").suffix.lower()
    if ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file extension. Allowed: {sorted(ALLOWED_EXTENSIONS)}",
        )
    return ext


def object_id_for(raw: Optional[str]) -> str:
    """A client may choose the object id, so it knows the URL before the upload returns."""
    if not raw:
        return uuid.uuid4().hex
    if not OBJECT_ID_PATTERN.fullmatch(raw):
        raise HTTPException(
            status_code=400,
            detail="objectId must be 32 lowercase hex characters.",
        )
    return raw


def meta_path_for(tour_id: str, folder: str, filename: str) -> Path:
    return META_ROOT / tour_id / folder / f"{filename}.json"


def write_meta(tour_id: str, folder: str, filename: str, caller: Caller) -> None:
    path = meta_path_for(tour_id, folder, filename)
    path.parent.mkdir(parents=True, exist_ok=True)
    record = {
        "uploaderEmail": "legacy" if caller.legacy else caller.email,
        "tourId": tour_id,
        "folder": folder,
    }
    path.write_text(json.dumps(record), encoding="utf-8")


def read_meta(tour_id: str, folder: str, filename: str) -> Optional[dict]:
    path = meta_path_for(tour_id, folder, filename)
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def may_delete(caller: Caller, role: str, meta: Optional[dict]) -> bool:
    if caller.legacy:
        return True
    if role in {"owner", "admin"}:
        return True
    return meta is not None and meta.get("uploaderEmail") == caller.email


@app.get("/health")
async def health():
    return {"status": "ok", "service": "bhromon-media-server"}


@app.post("/upload")
async def upload_media(
    file: UploadFile = File(...),
    tourId: str = Form(...),
    folder: str = Form(...),
    objectId: Optional[str] = Form(None),
    authorization: Optional[str] = Header(None),
    x_upload_key: Optional[str] = Header(None, alias="X-Upload-Key"),
):
    caller = await run_in_threadpool(authenticate, authorization, x_upload_key)
    check_tour_id(tourId)
    check_folder(folder)
    await run_in_threadpool(require_member, tourId, caller)

    ext = extension_of(file.filename)
    filename = f"{object_id_for(objectId)}{ext}"
    max_allowed = MAX_VIDEO_BYTES if ext in VIDEO_EXTENSIONS else MAX_IMAGE_BYTES

    target_dir = MEDIA_ROOT / tourId / folder
    target_dir.mkdir(parents=True, exist_ok=True)
    target = target_dir / filename

    total_bytes = 0
    try:
        # "xb" refuses to overwrite a file that already exists.
        async with aiofiles.open(target, "xb") as out_file:
            while chunk := await file.read(1024 * 1024):
                total_bytes += len(chunk)
                if total_bytes > max_allowed:
                    raise HTTPException(
                        status_code=413,
                        detail=f"File exceeds maximum allowed size ({max_allowed // (1024 * 1024)} MB)",
                    )
                await out_file.write(chunk)
        write_meta(tourId, folder, filename, caller)
    except FileExistsError:
        raise HTTPException(status_code=409, detail="That file already exists.")
    except Exception:
        target.unlink(missing_ok=True)
        raise

    return {
        "status": "success",
        "url": f"{BASE_URL.rstrip('/')}/{tourId}/{folder}/{filename}",
        "filename": filename,
        "bytes": total_bytes,
        "contentType": file.content_type,
    }


@app.delete("/media/{tourId}/{folder}/{filename}")
async def delete_media(
    tourId: str,
    folder: str,
    filename: str,
    authorization: Optional[str] = Header(None),
    x_upload_key: Optional[str] = Header(None, alias="X-Upload-Key"),
):
    caller = await run_in_threadpool(authenticate, authorization, x_upload_key)
    check_tour_id(tourId)
    check_folder(folder)
    if not FILENAME_PATTERN.fullmatch(filename):
        raise HTTPException(status_code=400, detail="Invalid file name.")
    role = await run_in_threadpool(require_member, tourId, caller)

    target = MEDIA_ROOT / tourId / folder / filename
    if not target.is_file():
        return {"status": "not_found"}

    meta = read_meta(tourId, folder, filename)
    if not may_delete(caller, role, meta):
        raise HTTPException(
            status_code=403,
            detail="Only the uploader, an owner or an admin can delete this file.",
        )

    target.unlink()
    meta_path_for(tourId, folder, filename).unlink(missing_ok=True)
    return {"status": "deleted", "path": f"{tourId}/{folder}/{filename}"}
