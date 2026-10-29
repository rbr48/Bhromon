"""Bhromon VPS 1-on-1 Chat, WebRTC Signaling & Push Notification Engine.

Replaces Firebase Firestore for 1-on-1 chats, call signaling, and device tokens.
All data is stored in a local SQLite database (bhromon_chat.db) with WAL mode,
completely eliminating Firestore read/write costs and quota exhaustion.
"""

from __future__ import annotations

import asyncio
import base64
import hashlib
import hmac
import json
import logging
import os
import sqlite3
import threading
import time
from collections import deque
from pathlib import Path
from typing import Any, Deque, Dict, List, Optional, Set, Tuple

from fastapi import APIRouter, Depends, Header, HTTPException, Query, WebSocket, WebSocketDisconnect, status
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel

logger = logging.getLogger("bhromon.chat")

DEAD_TOKEN_CODES = {
    "messaging/registration-token-not-registered",
    "messaging/invalid-registration-token",
    "registration-token-not-registered",
    "invalid-registration-token",
}


def _now_ms() -> int:
    return int(time.time() * 1000)


class ChatDatabase:
    """Thread-safe SQLite storage for chats, messages, and device push tokens."""

    def __init__(self, db_path: str | Path) -> None:
        self.db_path = str(db_path)
        os.makedirs(os.path.dirname(os.path.abspath(self.db_path)), exist_ok=True)
        self._local = threading.local()
        self._init_schema()

    def _get_conn(self) -> sqlite3.Connection:
        if not hasattr(self._local, "conn") or self._local.conn is None:
            conn = sqlite3.connect(self.db_path, timeout=30.0)
            conn.row_factory = sqlite3.Row
            conn.execute("PRAGMA journal_mode=WAL;")
            conn.execute("PRAGMA synchronous=NORMAL;")
            conn.execute("PRAGMA foreign_keys=ON;")
            self._local.conn = conn
        return self._local.conn

    def _init_schema(self) -> None:
        conn = self._get_conn()
        with conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS device_tokens (
                    uid TEXT NOT NULL,
                    device_id TEXT NOT NULL,
                    token TEXT NOT NULL,
                    email TEXT,
                    platform TEXT,
                    updated_at INTEGER NOT NULL,
                    PRIMARY KEY (uid, device_id)
                );
                CREATE INDEX IF NOT EXISTS idx_device_tokens_uid ON device_tokens(uid);
                CREATE INDEX IF NOT EXISTS idx_device_tokens_token ON device_tokens(token);

                CREATE TABLE IF NOT EXISTS conversations (
                    chat_id TEXT PRIMARY KEY,
                    participants TEXT NOT NULL,
                    participant_emails TEXT,
                    last_message TEXT,
                    last_message_time INTEGER,
                    last_sender_id TEXT,
                    unread_counts TEXT,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_conversations_updated ON conversations(updated_at DESC);

                CREATE TABLE IF NOT EXISTS messages (
                    id TEXT PRIMARY KEY,
                    chat_id TEXT NOT NULL,
                    sender_id TEXT NOT NULL,
                    sender_name TEXT,
                    sender_avatar TEXT,
                    text TEXT,
                    type TEXT DEFAULT 'text',
                    media_url TEXT,
                    media_path TEXT,
                    thumbnail_url TEXT,
                    reply_to TEXT,
                    reactions TEXT,
                    read_by TEXT,
                    status TEXT DEFAULT 'sent',
                    metadata TEXT,
                    created_at INTEGER NOT NULL,
                    deleted_for TEXT
                );
                CREATE INDEX IF NOT EXISTS idx_messages_chat_created ON messages(chat_id, created_at DESC);
                CREATE INDEX IF NOT EXISTS idx_messages_sender ON messages(sender_id);
                """
            )

    # ── Device Tokens ─────────────────────────────────────────────────────────

    def register_device_token(
        self,
        uid: str,
        token: str,
        device_id: Optional[str] = None,
        email: Optional[str] = None,
        platform: Optional[str] = None,
    ) -> None:
        clean_uid = uid.strip()
        clean_token = token.strip()
        if not clean_uid or not clean_token:
            return
        dev_id = (device_id or clean_token[:32]).strip()
        now = _now_ms()

        conn = self._get_conn()
        with conn:
            conn.execute(
                """
                INSERT INTO device_tokens (uid, device_id, token, email, platform, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(uid, device_id) DO UPDATE SET
                    token=excluded.token,
                    email=coalesce(excluded.email, device_tokens.email),
                    platform=coalesce(excluded.platform, device_tokens.platform),
                    updated_at=excluded.updated_at;
                """,
                (clean_uid, dev_id, clean_token, (email or "").strip().lower(), platform or "unknown", now),
            )

    def get_device_tokens(self, uid: str) -> List[Dict[str, str]]:
        conn = self._get_conn()
        cursor = conn.execute(
            "SELECT token, platform FROM device_tokens WHERE uid = ?",
            (uid.strip(),),
        )
        return [{"token": row["token"], "platform": row["platform"]} for row in cursor.fetchall()]

    def delete_device_token(self, token: str) -> None:
        conn = self._get_conn()
        with conn:
            conn.execute("DELETE FROM device_tokens WHERE token = ?", (token.strip(),))

    # ── Conversations ─────────────────────────────────────────────────────────

    def get_or_create_conversation(
        self,
        chat_id: str,
        participants: List[str],
        participant_emails: Optional[List[str]] = None,
    ) -> Dict[str, Any]:
        conn = self._get_conn()
        cursor = conn.execute("SELECT * FROM conversations WHERE chat_id = ?", (chat_id,))
        row = cursor.fetchone()
        if row:
            return self._row_to_conversation(row)

        now = _now_ms()
        clean_parts = sorted(list({p.strip() for p in participants if p.strip()}))
        unread = {p: 0 for p in clean_parts}

        with conn:
            conn.execute(
                """
                INSERT INTO conversations (
                    chat_id, participants, participant_emails,
                    last_message, last_message_time, last_sender_id,
                    unread_counts, created_at, updated_at
                ) VALUES (?, ?, ?, '', ?, '', ?, ?, ?)
                """,
                (
                    chat_id,
                    json.dumps(clean_parts),
                    json.dumps(participant_emails or []),
                    now,
                    json.dumps(unread),
                    now,
                    now,
                ),
            )
        return {
            "chatId": chat_id,
            "participants": clean_parts,
            "participantEmails": participant_emails or [],
            "lastMessage": "",
            "lastMessageTime": now,
            "lastSenderId": "",
            "unreadCounts": unread,
            "createdAt": now,
            "updatedAt": now,
        }

    def participants_of(self, chat_id: str) -> Optional[List[str]]:
        """The uids in a conversation, or None when there is no conversation with that id."""
        row = self._get_conn().execute(
            "SELECT participants FROM conversations WHERE chat_id = ?", (chat_id,)
        ).fetchone()
        if row is None:
            return None
        try:
            return [str(uid) for uid in json.loads(row["participants"])]
        except (TypeError, ValueError):
            return []

    def list_conversations(self, uid: str) -> List[Dict[str, Any]]:
        conn = self._get_conn()
        cursor = conn.execute("SELECT * FROM conversations ORDER BY updated_at DESC")
        results = []
        for row in cursor.fetchall():
            conv = self._row_to_conversation(row)
            if uid in conv["participants"]:
                results.append(conv)
        return results

    def _row_to_conversation(self, row: sqlite3.Row) -> Dict[str, Any]:
        try:
            parts = json.loads(row["participants"])
        except Exception:
            parts = []
        try:
            emails = json.loads(row["participant_emails"]) if row["participant_emails"] else []
        except Exception:
            emails = []
        try:
            unread = json.loads(row["unread_counts"]) if row["unread_counts"] else {}
        except Exception:
            unread = {}

        return {
            "chatId": row["chat_id"],
            "participants": parts,
            "participantEmails": emails,
            "lastMessage": row["last_message"] or "",
            "lastMessageTime": row["last_message_time"] or row["updated_at"],
            "lastSenderId": row["last_sender_id"] or "",
            "unreadCounts": unread,
            "createdAt": row["created_at"],
            "updatedAt": row["updated_at"],
        }

    # ── Messages ──────────────────────────────────────────────────────────────

    def save_message(self, msg: Dict[str, Any]) -> Dict[str, Any]:
        msg_id = msg.get("id") or os.urandom(16).hex()
        chat_id = msg["chatId"]
        sender_id = msg["senderId"]
        created_at = msg.get("createdAt") or _now_ms()
        text = msg.get("text") or ""
        mtype = msg.get("type") or "text"

        conn = self._get_conn()
        with conn:
            conn.execute(
                """
                INSERT OR REPLACE INTO messages (
                    id, chat_id, sender_id, sender_name, sender_avatar,
                    text, type, media_url, media_path, thumbnail_url,
                    reply_to, reactions, read_by, status, metadata,
                    created_at, deleted_for
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    msg_id,
                    chat_id,
                    sender_id,
                    msg.get("senderName"),
                    msg.get("senderAvatar"),
                    text,
                    mtype,
                    msg.get("mediaUrl"),
                    msg.get("mediaPath"),
                    msg.get("thumbnailUrl"),
                    json.dumps(msg.get("replyTo")) if msg.get("replyTo") else None,
                    json.dumps(msg.get("reactions")) if msg.get("reactions") else "{}",
                    json.dumps(msg.get("readBy") or [sender_id]),
                    msg.get("status") or "sent",
                    json.dumps(msg.get("metadata")) if msg.get("metadata") else None,
                    created_at,
                    json.dumps(msg.get("deletedFor") or []),
                ),
            )

            # Update conversation summary and increment unread counts for recipients
            cursor = conn.execute("SELECT * FROM conversations WHERE chat_id = ?", (chat_id,))
            crow = cursor.fetchone()
            if crow:
                conv = self._row_to_conversation(crow)
                unread = conv["unreadCounts"]
                for p in conv["participants"]:
                    if p != sender_id:
                        unread[p] = unread.get(p, 0) + 1
                    else:
                        unread[p] = 0

                preview = text if text else (f"[{mtype}]" if mtype != "text" else "")
                conn.execute(
                    """
                    UPDATE conversations SET
                        last_message = ?,
                        last_message_time = ?,
                        last_sender_id = ?,
                        unread_counts = ?,
                        updated_at = ?
                    WHERE chat_id = ?
                    """,
                    (preview, created_at, sender_id, json.dumps(unread), created_at, chat_id),
                )

        msg["id"] = msg_id
        msg["createdAt"] = created_at
        return msg

    def get_messages(
        self,
        chat_id: str,
        uid: str,
        before_time: Optional[int] = None,
        limit: int = 50,
    ) -> List[Dict[str, Any]]:
        conn = self._get_conn()
        limit = max(1, min(limit, 100))

        if before_time:
            cursor = conn.execute(
                """
                SELECT *, rowid FROM messages
                WHERE chat_id = ? AND created_at < ?
                ORDER BY created_at DESC, rowid DESC LIMIT ?
                """,
                (chat_id, before_time, limit),
            )
        else:
            cursor = conn.execute(
                """
                SELECT *, rowid FROM messages
                WHERE chat_id = ?
                ORDER BY created_at DESC, rowid DESC LIMIT ?
                """,
                (chat_id, limit),
            )

        messages = []
        for row in cursor.fetchall():
            m = self._row_to_message(row)
            if uid not in m.get("deletedFor", []):
                messages.append(m)

        # Return ascending order for chat window rendering
        messages.reverse()
        return messages

    def mark_read(self, chat_id: str, uid: str, message_ids: Optional[List[str]] = None) -> List[str]:
        conn = self._get_conn()
        now = _now_ms()
        updated_ids: List[str] = []

        with conn:
            if message_ids:
                for mid in message_ids:
                    row = conn.execute("SELECT read_by FROM messages WHERE id = ?", (mid,)).fetchone()
                    if row:
                        try:
                            read_by = json.loads(row["read_by"])
                        except Exception:
                            read_by = []
                        if uid not in read_by:
                            read_by.append(uid)
                            conn.execute(
                                "UPDATE messages SET read_by = ?, status = 'read' WHERE id = ?",
                                (json.dumps(read_by), mid),
                            )
                            updated_ids.append(mid)
            else:
                cursor = conn.execute(
                    "SELECT id, read_by FROM messages WHERE chat_id = ? AND sender_id != ?",
                    (chat_id, uid),
                )
                for row in cursor.fetchall():
                    try:
                        read_by = json.loads(row["read_by"])
                    except Exception:
                        read_by = []
                    if uid not in read_by:
                        read_by.append(uid)
                        conn.execute(
                            "UPDATE messages SET read_by = ?, status = 'read' WHERE id = ?",
                            (json.dumps(read_by), row["id"]),
                        )
                        updated_ids.append(row["id"])

            # Reset user's unread count in conversation
            crow = conn.execute("SELECT * FROM conversations WHERE chat_id = ?", (chat_id,)).fetchone()
            if crow:
                conv = self._row_to_conversation(crow)
                unread = conv["unreadCounts"]
                unread[uid] = 0
                conn.execute(
                    "UPDATE conversations SET unread_counts = ?, updated_at = ? WHERE chat_id = ?",
                    (json.dumps(unread), now, chat_id),
                )

        return updated_ids

    def set_reaction(self, chat_id: str, message_id: str, uid: str, emoji: str) -> Dict[str, Any]:
        conn = self._get_conn()
        with conn:
            row = conn.execute("SELECT reactions FROM messages WHERE id = ?", (message_id,)).fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Message not found")
            try:
                reactions: Dict[str, List[str]] = json.loads(row["reactions"]) if row["reactions"] else {}
            except Exception:
                reactions = {}

            # Toggle reaction: if already reacted with this emoji, remove it; else add it
            users = reactions.get(emoji, [])
            if uid in users:
                users.remove(uid)
                if not users:
                    reactions.pop(emoji, None)
                else:
                    reactions[emoji] = users
            else:
                users.append(uid)
                reactions[emoji] = users

            conn.execute(
                "UPDATE messages SET reactions = ? WHERE id = ?",
                (json.dumps(reactions), message_id),
            )
        return reactions

    def delete_message(self, chat_id: str, message_id: str, uid: str, for_everyone: bool = False) -> bool:
        conn = self._get_conn()
        with conn:
            row = conn.execute("SELECT sender_id, deleted_for FROM messages WHERE id = ?", (message_id,)).fetchone()
            if not row:
                return False

            if for_everyone:
                if row["sender_id"] != uid:
                    raise HTTPException(status_code=403, detail="Only sender can delete for everyone")
                conn.execute("DELETE FROM messages WHERE id = ?", (message_id,))
                return True
            else:
                try:
                    deleted_for = json.loads(row["deleted_for"]) if row["deleted_for"] else []
                except Exception:
                    deleted_for = []
                if uid not in deleted_for:
                    deleted_for.append(uid)
                    conn.execute(
                        "UPDATE messages SET deleted_for = ? WHERE id = ?",
                        (json.dumps(deleted_for), message_id),
                    )
                return True

    def _row_to_message(self, row: sqlite3.Row) -> Dict[str, Any]:
        try:
            reply_to = json.loads(row["reply_to"]) if row["reply_to"] else None
        except Exception:
            reply_to = None
        try:
            reactions = json.loads(row["reactions"]) if row["reactions"] else {}
        except Exception:
            reactions = {}
        try:
            read_by = json.loads(row["read_by"]) if row["read_by"] else []
        except Exception:
            read_by = []
        try:
            metadata = json.loads(row["metadata"]) if row["metadata"] else None
        except Exception:
            metadata = None
        try:
            deleted_for = json.loads(row["deleted_for"]) if row["deleted_for"] else []
        except Exception:
            deleted_for = []

        return {
            "id": row["id"],
            "chatId": row["chat_id"],
            "senderId": row["sender_id"],
            "senderName": row["sender_name"],
            "senderAvatar": row["sender_avatar"],
            "text": row["text"] or "",
            "type": row["type"] or "text",
            "mediaUrl": row["media_url"],
            "mediaPath": row["media_path"],
            "thumbnailUrl": row["thumbnail_url"],
            "replyTo": reply_to,
            "reactions": reactions,
            "readBy": read_by,
            "status": row["status"] or "sent",
            "metadata": metadata,
            "createdAt": row["created_at"],
            "deletedFor": deleted_for,
        }


# ── Real-Time WebSocket Connection Manager ────────────────────────────────────

class ChatWebSocketManager:
    """Manages active WebSocket connections per UID, enabling instant messaging and WebRTC signaling."""

    def __init__(self) -> None:
        self._connections: Dict[str, Set[WebSocket]] = {}
        # Sockets whose app confirms chat messages once it shows them.
        self._confirming: Set[WebSocket] = set()
        # Messages waiting for their recipient to confirm them: id -> (recipient, event).
        self._awaiting_ack: Dict[str, Tuple[str, asyncio.Event]] = {}
        self._lock = threading.Lock()

    async def connect(self, uid: str, websocket: WebSocket) -> None:
        await websocket.accept()
        with self._lock:
            if uid not in self._connections:
                self._connections[uid] = set()
            self._connections[uid].add(websocket)
        logger.info("WS connected: uid=%s (active sockets=%d)", uid, len(self._connections[uid]))

    def disconnect(self, uid: str, websocket: WebSocket) -> None:
        with self._lock:
            self._confirming.discard(websocket)
            if uid in self._connections:
                self._connections[uid].discard(websocket)
                if not self._connections[uid]:
                    del self._connections[uid]
        logger.info("WS disconnected: uid=%s", uid)

    def is_online(self, uid: str) -> bool:
        with self._lock:
            return bool(self._connections.get(uid))

    def mark_confirming(self, websocket: WebSocket) -> None:
        with self._lock:
            self._confirming.add(websocket)

    def recipient_confirms(self, uid: str) -> bool:
        """True when one of the user's sockets confirms messages it shows on screen."""
        with self._lock:
            return any(ws in self._confirming for ws in self._connections.get(uid, ()))

    def expect_ack(self, message_id: str, recipient_uid: str) -> asyncio.Event:
        """Returns an event that is set when [recipient_uid] confirms [message_id]."""
        event = asyncio.Event()
        with self._lock:
            self._awaiting_ack[message_id] = (recipient_uid, event)
        return event

    def acknowledge(self, message_id: str, uid: str) -> None:
        """Marks a message as shown. Only its recipient can confirm it."""
        with self._lock:
            pending = self._awaiting_ack.get(message_id)
        if pending is not None and pending[0] == uid:
            pending[1].set()

    def forget_ack(self, message_id: str) -> None:
        with self._lock:
            self._awaiting_ack.pop(message_id, None)

    async def send_to_user(self, uid: str, payload: Dict[str, Any]) -> bool:
        """Sends payload to user's active sockets. Returns True if at least one socket received it."""
        sockets: List[WebSocket] = []
        with self._lock:
            if uid in self._connections:
                sockets = list(self._connections[uid])

        if not sockets:
            return False

        delivered = False
        message_json = json.dumps(payload)
        for ws in sockets:
            try:
                await ws.send_text(message_json)
                delivered = True
            except Exception as e:
                logger.warning("Failed to send WS message to uid %s: %s", uid, e)
                self.disconnect(uid, ws)
        return delivered

    async def broadcast_to_participants(
        self,
        participants: List[str],
        payload: Dict[str, Any],
        exclude_uid: Optional[str] = None,
    ) -> List[str]:
        """Broadcasts to all online participants. Returns list of uids who received it online."""
        delivered_uids = []
        for p in participants:
            if exclude_uid and p == exclude_uid:
                continue
            if await self.send_to_user(p, payload):
                delivered_uids.append(p)
        return delivered_uids


# ── Push Notification Dispatcher (Direct FCM v1, Zero Firestore) ─────────────

class PushNotificationDispatcher:
    """Sends direct FCM HTTP v1 notifications using Firebase Admin SDK without calling Firestore."""

    def __init__(self, db: ChatDatabase) -> None:
        self.db = db

    def send_push_to_uid(
        self,
        recipient_uid: str,
        title: str,
        body: str,
        data: Dict[str, str],
        image_url: Optional[str] = None,
    ) -> int:
        tokens = self.db.get_device_tokens(recipient_uid)
        if not tokens:
            return 0

        import firebase_admin
        from firebase_admin import messaging

        if not firebase_admin._apps:
            logger.warning("Firebase Admin SDK not initialized; skipping push.")
            return 0

        # Build notification object
        sent_count = 0
        for entry in tokens:
            token = entry["token"]
            try:
                android_config = messaging.AndroidConfig(
                    priority="high",
                    notification=messaging.AndroidNotification(
                        title=title,
                        body=body,
                        sound="default",
                        channel_id="bhromon_general",
                        image=image_url,
                    ),
                )
                web_config = messaging.WebpushConfig(
                    headers={"Urgency": "high"},
                    notification=messaging.WebpushNotification(
                        title=title,
                        body=body,
                        icon="/icons/Icon-192.png",
                        image=image_url,
                    ),
                )

                msg = messaging.Message(
                    token=token,
                    notification=messaging.Notification(title=title, body=body, image=image_url),
                    data=data,
                    android=android_config,
                    webpush=web_config,
                )

                messaging.send(msg)
                sent_count += 1
            except Exception as e:
                err_str = str(e)
                logger.warning("Failed to send push to token %s: %s", token[:15], err_str)
                if any(dead_code in err_str for dead_code in DEAD_TOKEN_CODES):
                    self.db.delete_device_token(token)

        return sent_count


# ── Global Singletons & Router ────────────────────────────────────────────────

DATA_DIR = Path(os.getenv("MEDIA_META_ROOT", "/data/media-meta"))
chat_db = ChatDatabase(DATA_DIR / "bhromon_chat.db")
ws_manager = ChatWebSocketManager()
push_dispatcher = PushNotificationDispatcher(chat_db)

# Confirmation waits still running. Held here so the tasks are not dropped early.
_confirmation_waits: Set[asyncio.Task] = set()


def _start_background(coro: Any) -> None:
    """Runs [coro] after the request that started it has returned."""
    task = asyncio.ensure_future(coro)
    _confirmation_waits.add(task)
    task.add_done_callback(_confirmation_waits.discard)


async def _push_unless_confirmed(ack: asyncio.Event, message_id: str, push_args: Dict[str, Any]) -> None:
    """Pushes a chat message unless its recipient's app confirms it on screen in time."""
    try:
        await asyncio.wait_for(ack.wait(), timeout=MESSAGE_ACK_SECONDS)
        return
    except asyncio.TimeoutError:
        pass
    finally:
        ws_manager.forget_ack(message_id)
    await run_in_threadpool(push_dispatcher.send_push_to_uid, **push_args)


chat_router = APIRouter(tags=["chat"])


# ── Dependency Authentication ─────────────────────────────────────────────────

def verify_firebase_uid(token: str) -> str:
    """The uid of a valid Firebase ID token. Raises ValueError for anything else."""
    from firebase_admin import auth

    decoded = auth.verify_id_token(token, clock_skew_seconds=10)
    uid = str(decoded.get("uid") or "")
    if not uid:
        raise ValueError("Token contains no UID")
    return uid


def authenticate_user(
    authorization: Optional[str] = Header(None),
) -> str:
    """Verifies Firebase ID token and returns authenticated uid."""
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or invalid Bearer token",
        )
    token = authorization[7:].strip()
    try:
        return verify_firebase_uid(token)
    except Exception as e:
        logger.warning("Token verification failed: %s", e)
        raise HTTPException(status_code=401, detail="Invalid authentication token.")


