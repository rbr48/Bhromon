"""Bhromon media server.

Files are stored at MEDIA_ROOT/{tourId}/{folder}/{objectId}{ext} and served by
nginx under /media/. Every upload and delete needs a Firebase ID token from an
active member of the tour. A delete is allowed for the file's uploader, or for
a tour owner or admin. Ownership is recorded in a metadata file kept outside the
public tree.

There is no shared upload key. An old app build that still sends one is refused.
"""

import asyncio
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
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import aiofiles
from fastapi import FastAPI, File, Form, Header, HTTPException, Request, Response, UploadFile, status
from fastapi.concurrency import run_in_threadpool
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

import cdn
import chat
import limits
import media_access
import news
from chat import chat_db, chat_is_encrypted, chat_router
from ack_reminders import AckReminderScheduler, run_ack_reminders
from family_dates import FamilyDateReminderScheduler
from session_reminders import SessionReminderScheduler, run_session_reminders
from news import router as news_router
from story_cleanup import StoryCleanupScheduler, run_story_cleanup
from call_cleanup import run_call_cleanup
from journey_cleanup import run_journey_event_cleanup
import live
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
# Optional. Lets an operator run the answer reminders on demand; unset, that is refused.
ACK_REMINDER_RUN_KEY = os.getenv("ACK_REMINDER_RUN_KEY", "")
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
    "expenses", "study",
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

notification_engine = NotificationEngine(chat_db=chat_db)
notification_watcher = FirestoreNotificationWatcher(notification_engine)
family_date_scheduler = FamilyDateReminderScheduler(notification_engine)
ack_reminder_scheduler = AckReminderScheduler(
    lambda: run_ack_reminders(
        backend._client(), notification_engine, datetime.now(timezone.utc)
    )
)
session_reminder_scheduler = SessionReminderScheduler(
    lambda: run_session_reminders(
        backend._client(), notification_engine, datetime.now(timezone.utc)
    )
)
def run_daily_cleanup(now: datetime) -> Dict[str, Any]:
    """The 04:00 run: expired stories and their files, then old call records."""
    db = backend._client()
    stories = run_story_cleanup(
        db,
        MEDIA_ROOT,
        META_ROOT,
        now,
        base_url=BASE_URL,
        purge=purge_cdn_quietly,
    )
    try:
        calls = run_call_cleanup(db, now)
    except Exception as error:
        logger.error("Call cleanup failed: %s", error)
        calls = {"deleted": 0, "errors": 1}
    try:
        journey = run_journey_event_cleanup(db, now)
    except Exception as error:
        logger.error("Journey event cleanup failed: %s", error)
        journey = {"deleted": 0, "errors": 1}
    return {
        **stories,
        "calls_deleted": calls["deleted"],
        "call_errors": calls["errors"],
        "journey_events_deleted": journey["deleted"],
        "journey_event_errors": journey["errors"],
    }


story_cleanup_scheduler = StoryCleanupScheduler(run_daily_cleanup)


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

    # Start the watcher and the family-date reminders if Firebase credentials exist
    if FIREBASE_CREDENTIALS or os.path.exists("/run/secrets/firebase-admin.json"):
        notification_watcher.start()
        family_date_scheduler.start()
        story_cleanup_scheduler.start()
        ack_reminder_scheduler.start()
        session_reminder_scheduler.start()
    # The live relay drops members who have been silent for two minutes.
    live_sweep = asyncio.create_task(live.sweep_forever())
    yield
    # Stop them on shutdown
    live_sweep.cancel()
    ack_reminder_scheduler.stop()
    session_reminder_scheduler.stop()
    story_cleanup_scheduler.stop()
    family_date_scheduler.stop()
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
app.include_router(live.router, prefix="/api")

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=False,
    allow_methods=["GET", "POST", "DELETE", "OPTIONS"],
    allow_headers=["*"],
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

# The live journey relay (roadmap LJ-4.4) checks a member's ID token, and that the
# member is an active member of the tour, before it lets them in.
live.configure(
    identify=lambda token: backend.identity_for_token(token),
    is_member=lambda tour_id, email: backend.role_for(tour_id, email) is not None,
)

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


