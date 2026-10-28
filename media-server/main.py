"""Bhromon media server.

Files are stored at MEDIA_ROOT/{tourId}/{folder}/{objectId}{ext} and served by
nginx under /media/. Every upload and delete needs a Firebase ID token from an
active member of the tour. A delete is allowed for the file's uploader, or for
a tour owner or admin. Ownership is recorded in a metadata file kept outside the
public tree.

LEGACY_UPLOAD_KEY is a transition aid for app builds that predate token auth.
It is unset by default and should be removed once those builds are gone.
"""

import hashlib
import os
import json
import logging
import re
import secrets
import uuid
from contextlib import asynccontextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Optional

import aiofiles
from fastapi import FastAPI, File, Form, Header, HTTPException, UploadFile, status
from fastapi.concurrency import run_in_threadpool
from fastapi.middleware.cors import CORSMiddleware

from chat import chat_router
from notifications import FirestoreNotificationWatcher, NotificationEngine
from quiz import quiz_router

logger = logging.getLogger("media-server")

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

ALLOWED_FOLDERS = frozenset({
    "posts", "reels", "covers", "stories", "channels",
    "avatars", "profiles", "chat_media", "chat_voice", "chat_docs", "trip_logs", "media",
    "expenses",
})
ALLOWED_EXTENSIONS = frozenset({
    ".jpg", ".jpeg", ".png", ".webp", ".gif", ".heic", ".heif",
    ".mp4", ".mov", ".m4v", ".webm", ".3gp", ".mkv",
    # Audio extensions
    ".m4a", ".mp3", ".aac", ".wav", ".ogg", ".opus",
    # Document extensions
    ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx", ".txt", ".csv", ".zip",
})
VIDEO_EXTENSIONS = frozenset({".mp4", ".mov", ".m4v", ".webm", ".3gp", ".mkv"})
AUDIO_EXTENSIONS = frozenset({".m4a", ".mp3", ".aac", ".wav", ".ogg", ".opus"})
DOC_EXTENSIONS = frozenset({".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx", ".txt", ".csv", ".zip"})

# These match the app's limits (lib/features/tour_group/domain/services/media_rules.dart).
MAX_IMAGE_BYTES = 10 * 1024 * 1024  # 10 MB
MAX_VIDEO_BYTES = 100 * 1024 * 1024  # 100 MB
MAX_AUDIO_BYTES = 25 * 1024 * 1024  # 25 MB
MAX_DOC_BYTES = 50 * 1024 * 1024  # 50 MB

TOUR_ID_PATTERN = re.compile(r"[A-Za-z0-9_-]{1,64}")
OBJECT_ID_PATTERN = re.compile(r"[0-9a-f]{32}")
FILENAME_PATTERN = re.compile(
    r"([0-9a-f]{32})\.(jpg|jpeg|png|webp|gif|heic|heif|mp4|mov|m4v|webm|3gp|mkv|m4a|mp3|aac|wav|ogg|opus|pdf|doc|docx|xls|xlsx|ppt|pptx|txt|csv|zip)"
)

notification_engine = NotificationEngine()
notification_watcher = FirestoreNotificationWatcher(notification_engine)


def init_firebase_admin() -> None:
    """Initialize Firebase Admin SDK once with credentials or default."""
    import firebase_admin
    from firebase_admin import credentials

    if not firebase_admin._apps:
        cred_path = (
            FIREBASE_CREDENTIALS
            if (FIREBASE_CREDENTIALS and os.path.exists(FIREBASE_CREDENTIALS))
            else ("/run/secrets/firebase-admin.json" if os.path.exists("/run/secrets/firebase-admin.json") else "")
        )
        cred = (
            credentials.Certificate(cred_path)
            if cred_path
            else credentials.ApplicationDefault()
        )
        firebase_admin.initialize_app(cred)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Initialize Firebase Admin SDK first
    try:
        init_firebase_admin()
    except Exception as e:
        logger.error("Failed to initialize Firebase Admin SDK: %s", e)

    # Start watcher on startup if Firebase credentials exist
    if FIREBASE_CREDENTIALS or os.path.exists("/run/secrets/firebase-admin.json"):
        notification_watcher.start()
    yield
    # Stop watcher on shutdown
    notification_watcher.stop()