# ── Pydantic Request Models ───────────────────────────────────────────────────

class TokenRegistrationRequest(BaseModel):
    token: str
    deviceId: Optional[str] = None
    email: Optional[str] = None
    platform: Optional[str] = None


class SendMessageRequest(BaseModel):
    chatId: str
    recipientId: str
    text: Optional[str] = ""
    type: Optional[str] = "text"
    senderName: Optional[str] = None
    senderAvatar: Optional[str] = None
    mediaUrl: Optional[str] = None
    mediaPath: Optional[str] = None
    thumbnailUrl: Optional[str] = None
    replyTo: Optional[Dict[str, Any]] = None
    metadata: Optional[Dict[str, Any]] = None


class MarkReadRequest(BaseModel):
    chatId: str
    messageIds: Optional[List[str]] = None


class ReactionRequest(BaseModel):
    chatId: str
    messageId: str
    emoji: str


class DeleteMessageRequest(BaseModel):
    chatId: str
    messageId: str
    forEveryone: bool = False


# ── REST Endpoints ────────────────────────────────────────────────────────────

@chat_router.post("/token")
async def register_device_token(
    req: TokenRegistrationRequest,
    uid: str = Depends(authenticate_user),
):
    """Registers device FCM token on the VPS for push notifications."""
    await run_in_threadpool(
        chat_db.register_device_token,
        uid=uid,
        token=req.token,
        device_id=req.deviceId,
        email=req.email,
        platform=req.platform,
    )
    return {"status": "success"}


