"""Clears cached copies of deleted media from the CDN.

The CDN keeps a copy of each media file for a while, so a deleted file can stay
reachable until that copy expires. Cloudflare's purge_cache removes the copies at
once. Nothing is sent until the zone and token are set in the Firestore document
config/cdn, the same settings the Cloud Functions use.
"""

import json
import logging
import urllib.parse
import urllib.request
from typing import Callable, Dict, List, Optional, Sequence

logger = logging.getLogger("media-server.cdn")

CLOUDFLARE_API = "https://api.cloudflare.com/client/v4"
MEDIA_BASE_URL = "https://bhromon.fun/media"
# Cloudflare accepts this many file URLs in one purge request.
MAX_FILES_PER_REQUEST = 30
TIMEOUT_SECONDS = 10

ReadConfig = Callable[[], Optional[Dict]]
Send = Callable[[str, Dict[str, str], Dict], None]


def media_urls_for(paths: Sequence[str], base_url: str = MEDIA_BASE_URL) -> List[str]:
    """The public URLs of media files, from their paths (tour/folder/file)."""
    return [f"{base_url.rstrip('/')}/{path.lstrip('/')}" for path in paths]


def chunk_urls(urls: Sequence[str], size: int = MAX_FILES_PER_REQUEST) -> List[List[str]]:
    """The URLs split into the batches Cloudflare accepts."""
    return [list(urls[start:start + size]) for start in range(0, len(urls), size)]


def post_json(url: str, headers: Dict[str, str], body: Dict) -> None:
    """Sends one purge request. Raises when Cloudflare does not confirm it."""
    request = urllib.request.Request(
        url,
        data=json.dumps(body).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
        payload = json.loads(response.read().decode("utf-8") or "{}")
    if payload.get("success") is not True:
        raise RuntimeError("the CDN did not confirm the purge")


def purge_paths(paths: Sequence[str], read_config: ReadConfig, send: Send = post_json) -> int:
    """Purges the media at `paths`. Returns how many URLs were sent.

    Does nothing, and returns 0, until the zone and token are set in config/cdn.
    """
    if not paths:
        return 0
    config = read_config() or {}
    zone = config.get("zoneId")
    token = config.get("apiToken")
    if not isinstance(zone, str) or not zone or not isinstance(token, str) or not token:
        return 0

    url = f"{CLOUDFLARE_API}/zones/{urllib.parse.quote(zone, safe='')}/purge_cache"
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    sent = 0
    for files in chunk_urls(media_urls_for(paths)):
        send(url, headers, {"files": files})
        sent += len(files)
    return sent
