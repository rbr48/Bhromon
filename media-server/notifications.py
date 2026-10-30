"""Bhromon VPS Notification & Background Worker Engine.

Replaces Firebase Cloud Functions on the VPS with direct Firestore real-time
listeners and FCM push notifications via the Firebase Admin SDK.
"""

from __future__ import annotations

import logging
import threading
import time
from collections import deque
from datetime import datetime, timezone
from typing import Any, Callable, Dict, List, Optional, Set, Tuple

logger = logging.getLogger("bhromon.notifications")

AUTH_LOOKUP_LIMIT = 100
FCM_BATCH_LIMIT = 500
PREVIEW_LIMIT = 120
EVERYONE_CHANNEL_ID = "emergency"
CALL_RING_SECONDS = 45
CALL_OFFERS_PER_WINDOW = 10
CALL_OFFER_WINDOW_SECONDS = 600.0

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
            if first.get("kind") == "audio":
                body = "🎤 Voice message"
            elif first.get("isVideo") is True or first.get("kind") == "video":
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
            "call_pushes_sent": 0,
            "dead_tokens_purged": 0,
            "errors": 0,
        }
        self._call_push_times: Dict[str, deque[float]] = {}
        self._call_lock = threading.Lock()

    def _get_db(self):
        if self._db is None:
            import firebase_admin
            from firebase_admin import firestore

            if not firebase_admin._apps:
                import main
                main.init_firebase_admin()
            self._db = firestore.client()
        return self._db

    def _get_auth(self):
        if self._auth is None:
            import firebase_admin
            from firebase_admin import auth

            if not firebase_admin._apps:
                import main
                main.init_firebase_admin()
            self._auth = auth
        return self._auth

    def _get_messaging(self):
        if self._messaging is None:
            import firebase_admin
            from firebase_admin import messaging

            if not firebase_admin._apps:
                import main
                main.init_firebase_admin()
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

    def send_call_push(
        self,
        call_id: str,
        caller_id: str,
        callee_id: str,
        is_video: bool = False,
        caller_name: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Dispatch high-priority call push notification to the callee's devices.

        Android gets a data-only payload (no notification block) so the background
        handler runs and triggers FlutterCallkitIncoming to ring.
        iOS gets an APNs alert block so the system alerts the recipient.
        """
        logger.info("Triggering call push for call=%s from caller=%s to callee=%s", call_id, caller_id, callee_id)
        now = time.monotonic()
        # Rate limiting check
        with self._call_lock:
            times = self._call_push_times.setdefault(caller_id, deque())
            cutoff = now - CALL_OFFER_WINDOW_SECONDS
            while times and times[0] <= cutoff:
                times.popleft()
            if len(times) >= CALL_OFFERS_PER_WINDOW:
                logger.warning("Caller %s rate limited for call pushes (exceeded %d in %ds)", caller_id, CALL_OFFERS_PER_WINDOW, CALL_OFFER_WINDOW_SECONDS)
                return {"status": "rate_limited"}
            times.append(now)

        try:
            # Resolve callee email to UID if needed
            callee_uid = callee_id.strip()
            if "@" in callee_uid:
                uids = self.get_uids_for_emails([callee_uid.lower()])
                if uids:
                    callee_uid = uids[0]
                else:
                    logger.warning("Could not resolve callee email %s to UID", callee_uid)
                    return {"status": "callee_not_found"}

            if callee_uid == caller_id:
                return {"status": "self_call"}

            # Resolve caller displayName if not provided
            c_name = (caller_name or "").strip()
            if not c_name:
                try:
                    db = self._get_db()
                    profile_doc = db.collection("explorer_profiles").document(caller_id).get()
                    if profile_doc.exists:
                        c_name = str((profile_doc.to_dict() or {}).get("displayName", "")).strip()
                except Exception as ex:
                    logger.debug("Failed to fetch caller profile for %s: %s", caller_id, ex)
            if not c_name:
                c_name = "Traveler"

            targets = self.get_push_targets_for_uids([callee_uid])
            if not targets:
                logger.info("No FCM tokens registered for callee %s", callee_uid)
                return {"status": "no_targets"}

            messaging_mod = self._get_messaging()
            now_epoch = int(time.time())
            kind = "Video" if is_video else "Voice"

            data_payload = {
                "action": "call",
                "callId": str(call_id),
                "callerId": str(caller_id),
                "callerName": str(c_name)[:80],
                "isVideo": "true" if is_video else "false",
            }

            android_config = None
            if hasattr(messaging_mod, "AndroidConfig"):
                android_config = messaging_mod.AndroidConfig(
                    priority="high",
                    ttl=CALL_RING_SECONDS,
                )

            apns_config = None
            if hasattr(messaging_mod, "APNSConfig"):
                apns_config = messaging_mod.APNSConfig(
                    headers={
                        "apns-priority": "10",
                        "apns-expiration": str(now_epoch + CALL_RING_SECONDS),
                    },
                    payload=messaging_mod.APNSPayload(
                        aps=messaging_mod.Aps(
                            alert=messaging_mod.ApsAlert(
                                title=f"Incoming {kind} Call",
                                body=f"{c_name} is calling you on Bhromon...",
                            ),
                            sound="default",
                            content_available=True,
                        ),
                    ),
                )

            sent_count = 0
            for i in range(0, len(targets), FCM_BATCH_LIMIT):
                batch = targets[i : i + FCM_BATCH_LIMIT]
                tokens = [t[0] for t in batch]

                multicast = messaging_mod.MulticastMessage(
                    tokens=tokens,
                    data=data_payload,  # DATA-ONLY for Android!
                    android=android_config,
                    apns=apns_config,
                )

                try:
                    response = messaging_mod.send_each_for_multicast(multicast)
                    sent_count += response.success_count

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
                    logger.error("Failed to send call multicast batch: %s", e)

            self.stats["call_pushes_sent"] += sent_count
            logger.info("Sent call push for call %s to %d devices", call_id, sent_count)
            return {"status": "success", "devices_sent": sent_count}
        except Exception as e:
            self.stats["errors"] += 1
            logger.error("Error in send_call_push: %s", e)
            return {"status": "error", "error": str(e)}

    def send_call_ended_push(self, call_id: str, callee_id: str) -> Dict[str, Any]:
        """Notify callee devices that the ringing call ended, dismissing incoming CallKit UI."""
        try:
            callee_uid = callee_id.strip()
            if "@" in callee_uid:
                uids = self.get_uids_for_emails([callee_uid.lower()])
                if uids:
                    callee_uid = uids[0]
                else:
                    return {"status": "callee_not_found"}

            targets = self.get_push_targets_for_uids([callee_uid])
            if not targets:
                return {"status": "no_targets"}

            messaging_mod = self._get_messaging()
            android_config = None
            if hasattr(messaging_mod, "AndroidConfig"):
                android_config = messaging_mod.AndroidConfig(
                    priority="high",
                    ttl=10,
                )

            data_payload = {
                "action": "end_call",
                "callId": str(call_id),
            }

            multicast = messaging_mod.MulticastMessage(
                tokens=[t[0] for t in targets],
                data=data_payload,
                android=android_config,
            )
            response = messaging_mod.send_each_for_multicast(multicast)
            return {"status": "success", "devices_sent": response.success_count}
        except Exception as e:
            logger.error("Error in send_call_ended_push: %s", e)
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

    def on_call_snapshot(self, col_snapshot, changes, read_time):
        """Called when call documents are created or updated in Firestore."""
        for change in changes:
            if change.type.name in {"ADDED", "MODIFIED"}:
                doc = change.document
                call_id = doc.id
                data = doc.to_dict() or {}
                status = data.get("status")

                if status == "calling":
                    if self.is_seen(f"call_start_{call_id}"):
                        continue

                    created_at = data.get("createdAt")
                    if isinstance(created_at, datetime):
                        if created_at.tzinfo is None:
                            created_at = created_at.replace(tzinfo=timezone.utc)
                        if created_at < self.started_at:
                            continue
                        age = (datetime.now(timezone.utc) - created_at).total_seconds()
                        if age > 60:
                            continue

                    caller_id = str(data.get("callerId", "")).strip()
                    callee_id = str(data.get("calleeId", "")).strip()
                    if not caller_id or not callee_id or caller_id == callee_id:
                        continue

                    is_video = bool(data.get("isVideo", False))
                    caller_name = data.get("callerName")

                    self.engine.send_call_push(
                        call_id=call_id,
                        caller_id=caller_id,
                        callee_id=callee_id,
                        is_video=is_video,
                        caller_name=caller_name,
                    )
                elif status in {"ended", "declined", "missed"}:
                    if self.is_seen(f"call_end_{call_id}"):
                        continue
                    callee_id = str(data.get("calleeId", "")).strip()
                    if callee_id:
                        self.engine.send_call_ended_push(call_id, callee_id)

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
            calls_watch = db.collection("calls").on_snapshot(self.on_call_snapshot)
            self.active_listeners.append(calls_watch)
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