@chat_router.get("/conversations")
async def list_conversations(uid: str = Depends(authenticate_user)):
    """Returns all conversations for the authenticated user."""
    convs = await run_in_threadpool(chat_db.list_conversations, uid=uid)
    return {"conversations": convs}


@chat_router.get("/messages/{chat_id}")
async def get_messages(
    chat_id: str,
    before: Optional[int] = Query(None),
    limit: int = Query(50, ge=1, le=100),
    uid: str = Depends(authenticate_user),
):
    """Returns paginated messages for a conversation."""
    msgs = await run_in_threadpool(
        chat_db.get_messages,
        chat_id=chat_id,
        uid=uid,
        before_time=before,
        limit=limit,
    )
    return {"messages": msgs}


@chat_router.post("/message")
async def send_message(
    req: SendMessageRequest,
    uid: str = Depends(authenticate_user),
):
    """Sends a message, delivers via WebSocket if recipient is online, or via FCM push."""
    participants = sorted([uid, req.recipientId])
    await run_in_threadpool(
        chat_db.get_or_create_conversation,
        chat_id=req.chatId,
        participants=participants,
    )

    msg_dict = {
        "chatId": req.chatId,
        "senderId": uid,
        "senderName": req.senderName or "Explorer",
        "senderAvatar": req.senderAvatar,
        "text": req.text or "",
        "type": req.type or "text",
        "mediaUrl": req.mediaUrl,
        "mediaPath": req.mediaPath,
        "thumbnailUrl": req.thumbnailUrl,
        "replyTo": req.replyTo,
        "metadata": req.metadata,
        "status": "sent",
        "createdAt": _now_ms(),
    }

    saved = await run_in_threadpool(chat_db.save_message, msg_dict)
    message_id = saved["id"]

    # A socket that accepted the write is not proof that the phone showed the
    # message: a phone that is asleep or frozen accepts writes too. A recipient
    # whose app confirms messages is pushed unless the confirmation arrives.
    confirming = ws_manager.recipient_confirms(req.recipientId)
    ack = ws_manager.expect_ack(message_id, req.recipientId) if confirming else None

    # Broadcast to recipient via WebSocket
    ws_payload = {"type": "new_message", "message": saved}
    delivered = await ws_manager.send_to_user(req.recipientId, ws_payload)

    preview = req.text or (f"Sent a {req.type}" if req.type != "text" else "New message")
    push_args = {
        "recipient_uid": req.recipientId,
        "title": req.senderName or "New Message",
        "body": preview,
        "data": {
            "action": "chat",
            "chatId": req.chatId,
            "senderId": uid,
            "senderName": req.senderName or "Explorer",
            "messageId": message_id,
        },
        "image_url": req.thumbnailUrl or req.mediaUrl,
    }
    if not delivered:
        # No socket took the message, so trigger immediate high-priority FCM push.
        ws_manager.forget_ack(message_id)
        await run_in_threadpool(push_dispatcher.send_push_to_uid, **push_args)
    elif ack is not None:
        _start_background(_push_unless_confirmed(ack, message_id, push_args))

    return {"status": "success", "message": saved, "onlineDelivered": delivered}


