"""Signed links for private media.

Media is not public. Each link to a file carries two query values: `u`, the uid of the
person the link is for, and `s`, a signature of the file's path. The signature is made with
a key that only that person's app holds. The server derives the key from
MEDIA_ACCESS_SECRET, so nobody can make a valid link without it, and a link for one file
opens no other file.

nginx asks the media server before it serves a file (`/internal/media-auth`). The server
checks the signature, then checks that the person may read that space: an active member
of the tour, one of the two people in a chat who share a tour, the owner of a user space,
or any signed-in person for the public spaces. Each answer is kept for a minute, so someone
who leaves a tour loses access within that time.

Links do not expire. A time limit would break cached copies and offline viewing. A link
stops working when its person leaves the tour, when the file is deleted, or when the
secret changes, which revokes every link at once.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import re
import threading
import time
from typing import Callable, Dict, Optional, Tuple
from urllib.parse import parse_qs

# Keys are derived with this label, so a key for one purpose cannot be used for another.
KEY_LABEL = b"bhromon-media-key-v1|"
# Signatures cover this prefix, so the scheme can change later without reusing old ones.
SIGNING_PREFIX = "v1|"
MIN_SECRET_BYTES = 32
# How long a person's access to a space is remembered before it is checked again.
DECISION_SECONDS = 60
MAX_DECISIONS = 5000
UID_PATTERN = re.compile(r"[A-Za-z0-9_-]{1,128}")


def secret_is_usable(secret: bytes) -> bool:
    return len(secret) >= MIN_SECRET_BYTES


def b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def derive_key(secret: bytes, uid: str) -> str:
    """The key the app of `uid` signs its media links with. Only that app and the server hold it."""
    digest = hmac.new(secret, KEY_LABEL + uid.encode("utf-8"), hashlib.sha256).digest()
    return b64url(digest)


def signature_for(key: str, path: str) -> str:
    """The signature of a file path under a key. The Dart client computes the same value."""
    message = (SIGNING_PREFIX + path).encode("utf-8")
    return b64url(hmac.new(key.encode("utf-8"), message, hashlib.sha256).digest())


def parse_link(raw_uri: str) -> Optional[Tuple[str, str, str]]:
    """(path, uid, signature) of a request URI that has exactly one `u` and one `s`, else None."""
    path, _, query = raw_uri.partition("?")
    params = parse_qs(query, keep_blank_values=True)
    if set(params) != {"u", "s"} or any(len(values) != 1 for values in params.values()):
        return None
    uid, signature = params["u"][0], params["s"][0]
    if not UID_PATTERN.fullmatch(uid) or not signature:
        return None
    return path, uid, signature


def signature_is_valid(secret: bytes, path: str, uid: str, signature: str) -> bool:
    if not secret_is_usable(secret) or not UID_PATTERN.fullmatch(uid):
        return False
    expected = signature_for(derive_key(secret, uid), path)
    return hmac.compare_digest(expected.encode("utf-8"), signature.encode("utf-8"))


class AccessDecisions:
    """Remembers whether a person may read a space, for DECISION_SECONDS.

    Each media request is checked, and a Firestore read per request would be costly. A
    person who leaves a tour is refused once the remembered answer expires. Only a
    completed check is remembered: one that raises is asked again next time.
    """

    def __init__(self, clock: Callable[[], float] = time.monotonic) -> None:
        self._clock = clock
        self._lock = threading.Lock()
        self._entries: Dict[Tuple[str, str], Tuple[float, bool]] = {}

    def allowed(self, uid: str, space: str, decide: Callable[[], bool]) -> bool:
        key = (uid, space)
        now = self._clock()
        with self._lock:
            hit = self._entries.get(key)
            if hit is not None and now - hit[0] < DECISION_SECONDS:
                return hit[1]
        result = bool(decide())
        with self._lock:
            if len(self._entries) >= MAX_DECISIONS:
                self._entries.clear()
            self._entries[key] = (now, result)
        return result
