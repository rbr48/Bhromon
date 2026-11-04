"""The live journey relay (roadmap LJ-4.4).

Each member who shares during a trip keeps one WebSocket open to this relay. The
relay checks the member's Firebase ID token and that the member is an active
member of the tour. It then passes each member's position to the other members who
are sharing.

Positions live in memory only. They are never written to disk and never sent to
Firestore. A member who sends nothing for two minutes is disconnected, and the app
reconnects on its own. The room state is in memory, so the relay must run in one
worker process.

Protocol (JSON text messages)::

    client -> server  {"t": "auth", "token": "<ID token>"}   first, only once
                      {"t": "pos", "lat", "lng", "acc", "spd", "ts"}  at most one per 5 s
                      {"t": "hb"}                             keeps the member fresh
                      {"t": "share", "on": true | false}
    server -> client  {"t": "ready"}
                      {"t": "pos", "uid", "lat", "lng", "acc", "ts"}
                      {"t": "left", "uid"}
                      {"t": "err", "code": "bad" | "rate" | "auth" | "forbidden" | "full"}

The token is read from a message, not the URL, so it stays out of the access logs.
"""

import asyncio
import json
import logging
import math
import time
from dataclasses import dataclass
from typing import Any, Awaitable, Callable, Dict, List, Optional, Tuple

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

logger = logging.getLogger("bhromon.live")

# One position per member every five seconds (roadmap LJ-4.4).
MIN_SEND_INTERVAL_S = 5.0
# A member silent for two minutes is disconnected (roadmap section 4).
STALE_AFTER_S = 120.0
SWEEP_EVERY_S = 15.0
AUTH_TIMEOUT_S = 10.0
MAX_MESSAGE_CHARS = 1024
MAX_TOUR_ID_CHARS = 128
MAX_MEMBERS_PER_TOUR = 60

router = APIRouter()

Send = Callable[[Dict[str, Any]], Awaitable[None]]
Close = Callable[[int, str], Awaitable[None]]
Identify = Callable[[str], Tuple[str, str]]
IsMember = Callable[[str, str], bool]


@dataclass(eq=False)
class Member:
    """One connected member of one tour. Compared by identity, so a replaced
    connection is never mistaken for the current one."""

    tour_id: str
    uid: str
    send: Send
    close: Close
    sharing: bool = True
    last_seen: float = 0.0
    last_sent: float = float("-inf")


def _number(value: Any) -> Optional[float]:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    number = float(value)
    return number if math.isfinite(number) else None