@chat_router.post("/read")
async def mark_messages_read(
    req: MarkReadRequest,
    uid: str = Depends(authenticate_user),
):
    updated_ids = await run_in_threadpool(
        chat_db.mark_read,
        chat_id=req.chatId,
        uid=uid,
        message_ids=req.messageIds,
    )
    # Notify other participants via WebSocket
    crow = await run_in_threadpool(chat_db._get_conn().execute, "SELECT participants FROM conversations WHERE chat_id = ?", (req.chatId,))
    row = crow.fetchone()
    if row:
        try:
            parts = json.loads(row["participants"])
            await ws_manager.broadcast_to_participants(
                parts,
                {"type": "read", "chatId": req.chatId, "readerId": uid, "messageIds": updated_ids},
                exclude_uid=uid,
            )
        except Exception:
            pass
    return {"status": "success", "updatedCount": len(updated_ids)}


@chat_router.post("/reaction")
async def toggle_reaction(
    req: ReactionRequest,
    uid: str = Depends(authenticate_user),
):
    reactions = await run_in_threadpool(
        chat_db.set_reaction,
        chat_id=req.chatId,
        message_id=req.messageId,
        uid=uid,
        emoji=req.emoji,
    )
    # Broadcast reaction event
    crow = await run_in_threadpool(chat_db._get_conn().execute, "SELECT participants FROM conversations WHERE chat_id = ?", (req.chatId,))
    row = crow.fetchone()
    if row:
        try:
            parts = json.loads(row["participants"])
            await ws_manager.broadcast_to_participants(
                parts,
                {"type": "reaction", "chatId": req.chatId, "messageId": req.messageId, "reactions": reactions},
            )
        except Exception:
            pass
    return {"status": "success", "reactions": reactions}


