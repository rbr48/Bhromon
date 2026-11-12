"""Purge and manual/admin reminder routes for the Bhromon media server.

Reads runtime configuration and dependencies (`MEDIA_ROOT`, `META_ROOT`, `PURGE_KEY`,
`ACK_REMINDER_RUN_KEY`, `backend`, `notification_engine`, `send_ack_ping`) from `main`
at call time so tests that monkeypatch `main.*` attributes take effect immediately.
"""

from datetime import datetime, timezone
import json
import re
import secrets
import shutil
from typing import List, Optional

from fastapi import APIRouter, Header, HTTPException, status
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel

from ack_reminders import PingRefused

purge_router = APIRouter()

NOTICE_ID_PATTERN = re.compile(r"[A-Za-z0-9_-]{1,128}")


class PurgeRequest(BaseModel):
    tourId: str
    uploaderEmail: Optional[str] = None


class AccountPurgeRequest(BaseModel):
    uid: str
    email: str


class NoticePingRequest(BaseModel):
    tourId: str
    noticeId: str


def purge_tour_files(tour_id: str, uploader: Optional[str]) -> List[str]:
    """Deletes one uploader's files in a tour, or every file of the tour.

    An uploader is matched on the sidecar written when each file was saved.
    Files saved before sidecars existed have no uploader, so they only go with
    the whole tour. Returns the paths removed, relative to the tour's folder.
    """
    import main

    if uploader is None:
        tour_dir = main.MEDIA_ROOT / tour_id
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
        shutil.rmtree(main.META_ROOT / tour_id, ignore_errors=True)
        return removed

    removed: List[str] = []
    for meta_file in (main.META_ROOT / tour_id).glob("*/*.json"):
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
        (main.MEDIA_ROOT / tour_id / folder / filename).unlink(missing_ok=True)
        meta_file.unlink(missing_ok=True)
        removed.append(f"{folder}/{filename}")
    return removed


def purge_user_files(email: str) -> List[str]:
    """Deletes every file `email` uploaded, in every tour and space. Returns the paths removed."""
    import main

    removed: List[str] = []
    if not main.META_ROOT.is_dir():
        return removed
    for meta_file in main.META_ROOT.glob("*/*/*.json"):
        try:
            meta = json.loads(meta_file.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if (
            not isinstance(meta, dict)
            or str(meta.get("uploaderEmail", "")).strip().lower() != email
        ):
            continue
        tour_id = meta_file.parent.parent.name
        folder = meta_file.parent.name
        filename = meta_file.name[: -len(".json")]
        (main.MEDIA_ROOT / tour_id / folder / filename).unlink(missing_ok=True)
        meta_file.unlink(missing_ok=True)
        removed.append(f"{tour_id}/{folder}/{filename}")
    return removed


def _require_purge_key(provided: Optional[str]) -> None:
    """Refuses a purge unless the back end sent the purge key this server was given."""
    import main

    if not main.PURGE_KEY:
        raise HTTPException(status_code=503, detail="Purging is not configured.")
    if not provided or not secrets.compare_digest(
        provided.encode("utf-8"), main.PURGE_KEY.encode("utf-8")
    ):
        raise HTTPException(status_code=401, detail="Wrong purge key.")


def _require_ack_reminder_key(provided: Optional[str]) -> None:
    """Refuses a manual reminder run unless the operator sent the key this server was given."""
    import main

    if not main.ACK_REMINDER_RUN_KEY:
        raise HTTPException(
            status_code=503, detail="Manual reminder runs are not configured."
        )
    if not provided or not secrets.compare_digest(
        provided.encode("utf-8"), main.ACK_REMINDER_RUN_KEY.encode("utf-8")
    ):
        raise HTTPException(status_code=401, detail="Wrong reminder key.")


@purge_router.post("/internal/ack-reminders/run")
async def run_ack_reminders_now(x_ack_reminder_key: Optional[str] = Header(None)):
    """Runs the answer reminders once, now.

    The media server runs them every 15 minutes on its own. This lets an operator, or a
    cron job on the VPS, run them on demand. A run that finds nothing due sends nothing,
    and each reminder is claimed once, so repeating the call is safe.
    """
    import main

    _require_ack_reminder_key(x_ack_reminder_key)
    return await run_in_threadpool(
        main.run_ack_reminders,
        main.backend._client(),
        main.notification_engine,
        datetime.now(timezone.utc),
    )


@purge_router.post("/notify/notice/ping")
async def ping_notice(
    body: NoticePingRequest,
    authorization: Optional[str] = Header(None),
):
    """An owner or admin reminds the members who have not answered a notice, now.

    The push is the scheduled answer reminder's. A notice can be pinged once every
    30 minutes (ack_reminders.PING_GAP); an earlier ping gets 429 with Retry-After.
    """
    import main

    caller = await run_in_threadpool(main.authenticate, authorization)
    main.check_tour_id(body.tourId)
    if not NOTICE_ID_PATTERN.fullmatch(body.noticeId):
        raise HTTPException(status_code=400, detail="Invalid notice id.")
    role = await run_in_threadpool(main.backend.role_for, body.tourId, caller.email)
    if role not in {"owner", "admin"}:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the group's owner or an admin can send a reminder.",
        )
    try:
        return await run_in_threadpool(
            main.send_ack_ping,
            main.backend._client(),
            main.notification_engine,
            body.tourId,
            body.noticeId,
            datetime.now(timezone.utc),
        )
    except PingRefused as refused:
        detail = {"reason": refused.reason, "retryAfter": refused.retry_after}
        if refused.reason == "not_found":
            raise HTTPException(status_code=404, detail=detail)
        if refused.reason == "too_soon":
            raise HTTPException(
                status_code=429,
                detail=detail,
                headers={"Retry-After": str(refused.retry_after)},
            )
        raise HTTPException(status_code=409, detail=detail)


@purge_router.post("/purge")
async def purge_tour_content(
    body: PurgeRequest,
    x_purge_key: Optional[str] = Header(None),
):
    """Removes a tour's files on the request of the Bhromon back end.

    With an uploader email, only that person's files in the tour go. Without
    one, every file of the tour goes. The response lists the paths removed, so
    the back end can clear the links that pointed to them.
    """
    import main

    _require_purge_key(x_purge_key)
    main.check_tour_id(body.tourId)
    uploader = body.uploaderEmail.strip().lower() if body.uploaderEmail else None
    removed = await run_in_threadpool(purge_tour_files, body.tourId, uploader)
    return {"removed": len(removed), "paths": removed}


@purge_router.post("/purge/account")
async def purge_account_content(
    body: AccountPurgeRequest,
    x_purge_key: Optional[str] = Header(None),
):
    """Removes what one person left here when their account is closed.

    That is every file they uploaded, in any space, and their part in the chat
    service. The back end calls this before it deletes the sign-in account, so a
    failure can be retried. Repeating the call is harmless.
    """
    import main

    _require_purge_key(x_purge_key)
    uid = body.uid.strip()
    email = body.email.strip().lower()
    if not main.TOUR_ID_PATTERN.fullmatch(uid) or "@" not in email:
        raise HTTPException(
            status_code=400, detail="A uid and an email are required."
        )
    files = await run_in_threadpool(purge_user_files, email)
    chat_counts = await run_in_threadpool(main.chat_db.erase_user, uid, email)
    return {"files": len(files), "paths": files, "chat": chat_counts}
