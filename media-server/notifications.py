"""Bhromon VPS Notification & Background Worker Engine.

Replaces Firebase Cloud Functions on the VPS with direct Firestore real-time
listeners and FCM push notifications via the Firebase Admin SDK.
"""

from __future__ import annotations

import logging
import threading
import time
from datetime import datetime, timezone
from typing import Any, Callable, Dict, List, Optional, Set, Tuple

logger = logging.getLogger("bhromon.notifications")

AUTH_LOOKUP_LIMIT = 100
FCM_BATCH_LIMIT = 500
PREVIEW_LIMIT = 120
EVERYONE_CHANNEL_ID = "emergency"

DEAD_TOKEN_CODES = {
    "messaging/registration-token-not-registered",
    "messaging/invalid-registration-token",
    "registration-token-not-registered",
    "invalid-registration-token",
}


def _preview_of(text: Optional[str], attachments: Optional[list] = None, kind: str = "text") -> str:
    """Format push notification preview text."""
    body = (text or "").strip()
    if not body:
        if attachments:
            first = attachments[0] if isinstance(attachments[0], dict) else {}
            if first.get("isVideo") is True or first.get("kind") == "video":
                body = "🎬 Video"
            else:
                body = "📷 Photo"
        elif kind == "poll":
            body = "📊 Poll"
        elif kind == "expense":
            body = "💸 Expense"
        else:
            body = "New message"

    if len(body) > PREVIEW_LIMIT:
        return body[: PREVIEW_LIMIT - 1] + "…"
    return body