@chat_router.post("/delete")
async def delete_message(
    req: DeleteMessageRequest,
    uid: str = Depends(authenticate_user),
):
    deleted = await run_in_threadpool(
        chat_db.delete_message,
        chat_id=req.chatId,
        message_id=req.messageId,
        uid=uid,
        for_everyone=req.forEveryone,
    )
    if req.forEveryone:
        crow = await run_in_threadpool(chat_db._get_conn().execute, "SELECT participants FROM conversations WHERE chat_id = ?", (req.chatId,))
        row = crow.fetchone()
        if row:
            try:
                parts = json.loads(row["participants"])
                await ws_manager.broadcast_to_participants(
                    parts,
                    {"type": "message_deleted", "chatId": req.chatId, "messageId": req.messageId},
                )
            except Exception:
                pass
    return {"status": "success", "deleted": deleted}


@chat_router.get("/online_status/{target_uid}")
async def get_online_status(
    target_uid: str,
    uid: str = Depends(authenticate_user),
):
    return {"uid": target_uid, "isOnline": ws_manager.is_online(target_uid)}


STUN_URLS = [
    "stun:stun.l.google.com:19302",
    "stun:stun1.l.google.com:19302",
    "stun:stun2.l.google.com:19302",
    "stun:stun.cloudflare.com:3478",
]
TURN_URLS = [
    "turn:148.135.137.245:3478?transport=udp",
    "turn:148.135.137.245:3478?transport=tcp",
]
# A TURN credential is short-lived and bound to the caller. The app refetches it
# before it expires, so a leaked credential stops working within the hour.
ICE_CREDENTIAL_TTL_SECONDS = 3600


