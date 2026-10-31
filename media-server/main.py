"""Bhromon media server.

Files are stored at MEDIA_ROOT/{tourId}/{folder}/{objectId}{ext} and served by
nginx under /media/. Every upload and delete needs a Firebase ID token from an
active member of the tour. A delete is allowed for the file's uploader, or for
a tour owner or admin. Ownership is recorded in a metadata file kept outside the
public tree.

There is no shared upload key. An old app build that still sends one is refused.
"""

import hashlib
import os
import json
import logging
import re
import secrets
import shutil
import time
import uuid
from contextlib import asynccontextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import aiofiles
from fastapi import FastAPI, File, Form, Header, HTTPException, UploadFile, status
from fastapi.concurrency import run_in_threadpool
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

import chat
import news
from chat import chat_db, chat_router
from news import router as news_router
from notifications import FirestoreNotificationWatcher, NotificationEngine
from quiz import quiz_router

logger = logging.getLogger("media-server")

MEDIA_ROOT = Path(os.getenv("MEDIA_ROOT", "/data/media"))
META_ROOT = Path(os.getenv("MEDIA_META_ROOT", "/data/media-meta"))
BASE_URL = os.getenv("BASE_URL", "https://bhromon.fun/media")
FIREBASE_CREDENTIALS = os.getenv("FIREBASE_CREDENTIALS", "")
# Held by the Bhromon back end only. It lets that back end remove a tour's
# files when a member leaves or a tour is deleted.
PURGE_KEY = os.getenv("PURGE_KEY", "")
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
app.include_router(news_router, prefix="/api/news")
app.include_router(news_router, prefix="/news")

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=False,
    allow_methods=["GET", "POST", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)


@dataclass(frozen=True)
class Caller:
    """Who is calling, from a verified Firebase ID token."""

    email: str
    uid: str


# How long a uid's email, and a person's tours, are remembered. A person who leaves
# a tour can still be reached for at most this long.
EMAIL_CACHE_SECONDS = 600
TOURS_CACHE_SECONDS = 15


class FirebaseBackend:
    """Checks ID tokens and tour memberships with the Firebase Admin SDK."""

    def __init__(self) -> None:
        self._db = None
        self._email_cache: Dict[str, Tuple[float, str]] = {}
        self._tours_cache: Dict[str, Tuple[float, frozenset]] = {}

    def _ensure_app(self) -> None:
        init_firebase_admin()

    def _client(self):
        if self._db is None:
            from firebase_admin import firestore

            self._ensure_app()
            self._db = firestore.client()
        return self._db

    def _account_email(self, uid: str) -> str:
        """The email Firebase Auth holds for a uid, once it is verified. "" otherwise."""
        self._ensure_app()
        from firebase_admin import auth

        try:
            user = auth.get_user(uid)
        except Exception as e:  # No such account, or the lookup failed.
            logger.info("No account for uid %s: %s", uid, e)
            return ""
        return (user.email or "").strip().lower() if user.email_verified else ""

    def identity_for_token(self, token: str) -> Tuple[str, str]:
        """The (uid, email) a Firebase ID token belongs to. Raises when either is missing.

        Only a verified address counts. Anyone can register an address they do not own,
        so an unverified one must not open a person's tours.
        """
        self._ensure_app()
        from firebase_admin import auth

        decoded = auth.verify_id_token(token, clock_skew_seconds=10)
        uid = str(decoded.get("uid") or "")
        if not uid:
            raise ValueError("The token has no uid.")
        email = (decoded.get("email") or "").strip().lower()
        if not email or decoded.get("email_verified") is not True:
            # A token can be older than the account, so the account decides.
            email = self._account_email(uid)
        if not email:
            raise ValueError("The token has no verified email address.")
        return uid, email

    def email_for_token(self, token: str) -> str:
        return self.identity_for_token(token)[1]

    def tier_for_uid(self, uid: str) -> Optional[str]:
        """The explorer tier stored on the user's profile, or None when there is no profile."""
        if not uid:
            return None
        profile = self._client().collection("explorer_profiles").document(uid).get()
        if not profile.exists:
            return None
        return str((profile.to_dict() or {}).get("tier") or "") or None

    def email_for_uid(self, uid: str) -> str:
        """The verified email Firebase Auth holds for a uid, or "" when there is none."""
        if not uid:
            return ""
        now = time.monotonic()
        cached = self._email_cache.get(uid)
        if cached and now - cached[0] < EMAIL_CACHE_SECONDS:
            return cached[1]
        email = self._account_email(uid)
        if email:
            # Only a verified address is remembered, so one verified just now counts at once.
            self._email_cache[uid] = (now, email)
        return email

    def active_tours_for_email(self, email: str) -> frozenset:
        """The tours the email is an active member of, owned tours included."""
        if not email:
            return frozenset()
        now = time.monotonic()
        cached = self._tours_cache.get(email)
        if cached and now - cached[0] < TOURS_CACHE_SECONDS:
            return cached[1]
        db = self._client()
        rows = db.collection("memberships").where("email", "==", email).where("status", "==", "active").stream()
        tours = {str((row.to_dict() or {}).get("tourId") or "") for row in rows}
        tours |= {doc.id for doc in db.collection("tours").where("ownerEmail", "==", email).stream()}
        tours.discard("")
        result = frozenset(tours)
        self._tours_cache[email] = (now, result)
        return result

    def shares_group(self, uid_a: str, uid_b: str) -> bool:
        """Whether two people are active members of one tour together."""
        if not uid_a or not uid_b or uid_a == uid_b:
            return False
        tours_a = self.active_tours_for_email(self.email_for_uid(uid_a))
        if not tours_a:
            return False
        return not tours_a.isdisjoint(self.active_tours_for_email(self.email_for_uid(uid_b)))

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