# The official Bhromon feed: posts the team publishes for everyone signed in. Only the
# publisher writes it (publish_official_post), and nothing records who reads it.
OFFICIAL_SPACE = "official"
OFFICIAL_TOPIC = "official_instafeed"
OFFICIAL_PUBLISH_KEY = os.getenv("OFFICIAL_PUBLISH_KEY", "")
OFFICIAL_IMAGE_EXTENSIONS = frozenset({".jpg", ".jpeg", ".png", ".webp"})
MAX_OFFICIAL_CAPTION = 300
MAX_OFFICIAL_DURATION_SECONDS = 3600

PUBLIC_OR_USER_SPACES = frozenset({
    "profiles", "users", "general", "explorer", "trip_logs", OFFICIAL_SPACE,
})

# Private media. The secret derives each person's link key (media_access.py). With
# enforcement off, a request that fails the check is logged and still served, so the app
# can roll out before the check is enforced.
MEDIA_ACCESS_SECRET = os.getenv("MEDIA_ACCESS_SECRET", "").encode("utf-8")
MEDIA_ACCESS_ENFORCE = os.getenv("MEDIA_ACCESS_ENFORCE", "0").strip() == "1"
media_decisions = media_access.AccessDecisions()
MEDIA_PATH = re.compile(r"/media/([A-Za-z0-9_-]{1,128})/([a-z_]{1,32})/([^/]+)")


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


def can_read_space(space: str, caller: Caller) -> bool:
    """Whether the caller may read files in the space. The rules are the same as for uploads."""
    try:
        require_member(space, caller)
    except HTTPException:
        return False
    return True


def media_read_decision(raw_uri: str) -> Tuple[bool, str]:
    """Whether nginx may serve a media file, and why. The reason never includes the link."""
    path = raw_uri.partition("?")[0]
    match = MEDIA_PATH.fullmatch(path)
    if match is None or FILENAME_PATTERN.fullmatch(match.group(3)) is None:
        return False, "not a media file"
    space, folder, _filename = match.groups()
    if folder not in ALLOWED_FOLDERS:
        return False, "unknown folder"
    if not media_access.secret_is_usable(MEDIA_ACCESS_SECRET):
        return False, "private media is not configured"
    link = media_access.parse_link(raw_uri)
    if link is None:
        return False, "unsigned link"
    _path, uid, signature = link
    if not media_access.signature_is_valid(MEDIA_ACCESS_SECRET, path, uid, signature):
        return False, "bad signature"
    try:
        email = backend.email_for_uid(uid)
        if not email:
            return False, "no verified account"
        caller = Caller(email=email, uid=uid)
        allowed = media_decisions.allowed(uid, space, lambda: can_read_space(space, caller))
    except Exception as error:  # Fail closed: a check that fails refuses the file.
        logger.error("Media access check failed: %s: %s", type(error).__name__, error)
        return False, "check failed"
    return (True, "allowed") if allowed else (False, "not a member of that space")


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


def write_meta(
    tour_id: str,
    folder: str,
    filename: str,
    caller: Caller,
    size: Optional[int] = None,
) -> None:
    path = meta_path_for(tour_id, folder, filename)
    path.parent.mkdir(parents=True, exist_ok=True)
    record: Dict[str, Any] = {
        "uploaderEmail": caller.email,
        "tourId": tour_id,
        "folder": folder,
    }
    if size is not None:
        record["bytes"] = size
    path.write_text(json.dumps(record), encoding="utf-8")


# One limiter for the whole server: the app runs as a single worker process.
upload_limiter = limits.RateLimiter(limits.UPLOADS_PER_MINUTE)


async def enforce_upload_budget(email: str) -> None:
    """Refuses an upload when the disk is nearly full or the person is uploading too fast."""
    if not upload_limiter.allow(email):
        raise HTTPException(
            status_code=429,
            detail="Too many uploads. Try again in a minute.",
        )
    try:
        await run_in_threadpool(limits.check_free_disk, MEDIA_ROOT, limits.MIN_FREE_BYTES)
    except limits.LimitExceeded as error:
        raise HTTPException(status_code=error.status_code, detail=error.detail)