class NotificationEngine:
    """Core push notification and maintenance worker backed by Firebase Admin SDK."""

    def __init__(self, db=None, auth_mod=None, messaging_mod=None) -> None:
        self._db = db
        self._auth = auth_mod
        self._messaging = messaging_mod
        self.stats = {
            "sos_sent": 0,
            "channel_pushes_sent": 0,
            "chat_pushes_sent": 0,
            "dead_tokens_purged": 0,
            "errors": 0,
        }

    def _get_db(self):
        if self._db is None:
            import firebase_admin
            from firebase_admin import firestore

            self._db = firestore.client()
        return self._db

    def _get_auth(self):
        if self._auth is None:
            from firebase_admin import auth

            self._auth = auth
        return self._auth

    def _get_messaging(self):
        if self._messaging is None:
            from firebase_admin import messaging

            self._messaging = messaging
        return self._messaging

    def get_active_tour_members(self, tour_id: str, except_email: str = "") -> List[str]:
        """Fetch emails of active tour members excluding sender."""
        db = self._get_db()
        except_clean = except_email.strip().lower()

        docs = (
            db.collection("memberships")
            .where("tourId", "==", tour_id)
            .where("status", "==", "active")
            .stream()
        )

        emails: Set[str] = set()
        for doc in docs:
            data = doc.to_dict() or {}
            email = str(data.get("email", "")).strip().lower()
            if email and email != except_clean:
                emails.add(email)
        return list(emails)

    def get_uids_for_emails(self, emails: List[str]) -> List[str]:
        """Resolve list of user emails to Firebase UIDs."""
        auth_mod = self._get_auth()
        uids: List[str] = []

        for i in range(0, len(emails), AUTH_LOOKUP_LIMIT):
            batch = emails[i : i + AUTH_LOOKUP_LIMIT]
            try:
                # get_users accepts list of UserIdentifier or email strings in admin SDK
                records = [auth_mod.EmailIdentifier(e) for e in batch]
                result = auth_mod.get_users(records)
                for user in result.users:
                    uids.append(user.uid)
            except Exception as e:
                logger.warning("Error fetching UIDs for batch: %s", e)
                # Fallback to single lookup if batch lookup fails
                for email in batch:
                    try:
                        u = auth_mod.get_user_by_email(email)
                        uids.append(u.uid)
                    except Exception:
                        pass
        return uids

    def get_push_targets_for_uids(self, uids: List[str]) -> List[Tuple[str, Any]]:
        """Fetch registered FCM device tokens and document refs for users."""
        db = self._get_db()
        targets: List[Tuple[str, Any]] = []
        seen_tokens: Set[str] = set()

        for uid in uids:
            try:
                user_ref = db.collection("fcm_tokens").document(uid)
                # Multi-device subcollection
                devices = user_ref.collection("devices").stream()
                for d in devices:
                    tok = (d.to_dict() or {}).get("token")
                    if tok and tok not in seen_tokens:
                        seen_tokens.add(tok)
                        targets.append((tok, d.reference))

                # Legacy single token
                legacy = user_ref.get()
                if legacy.exists:
                    legacy_tok = (legacy.to_dict() or {}).get("token")
                    if legacy_tok and legacy_tok not in seen_tokens:
                        seen_tokens.add(legacy_tok)
                        targets.append((legacy_tok, user_ref))
            except Exception as e:
                logger.error("Error reading fcm_tokens for uid %s: %s", uid, e)

        return targets

    def send_multicast(
        self,
        targets: List[Tuple[str, Any]],
        title: str,
        body: str,
        data: Dict[str, str],
        high_priority: bool = False,
    ) -> int:
        """Send multicast push notification in batches of 500."""
        if not targets:
            return 0

        messaging_mod = self._get_messaging()
        sent_count = 0

        for i in range(0, len(targets), FCM_BATCH_LIMIT):
            batch = targets[i : i + FCM_BATCH_LIMIT]
            tokens = [t[0] for t in batch]

            android_config = None
            if hasattr(messaging_mod, "AndroidConfig"):
                android_config = messaging_mod.AndroidConfig(
                    priority="high" if high_priority else "normal"
                )

            multicast = messaging_mod.MulticastMessage(
                tokens=tokens,
                notification=messaging_mod.Notification(title=title, body=body),
                data={str(k): str(v) for k, v in data.items()},
                android=android_config,
            )

            try:
                response = messaging_mod.send_each_for_multicast(multicast)
                sent_count += response.success_count

                # Clean up expired/invalid tokens
                for idx, resp in enumerate(response.responses):
                    if not resp.success and resp.exception:
                        err_code = getattr(resp.exception, "code", "") or str(resp.exception)
                        if any(code in err_code for code in DEAD_TOKEN_CODES):
                            try:
                                batch[idx][1].delete()
                                self.stats["dead_tokens_purged"] += 1
                                logger.info("Purged dead FCM token: %s", err_code)
                            except Exception as ex:
                                logger.warning("Could not delete dead token doc: %s", ex)
            except Exception as e:
                self.stats["errors"] += 1
                logger.error("Failed to send multicast batch: %s", e)

        return sent_count

    def send_sos_alert(
        self,
        tour_id: str,
        alert_id: str,
        sender_email: str,
        sender_name: str = "A member",
    ) -> Dict[str, Any]:
        """Send emergency SOS alert to all other active tour members."""
        logger.info("Triggering SOS alert for tour=%s sender=%s", tour_id, sender_email)
        try:
            emails = self.get_active_tour_members(tour_id, except_email=sender_email)
            if not emails:
                return {"status": "no_recipients"}

            uids = self.get_uids_for_emails(emails)
            targets = self.get_push_targets_for_uids(uids)

            title = f"🚨 SOS from {sender_name}"
            body = "Open Bhromon and check the Family Safety Hub."
            data = {
                "action": "sos",
                "type": "sos",
                "tourId": tour_id,
                "alertId": alert_id,
            }

            count = self.send_multicast(targets, title, body, data, high_priority=True)
            self.stats["sos_sent"] += 1
            return {"status": "success", "recipients": len(emails), "devices_sent": count}
        except Exception as e:
            self.stats["errors"] += 1
            logger.error("Error in send_sos_alert: %s", e)
            return {"status": "error", "error": str(e)}

    def send_channel_message_notification(
        self,
        tour_id: str,
        channel_id: str,
        message_id: str,
        sender_email: str,
        sender_name: str = "A member",
        text: str = "",
        mentions: Optional[List[str]] = None,
        attachments: Optional[List[Dict[str, Any]]] = None,
        kind: str = "text",
    ) -> Dict[str, Any]:
        """Notify emergency channel or mentioned members."""
        try:
            members = self.get_active_tour_members(tour_id, except_email=sender_email)
            mentions_set = {str(m).strip().lower() for m in (mentions or [])}

            if channel_id == EVERYONE_CHANNEL_ID:
                recipients = members
            else:
                recipients = [m for m in members if m in mentions_set or "everyone" in mentions_set]

            if not recipients:
                return {"status": "no_recipients"}

            db = self._get_db()
            channel_doc = (
                db.collection("tours")
                .document(tour_id)
                .collection("channels")
                .document(channel_id)
                .get()
            )
            channel_name = channel_id
            if channel_doc.exists:
                channel_name = (channel_doc.to_dict() or {}).get("name") or channel_id

            uids = self.get_uids_for_emails(recipients)
            targets = self.get_push_targets_for_uids(uids)

            preview = _preview_of(text, attachments, kind)
            title = f"{sender_name} in #{channel_name}"
            data = {
                "action": "channel",
                "tourId": tour_id,
                "channelId": channel_id,
                "messageId": message_id,
            }

            is_high = channel_id == EVERYONE_CHANNEL_ID
            count = self.send_multicast(targets, title, preview, data, high_priority=is_high)
            self.stats["channel_pushes_sent"] += count
            return {"status": "success", "recipients": len(recipients), "devices_sent": count}
        except Exception as e:
            self.stats["errors"] += 1
            logger.error("Error in send_channel_message_notification: %s", e)
            return {"status": "error", "error": str(e)}

    def send_chat_notification(
        self,
        chat_id: str,
        sender_id: str,
        text: str = "",
        message_type: str = "text",
    ) -> Dict[str, Any]:
        """Notify direct chat recipient."""
        try:
            db = self._get_db()
            chat_doc = db.collection("chats").document(chat_id).get()
            if not chat_doc.exists:
                return {"status": "chat_not_found"}

            participants: List[str] = (chat_doc.to_dict() or {}).get("participants", [])
            recipient_id = next((uid for uid in participants if uid != sender_id), None)
            if not recipient_id:
                return {"status": "no_recipient"}

            # Fetch sender name
            sender_name = "Explorer"
            try:
                profile_doc = db.collection("explorer_profiles").document(sender_id).get()
                if profile_doc.exists:
                    sender_name = (profile_doc.to_dict() or {}).get("displayName") or "Explorer"
            except Exception:
                pass

            preview = _preview_of(text, kind=message_type)

            # In-app notification
            try:
                db.collection("users").document(recipient_id).collection("notifications").add({
                    "title": f"New message from {sender_name}",
                    "body": preview,
                    "action": "chat",
                    "uid": sender_id,
                    "chatId": chat_id,
                    "messageType": message_type,
                    "timestamp": datetime.now(timezone.utc),
                })
            except Exception as e:
                logger.warning("Could not write in-app notification: %s", e)

            # Push notification
            targets = self.get_push_targets_for_uids([recipient_id])
            data = {"action": "chat", "chatId": chat_id, "senderId": sender_id}
            count = self.send_multicast(
                targets,
                title=f"New message from {sender_name}",
                body=preview,
                data=data,
                high_priority=False,
            )
            self.stats["chat_pushes_sent"] += count
            return {"status": "success", "devices_sent": count}
        except Exception as e:
            self.stats["errors"] += 1
            logger.error("Error in send_chat_notification: %s", e)
            return {"status": "error", "error": str(e)}

    def run_retention_sweep(self, max_days: int = 90) -> Dict[str, int]:
        """Purge trust events and audit logs older than max_days."""
        try:
            db = self._get_db()
            cutoff = datetime.fromtimestamp(
                time.time() - (max_days * 86400), tz=timezone.utc
            )
            purged_events = 0
            purged_logs = 0

            # trust_events
            old_events = db.collection("trust_events").where("timestamp", "<", cutoff).limit(500).stream()
            for doc in old_events:
                doc.reference.delete()
                purged_events += 1

            # admin_audit_logs
            old_logs = db.collection("admin_audit_logs").where("timestamp", "<", cutoff).limit(500).stream()
            for doc in old_logs:
                doc.reference.delete()
                purged_logs += 1

            logger.info("Retention sweep: purged %d events, %d logs", purged_events, purged_logs)
            return {"purged_events": purged_events, "purged_logs": purged_logs}
        except Exception as e:
            logger.error("Retention sweep error: %s", e)
            return {"error": str(e)}