def build_ice_servers(uid: str, secret: str, now: Optional[int] = None) -> Dict[str, Any]:
    """ICE servers for one caller. The TURN username is `<expiry>:<uid>`, the shared-secret form coturn checks."""
    expires_at = (int(time.time()) if now is None else now) + ICE_CREDENTIAL_TTL_SECONDS
    username = f"{expires_at}:{uid}"
    digest = hmac.new(secret.encode("utf-8"), username.encode("utf-8"), hashlib.sha1).digest()
    return {
        "iceServers": [
            {"urls": STUN_URLS},
            {
                "urls": TURN_URLS,
                "username": username,
                "credential": base64.b64encode(digest).decode("ascii"),
            },
        ],
        "sdpSemantics": "unified-plan",
        "expiresAt": expires_at,
    }


@chat_router.get("/ice_servers")
async def get_ice_servers(uid: str = Depends(authenticate_user)):
    """STUN and TURN settings for a call. Needs a signed-in user, and fails closed without the TURN secret."""
    secret = os.getenv("SOTTO_TURN_SECRET", "")
    if not secret:
        # Without the secret no TURN credential can be issued. The app then falls back to STUN only.
        raise HTTPException(status_code=503, detail="The call relay is not configured.")
    return build_ice_servers(uid, secret)