async def enforce_storage(tour_id: str, email: str, size: int) -> None:
    """Refuses a new file that would take the tour, or the person's share of it, past its limit."""
    try:
        await run_in_threadpool(
            limits.check_storage,
            META_ROOT,
            MEDIA_ROOT,
            tour_id,
            email,
            size,
            tour_quota=limits.TOUR_QUOTA_BYTES,
            uploader_quota=limits.UPLOADER_QUOTA_BYTES,
        )
    except limits.LimitExceeded as error:
        raise HTTPException(status_code=error.status_code, detail=error.detail)


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
            "active_listeners": len(notification_watcher.active_listeners),
            "device_tokens": chat_db.count_device_tokens(),
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
    await enforce_upload_budget(caller.email)

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
                await enforce_storage(tourId, caller.email, total_bytes)
                await run_in_threadpool(
                    write_meta, tourId, folder, filename, caller, total_bytes
                )
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


def _require_official_publisher(provided_key: Optional[str], authorization: Optional[str]) -> None:
    """Lets only the team publish to the official feed: with the publish key, or as a platform admin."""
    if OFFICIAL_PUBLISH_KEY and provided_key and secrets.compare_digest(
        provided_key.encode("utf-8"), OFFICIAL_PUBLISH_KEY.encode("utf-8")
    ):
        return
    require_platform_admin(authenticate(authorization))


async def store_official_file(upload: UploadFile, folder: str, filename: str, max_allowed: int) -> str:
    """Stores one file of the official feed and returns its public address."""
    target_dir = MEDIA_ROOT / OFFICIAL_SPACE / folder
    target_dir.mkdir(parents=True, exist_ok=True)
    target = target_dir / filename
    part = target_dir / f".{filename}.{uuid.uuid4().hex}.part"
    try:
        await store_stream(upload, part, max_allowed)
        # A hard link never replaces an existing file.
        os.link(part, target)
    finally:
        part.unlink(missing_ok=True)
    return f"{BASE_URL.rstrip('/')}/{OFFICIAL_SPACE}/{folder}/{filename}"


def create_official_post(
    post_id: str,
    caption: str,
    video_url: Optional[str] = None,
    cover_url: Optional[str] = None,
    duration_seconds: Optional[int] = None,
    image_url: Optional[str] = None,
    kind: str = "reel",
) -> None:
    """Writes the feed entry the app reads. Only the server writes these."""
    data = {
        "caption": caption,
        "kind": kind,
        "publisher": "Bhromon",
        "createdAt": datetime.now(timezone.utc),
        "videoUrl": video_url,
        "coverUrl": cover_url,
    }
    if image_url is not None:
        data["imageUrl"] = image_url
        if not data["coverUrl"]:
            data["coverUrl"] = image_url
    if duration_seconds is not None:
        data["durationSeconds"] = duration_seconds

    backend._client().collection("official_instafeed").document(post_id).set(data)