app = FastAPI(
    title="Bhromon Media & Notification Server",
    version="2.1.0",
    lifespan=lifespan,
)

app.include_router(chat_router, prefix="/api/chat")
app.include_router(chat_router, prefix="/chat")
app.include_router(quiz_router, prefix="/api/quiz")
app.include_router(quiz_router, prefix="/quiz")

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

    def _ensure_app(self) -> None:
        init_firebase_admin()

    def _client(self):
        if self._db is None:
            from firebase_admin import firestore

            self._ensure_app()
            self._db = firestore.client()
        return self._db

    def email_for_token(self, token: str) -> str:
        self._ensure_app()
        from firebase_admin import auth

        decoded = auth.verify_id_token(token, clock_skew_seconds=10)
        email = (decoded.get("email") or "").strip().lower()
        if not email and "uid" in decoded:
            try:
                user = auth.get_user(decoded["uid"])
                email = (user.email or "").strip().lower()
            except Exception as e:
                logger.warning("Could not fetch user by uid %s: %s", decoded.get("uid"), e)
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
        except Exception as e:
            logger.warning("Bearer token authentication failed: %s: %s", type(e).__name__, e)
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


PUBLIC_OR_USER_SPACES = frozenset({
    "profiles", "users", "general", "explorer", "trip_logs"
})


def require_member(tour_id: str, caller: Caller) -> str:
    """The caller's role in the tour. Raises 403 when they are not an active member."""
    if caller.legacy:
        return "legacy"
    if tour_id in PUBLIC_OR_USER_SPACES or tour_id.startswith("chat_") or tour_id.startswith("user_"):
        if caller.email:
            return "member"
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
    return {
        "status": "ok",
        "service": "bhromon-media-server",
        "notifications": {
            "watcher_running": notification_watcher._is_running,
            "stats": notification_engine.stats,
        },
    }


async def store_stream(file: UploadFile, dest: Path, max_allowed: int) -> int:
    """Writes the upload to [dest] and returns its size. Stops at [max_allowed]."""
    total = 0
    async with aiofiles.open(dest, "xb") as out_file:
        while chunk := await file.read(1024 * 1024):
            total += len(chunk)
            if total > max_allowed:
                raise HTTPException(
                    status_code=413,
                    detail=f"File exceeds maximum allowed size ({max_allowed // (1024 * 1024)} MB)",
                )
            await out_file.write(chunk)
    return total


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def is_retry_of(
    tourId: str,
    folder: str,
    filename: str,
    caller: Caller,
    part: Path,
    target: Path,
) -> bool:
    """True when the stored file is this same member's earlier send of identical bytes.

    A phone that loses its connection after the server has stored a file cannot
    tell whether it got through, so it sends again. The repeat gets the existing
    URL back instead of a conflict. Anything else with the same name is refused.
    """
    if caller.legacy:
        return False
    meta = read_meta(tourId, folder, filename)
    if meta is None or meta.get("uploaderEmail") != caller.email:
        return False
    return sha256_of(target) == sha256_of(part)


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
    if ext in VIDEO_EXTENSIONS:
        max_allowed = MAX_VIDEO_BYTES
    elif ext in AUDIO_EXTENSIONS:
        max_allowed = MAX_AUDIO_BYTES
    elif ext in DOC_EXTENSIONS:
        max_allowed = MAX_DOC_BYTES
    else:
        max_allowed = MAX_IMAGE_BYTES

    target_dir = MEDIA_ROOT / tourId / folder
    target_dir.mkdir(parents=True, exist_ok=True)
    target = target_dir / filename
    # The bytes land under a temporary name and are linked into place only when
    # complete, so a file never appears half written and nothing is left behind.
    part = target_dir / f".{filename}.{uuid.uuid4().hex}.part"

    try:
        total_bytes = await store_stream(file, part, max_allowed)
        try:
            # A hard link fails when the target exists, which keeps uploads from
            # overwriting a file.
            os.link(part, target)
        except FileExistsError:
            if not await run_in_threadpool(is_retry_of, tourId, folder, filename, caller, part, target):
                raise HTTPException(status_code=409, detail="That file already exists.")
        else:
            try:
                await run_in_threadpool(write_meta, tourId, folder, filename, caller)
            except Exception:
                target.unlink(missing_ok=True)
                raise
    finally:
        part.unlink(missing_ok=True)

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