class FirestoreNotificationWatcher:
    """Real-time listener daemon running on the VPS to capture events as they happen."""

    def __init__(self, engine: NotificationEngine) -> None:
        self.engine = engine
        self.started_at = datetime.now(timezone.utc)
        self.active_listeners: List[Any] = []
        self._processed_ids: Set[str] = set()
        self._lock = threading.Lock()
        self._is_running = False

    def is_seen(self, doc_id: str) -> bool:
        with self._lock:
            if doc_id in self._processed_ids:
                return True
            self._processed_ids.add(doc_id)
            if len(self._processed_ids) > 10000:
                # Keep cache bounded
                to_remove = list(self._processed_ids)[:2000]
                for old in to_remove:
                    self._processed_ids.remove(old)
            return False

    def on_sos_snapshot(self, col_snapshot, changes, read_time):
        """Called when SOS alerts are created in Firestore."""
        for change in changes:
            if change.type.name in {"ADDED", "MODIFIED"}:
                doc = change.document
                if self.is_seen(doc.id):
                    continue
                data = doc.to_dict() or {}
                # Only notify if created after watcher started or flagged pending
                created_at = data.get("createdAt")
                if isinstance(created_at, datetime) and created_at < self.started_at:
                    continue

                tour_ref = doc.reference.parent.parent
                tour_id = tour_ref.id if tour_ref else data.get("tourId")
                sender_email = str(data.get("senderEmail", "")).strip().lower()
                sender_name = str(data.get("senderName", "A member")).strip()

                if tour_id and sender_email:
                    self.engine.send_sos_alert(
                        tour_id=tour_id,
                        alert_id=doc.id,
                        sender_email=sender_email,
                        sender_name=sender_name,
                    )

    def start(self) -> None:
        """Start real-time Firestore listeners."""
        if self._is_running:
            return
        self._is_running = True
        try:
            db = self.engine._get_db()
            logger.info("Starting FirestoreNotificationWatcher listeners...")
            sos_watch = db.collection_group("sos").on_snapshot(self.on_sos_snapshot)
            self.active_listeners.append(sos_watch)
        except Exception as e:
            logger.warning("Could not attach real-time Firestore listener: %s", e)

    def stop(self) -> None:
        """Unsubscribe all listeners."""
        self._is_running = False
        for listener in self.active_listeners:
            try:
                listener.unsubscribe()
            except Exception:
                pass
        self.active_listeners.clear()
        logger.info("FirestoreNotificationWatcher stopped.")
