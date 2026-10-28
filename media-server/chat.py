"""Bhromon VPS 1-on-1 Chat, WebRTC Signaling & Push Notification Engine.

Replaces Firebase Firestore for 1-on-1 chats, call signaling, and device tokens.
All data is stored in a local SQLite database (bhromon_chat.db) with WAL mode,
completely eliminating Firestore read/write costs and quota exhaustion.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import logging
import os
import sqlite3
import threading
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

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
            if uid in self._connections:
                self._connections[uid].discard(websocket)
                if not self._connections[uid]:
                    del self._connections[uid]
        logger.info("WS disconnected: uid=%s", uid)

    def is_online(self, uid: str) -> bool:
        with self._lock:
            return bool(self._connections.get(uid))

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
        is_call: bool = False,
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
                        channel_id="bhromon_calls" if is_call else "bhromon_general",
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

chat_router = APIRouter(tags=["chat"])


# ── Dependency Authentication ─────────────────────────────────────────────────

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
        import firebase_admin
        from firebase_admin import auth

        decoded = auth.verify_id_token(token, clock_skew_seconds=10)
        uid = decoded.get("uid") or ""
        if not uid:
            raise HTTPException(status_code=401, detail="Token contains no UID")
        return uid
    except Exception as e:
        logger.warning("Token verification failed: %s", e)
        raise HTTPException(status_code=401, detail=f"Invalid authentication token: {e}")


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

    # Broadcast to recipient via WebSocket
    ws_payload = {"type": "new_message", "message": saved}
    delivered = await ws_manager.send_to_user(req.recipientId, ws_payload)

    # If recipient did not receive via WebSocket, trigger immediate high-priority FCM push
    if not delivered:
        preview = req.text or (f"Sent a {req.type}" if req.type != "text" else "New message")
        data_payload = {
            "action": "chat",
            "chatId": req.chatId,
            "senderId": uid,
            "senderName": req.senderName or "Explorer",
            "messageId": saved["id"],
        }
        await run_in_threadpool(
            push_dispatcher.send_push_to_uid,
            recipient_uid=req.recipientId,
            title=req.senderName or "New Message",
            body=preview,
            data=data_payload,
            image_url=req.thumbnailUrl or req.mediaUrl,
        )

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


@chat_router.get("/ice_servers")
async def get_ice_servers():
    """Returns dynamic WebRTC STUN and TURN configurations for robust P2P calling and voice rooms."""
    secret = os.getenv("SOTTO_TURN_SECRET", "cca5620f5cc7916ccdb0112238e9e4b2ff1c4bd0dabd7583a7858d74b282b340").encode("utf-8")
    expiry = int(time.time()) + 86400 * 7  # 7 days
    turn_username = f"{expiry}:bhromon"
    turn_credential = base64.b64encode(hmac.new(secret, turn_username.encode("utf-8"), hashlib.sha1).digest()).decode("utf-8")

    return {
        "iceServers": [
            {
                "urls": [
                    "stun:stun.l.google.com:19302",
                    "stun:stun1.l.google.com:19302",
                    "stun:stun2.l.google.com:19302",
                    "stun:stun.cloudflare.com:3478",
                ],
            },
            {
                "urls": [
                    "turn:openrelay.metered.ca:80",
                    "turn:openrelay.metered.ca:443",
                    "turn:openrelay.metered.ca:443?transport=tcp",
                ],
                "username": "openrelayproject",
                "credential": "openrelayproject",
            },
            {
                "urls": [
                    "turn:148.135.137.245:3478?transport=udp",
                    "turn:148.135.137.245:3478?transport=tcp",
                ],
                "username": turn_username,
                "credential": turn_credential,
            },
        ],
        "sdpSemantics": "unified-plan",
    }


# ── Real-Time WebSocket Endpoint ──────────────────────────────────────────────

@chat_router.websocket("/ws")
async def chat_websocket(
    websocket: WebSocket,
    token: Optional[str] = Query(None),
):
    """Bidirectional WebSocket connection for instant 1-on-1 messages, typing, and WebRTC calls."""
    # Authenticate from query token or first message
    authenticated_uid: Optional[str] = None

    if token:
        try:
            import firebase_admin
            from firebase_admin import auth

            decoded = auth.verify_id_token(token, clock_skew_seconds=10)
            authenticated_uid = decoded.get("uid")
        except Exception as e:
            logger.warning("WS token auth failed: %s", e)

    if not authenticated_uid:
        await websocket.accept()
        try:
            auth_msg = await websocket.receive_json()
            if auth_msg.get("type") == "auth" and auth_msg.get("token"):
                import firebase_admin
                from firebase_admin import auth

                decoded = auth.verify_id_token(auth_msg["token"], clock_skew_seconds=10)
                authenticated_uid = decoded.get("uid")
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
                # Instant WebRTC signaling relay between peers (zero Firestore reads/writes!)
                recipient_id = data.get("recipientId")
                signal_type = data.get("signalType")  # offer, answer, candidate, decline, end
                payload = data.get("payload")

                if recipient_id:
                    delivered = await ws_manager.send_to_user(
                        recipient_id,
                        {
                            "type": "call_signal",
                            "callId": data.get("callId"),
                            "callerId": uid,
                            "signalType": signal_type,
                            "payload": payload,
                            "isVideo": data.get("isVideo", False),
                            "callerName": data.get("callerName"),
                            "avatarUrl": data.get("avatarUrl"),
                        },
                    )
                    # If recipient is offline and this is a new call offer, send high-priority FCM call push
                    if not delivered and signal_type == "offer":
                        await run_in_threadpool(
                            push_dispatcher.send_push_to_uid,
                            recipient_uid=recipient_id,
                            title=f"Incoming Call from {data.get('callerName', 'Traveler')}",
                            body="Tap to answer audio/video call",
                            data={
                                "action": "call",
                                "callId": data.get("callId", ""),
                                "callerId": uid,
                                "callerName": data.get("callerName", "Traveler"),
                                "isVideo": "true" if data.get("isVideo") else "false",
                                "avatarUrl": data.get("avatarUrl", ""),
                            },
                            is_call=True,
                        )

    except WebSocketDisconnect:
        ws_manager.disconnect(uid, websocket)
    except Exception as e:
        logger.warning("WS exception for uid %s: %s", uid, e)
        ws_manager.disconnect(uid, websocket)