# Chat and call routes ask this before they reach another person. The lookup goes
# through `backend` at call time, so tests that swap the backend swap this too.
chat.shares_group = lambda uid_a, uid_b: backend.shares_group(uid_a, uid_b)

# Only a platform admin may start a news sync.
news.sync_guard = lambda authorization: require_platform_admin(authenticate(authorization))


def authenticate(authorization: Optional[str]) -> Caller:
    """Identifies the caller from a Firebase ID token. Anything else is refused."""
    if authorization and authorization.lower().startswith("bearer "):
        token = authorization[7:].strip()
        try:
            uid, email = backend.identity_for_token(token)
            return Caller(email=email, uid=uid)
        except Exception as e:
            logger.warning("Bearer token authentication failed: %s: %s", type(e).__name__, e)
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Sign in again to upload or delete media.",
            )
    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Missing or invalid authorization.",
    )


# The explorer tiers the Firestore rules trust as platform admins (isRegionExpertOrAbove).
PLATFORM_ADMIN_TIERS = frozenset({"regionExpert", "pioneer"})


def require_platform_admin(caller: Caller) -> None:
    """Raises 403 unless the caller is a platform admin."""
    if not caller.uid or backend.tier_for_uid(caller.uid) not in PLATFORM_ADMIN_TIERS:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only platform admins can do this.",
        )


PUBLIC_OR_USER_SPACES = frozenset({
    "profiles", "users", "general", "explorer", "trip_logs"
})


def chat_partner_of(space: str, uid: str) -> Optional[str]:
    """The other person in a chat space (`chat_{uidA}_{uidB}`), or None when `uid` is not one of them."""
    if not uid or not space.startswith("chat_"):
        return None
    rest = space[len("chat_"):]
    if rest.startswith(uid + "_"):
        other = rest[len(uid) + 1:]
    elif rest.endswith("_" + uid):
        other = rest[: -(len(uid) + 1)]
    else:
        return None
    return other if other and other != uid else None


def require_member(tour_id: str, caller: Caller) -> str:
    """The caller's role in the tour. Raises 403 when they are not allowed in it.

    A chat space is open only to the two people in it, and only while they share a
    tour. A user space is open only to its owner. The public spaces are open to any
    signed-in person, as they always were.
    """
    if tour_id.startswith("chat_"):
        other = chat_partner_of(tour_id, caller.uid)
        if other is None or not backend.shares_group(caller.uid, other):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You can only use media in a chat with someone you share a tour with.",
            )
        return "member"
    if tour_id.startswith("user_"):
        if caller.uid and tour_id == f"user_{caller.uid}":
            return "owner"
        raise HTTPException(status_code=403, detail="That space belongs to someone else.")
    if tour_id in PUBLIC_OR_USER_SPACES:
        if caller.email:
            return "member"
        raise HTTPException(status_code=403, detail="Sign in to use this space.")
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
        "uploaderEmail": caller.email,
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
):
    caller = await run_in_threadpool(authenticate, authorization)
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
):
    caller = await run_in_threadpool(authenticate, authorization)
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


class PurgeRequest(BaseModel):
    tourId: str
    uploaderEmail: Optional[str] = None


