"""Limits on how much media a tour and a person may store, and how fast uploads may come.

The media server is one small VPS that also runs chat, news, games and notifications.
A full disk would stop all of them, so storage is limited per tour, per person within
a tour, and by a floor of free disk. Uploads are also rate-limited per person.

Every limit can be set with an environment variable; the defaults are the ones the
app was built for. The storage totals are read from the upload sidecars, so they
follow deletes and purges without a separate counter to keep in step.
"""

import json
import os
import shutil
import threading
import time
from collections import deque
from pathlib import Path
from typing import Callable, Deque, Dict, Tuple

GiB = 1024 ** 3


def _env_int(name: str, default: int) -> int:
    raw = os.getenv(name, "").strip()
    try:
        return int(raw) if raw else default
    except ValueError:
        return default


TOUR_QUOTA_BYTES = _env_int("MEDIA_TOUR_QUOTA_BYTES", 20 * GiB)
UPLOADER_QUOTA_BYTES = _env_int("MEDIA_UPLOADER_QUOTA_BYTES", 4 * GiB)
MIN_FREE_BYTES = _env_int("MEDIA_MIN_FREE_BYTES", 5 * GiB)
UPLOADS_PER_MINUTE = _env_int("MEDIA_UPLOADS_PER_MINUTE", 60)


class LimitExceeded(Exception):
    """A limit was reached. [status_code] and [detail] are shown to the caller."""

    def __init__(self, status_code: int, detail: str) -> None:
        super().__init__(detail)
        self.status_code = status_code
        self.detail = detail


def free_bytes(path: Path) -> int:
    """Free space on the disk that holds [path] (or the nearest parent that exists)."""
    probe = path
    while not probe.exists() and probe != probe.parent:
        probe = probe.parent
    return shutil.disk_usage(probe).free


def check_free_disk(media_root: Path, min_free: int) -> None:
    if free_bytes(media_root) < min_free:
        raise LimitExceeded(507, "The media server is nearly full. Try again later.")


class RateLimiter:
    """Allows at most `per_minute` events per key in any sliding minute."""

    def __init__(self, per_minute: int, clock: Callable[[], float] = time.monotonic) -> None:
        self._per_minute = per_minute
        self._clock = clock
        self._recent: Dict[str, Deque[float]] = {}
        self._lock = threading.Lock()

    def allow(self, key: str) -> bool:
        now = self._clock()
        with self._lock:
            window = self._recent.setdefault(key, deque())
            while window and now - window[0] >= 60:
                window.popleft()
            if len(window) >= self._per_minute:
                return False
            window.append(now)
            return True


def tour_usage(meta_root: Path, media_root: Path, tour_id: str) -> Tuple[int, Dict[str, int]]:
    """The bytes stored for a tour, and the bytes each uploader stored in it.

    A file saved before sidecars recorded its size is counted by its size on disk.
    """
    total = 0
    by_uploader: Dict[str, int] = {}
    for meta_file in (meta_root / tour_id).glob("*/*.json"):
        try:
            meta = json.loads(meta_file.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if not isinstance(meta, dict):
            continue
        size = meta.get("bytes")
        if not isinstance(size, int):
            media = media_root / tour_id / meta_file.parent.name / meta_file.name[: -len(".json")]
            try:
                size = media.stat().st_size
            except OSError:
                size = 0
        total += size
        uploader = str(meta.get("uploaderEmail", "")).strip().lower()
        by_uploader[uploader] = by_uploader.get(uploader, 0) + size
    return total, by_uploader


def check_storage(
    meta_root: Path,
    media_root: Path,
    tour_id: str,
    uploader: str,
    size: int,
    *,
    tour_quota: int,
    uploader_quota: int,
) -> None:
    """Raises unless `size` more bytes fit in the tour and in the uploader's share of it."""
    total, by_uploader = tour_usage(meta_root, media_root, tour_id)
    if total + size > tour_quota:
        raise LimitExceeded(507, "This trip has reached its media storage limit.")
    if by_uploader.get(uploader.strip().lower(), 0) + size > uploader_quota:
        raise LimitExceeded(
            507, "You have reached your media storage limit for this trip."
        )

