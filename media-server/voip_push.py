"""Rings an iPhone through Apple's VoIP push (PushKit).

An iPhone whose app is closed shows the system call screen only for a VoIP
push, which comes from Apple directly; Firebase cannot send one. The app
registers its PushKit token with the platform VOIP_PLATFORM, and a call offer is
sent to it here. Nothing is sent unless the APNs key is configured:

    APNS_KEY_PATH   path to the .p8 key from the Apple developer account
    APNS_KEY_ID     the key's id
    APNS_TEAM_ID    the team id
    APNS_BUNDLE_ID  the app's bundle id (the topic is "<bundle>.voip")
    APNS_SANDBOX    "1" for development builds

Apple requires the app to show a call for every VoIP push it receives, so only
an offer that rings is sent this way, never a ring-stop.
"""

from __future__ import annotations

import json
import logging
import os
import threading
import time
from pathlib import Path
from typing import Any, Callable, Dict, Optional

logger = logging.getLogger("bhromon.voip_push")

VOIP_PLATFORM = "ios-voip"
# A provider token is valid for an hour; it is renewed well before.
TOKEN_LIFETIME_SECONDS = 50 * 60
RING_SECONDS = 45


class VoipPushSender:
    """Sends VoIP pushes over HTTP/2 with a token-based (p8) provider key."""

    def __init__(
        self,
        env: Optional[Dict[str, str]] = None,
        clock: Callable[[], float] = time.time,
        post: Optional[Callable[..., Any]] = None,
    ) -> None:
        env = dict(os.environ) if env is None else env
        self.key_path = env.get("APNS_KEY_PATH", "")
        self.key_id = env.get("APNS_KEY_ID", "")
        self.team_id = env.get("APNS_TEAM_ID", "")
        self.bundle_id = env.get("APNS_BUNDLE_ID", "com.bhromon.bhromon")
        sandbox = env.get("APNS_SANDBOX", "") == "1"
        self.host = "https://api.sandbox.push.apple.com" if sandbox else "https://api.push.apple.com"
        self._clock = clock
        self._post = post
        self._lock = threading.Lock()
        self._token: Optional[str] = None
        self._token_at = 0.0

    @property
    def configured(self) -> bool:
        return bool(self.key_path and self.key_id and self.team_id and Path(self.key_path).is_file())

    def _provider_token(self) -> str:
        with self._lock:
            now = self._clock()
            if self._token and now - self._token_at < TOKEN_LIFETIME_SECONDS:
                return self._token
            import jwt  # PyJWT, installed with firebase-admin

            key = Path(self.key_path).read_text()
            self._token = jwt.encode(
                {"iss": self.team_id, "iat": int(now)},
                key,
                algorithm="ES256",
                headers={"kid": self.key_id},
            )
            self._token_at = now
            return self._token

    def _send(self, url: str, headers: Dict[str, str], body: bytes) -> Any:
        if self._post is not None:
            return self._post(url, headers=headers, content=body)
        import httpx  # with the http2 extra; Apple accepts HTTP/2 only

        with httpx.Client(http2=True, timeout=10.0) as client:
            return client.post(url, headers=headers, content=body)

    def send_call(
        self,
        device_token: str,
        *,
        call_id: str,
        caller_id: str,
        caller_name: str,
        is_video: bool,
    ) -> str:
        """Rings one iPhone. Returns "sent", "dead" (the token is no longer
        valid and should be removed), "skipped" or "failed"."""
        if not self.configured or not device_token:
            return "skipped"
        payload = {
            "id": call_id,
            "nameCaller": caller_name,
            "handle": "Bhromon Video Call" if is_video else "Bhromon Voice Call",
            "isVideo": is_video,
            "extra": {
                "callId": call_id,
                "callerId": caller_id,
                "callerName": caller_name,
                "isVideo": is_video,
            },
        }
        headers = {
            "authorization": f"bearer {self._provider_token()}",
            "apns-topic": f"{self.bundle_id}.voip",
            "apns-push-type": "voip",
            "apns-priority": "10",
            "apns-expiration": str(int(self._clock()) + RING_SECONDS),
        }
        try:
            response = self._send(
                f"{self.host}/3/device/{device_token}",
                headers,
                json.dumps(payload).encode("utf-8"),
            )
        except Exception as error:
            logger.warning("VoIP push failed for call %s: %s", call_id, error)
            return "failed"
        status = getattr(response, "status_code", 0)
        if status == 200:
            return "sent"
        if status == 410 or (status == 400 and "BadDeviceToken" in getattr(response, "text", "")):
            return "dead"
        logger.warning("VoIP push for call %s refused: %s %s", call_id, status, getattr(response, "text", ""))
        return "failed"


voip_sender = VoipPushSender()