@app.get("/notify/status")
def notification_status():
    return {
        "watcher_running": notification_watcher._is_running,
        "listeners": len(notification_watcher.active_listeners),
        "stats": notification_engine.stats,
    }


@app.post("/notify/sos")
async def trigger_sos_notification(
    payload: Dict[str, Any],
    authorization: Optional[str] = Header(None),
    x_upload_key: Optional[str] = Header(None, alias="X-Upload-Key"),
):
    caller = await run_in_threadpool(authenticate, authorization, x_upload_key)
    tour_id = payload.get("tourId", "")
    alert_id = payload.get("alertId", "")
    sender_name = payload.get("senderName", "A member")
    check_tour_id(tour_id)
    await run_in_threadpool(require_member, tour_id, caller)

    res = await run_in_threadpool(
        notification_engine.send_sos_alert,
        tour_id=tour_id,
        alert_id=alert_id,
        sender_email=caller.email,
        sender_name=sender_name,
    )
    return res


@app.post("/notify/channel")
async def trigger_channel_notification(
    payload: Dict[str, Any],
    authorization: Optional[str] = Header(None),
    x_upload_key: Optional[str] = Header(None, alias="X-Upload-Key"),
):
    caller = await run_in_threadpool(authenticate, authorization, x_upload_key)
    tour_id = payload.get("tourId", "")
    channel_id = payload.get("channelId", "")
    message_id = payload.get("messageId", "")
    sender_name = payload.get("senderName", "A member")
    text = payload.get("text", "")
    mentions = payload.get("mentions", [])
    attachments = payload.get("attachments", [])
    kind = payload.get("kind", "text")
    check_tour_id(tour_id)
    await run_in_threadpool(require_member, tour_id, caller)

    res = await run_in_threadpool(
        notification_engine.send_channel_message_notification,
        tour_id=tour_id,
        channel_id=channel_id,
        message_id=message_id,
        sender_email=caller.email,
        sender_name=sender_name,
        text=text,
        mentions=mentions,
        attachments=attachments,
        kind=kind,
    )
    return res


@app.post("/notify/chat")
async def trigger_chat_notification(
    payload: Dict[str, Any],
    authorization: Optional[str] = Header(None),
    x_upload_key: Optional[str] = Header(None, alias="X-Upload-Key"),
):
    caller = await run_in_threadpool(authenticate, authorization, x_upload_key)
    chat_id = payload.get("chatId", "")
    sender_id = payload.get("senderId", "")
    text = payload.get("text", "")
    message_type = payload.get("type", "text")

    res = await run_in_threadpool(
        notification_engine.send_chat_notification,
        chat_id=chat_id,
        sender_id=sender_id,
        text=text,
        message_type=message_type,
    )
    return res


@app.post("/admin/maintenance")
async def trigger_maintenance(
    authorization: Optional[str] = Header(None),
    x_upload_key: Optional[str] = Header(None, alias="X-Upload-Key"),
):
    await run_in_threadpool(authenticate, authorization, x_upload_key)
    res = await run_in_threadpool(notification_engine.run_retention_sweep)
    return res