# ── Call Signaling Relay ──────────────────────────────────────────────────────

# The signals the app sends (call_signaling_service.dart). Anything else is refused.
CALL_SIGNAL_TYPES = frozenset({"offer", "answer", "candidate", "end", "declined"})
MAX_CALL_SIGNAL_BYTES = 64 * 1024
CALL_OFFERS_PER_WINDOW = 6
CALL_OFFER_WINDOW_SECONDS = 600.0
WS_AUTH_TIMEOUT_SECONDS = 10.0
# How long a chat message waits for its recipient's app to confirm it on screen,
# over a socket that can confirm, before the push goes out.
MESSAGE_ACK_SECONDS = 8.0


class CallOfferLimiter:
    """Caps how often one caller can ring. An offer is what rings a phone, so offers are counted per caller."""

    def __init__(
        self,
        limit: int = CALL_OFFERS_PER_WINDOW,
        window_seconds: float = CALL_OFFER_WINDOW_SECONDS,
    ) -> None:
        self.limit = limit
        self.window_seconds = window_seconds
        self._offers: Dict[str, Deque[float]] = {}
        self._lock = threading.Lock()

    def allow(self, uid: str, now: Optional[float] = None) -> bool:
        now = time.monotonic() if now is None else now
        cutoff = now - self.window_seconds
        with self._lock:
            times = self._offers.setdefault(uid, deque())
            while times and times[0] <= cutoff:
                times.popleft()
            if len(times) >= self.limit:
                return False
            times.append(now)
            return True


call_offer_limiter = CallOfferLimiter()


def _short_text(value: Any, limit: int) -> Optional[str]:
    """Display text from client input, cut to `limit` characters. Non-text or blank input gives None."""
    if not isinstance(value, str):
        return None
    return value.strip()[:limit] or None


def _https_url(value: Any) -> Optional[str]:
    """Only https avatars are passed on, so a caller cannot point the callee's screen at another scheme."""
    if isinstance(value, str) and value.startswith("https://") and len(value) <= 512:
        return value
    return None