def clean_reading(message: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """The numbers of a position message, or None when it is not a plausible fix."""
    lat = _number(message.get("lat"))
    lng = _number(message.get("lng"))
    if lat is None or lng is None:
        return None
    if not -90 <= lat <= 90 or not -180 <= lng <= 180:
        return None
    acc = _number(message.get("acc"))
    spd = _number(message.get("spd"))
    ts = _number(message.get("ts"))
    return {
        "lat": lat,
        "lng": lng,
        "acc": acc if acc is not None and 0 <= acc <= 10000 else None,
        "spd": spd if spd is not None and 0 <= spd <= 100 else None,
        "ts": int(ts) if ts is not None else None,
    }


async def _deliver(member: Member, message: Dict[str, Any]) -> None:
    try:
        await member.send(message)
    except Exception as error:  # A closed socket must not stop the others.
        logger.debug("Live message not delivered: %s", error)


async def _deliver_all(members: List[Member], message: Dict[str, Any]) -> None:
    if members:
        await asyncio.gather(*(_deliver(m, message) for m in members))


class LiveRelay:
    """The members connected right now, by tour. Memory only."""

    def __init__(self, clock: Callable[[], float] = time.monotonic) -> None:
        self._clock = clock
        self._rooms: Dict[str, Dict[str, Member]] = {}

    def members(self, tour_id: str) -> List[str]:
        return sorted(self._rooms.get(tour_id, {}))

    def join(
        self, tour_id: str, uid: str, send: Send, close: Close
    ) -> Tuple[Optional[Member], Optional[Member]]:
        """Adds a member. Returns (member, replaced), where replaced is the member's
        earlier connection on another phone, or None. Returns (None, None) when the
        tour is full."""
        room = self._rooms.setdefault(tour_id, {})
        replaced = room.get(uid)
        if replaced is None and len(room) >= MAX_MEMBERS_PER_TOUR:
            if not room:
                del self._rooms[tour_id]
            return None, None
        member = Member(
            tour_id=tour_id,
            uid=uid,
            send=send,
            close=close,
            last_seen=self._clock(),
        )
        room[uid] = member
        return member, replaced

    def leave(self, member: Member) -> List[Member]:
        """Removes the member if this is still its current connection. Returns the
        members who must hear that it left."""
        room = self._rooms.get(member.tour_id)
        if room is None or room.get(member.uid) is not member:
            return []
        del room[member.uid]
        if not room:
            del self._rooms[member.tour_id]
            return []
        return [other for other in room.values() if other.sharing]

    def touch(self, member: Member) -> None:
        member.last_seen = self._clock()

    def set_sharing(self, member: Member, on: bool) -> None:
        member.sharing = on
        self.touch(member)

    async def accept_position(self, member: Member, message: Dict[str, Any]) -> str:
        """Passes one position to the other sharing members. Returns the outcome:
        "ok", "not_sharing", "bad" or "rate"."""
        now = self._clock()
        member.last_seen = now
        if not member.sharing:
            return "not_sharing"
        reading = clean_reading(message)
        if reading is None:
            return "bad"
        if now - member.last_sent < MIN_SEND_INTERVAL_S:
            return "rate"
        member.last_sent = now
        room = self._rooms.get(member.tour_id, {})
        recipients = [o for o in room.values() if o is not member and o.sharing]
        await _deliver_all(recipients, {"t": "pos", "uid": member.uid, **reading})
        return "ok"

    async def sweep(self) -> List[Member]:
        """Disconnects the members silent for longer than STALE_AFTER_S. Returns them."""
        now = self._clock()
        stale = [
            member
            for room in list(self._rooms.values())
            for member in list(room.values())
            if now - member.last_seen > STALE_AFTER_S
        ]
        for member in stale:
            others = self.leave(member)
            await _deliver_all(others, {"t": "left", "uid": member.uid})
            try:
                await member.close(4008, "stale")
            except Exception as error:
                logger.debug("Stale live member not closed cleanly: %s", error)
        return stale


RELAY = LiveRelay()
_identify: Optional[Identify] = None
_is_member: Optional[IsMember] = None


def configure(identify: Identify, is_member: IsMember) -> None:
    """Sets the token check and the membership check. The app passes its Firebase
    backend; the tests pass fakes."""
    global _identify, _is_member
    _identify = identify
    _is_member = is_member


async def _read_token(websocket: WebSocket) -> Optional[str]:
    try:
        raw = await asyncio.wait_for(websocket.receive_text(), AUTH_TIMEOUT_S)
        message = json.loads(raw)
    except (asyncio.TimeoutError, WebSocketDisconnect, ValueError):
        return None
    if not isinstance(message, dict) or message.get("t") != "auth":
        return None
    token = message.get("token")
    return token if isinstance(token, str) and token else None


async def _refuse(websocket: WebSocket, code: str, close_code: int) -> None:
    try:
        await websocket.send_json({"t": "err", "code": code})
    except Exception:
        pass
    try:
        await websocket.close(close_code, code)
    except Exception:
        pass


@router.websocket("/live/ws")
async def live_socket(websocket: WebSocket) -> None:
    tour_id = (websocket.query_params.get("tour") or "").strip()
    await websocket.accept()
    if not tour_id or len(tour_id) > MAX_TOUR_ID_CHARS or "/" in tour_id:
        await _refuse(websocket, "bad", 4400)
        return

    token = await _read_token(websocket)
    if token is None or _identify is None:
        await _refuse(websocket, "auth", 4401)
        return
    try:
        uid, email = await asyncio.to_thread(_identify, token)
    except Exception:
        await _refuse(websocket, "auth", 4401)
        return

    try:
        allowed = await asyncio.to_thread(_is_member_of, tour_id, email)
    except Exception as error:
        # A failed lookup is not a refusal, so the app retries.
        logger.warning("Live membership check failed: %s", error)
        await _refuse(websocket, "unavailable", 1013)
        return
    if not allowed:
        await _refuse(websocket, "forbidden", 4403)
        return

    member, replaced = RELAY.join(
        tour_id, uid, send=websocket.send_json, close=websocket.close
    )
    if member is None:
        await _refuse(websocket, "full", 4429)
        return
    if replaced is not None:
        # The same member on another phone: the newer connection takes over.
        try:
            await replaced.close(4001, "replaced")
        except Exception:
            pass
    await websocket.send_json({"t": "ready"})

    try:
        while True:
            raw = await websocket.receive_text()
            if len(raw) > MAX_MESSAGE_CHARS:
                await _send_error(member, "bad")
                continue
            try:
                message = json.loads(raw)
            except ValueError:
                continue
            if not isinstance(message, dict):
                continue
            kind = message.get("t")
            if kind == "pos":
                outcome = await RELAY.accept_position(member, message)
                if outcome in ("rate", "bad"):
                    await _send_error(member, outcome)
            elif kind == "hb":
                RELAY.touch(member)
            elif kind == "share":
                RELAY.set_sharing(member, message.get("on") is True)
    except WebSocketDisconnect:
        pass
    finally:
        others = RELAY.leave(member)
        await _deliver_all(others, {"t": "left", "uid": uid})


def _is_member_of(tour_id: str, email: str) -> bool:
    if _is_member is None:
        raise RuntimeError("The live relay has no membership check")
    return bool(_is_member(tour_id, email))


async def _send_error(member: Member, code: str) -> None:
    await _deliver(member, {"t": "err", "code": code})


async def sweep_forever() -> None:
    """Disconnects silent members for as long as the server runs."""
    while True:
        await asyncio.sleep(SWEEP_EVERY_S)
        try:
            await RELAY.sweep()
        except Exception as error:
            logger.warning("Live relay sweep failed: %s", error)