@app.post("/official/posts")
async def publish_official_post(
    file: UploadFile = File(...),
    caption: str = Form(""),
    durationSeconds: Optional[int] = Form(None),
    cover: Optional[UploadFile] = File(None),
    x_official_key: Optional[str] = Header(None),
    authorization: Optional[str] = Header(None),
):
    """Publishes a video or image to the official feed, for everyone signed in to read."""
    await run_in_threadpool(_require_official_publisher, x_official_key, authorization)
    text = caption.strip()
    if len(text) > MAX_OFFICIAL_CAPTION:
        raise HTTPException(status_code=400, detail="The caption is too long.")
    if durationSeconds is not None and not 0 < durationSeconds <= MAX_OFFICIAL_DURATION_SECONDS:
        raise HTTPException(status_code=400, detail="The duration is out of range.")
    ext = extension_of(file.filename)
    is_video = ext in VIDEO_EXTENSIONS
    is_image = ext in OFFICIAL_IMAGE_EXTENSIONS
    if not is_video and not is_image:
        raise HTTPException(status_code=400, detail="The post must be a video or an image.")
    cover_ext = ""
    if cover is not None and cover.filename:
        cover_ext = extension_of(cover.filename)
        if cover_ext not in OFFICIAL_IMAGE_EXTENSIONS:
            raise HTTPException(status_code=400, detail="The cover must be an image.")

    post_id = uuid.uuid4().hex
    if is_video:
        video_url = await store_official_file(file, "reels", f"{post_id}{ext}", MAX_VIDEO_BYTES)
        cover_url = None
        if cover_ext:
            cover_url = await store_official_file(cover, "covers", f"{post_id}{cover_ext}", MAX_IMAGE_BYTES)
        await run_in_threadpool(
            create_official_post,
            post_id,
            text,
            video_url=video_url,
            cover_url=cover_url,
            duration_seconds=durationSeconds,
            kind="reel",
        )
        await run_in_threadpool(
            notification_engine.send_topic_push,
            OFFICIAL_TOPIC,
            "Bhromon",
            text or "A new post in the official feed",
            {"action": "official", "postId": post_id},
        )
        return {"status": "success", "id": post_id, "videoUrl": video_url, "coverUrl": cover_url, "kind": "reel"}
    else:
        image_url = await store_official_file(file, "images", f"{post_id}{ext}", MAX_IMAGE_BYTES)
        await run_in_threadpool(
            create_official_post,
            post_id,
            text,
            image_url=image_url,
            cover_url=image_url,
            kind="image",
        )
        await run_in_threadpool(
            notification_engine.send_topic_push,
            OFFICIAL_TOPIC,
            "Bhromon",
            text or "A new post in the official feed",
            {"action": "official", "postId": post_id},
        )
        return {"status": "success", "id": post_id, "imageUrl": image_url, "coverUrl": image_url, "kind": "image"}


def read_cdn_config() -> Optional[Dict]:
    """The CDN settings in Firestore (config/cdn), or None when none are set."""
    snapshot = backend._client().collection("config").document("cdn").get()
    return snapshot.to_dict() if snapshot.exists else None


def purge_cdn_quietly(paths: List[str]) -> None:
    """Clears the CDN's copies of `paths`. A failure is logged, not raised: the file
    is already gone from the server, and the cached copy expires on its own."""
    try:
        cdn.purge_paths(paths, read_cdn_config, send=cdn.post_json)
    except Exception as error:
        logger.error("CDN purge failed for %s: %s", paths, error)


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
    await run_in_threadpool(purge_cdn_quietly, [f"{tourId}/{folder}/{filename}"])
    return {"status": "deleted", "path": f"{tourId}/{folder}/{filename}"}


class CopyRequest(BaseModel):
    tourId: str
    folder: str
    sourceUrl: str


def media_location_of(url: str, tour_id: str) -> Optional[Tuple[str, str]]:
    """(folder, filename) of a media URL of `tour_id`, or None for any other URL."""
    prefix = f"{BASE_URL.rstrip('/')}/{tour_id}/"
    if not url.startswith(prefix):
        return None
    parts = url[len(prefix):].split("/")
    if len(parts) != 2:
        return None
    folder, filename = parts
    if folder not in ALLOWED_FOLDERS or not FILENAME_PATTERN.fullmatch(filename):
        return None
    return folder, filename


@app.post("/copy")
async def copy_media(
    body: CopyRequest,
    authorization: Optional[str] = Header(None),
):
    """Makes the caller's own name for a file of the same tour (a reshare).

    The copy is a hard link to the original's bytes, so the two names share one
    copy of the data: deleting either name leaves the other intact. The copy is
    recorded as the caller's, so it is removed with their own content.
    """
    caller = await run_in_threadpool(authenticate, authorization)
    check_tour_id(body.tourId)
    check_folder(body.folder)
    await run_in_threadpool(require_member, body.tourId, caller)

    location = media_location_of(body.sourceUrl, body.tourId)
    if location is None:
        raise HTTPException(
            status_code=400,
            detail="Only media of this tour can be copied.",
        )
    source_folder, source_name = location
    source = MEDIA_ROOT / body.tourId / source_folder / source_name
    if not source.is_file():
        raise HTTPException(status_code=404, detail="The file to copy is gone.")
    size = source.stat().st_size
    await enforce_upload_budget(caller.email)
    await enforce_storage(body.tourId, caller.email, size)

    filename = f"{uuid.uuid4().hex}{Path(source_name).suffix}"
    target_dir = MEDIA_ROOT / body.tourId / body.folder
    target_dir.mkdir(parents=True, exist_ok=True)
    target = target_dir / filename
    try:
        os.link(source, target)
    except OSError as error:
        logger.error("Could not link %s for a copy: %s", source, error)
        raise HTTPException(status_code=500, detail="The copy could not be made.")
    try:
        await run_in_threadpool(
            write_meta, body.tourId, body.folder, filename, caller, size
        )
    except Exception:
        target.unlink(missing_ok=True)
        raise

    return {
        "status": "success",
        "url": f"{BASE_URL.rstrip('/')}/{body.tourId}/{body.folder}/{filename}",
        "filename": filename,
    }


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