def purge_tour_files(tour_id: str, uploader: Optional[str]) -> List[str]:
    """Deletes one uploader's files in a tour, or every file of the tour.

    An uploader is matched on the sidecar written when each file was saved.
    Files saved before sidecars existed have no uploader, so they only go with
    the whole tour. Returns the paths removed, relative to the tour's folder.
    """
    if uploader is None:
        tour_dir = MEDIA_ROOT / tour_id
        removed = (
            sorted(
                path.relative_to(tour_dir).as_posix()
                for path in tour_dir.rglob("*")
                if path.is_file()
            )
            if tour_dir.is_dir()
            else []
        )
        shutil.rmtree(tour_dir, ignore_errors=True)
        shutil.rmtree(META_ROOT / tour_id, ignore_errors=True)
        return removed

    removed: List[str] = []
    for meta_file in (META_ROOT / tour_id).glob("*/*.json"):
        try:
            meta = json.loads(meta_file.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if not isinstance(meta, dict):
            continue
        saved_by = str(meta.get("uploaderEmail", "")).strip().lower()
        if saved_by != uploader:
            continue
        folder = meta_file.parent.name
        filename = meta_file.name[: -len(".json")]
        (MEDIA_ROOT / tour_id / folder / filename).unlink(missing_ok=True)
        meta_file.unlink(missing_ok=True)
        removed.append(f"{folder}/{filename}")
    return removed


def _require_purge_key(provided: Optional[str]) -> None:
    """Refuses a purge unless the back end sent the purge key this server was given."""
    if not PURGE_KEY:
        raise HTTPException(status_code=503, detail="Purging is not configured.")
    if not provided or not secrets.compare_digest(
        provided.encode("utf-8"), PURGE_KEY.encode("utf-8")
    ):
        raise HTTPException(status_code=401, detail="Wrong purge key.")


@app.post("/purge")
async def purge_tour_content(
    body: PurgeRequest,
    x_purge_key: Optional[str] = Header(None),
):
    """Removes a tour's files on the request of the Bhromon back end.

    With an uploader email, only that person's files in the tour go. Without
    one, every file of the tour goes. The response lists the paths removed, so
    the back end can clear the links that pointed to them.
    """
    _require_purge_key(x_purge_key)
    check_tour_id(body.tourId)
    uploader = body.uploaderEmail.strip().lower() if body.uploaderEmail else None
    removed = await run_in_threadpool(purge_tour_files, body.tourId, uploader)
    return {"removed": len(removed), "paths": removed}


def purge_user_files(email: str) -> List[str]:
    """Deletes every file `email` uploaded, in every tour and space. Returns the paths removed."""
    removed: List[str] = []
    if not META_ROOT.is_dir():
        return removed
    for meta_file in META_ROOT.glob("*/*/*.json"):
        try:
            meta = json.loads(meta_file.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if not isinstance(meta, dict) or str(meta.get("uploaderEmail", "")).strip().lower() != email:
            continue
        tour_id = meta_file.parent.parent.name
        folder = meta_file.parent.name
        filename = meta_file.name[: -len(".json")]
        (MEDIA_ROOT / tour_id / folder / filename).unlink(missing_ok=True)
        meta_file.unlink(missing_ok=True)
        removed.append(f"{tour_id}/{folder}/{filename}")
    return removed


class AccountPurgeRequest(BaseModel):
    uid: str
    email: str


@app.post("/purge/account")
async def purge_account_content(
    body: AccountPurgeRequest,
    x_purge_key: Optional[str] = Header(None),
):
    """Removes what one person left here when their account is closed.

    That is every file they uploaded, in any space, and their part in the chat
    service. The back end calls this before it deletes the sign-in account, so a
    failure can be retried. Repeating the call is harmless.
    """
    _require_purge_key(x_purge_key)
    uid = body.uid.strip()
    email = body.email.strip().lower()
    if not TOUR_ID_PATTERN.fullmatch(uid) or "@" not in email:
        raise HTTPException(status_code=400, detail="A uid and an email are required.")
    files = await run_in_threadpool(purge_user_files, email)
    chat_counts = await run_in_threadpool(chat_db.erase_user, uid, email)
    return {"files": len(files), "paths": files, "chat": chat_counts}


@app.get("/notify/status")
async def notification_status(authorization: Optional[str] = Header(None)):
    caller = await run_in_threadpool(authenticate, authorization)
    await run_in_threadpool(require_platform_admin, caller)
    return {
        "watcher_running": notification_watcher._is_running,
        "listeners": len(notification_watcher.active_listeners),
        "stats": notification_engine.stats,
    }


@app.post("/notify/sos")
async def trigger_sos_notification(
    payload: Dict[str, Any],
    authorization: Optional[str] = Header(None),
):
    caller = await run_in_threadpool(authenticate, authorization)
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
):
    caller = await run_in_threadpool(authenticate, authorization)
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
):
    caller = await run_in_threadpool(authenticate, authorization)
    chat_id = payload.get("chatId", "")
    sender_id = payload.get("senderId", "")
    text = payload.get("text", "")
    message_type = payload.get("type", "text")

    # Only a member of the conversation can notify it, and only as themselves.
    participants = await run_in_threadpool(chat_db.participants_of, chat_id)
    if participants is None or caller.uid not in participants or sender_id != caller.uid:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only notify a chat you are in, as yourself.",
        )

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
):
    caller = await run_in_threadpool(authenticate, authorization)
    await run_in_threadpool(require_platform_admin, caller)
    res = await run_in_threadpool(notification_engine.run_retention_sweep)
    return res