async def relay_call_signal(websocket: WebSocket, uid: str, data: Dict[str, Any]) -> None:
    """Relays one call signal to the callee, or tells the caller why it was refused.

    The sender's uid comes from the socket, never from the message. An offer also
    counts against the sender's rate limit. Only an offer gets an ack, which says
    whether the callee was connected. A callee who is offline is still rung through
    the Firestore call document.
    """
    call_id = _short_text(data.get("callId"), 64) or ""
    signal_type = data.get("signalType")
    recipient_id = data.get("recipientId")

    refusal: Optional[str] = None
    if (
        not isinstance(signal_type, str)
        or signal_type not in CALL_SIGNAL_TYPES
        or not isinstance(recipient_id, str)
        or not recipient_id
        or recipient_id == uid
    ):
        refusal = "invalid"
    elif len(json.dumps(data)) > MAX_CALL_SIGNAL_BYTES:
        refusal = "too_large"
    elif signal_type == "offer" and not call_offer_limiter.allow(uid):
        refusal = "rate_limited"

    if refusal:
        logger.info("Refused call signal %s from uid %s: %s", signal_type, uid, refusal)
        await websocket.send_json(
            {"type": "call_signal_error", "callId": call_id, "signalType": signal_type, "reason": refusal}
        )
        return

    delivered = await ws_manager.send_to_user(
        recipient_id,
        {
            "type": "call_signal",
            "callId": call_id,
            "callerId": uid,
            "signalType": signal_type,
            "payload": data.get("payload"),
            "isVideo": bool(data.get("isVideo", False)),
            "callerName": _short_text(data.get("callerName"), 80),
            "avatarUrl": _https_url(data.get("avatarUrl")),
        },
    )
    if signal_type == "offer":
        await websocket.send_json({"type": "call_signal_ack", "callId": call_id, "delivered": delivered})


# ── Real-Time WebSocket Endpoint ──────────────────────────────────────────────

@chat_router.websocket("/ws")
async def chat_websocket(
    websocket: WebSocket,
    token: Optional[str] = Query(None),
):
    """Bidirectional WebSocket connection for instant 1-on-1 messages, typing, and WebRTC calls."""
    # The app sends its token as the first message. The query token is still read
    # for builds that predate that change, and it is the reason this path is
    # deprecated: a URL token can end up in proxy and access logs.
    authenticated_uid: Optional[str] = None
    confirms = False

    if token:
        try:
            authenticated_uid = await run_in_threadpool(verify_firebase_uid, token)
        except Exception as e:
            logger.warning("WS token auth failed: %s", e)

    if not authenticated_uid:
        await websocket.accept()
        try:
            auth_msg = await asyncio.wait_for(websocket.receive_json(), timeout=WS_AUTH_TIMEOUT_SECONDS)
            if auth_msg.get("type") == "auth" and auth_msg.get("token"):
                authenticated_uid = await run_in_threadpool(verify_firebase_uid, auth_msg["token"])
                confirms = auth_msg.get("confirms") is True
        except Exception:
            pass

        if not authenticated_uid:
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
            return

        # Register connection
        with ws_manager._lock:
            if authenticated_uid not in ws_manager._connections:
                ws_manager._connections[authenticated_uid] = set()
            ws_manager._connections[authenticated_uid].add(websocket)
        if confirms:
            ws_manager.mark_confirming(websocket)
    else:
        await ws_manager.connect(authenticated_uid, websocket)

    uid = authenticated_uid
    try:
        await websocket.send_json({"type": "authenticated", "uid": uid})

        while True:
            data = await websocket.receive_json()
            mtype = data.get("type")

            if mtype == "ping":
                await websocket.send_json({"type": "pong"})

            elif mtype == "ack":
                message_id = data.get("messageId")
                if isinstance(message_id, str):
                    ws_manager.acknowledge(message_id, uid)

            elif mtype == "typing":
                chat_id = data.get("chatId")
                recipient_id = data.get("recipientId")
                is_typing = bool(data.get("isTyping", False))
                if recipient_id:
                    await ws_manager.send_to_user(
                        recipient_id,
                        {"type": "typing", "chatId": chat_id, "uid": uid, "isTyping": is_typing},
                    )

            elif mtype == "read":
                chat_id = data.get("chatId")
                message_ids = data.get("messageIds")
                if chat_id:
                    updated = await run_in_threadpool(chat_db.mark_read, chat_id, uid, message_ids)
                    recipient_id = data.get("recipientId")
                    if recipient_id:
                        await ws_manager.send_to_user(
                            recipient_id,
                            {"type": "read", "chatId": chat_id, "readerId": uid, "messageIds": updated},
                        )

            elif mtype == "call_signal":
                await relay_call_signal(websocket, uid, data)

    except WebSocketDisconnect:
        ws_manager.disconnect(uid, websocket)
    except Exception as e:
        logger.warning("WS exception for uid %s: %s", uid, e)
        ws_manager.disconnect(uid, websocket)