def _require_ack_reminder_key(provided: Optional[str]) -> None:
    """Refuses a manual reminder run unless the operator sent the key this server was given."""
    if not ACK_REMINDER_RUN_KEY:
        raise HTTPException(status_code=503, detail="Manual reminder runs are not configured.")
    if not provided or not secrets.compare_digest(
        provided.encode("utf-8"), ACK_REMINDER_RUN_KEY.encode("utf-8")
    ):
        raise HTTPException(status_code=401, detail="Wrong reminder key.")


@app.post("/internal/ack-reminders/run")
async def run_ack_reminders_now(x_ack_reminder_key: Optional[str] = Header(None)):
    """Runs the answer reminders once, now.

    The media server runs them every 15 minutes on its own. This lets an operator, or a
    cron job on the VPS, run them on demand. A run that finds nothing due sends nothing,
    and each reminder is claimed once, so repeating the call is safe.
    """
    _require_ack_reminder_key(x_ack_reminder_key)
    return await run_in_threadpool(
        run_ack_reminders, backend._client(), notification_engine, datetime.now(timezone.utc)
    )


@app.api_route("/internal/media-auth", methods=["GET", "HEAD"])
async def media_auth(request: Request):
    """Asked by nginx before it serves a media file: 200 lets it through, 403 refuses it."""
    raw_uri = request.headers.get("x-original-uri", "")
    allowed, reason = await run_in_threadpool(media_read_decision, raw_uri)
    if allowed:
        return Response(status_code=200)
    if MEDIA_ACCESS_ENFORCE:
        logger.info("Media refused: %s", reason)
        return Response(status_code=403)
    logger.info("Media would be refused (log only): %s", reason)
    return Response(status_code=200)


@app.post("/access-key")
async def media_access_key(authorization: Optional[str] = Header(None)):
    """The key the caller's app signs its media links with. Only the caller is given it."""
    caller = await run_in_threadpool(authenticate, authorization)
    if not media_access.secret_is_usable(MEDIA_ACCESS_SECRET):
        raise HTTPException(status_code=503, detail="Private media is not configured on this server.")
    if not media_access.UID_PATTERN.fullmatch(caller.uid):
        raise HTTPException(status_code=400, detail="Unsupported account id.")
    return {"uid": caller.uid, "key": media_access.derive_key(MEDIA_ACCESS_SECRET, caller.uid)}


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

    # The text of an encrypted chat never reaches the server, so none is pushed.
    encrypted = await chat_is_encrypted(chat_id)
    if encrypted:
        text = ""
        message_type = "text"

    res = await run_in_threadpool(
        notification_engine.send_chat_notification,
        chat_id=chat_id,
        sender_id=sender_id,
        text=text,
        message_type=message_type,
        encrypted=encrypted,
    )
    return res


@app.post("/notify/post")
async def trigger_post_notification(
    payload: Dict[str, Any],
    authorization: Optional[str] = Header(None),
):
    caller = await run_in_threadpool(authenticate, authorization)
    tour_id = payload.get("tourId", "")
    post_id = payload.get("postId", "")
    author_name = payload.get("authorName", "A member")
    caption = payload.get("caption", "")
    is_reel = bool(payload.get("isReel", False))
    image_url = payload.get("imageUrl")
    check_tour_id(tour_id)
    await run_in_threadpool(require_member, tour_id, caller)

    res = await run_in_threadpool(
        notification_engine.send_post_notification,
        tour_id=tour_id,
        post_id=post_id,
        author_email=caller.email,
        author_name=author_name,
        caption=caption,
        is_reel=is_reel,
        image_url=image_url,
    )
    return res


