"""
Bhromon Travel Crawler — HTTP utility with rotation, retries, and rate limiting.
"""
import time
import random
import requests
from typing import Optional
from config import USER_AGENTS, RATE_LIMITS


_last_request_time: dict[str, float] = {}


def _get_domain(url: str) -> str:
    from urllib.parse import urlparse
    return urlparse(url).netloc


def make_session(cookies: Optional[dict] = None) -> requests.Session:
    s = requests.Session()
    s.headers.update({
        "User-Agent": random.choice(USER_AGENTS),
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.9,bn;q=0.8",
        "Accept-Encoding": "gzip, deflate, br",
        "Connection": "keep-alive",
        "Upgrade-Insecure-Requests": "1",
    })
    if cookies:
        s.cookies.update(cookies)
    return s


def get(url: str, session: Optional[requests.Session] = None,
        cookies: Optional[dict] = None, timeout: int = None) -> Optional[requests.Response]:
    """Polite GET with rate-limiting per domain and exponential backoff."""
    domain = _get_domain(url)
    now = time.time()
    since_last = now - _last_request_time.get(domain, 0)
    wait_needed = RATE_LIMITS["request_delay_seconds"] - since_last
    if wait_needed > 0:
        time.sleep(wait_needed + random.uniform(0, 1.0))

    _last_request_time[domain] = time.time()

    if session is None:
        session = make_session(cookies)

    for attempt in range(RATE_LIMITS["retry_attempts"]):
        try:
            resp = session.get(
                url,
                timeout=timeout or RATE_LIMITS["timeout_seconds"],
                allow_redirects=True,
            )
            if resp.status_code == 429:
                wait = RATE_LIMITS["retry_delay_seconds"] * (2 ** attempt)
                print(f"    [Rate-limited] waiting {wait}s before retry...")
                time.sleep(wait)
                continue
            return resp
        except Exception as e:
            if attempt == RATE_LIMITS["retry_attempts"] - 1:
                print(f"    [HTTP Error] {url}: {e}")
                return None
            time.sleep(RATE_LIMITS["retry_delay_seconds"] * (attempt + 1))

    return None


def download_image(url: str, dest_path: str, session: Optional[requests.Session] = None) -> bool:
    """Download a single image to disk. Returns True on success."""
    import os
    from PIL import Image
    import io

    if os.path.exists(dest_path):
        return True  # Already downloaded

    resp = get(url, session=session)
    if not resp or resp.status_code != 200:
        return False

    content_length = len(resp.content)
    if content_length > RATE_LIMITS["max_image_size_mb"] * 1024 * 1024:
        return False

    try:
        img = Image.open(io.BytesIO(resp.content))
        # Skip tiny images (likely icons/ads)
        if img.width < 200 or img.height < 150:
            return False
        os.makedirs(os.path.dirname(dest_path), exist_ok=True)
        # Save as high-quality JPEG to save space
        if img.mode in ("RGBA", "P"):
            img = img.convert("RGB")
        img.save(dest_path, "JPEG", quality=88, optimize=True)
        return True
    except Exception:
        return False
