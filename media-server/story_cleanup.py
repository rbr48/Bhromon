"""Removes stories past their 24 hours, and the files that nothing else uses.

The app shows a story for 24 hours and hides it after that, but nothing deleted it, so
stories and their files grew forever. Once a day, at 04:00 in Dhaka, this removes the
expired stories a batch at a time. A file is removed only when no post, story or
highlight of its tour still uses it, so a file that is shared, or a highlight's cover,
is always kept. Stored paths come from data that clients write, so each one is checked
against strict patterns before anything is deleted.
"""

import logging
import re
import threading
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

import family_dates

logger = logging.getLogger("bhromon.story_cleanup")

STORY_LIFETIME = timedelta(hours=24)
RUN_HOUR_DHAKA = 4
BATCH_SIZE = 200
MAX_BATCHES_PER_RUN = 25
POLL_SECONDS = 60

# Only these folders hold a story's files or a post's files, and only those are removed.
SWEPT_FOLDERS = frozenset({"posts", "reels", "covers", "stories"})
_SAFE_TOUR = re.compile(r"[A-Za-z0-9_-]{1,64}")
_SAFE_FILE = re.compile(r"[0-9a-f]{32}\.[a-z0-9]{2,5}")

# Every field that can hold one of these files, and whether the field is a list.
IN_USE_FIELDS: Tuple[Tuple[str, str, bool], ...] = (
    ("posts", "images", True),
    ("posts", "videoUrl", False),
    ("posts", "coverUrl", False),
    ("posts", "audioUrl", False),
    ("stories", "mediaUrl", False),
    ("stories", "videoUrl", False),
    ("highlights", "coverUrl", False),
)


def media_location(url: Any, base_url: str) -> Optional[Tuple[str, str, str]]:
    """(tour, folder, filename) of one of this server's media URLs, or None.

    Only a URL that fits the strict patterns counts, so a crafted path cannot point
    outside the media folders.
    """
    prefix = base_url.rstrip("/") + "/"
    if not isinstance(url, str) or not url.startswith(prefix):
        return None
    parts = url[len(prefix):].split("/")
    if len(parts) != 3:
        return None
    tour, folder, filename = parts
    if not _SAFE_TOUR.fullmatch(tour) or folder not in SWEPT_FOLDERS:
        return None
    if not _SAFE_FILE.fullmatch(filename):
        return None
    return tour, folder, filename


def file_in_use(db: Any, tour_id: str, url: str) -> bool:
    """Whether a post, story or highlight of the tour still uses the file at `url`.

    Raises when the check cannot be made, so the caller keeps the file.
    """
    tour = db.collection("tours").document(tour_id)
    for collection, field, is_list in IN_USE_FIELDS:
        query = tour.collection(collection)
        if is_list:
            query = query.where(field, "array_contains", url)
        else:
            query = query.where(field, "==", url)
        if any(True for _ in query.limit(1).stream()):
            return True
    return False


def remove_media_file(media_root: Path, meta_root: Path, tour: str, folder: str, filename: str) -> bool:
    """Deletes one media file and its upload sidecar. Returns False when there was nothing to delete."""
    if not (_SAFE_TOUR.fullmatch(tour) and folder in SWEPT_FOLDERS and _SAFE_FILE.fullmatch(filename)):
        return False
    target = media_root / tour / folder / filename
    if not target.is_file():
        return False
    target.unlink()
    (meta_root / tour / folder / f"{filename}.json").unlink(missing_ok=True)
    return True


def run_story_cleanup(
    db: Any,
    media_root: Path,
    meta_root: Path,
    now: datetime,
    *,
    base_url: str,
    purge: Callable[[List[str]], None],
    batch: int = BATCH_SIZE,
    max_batches: int = MAX_BATCHES_PER_RUN,
) -> Dict[str, int]:
    """Removes expired stories, `batch` at a time, and the files that nothing else uses.

    A run goes on through batches until none are left, or until `max_batches` have been
    handled, so a large backlog is cleared over a few runs and a stuck story cannot loop
    forever. `purge` clears the removed paths from the CDN once, at the end, and its
    failure is logged, because the files are already gone from the server.
    """
    now_utc = now.astimezone(timezone.utc) if now.tzinfo else now.replace(tzinfo=timezone.utc)
    threshold = now_utc - STORY_LIFETIME
    stats = {"expired": 0, "files_removed": 0, "files_kept": 0, "errors": 0}
    removed: List[str] = []
    for _ in range(max_batches):
        expired = list(
            db.collection_group("stories").where("createdAt", "<", threshold).limit(batch).stream()
        )
        for doc in expired:
            stats["expired"] += 1
            try:
                tour_id = doc.reference.parent.parent.id
                data = doc.to_dict() or {}
                doc.reference.delete()
                for url in dict.fromkeys(filter(None, [data.get("mediaUrl"), data.get("videoUrl")])):
                    located = media_location(url, base_url)
                    if located is None or located[0] != tour_id:
                        continue  # Not this tour's media on this server: nothing to remove here.
                    try:
                        in_use = file_in_use(db, tour_id, url)
                    except Exception as error:
                        logger.error("Could not check use of %s, keeping it: %s", url, error)
                        in_use = True
                    if in_use:
                        stats["files_kept"] += 1
                        continue
                    if remove_media_file(media_root, meta_root, *located):
                        stats["files_removed"] += 1
                        removed.append("/".join(located))
            except Exception as error:
                stats["errors"] += 1
                logger.error("Story cleanup failed for %s: %s", doc.reference.path, error)
        if len(expired) < batch:
            break
    if removed:
        try:
            purge(removed)
        except Exception as error:
            logger.error("CDN purge after story cleanup failed: %s", error)
    return stats


class StoryCleanupScheduler:
    """Runs the cleanup once a day, from 04:00 Dhaka time, in a background thread.

    A run that was missed (the server was down) happens as soon as the server is up
    that day. A failed run is tried again after `family_dates.RETRY_AFTER`.
    """

    def __init__(
        self,
        run: Callable[[datetime], Dict[str, int]],
        *,
        clock: Optional[Callable[[], datetime]] = None,
        poll_seconds: float = POLL_SECONDS,
    ) -> None:
        self._run = run
        self._clock = clock or (lambda: datetime.now(timezone.utc))
        self._poll_seconds = poll_seconds
        self._stop = threading.Event()
        self._thread: Optional[threading.Thread] = None
        self._last_run_day: Optional[str] = None
        self._retry_after: Optional[datetime] = None

    def start(self) -> None:
        if self._thread is not None and self._thread.is_alive():
            return
        self._stop.clear()
        self._thread = threading.Thread(target=self._loop, name="story-cleanup", daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=5)

    def run_if_due(self) -> bool:
        """Runs the cleanup when today's run is due. Returns True when a run happened."""
        now = self._clock()
        if not family_dates.is_run_due(now, self._last_run_day, self._retry_after, run_hour=RUN_HOUR_DHAKA):
            return False
        today = family_dates.dhaka_day_key(now)
        try:
            stats = self._run(now)
        except Exception as error:
            self._retry_after = now + family_dates.RETRY_AFTER
            logger.error("Story cleanup run failed; retrying after %s: %s", family_dates.RETRY_AFTER, error)
            return False
        self._last_run_day = today
        self._retry_after = None
        logger.info("Story cleanup for %s: %s", today, stats)
        return True

    def _loop(self) -> None:
        while not self._stop.is_set():
            try:
                self.run_if_due()
            except Exception:
                logger.exception("Story cleanup scheduler error")
            self._stop.wait(self._poll_seconds)