@app.post("/notify/comment")
async def trigger_comment_notification(
    payload: Dict[str, Any],
    authorization: Optional[str] = Header(None),
):
    caller = await run_in_threadpool(authenticate, authorization)
    tour_id = payload.get("tourId", "")
    post_id = payload.get("postId", "")
    comment_id = payload.get("commentId", "")
    commenter_name = payload.get("commenterName", "A member")
    text = payload.get("text", "")
    post_author_email = payload.get("postAuthorEmail")
    check_tour_id(tour_id)
    await run_in_threadpool(require_member, tour_id, caller)

    res = await run_in_threadpool(
        notification_engine.send_comment_notification,
        tour_id=tour_id,
        post_id=post_id,
        comment_id=comment_id,
        commenter_email=caller.email,
        commenter_name=commenter_name,
        text=text,
        post_author_email=post_author_email,
    )
    return res


@app.post("/notify/reaction")
async def trigger_reaction_notification(
    payload: Dict[str, Any],
    authorization: Optional[str] = Header(None),
):
    caller = await run_in_threadpool(authenticate, authorization)
    tour_id = payload.get("tourId", "")
    post_id = payload.get("postId", "")
    reactor_name = payload.get("reactorName", "A member")
    reaction = payload.get("reaction", "like")
    post_author_email = payload.get("postAuthorEmail")
    check_tour_id(tour_id)
    await run_in_threadpool(require_member, tour_id, caller)

    res = await run_in_threadpool(
        notification_engine.send_reaction_notification,
        tour_id=tour_id,
        post_id=post_id,
        reactor_email=caller.email,
        reactor_name=reactor_name,
        reaction=reaction,
        post_author_email=post_author_email,
    )
    return res


@app.post("/notify/notice")
async def trigger_notice_notification(
    payload: Dict[str, Any],
    authorization: Optional[str] = Header(None),
):
    caller = await run_in_threadpool(authenticate, authorization)
    tour_id = payload.get("tourId", "")
    notice_id = payload.get("noticeId", "")
    title = payload.get("title", "")
    body = payload.get("body", "")
    priority = payload.get("priority", "normal")
    check_tour_id(tour_id)
    await run_in_threadpool(require_member, tour_id, caller)

    res = await run_in_threadpool(
        notification_engine.send_notice_notification,
        tour_id=tour_id,
        notice_id=notice_id,
        author_email=caller.email,
        title=title,
        body=body,
        priority=priority,
    )
    return res


@app.post("/notify/ledger")
async def trigger_ledger_notification(
    payload: Dict[str, Any],
    authorization: Optional[str] = Header(None),
):
    caller = await run_in_threadpool(authenticate, authorization)
    tour_id = payload.get("tourId", "")
    expense_id = payload.get("expenseId", "")
    payer_name = payload.get("payerName", "A member")
    title = payload.get("title", "trip expense")
    amount_paisa = int(payload.get("amountPaisa", 0))
    check_tour_id(tour_id)
    await run_in_threadpool(require_member, tour_id, caller)

    res = await run_in_threadpool(
        notification_engine.send_ledger_notification,
        tour_id=tour_id,
        expense_id=expense_id,
        added_by_email=caller.email,
        payer_name=payer_name,
        title=title,
        amount_paisa=amount_paisa,
    )
    return res


@app.post("/admin/broadcast")
async def trigger_broadcast_notification(
    payload: Dict[str, Any],
    authorization: Optional[str] = Header(None),
):
    caller = await run_in_threadpool(authenticate, authorization)
    await run_in_threadpool(require_platform_admin, caller)
    title = payload.get("title", "")
    body = payload.get("body", "")
    data = payload.get("data")
    image_url = payload.get("imageUrl")
    if not title or not body:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Title and body are required.",
        )

    res = await run_in_threadpool(
        notification_engine.send_broadcast_notification,
        title=title,
        body=body,
        data=data,
        image_url=image_url,
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
