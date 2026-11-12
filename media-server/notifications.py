"""Bhromon VPS Notification & Background Worker Engine.

Replaces Firebase Cloud Functions on the VPS with direct Firestore real-time
listeners and FCM push notifications via the Firebase Admin SDK.
"""

from __future__ import annotations

import logging
import threading
import time
from collections import deque
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict, List, Optional, Set, Tuple

from push_strings import DEFAULT_LANGUAGE, normalize_language, push_text
from fund_policy import fund_allowed
from sos_policy import sos_allowed

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


def _preview_of(
    text: Optional[str],
    attachments: Optional[list] = None,
    kind: str = "text",
    language: str = DEFAULT_LANGUAGE,
) -> str:
    """Format push notification preview text, in the recipient's language."""
    body = (text or "").strip()
    if not body:
        if attachments:
            first = attachments[0] if isinstance(attachments[0], dict) else {}
            if first.get("kind") == "audio":
                body = push_text(language, "preview.voice")
            elif first.get("isVideo") is True or first.get("kind") == "video":
                body = push_text(language, "preview.video")
            else:
                body = push_text(language, "preview.photo")
        elif kind == "poll":
            body = push_text(language, "preview.poll")
        elif kind == "expense":
            body = push_text(language, "preview.expense")
        else:
            body = push_text(language, "preview.text")

    if len(body) > PREVIEW_LIMIT:
        return body[: PREVIEW_LIMIT - 1] + "…"
    return body



# How long after it is created a call can still be ringing on some phone: the
# ring time plus room for a slow push. Older calls need no ring or ring-stop push.
CALL_PUSH_WINDOW_SECONDS = 120
# Journey events from around the start onwards are pushed; older ones are not.
JOURNEY_PUSH_WINDOW_SECONDS = 60
# Study replies and materials written or published from this long before the start onwards are pushed.
STUDY_PUSH_WINDOW_SECONDS = 15 * 60
# A material that this many members have reported is pushed to the owners and admins once, so they know the
# report is not one person's complaint. The first report already hides it and puts it in the review queue.
STUDY_REPEAT_REPORTS = 2
# One record per study push that was sent, so a restart does not send it again. Clients cannot read it.
PUSH_CLAIMS = "push_claims"
# SOS. An alert pushes once. One sender's alerts push at most once in each window of this many seconds, so a
# single person cannot ring the whole group again and again; the later alerts still show in the app.
SOS_RATE_WINDOW_SECONDS = 120
# A restart catches up on alerts raised this long before it started, so a deploy does not drop one.
SOS_CATCH_UP_SECONDS = 10 * 60
# The app asks the VPS to push its own alert right after writing it. The alert must be this recent.
SOS_OWN_ALERT_SECONDS = 10 * 60
# The channel of an SOS push: loud, and separate from the general channel every other push uses.
SOS_CHANNEL_ID = "bhromon_sos"
# The name of a sender with no name in the group.
SOS_DEFAULT_NAME = "A member"


def stamp_is_recent(stamp: Any, since: datetime) -> bool:
    """Whether a stored time is at or after `since`. A missing time counts as recent, so a push is not lost."""
    if not isinstance(stamp, datetime):
        return True
    if stamp.tzinfo is None:
        stamp = stamp.replace(tzinfo=timezone.utc)
    return stamp >= since


def call_may_still_ring(created_at: Any, now: Optional[datetime] = None) -> bool:
    """Whether a call created at `created_at` could still be ringing. A call with
    no readable creation time is treated as recent, so it is never left ringing."""
    if not isinstance(created_at, datetime):
        return True
    if created_at.tzinfo is None:
        created_at = created_at.replace(tzinfo=timezone.utc)
    now = now or datetime.now(timezone.utc)
    return (now - created_at).total_seconds() <= CALL_PUSH_WINDOW_SECONDS

# How many entries one batch of the notification list writes (Firestore allows 500 writes a batch).
INBOX_BATCH_SIZE = 400
# The fields of a push's data that name its item, in the order the list reads them. The first one present
# becomes the entry's itemId, which the app opens the page with.
INBOX_ITEM_KEYS = (
    "noticeId", "expenseId", "alertId", "eventId", "threadId", "materialId", "setId", "subjectId",
    "sessionId", "dateId", "dateKey",
)


class NotificationEngine:
    """Core push notification and maintenance worker backed by Firebase Admin SDK."""

    def __init__(self, db=None, auth_mod=None, messaging_mod=None, chat_db=None) -> None:
        self._db = db
        self._auth = auth_mod
        self._messaging = messaging_mod
        self._chat_db = chat_db
        self.stats = {
            "sos_sent": 0,
            "channel_pushes_sent": 0,
            "chat_pushes_sent": 0,
            "call_pushes_sent": 0,
            "post_pushes_sent": 0,
            "comment_pushes_sent": 0,
            "reaction_pushes_sent": 0,
            "notice_pushes_sent": 0,
            "ledger_pushes_sent": 0,
            "broadcast_pushes_sent": 0,
            "dead_tokens_purged": 0,
            "errors": 0,
        }
        self._call_push_times: Dict[str, deque[float]] = {}
        self._call_lock = threading.Lock()
        self._seen_keys: Set[str] = set()
        self._seen_lock = threading.Lock()

    def is_seen(self, key: str) -> bool:
        """Atomic deduplication check. Returns True if key was already processed."""
        with self._seen_lock:
            if key in self._seen_keys:
                return True
            self._seen_keys.add(key)
            if len(self._seen_keys) > 10000:
                for old in list(self._seen_keys)[:2000]:
                    self._seen_keys.remove(old)
            return False

    def set_chat_db(self, chat_db: Any) -> None:
        self._chat_db = chat_db

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

    def get_push_targets_for_uids(self, uids: List[str]) -> List[Tuple[str, Any, str]]:
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
                    device = d.to_dict() or {}
                    tok = device.get("token")
                    if tok and tok not in seen_tokens:
                        seen_tokens.add(tok)
                        targets.append(
                            (tok, d.reference, normalize_language(device.get("language")))
                        )

                # Legacy single token
                legacy = user_ref.get()
                if legacy.exists:
                    legacy_doc = legacy.to_dict() or {}
                    legacy_tok = legacy_doc.get("token")
                    if legacy_tok and legacy_tok not in seen_tokens:
                        seen_tokens.add(legacy_tok)
                        targets.append(
                            (
                                legacy_tok,
                                user_ref,
                                normalize_language(legacy_doc.get("language")),
                            )
                        )
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
        sos_tag: Optional[str] = None,
    ) -> int:
        """Send multicast push notification in batches of 500.

        `sos_tag` marks a safety alert. Its push goes on the SOS channel, and an iPhone shows it
        time-sensitive. An alert and its end share the tag, so the end replaces the alert on the phone.
        """
        if not targets:
            return 0

        messaging_mod = self._get_messaging()
        sent_count = 0

        for i in range(0, len(targets), FCM_BATCH_LIMIT):
            batch = targets[i : i + FCM_BATCH_LIMIT]
            tokens = [t[0] for t in batch]

            android_config = None
            if hasattr(messaging_mod, "AndroidConfig"):
                if sos_tag:
                    android_config = messaging_mod.AndroidConfig(
                        priority="high",
                        collapse_key=sos_tag,
                        notification=messaging_mod.AndroidNotification(
                            channel_id=SOS_CHANNEL_ID, tag=sos_tag
                        ),
                    )
                else:
                    android_config = messaging_mod.AndroidConfig(
                        priority="high" if high_priority else "normal"
                    )

            apns_config = None
            if sos_tag and hasattr(messaging_mod, "APNSConfig"):
                apns_config = messaging_mod.APNSConfig(
                    headers={"apns-priority": "10", "apns-collapse-id": sos_tag},
                    payload=messaging_mod.APNSPayload(
                        aps=messaging_mod.Aps(
                            sound="default",
                            custom_data={"interruption-level": "time-sensitive"},
                        ),
                    ),
                )

            multicast = messaging_mod.MulticastMessage(
                tokens=tokens,
                notification=messaging_mod.Notification(title=title, body=body),
                data={str(k): str(v) for k, v in data.items()},
                android=android_config,
                apns=apns_config,
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

    def record_inbox(self, uids: Any, data: Dict[str, str], make_text: Any) -> int:
        """Keeps a push in each member's notification list (users/{uid}/notifications), in the member's own
        language, so a push that was missed can still be read and opened. Every member is kept, including one
        with no device to push to. Written with the admin SDK in batches of INBOX_BATCH_SIZE. A failure is
        logged and never stops the push itself."""
        try:
            from google.cloud import firestore

            db = self._get_db()
            item = next((str(data[key]) for key in INBOX_ITEM_KEYS if data.get(key)), None)
            tour = str(data.get("tourId") or "") or None
            action = str(data.get("action", ""))
            written = 0
            pending = 0
            batch = db.batch()
            for uid in dict.fromkeys(u for u in uids if u):
                title, body = make_text(self.get_language_for_uid(uid))
                entry: Dict[str, Any] = {
                    "title": title,
                    "body": body,
                    "action": action,
                    "read": False,
                    "timestamp": firestore.SERVER_TIMESTAMP,
                }
                if tour:
                    entry["tourId"] = tour
                if item:
                    entry["itemId"] = item
                ref = db.collection("users").document(uid).collection("notifications").document()
                batch.set(ref, entry)
                written += 1
                pending += 1
                if pending == INBOX_BATCH_SIZE:
                    batch.commit()
                    batch = db.batch()
                    pending = 0
            if pending:
                batch.commit()
            return written
        except Exception as e:
            logger.warning("Could not keep the push in the notification list: %s", e)
            return 0

    def get_language_for_uid(self, uid: str) -> str:
        """The language the user's latest device registered with, or English."""
        try:
            doc = self._get_db().collection("fcm_tokens").document(uid).get()
            if doc.exists:
                return normalize_language((doc.to_dict() or {}).get("language"))
        except Exception as e:
            logger.debug("Could not read the push language for %s: %s", uid, e)
        return DEFAULT_LANGUAGE

    def send_localized(
        self,
        targets: List[Tuple[str, Any, str]],
        make_text,
        data: Dict[str, str],
        high_priority: bool = False,
        sos_tag: Optional[str] = None,
    ) -> int:
        """Send one push per language. make_text(language) returns (title, body).

        Each device gets the text in the language it registered with.
        """
        groups: Dict[str, List[Tuple[str, Any]]] = {}
        for token, ref, language in targets:
            groups.setdefault(normalize_language(language), []).append((token, ref))
        sent = 0
        # The SOS option is passed only for a safety alert, so other pushes keep their call as it was.
        options: Dict[str, Any] = {"high_priority": high_priority}
        if sos_tag:
            options["sos_tag"] = sos_tag
        for language, group in groups.items():
            title, body = make_text(language)
            sent += self.send_multicast(group, title, body, data, **options)
        return sent

    def claim_once(self, key: str) -> bool:
        """Records that a push was sent, under `key`, in a transaction. False when it was already recorded,
        so a restart, or a second route to the same push, does not send it again."""
        from google.cloud import firestore

        db = self._get_db()
        ref = db.collection(PUSH_CLAIMS).document(key)

        def claim(transaction: Any, ref_: Any) -> bool:
            if ref_.get(transaction=transaction).exists:
                return False
            transaction.create(ref_, {"sentAt": firestore.SERVER_TIMESTAMP})
            return True

        return firestore.transactional(claim)(db.transaction(), ref)

    def tour_allows_sos(self, tour_id: str) -> bool:
        """Whether the tour has SOS (sos_policy.py). A tour that is not there has none."""
        snapshot = self._get_db().collection("tours").document(tour_id).get()
        return bool(snapshot.exists) and sos_allowed(snapshot.to_dict() or {})

    def tour_allows_fund(self, tour_id: str) -> bool:
        """Whether the tour keeps the shared fund (fund_policy.py). A tour that is not there keeps none."""
        snapshot = self._get_db().collection("tours").document(tour_id).get()
        return bool(snapshot.exists) and fund_allowed(snapshot.to_dict() or {})

    def member_display_name(self, tour_id: str, email: str) -> str:
        """The name a member has in the group, from the membership row. The name an alert was written
        with is never used, because any member can write any name there."""
        snapshot = self._get_db().collection("memberships").document(f"{tour_id}__{email}").get()
        name = str((snapshot.to_dict() or {}).get("displayName", "")).strip() if snapshot.exists else ""
        return name[:80] or SOS_DEFAULT_NAME

    def _sos_recipients(self, tour_id: str, sender_email: str) -> Tuple[List[str], List[Tuple[str, Any, str]]]:
        """The uids and the devices of every other active member of the tour."""
        emails = self.get_active_tour_members(tour_id, except_email=sender_email)
        if not emails:
            return [], []
        uids = self.get_uids_for_emails(emails)
        return uids, self.get_push_targets_for_uids(uids)

    def send_sos_alert(
        self,
        tour_id: str,
        alert_id: str,
        sender_email: str,
        sender_name: str = "",
    ) -> Dict[str, Any]:
        """Push a safety alert to every other active member of its tour, once.

        Only a tour with SOS is pushed. The name is the one the group has for the sender, not the
        `sender_name` given (the argument is kept so older callers still work, and it is ignored).
        """
        sender = sender_email.strip().lower()
        if not self.tour_allows_sos(tour_id):
            logger.info("SOS not pushed: tour %s has no SOS", tour_id)
            return {"status": "not_allowed"}
        # The rate window is claimed first, so two alerts from one sender cannot both pass.
        bucket = int(time.time() // SOS_RATE_WINDOW_SECONDS)
        if not self.claim_once(f"sos_rate_{tour_id}_{sender}_{bucket}"):
            logger.info("SOS not pushed: %s has raised one in this window", sender)
            return {"status": "rate_limited"}
        if not self.claim_once(f"sos_{alert_id}"):
            return {"status": "already_sent"}
        try:
            uids, targets = self._sos_recipients(tour_id, sender)
            if not uids:
                return {"status": "no_recipients"}
            name = self.member_display_name(tour_id, sender)
            data = {"action": "sos", "type": "sos", "tourId": tour_id, "alertId": alert_id}

            def make_text(lang: str) -> Tuple[str, str]:
                return push_text(lang, "sos.title", sender=name), push_text(lang, "sos.body")

            self.record_inbox(uids, data, make_text)
            if not targets:
                return {"status": "no_recipients"}
            count = self.send_localized(
                targets,
                make_text,
                data,
                high_priority=True,
                sos_tag=f"sos_{alert_id}",
            )
            self.stats["sos_sent"] += 1
            return {"status": "success", "recipients": len(targets), "devices_sent": count}
        except Exception as e:
            self.stats["errors"] += 1
            logger.error("Error in send_sos_alert: %s", e)
            return {"status": "error", "error": str(e)}

    def send_sos_ended(self, tour_id: str, alert_id: str, sender_email: str) -> Dict[str, Any]:
        """Tell the members an alert is over. It is sent only for an alert that was pushed, and once. It
        shares the alert's tag, so it replaces the alert on the phones that still show it."""
        sender = sender_email.strip().lower()
        if not self._claim_recorded(f"sos_{alert_id}"):
            return {"status": "not_pushed"}
        if not self.claim_once(f"sos_ended_{alert_id}"):
            return {"status": "already_sent"}
        try:
            _, targets = self._sos_recipients(tour_id, sender)
            if not targets:
                return {"status": "no_recipients"}
            name = self.member_display_name(tour_id, sender)
            data = {"action": "sos", "type": "sos", "tourId": tour_id, "alertId": alert_id}
            count = self.send_localized(
                targets,
                lambda lang: (
                    push_text(lang, "sos.ended.title", sender=name),
                    push_text(lang, "sos.ended.body"),
                ),
                data,
                high_priority=True,
                sos_tag=f"sos_{alert_id}",
            )
            return {"status": "success", "devices_sent": count}
        except Exception as e:
            self.stats["errors"] += 1
            logger.error("Error in send_sos_ended: %s", e)
            return {"status": "error", "error": str(e)}

    def _claim_recorded(self, key: str) -> bool:
        """Whether a push was already recorded under `key`."""
        return bool(self._get_db().collection(PUSH_CLAIMS).document(key).get().exists)

    def push_own_sos(self, tour_id: str, alert_id: str, sender_email: str) -> Dict[str, Any]:
        """Push an alert the caller raised, for the request the app makes right after it writes the alert.

        The alert must exist, be the caller's, be unresolved, be recent, and be in a tour with SOS. Otherwise
        nothing is pushed and the reason is returned: the request cannot make an alert that the group cannot see.
        """
        sender = sender_email.strip().lower()
        if not self.tour_allows_sos(tour_id):
            return {"status": "refused", "reason": "not_allowed"}
        snapshot = (
            self._get_db().collection("tours").document(tour_id).collection("sos").document(alert_id).get()
        )
        if not snapshot.exists:
            return {"status": "refused", "reason": "no_alert"}
        data = snapshot.to_dict() or {}
        if str(data.get("senderEmail", "")).strip().lower() != sender:
            return {"status": "refused", "reason": "not_sender"}
        if data.get("resolved") is not False:
            return {"status": "refused", "reason": "resolved"}
        recent_since = datetime.now(timezone.utc) - timedelta(seconds=SOS_OWN_ALERT_SECONDS)
        if not stamp_is_recent(data.get("createdAt"), recent_since):
            return {"status": "refused", "reason": "too_old"}
        return self.send_sos_alert(tour_id, alert_id, sender)

    def get_active_tour_admins(self, tour_id: str, except_email: str = "") -> List[str]:
        """Emails of the active owners and admins of a tour, except one."""
        db = self._get_db()
        except_clean = except_email.strip().lower()
        emails: Set[str] = set()
        docs = (
            db.collection("memberships")
            .where("tourId", "==", tour_id)
            .where("status", "==", "active")
            .stream()
        )
        for doc in docs:
            data = doc.to_dict() or {}
            email = str(data.get("email", "")).strip().lower()
            if email and email != except_clean and data.get("role") in ("owner", "admin"):
                emails.add(email)
        return list(emails)

    def send_study_reply(
        self,
        tour_id: str,
        book_id: str,
        thread_id: str,
        asker_email: str,
        thread_title: str,
    ) -> int:
        """Tells the member who asked a discussion question that someone replied to it."""
        uids = self.get_uids_for_emails([asker_email])
        targets = self.get_push_targets_for_uids(uids)
        title = thread_title.strip()
        data = {"action": "study_reply", "tourId": tour_id, "bookId": book_id, "threadId": thread_id}

        def make_text(lang: str) -> Tuple[str, str]:
            return (
                push_text(lang, "study.reply.head"),
                push_text(lang, "study.reply.body", title=title or push_text(lang, "study.reply.untitled")),
            )

        count = self.send_localized(targets, make_text, data)
        self.record_inbox(uids, data, make_text)
        self.stats["study_reply_sent"] = self.stats.get("study_reply_sent", 0) + count
        return count

    def send_study_material(
        self,
        tour_id: str,
        book_id: str,
        material_id: str,
        title: str,
        emails: List[str],
        pending: bool,
        kind: Optional[str] = None,
    ) -> int:
        """Tells members that a material was shared, or the admins that one waits for their approval, or
        that it has been reported again (kind "reported")."""
        uids = self.get_uids_for_emails(emails)
        targets = self.get_push_targets_for_uids(uids)
        kind = kind or ("review" if pending else "shared")
        name = title.strip()
        data = {"action": "study_material", "tourId": tour_id, "bookId": book_id, "materialId": material_id}

        def make_text(lang: str) -> Tuple[str, str]:
            return (
                push_text(lang, f"study.material.{kind}.head"),
                push_text(lang, f"study.material.{kind}.body", title=name or push_text(lang, "study.material.untitled")),
            )

        count = self.send_localized(targets, make_text, data)
        self.record_inbox(uids, data, make_text)
        self.stats["study_material_sent"] = self.stats.get("study_material_sent", 0) + count
        return count

    def send_study_mention(self, tour_id: str, book_id: str, thread_id: str, title: str, emails: List[str]) -> int:
        """Tells the members a discussion names with @ that they were mentioned in it."""
        uids = self.get_uids_for_emails(emails)
        targets = self.get_push_targets_for_uids(uids)
        name = title.strip()
        data = {"action": "study_reply", "tourId": tour_id, "bookId": book_id, "threadId": thread_id}

        def make_text(lang: str) -> Tuple[str, str]:
            return (
                push_text(lang, "study.mention.head"),
                push_text(lang, "study.mention.body", title=name or push_text(lang, "study.reply.untitled")),
            )

        count = self.send_localized(targets, make_text, data)
        self.record_inbox(uids, data, make_text)
        self.stats["study_mention_sent"] = self.stats.get("study_mention_sent", 0) + count
        return count

    def send_study_subject(
        self,
        tour_id: str,
        subject_id: str,
        kind: str,
        title: str,
        subject_title: str,
        emails: List[str],
    ) -> int:
        """Tells members that an assignment or a past paper was added to a subject, or the admins that one waits
        for their approval. `kind` is one of assignment.new, assignment.review, paper.new or paper.review."""
        uids = self.get_uids_for_emails(emails)
        targets = self.get_push_targets_for_uids(uids)
        name = title.strip()
        subject_name = subject_title.strip()
        data = {"action": "study_subject", "tourId": tour_id, "subjectId": subject_id}

        def make_text(lang: str) -> Tuple[str, str]:
            return (
                push_text(lang, f"study.{kind}.head"),
                push_text(
                    lang,
                    f"study.{kind}.body",
                    title=name or push_text(lang, "study.assignment.untitled"),
                    subject=subject_name or push_text(lang, "study.subject.untitled"),
                ),
            )

        count = self.send_localized(targets, make_text, data)
        self.record_inbox(uids, data, make_text)
        self.stats["study_subject_sent"] = self.stats.get("study_subject_sent", 0) + count
        return count

    def send_journey_event(
        self,
        tour_id: str,
        event_id: str,
        sender_email: str,
        sender_name: str,
        stop_name: str,
        kind: str,
    ) -> Dict[str, Any]:
        """Tells the other active members of a tour that a member arrived at, or left, a
        stop (roadmap LJ-4.3). The push carries the stop's name and no position."""
        if kind not in ("arrive", "depart"):
            return {"status": "ignored"}
        logger.info("Journey %s for tour=%s sender=%s", kind, tour_id, sender_email)
        try:
            emails = self.get_active_tour_members(tour_id, except_email=sender_email)
            if not emails:
                return {"status": "no_recipients"}
            uids = self.get_uids_for_emails(emails)
            targets = self.get_push_targets_for_uids(uids)
            data = {
                "action": "journey",
                "type": "journey",
                "tourId": tour_id,
                "eventId": event_id,
            }
            def make_text(lang: str) -> Tuple[str, str]:
                return (
                    push_text(lang, f"journey.{kind}.title", sender=sender_name, place=stop_name),
                    push_text(lang, "journey.body"),
                )

            count = self.send_localized(targets, make_text, data)
            self.record_inbox(uids, data, make_text)
            self.stats["journey_sent"] = self.stats.get("journey_sent", 0) + 1
            return {"status": "success", "recipients": len(emails), "devices_sent": count}
        except Exception as e:
            self.stats["errors"] += 1
            logger.error("Error in send_journey_event: %s", e)
            return {"status": "error", "error": str(e)}

    def send_topic_push(
        self, topic: str, title: str, body: str, data: Dict[str, str]
    ) -> Dict[str, Any]:
        """Pushes one message to every device subscribed to `topic`. The caller decides what a failure means."""
        try:
            messaging_mod = self._get_messaging()
            message = messaging_mod.Message(
                topic=topic,
                notification=messaging_mod.Notification(title=title, body=body),
                data={str(k): str(v) for k, v in data.items()},
            )
            return {"status": "success", "messageId": messaging_mod.send(message)}
        except Exception as e:
            self.stats["errors"] += 1
            logger.error("Error in send_topic_push: %s", e)
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
        """Push a channel message to the other active members of the tour.

        Everyone hears about a message in a group channel. The emergency
        channel is high priority.
        """
        if self.is_seen(f"channel_{tour_id}_{channel_id}_{message_id}"):
            logger.info("Channel message %s already sent; skipping duplicate", message_id)
            return {"status": "already_sent"}
        try:
            members = self.get_active_tour_members(tour_id, except_email=sender_email)
            recipients = members

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

            data = {
                "action": "channel",
                "tourId": tour_id,
                "channelId": channel_id,
                "messageId": message_id,
            }

            is_high = channel_id == EVERYONE_CHANNEL_ID
            count = self.send_localized(
                targets,
                lambda lang: (
                    push_text(lang, "channel.title", sender=sender_name, channel=channel_name),
                    _preview_of(text, attachments, kind, language=lang),
                ),
                data,
                high_priority=is_high,
            )
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
        encrypted: bool = False,
    ) -> Dict[str, Any]:
        """Notify direct chat recipient. An encrypted chat's text is never shown in a push."""
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

            recipient_language = self.get_language_for_uid(recipient_id)
            preview = (
                push_text(recipient_language, "preview.text")
                if encrypted
                else _preview_of(text, kind=message_type, language=recipient_language)
            )

            # In-app notification
            try:
                db.collection("users").document(recipient_id).collection("notifications").add({
                    "title": push_text(recipient_language, "chat.title", sender=sender_name),
                    "body": preview,
                    "action": "chat",
                    "uid": sender_id,
                    "chatId": chat_id,
                    "messageType": message_type,
                    "read": False,
                    "timestamp": datetime.now(timezone.utc),
                })
            except Exception as e:
                logger.warning("Could not write in-app notification: %s", e)

            # Push notification
            targets = self.get_push_targets_for_uids([recipient_id])
            data = {"action": "chat", "chatId": chat_id, "senderId": sender_id}
            count = self.send_localized(
                targets,
                lambda lang: (
                    push_text(lang, "chat.title", sender=sender_name),
                    (
                        push_text(lang, "preview.text")
                        if encrypted
                        else _preview_of(text, kind=message_type, language=lang)
                    ),
                ),
                data,
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
        if self.is_seen(f"call_{call_id}"):
            logger.info("Call push for %s already sent; skipping duplicate", call_id)
            return {"status": "already_sent"}
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
                c_name = "Member"

            targets = self.get_push_targets_for_uids([callee_uid])
            if not targets:
                logger.info("No FCM tokens registered for callee %s", callee_uid)
                return {"status": "no_targets"}

            messaging_mod = self._get_messaging()
            now_epoch = int(time.time())

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

            groups: Dict[str, List[Tuple[str, Any]]] = {}
            for token, ref, language in targets:
                groups.setdefault(normalize_language(language), []).append((token, ref))

            sent_count = 0
            for language, group in groups.items():
                # The alert shows on iOS only, in the language of the callee's device.
                apns_config = None
                if hasattr(messaging_mod, "APNSConfig"):
                    kind_label = push_text(
                        language,
                        "call.kind.video" if is_video else "call.kind.voice",
                    )
                    apns_config = messaging_mod.APNSConfig(
                        headers={
                            "apns-priority": "10",
                            "apns-expiration": str(now_epoch + CALL_RING_SECONDS),
                        },
                        payload=messaging_mod.APNSPayload(
                            aps=messaging_mod.Aps(
                                alert=messaging_mod.ApsAlert(
                                    title=push_text(language, "call.title", kind=kind_label),
                                    body=push_text(language, "call.body", caller=c_name),
                                ),
                                sound="default",
                                content_available=True,
                            ),
                        ),
                    )

                for i in range(0, len(group), FCM_BATCH_LIMIT):
                    batch = group[i : i + FCM_BATCH_LIMIT]
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

    def send_post_notification(
        self,
        tour_id: str,
        post_id: str,
        author_email: str,
        author_name: str = "A member",
        caption: str = "",
        is_reel: bool = False,
        image_url: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Push notification when a member posts a photo or reel in Moments."""
        if self.is_seen(f"post_{tour_id}_{post_id}"):
            return {"status": "already_sent"}
        try:
            members = self.get_active_tour_members(tour_id, except_email=author_email)
            if not members:
                return {"status": "no_recipients"}

            uids = self.get_uids_for_emails(members)
            targets = self.get_push_targets_for_uids(uids)

            data = {
                "action": "post",
                "tourId": str(tour_id),
                "postId": str(post_id),
            }

            clean_caption = (caption or "").strip()
            short_caption = (
                (clean_caption[:99] + "…") if len(clean_caption) > 100 else clean_caption
            )
            title_key = "post.reel.title" if is_reel else "post.photo.title"
            body_fallback_key = "post.reel.body" if is_reel else "post.photo.body"

            count = self.send_localized(
                targets,
                lambda lang: (
                    push_text(lang, title_key, sender=author_name),
                    short_caption if short_caption else push_text(lang, body_fallback_key),
                ),
                data,
                high_priority=False,
            )
            self.stats["post_pushes_sent"] += count
            return {"status": "success", "recipients": len(members), "devices_sent": count}
        except Exception as e:
            self.stats["errors"] += 1
            logger.error("Error in send_post_notification: %s", e)
            return {"status": "error", "error": str(e)}

    def send_comment_notification(
        self,
        tour_id: str,
        post_id: str,
        comment_id: str,
        post_author_email: str,
        commenter_email: str,
        commenter_name: str = "A member",
        text: str = "",
    ) -> Dict[str, Any]:
        """Push notification to the post author when someone comments on their post."""
        if self.is_seen(f"comment_{tour_id}_{post_id}_{comment_id}"):
            return {"status": "already_sent"}
        clean_author = post_author_email.strip().lower()
        clean_commenter = commenter_email.strip().lower()
        if not clean_author or clean_author == clean_commenter:
            return {"status": "self_comment"}
        try:
            uids = self.get_uids_for_emails([clean_author])
            if not uids:
                return {"status": "no_recipients"}
            targets = self.get_push_targets_for_uids(uids)

            data = {
                "action": "comment",
                "tourId": str(tour_id),
                "postId": str(post_id),
                "commentId": str(comment_id),
            }

            clean_text = (text or "").strip()
            short_text = (
                (clean_text[:99] + "…") if len(clean_text) > 100 else clean_text
            )

            count = self.send_localized(
                targets,
                lambda lang: (
                    push_text(lang, "comment.title", sender=commenter_name),
                    short_text if short_text else push_text(lang, "comment.default"),
                ),
                data,
                high_priority=False,
            )
            self.stats["comment_pushes_sent"] += count
            return {"status": "success", "recipients": 1, "devices_sent": count}
        except Exception as e:
            self.stats["errors"] += 1
            logger.error("Error in send_comment_notification: %s", e)
            return {"status": "error", "error": str(e)}

    def send_reaction_notification(
        self,
        tour_id: str,
        post_id: str,
        post_author_email: str,
        liker_name: str = "A member",
        liker_email: str = "",
        reactor_name: Optional[str] = None,
        reactor_email: Optional[str] = None,
        reaction: str = "like",
    ) -> Dict[str, Any]:
        """Push notification to post author when someone likes their post."""
        liker_name = reactor_name or liker_name
        liker_email = reactor_email or liker_email
        clean_author = post_author_email.strip().lower()
        clean_liker = liker_email.strip().lower()
        if not clean_author or clean_author == clean_liker:
            return {"status": "self_like"}
        if self.is_seen(f"like_{tour_id}_{post_id}_{clean_liker}"):
            return {"status": "already_sent"}
        try:
            uids = self.get_uids_for_emails([clean_author])
            if not uids:
                return {"status": "no_recipients"}
            targets = self.get_push_targets_for_uids(uids)
            data = {
                "action": "like",
                "tourId": str(tour_id),
                "postId": str(post_id),
            }
            count = self.send_localized(
                targets,
                lambda lang: (
                    push_text(lang, "reaction.like.title"),
                    push_text(lang, "reaction.like.body", sender=liker_name),
                ),
                data,
                high_priority=False,
            )
            self.stats["reaction_pushes_sent"] += count
            return {"status": "success", "devices_sent": count}
        except Exception as e:
            self.stats["errors"] += 1
            logger.error("Error in send_reaction_notification: %s", e)
            return {"status": "error", "error": str(e)}

    def send_notice_notification(
        self,
        tour_id: str,
        notice_id: str,
        author_email: str,
        title: str = "",
        body: str = "",
        priority: str = "normal",
    ) -> Dict[str, Any]:
        """Push a new group notice/announcement to all active members."""
        if self.is_seen(f"notice_{tour_id}_{notice_id}"):
            return {"status": "already_sent"}
        try:
            members = self.get_active_tour_members(tour_id, except_email=author_email)
            if not members:
                return {"status": "no_recipients"}

            uids = self.get_uids_for_emails(members)
            targets = self.get_push_targets_for_uids(uids)

            data = {
                "action": "notice",
                "tourId": str(tour_id),
                "noticeId": str(notice_id),
            }

            clean_title = (title or "").strip()
            clean_body = (body or "").strip()
            short_body = (
                (clean_body[:99] + "…") if len(clean_body) > 100 else clean_body
            )
            is_high = priority.lower() in ("high", "urgent", "emergency")

            def make_text(lang: str) -> Tuple[str, str]:
                return (
                    push_text(lang, "notice.title", title=clean_title)
                    if clean_title
                    else push_text(lang, "notice.untitled"),
                    short_body if short_body else push_text(lang, "notice.body", body=clean_title),
                )

            count = self.send_localized(targets, make_text, data, high_priority=is_high)
            self.record_inbox(uids, data, make_text)
            self.stats["notice_pushes_sent"] += count
            return {"status": "success", "recipients": len(members), "devices_sent": count}
        except Exception as e:
            self.stats["errors"] += 1
            logger.error("Error in send_notice_notification: %s", e)
            return {"status": "error", "error": str(e)}

    def send_bazar_duty_notification(
        self,
        tour_id: str,
        date_key: str,
        assigned_emails: List[str],
        note: str = "",
        estimated_budget_paisa: Optional[int] = None,
    ) -> Dict[str, Any]:
        """Push a bazar duty reminder to assigned mess members."""
        dedup_key = f"bazar_{tour_id}_{date_key}"
        if self.is_seen(dedup_key):
            return {"status": "already_sent"}
        try:
            clean_emails = [e.strip().lower() for e in assigned_emails if e.strip()]
            if not clean_emails:
                return {"status": "no_recipients"}
            uids = self.get_uids_for_emails(clean_emails)
            targets = self.get_push_targets_for_uids(uids)

            data = {
                "action": "bazar_duty",
                "tourId": str(tour_id),
                "dateKey": str(date_key),
            }

            def make_text(lang: str) -> Tuple[str, str]:
                return push_text(lang, "bazar.duty.title"), push_text(lang, "bazar.duty.body")

            count = self.send_localized(targets, make_text, data, high_priority=True)
            self.record_inbox(uids, data, make_text)
            return {"status": "success", "recipients": len(clean_emails), "devices_sent": count}
        except Exception as e:
            self.stats["errors"] += 1
            logger.error("Error in send_bazar_duty_notification: %s", e)
            return {"status": "error", "error": str(e)}

    def send_ledger_notification(
        self,
        tour_id: str,
        expense_id: str,
        added_by_email: str,
        payer_name: str = "A member",
        title: str = "trip expense",
        amount_paisa: int = 0,
    ) -> Dict[str, Any]:
        """Push notification when a member records a group expense in Trip Ledger."""
        if self.is_seen(f"ledger_{tour_id}_{expense_id}"):
            return {"status": "already_sent"}
        try:
            if not self.tour_allows_fund(tour_id):
                return {"status": "no_fund"}
            members = self.get_active_tour_members(tour_id, except_email=added_by_email)
            if not members:
                return {"status": "no_recipients"}

            uids = self.get_uids_for_emails(members)
            targets = self.get_push_targets_for_uids(uids)

            data = {
                "action": "ledger",
                "tourId": str(tour_id),
                "expenseId": str(expense_id),
            }

            taka = round(amount_paisa / 100)
            clean_title = (title or "expense").strip()

            def make_text(lang: str) -> Tuple[str, str]:
                return (
                    push_text(lang, "ledger.title", taka=str(taka)),
                    push_text(lang, "ledger.body", payer=payer_name, taka=str(taka), title=clean_title),
                )

            count = self.send_localized(targets, make_text, data, high_priority=False)
            self.record_inbox(uids, data, make_text)
            self.stats["ledger_pushes_sent"] += count
            return {"status": "success", "recipients": len(members), "devices_sent": count}
        except Exception as e:
            self.stats["errors"] += 1
            logger.error("Error in send_ledger_notification: %s", e)
            return {"status": "error", "error": str(e)}

    def send_broadcast_notification(
        self,
        title: str,
        body: str,
        data: Optional[Dict[str, str]] = None,
        image_url: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Broadcast global notification to all registered devices in batches of 500."""
        try:
            db = self._get_db()
            targets: List[Tuple[str, Any]] = []
            seen_tokens: Set[str] = set()

            token_docs = db.collection("fcm_tokens").stream()
            for doc in token_docs:
                doc_data = doc.to_dict() or {}
                tok = doc_data.get("token")
                if tok and tok not in seen_tokens:
                    seen_tokens.add(tok)
                    targets.append((tok, doc.reference))

                for dev in doc.reference.collection("devices").stream():
                    d_data = dev.to_dict() or {}
                    d_tok = d_data.get("token")
                    if d_tok and d_tok not in seen_tokens:
                        seen_tokens.add(d_tok)
                        targets.append((d_tok, dev.reference))

            extra_data = data or {"action": "broadcast"}
            sent = self.send_multicast(targets, title, body, extra_data, high_priority=True)
            self.stats["broadcast_pushes_sent"] += sent
            return {"status": "success", "devices_sent": sent}
        except Exception as e:
            self.stats["errors"] += 1
            logger.error("Error in send_broadcast_notification: %s", e)
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

            purged_tokens = 0
            if self._chat_db is not None and hasattr(self._chat_db, "prune_stale_device_tokens"):
                try:
                    purged_tokens = self._chat_db.prune_stale_device_tokens(max_age_days=180)
                except Exception as ex:
                    logger.warning("Could not prune stale device tokens: %s", ex)

            logger.info("Retention sweep: purged %d events, %d logs, %d stale tokens", purged_events, purged_logs, purged_tokens)
            return {
                "purged_events": purged_events,
                "purged_logs": purged_logs,
                "purged_tokens": purged_tokens,
            }
        except Exception as e:
            logger.error("Retention sweep error: %s", e)
            return {"error": str(e)}


class FirestoreNotificationWatcher:
    """Real-time listener daemon running on the VPS to capture events as they happen."""

    def __init__(
        self,
        engine: NotificationEngine,
        claim_event: Optional[Callable[[Any], bool]] = None,
        claim_push: Optional[Callable[[str], bool]] = None,
    ) -> None:
        self.engine = engine
        self.started_at = datetime.now(timezone.utc)
        self.active_listeners: List[Any] = []
        self._processed_ids: Set[str] = set()
        self._lock = threading.Lock()
        self._is_running = False
        # Marks a journey event as pushed, once. Tests pass a stand-in.
        self._claim_event = claim_event or self._claim_in_transaction
        # Marks a study push as sent, once, under a key. Tests pass a stand-in.
        self._claim_push = claim_push or self._claim_key_in_transaction

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
        """Called when a safety alert is raised, or closed, in any tour.

        A raised alert is pushed once, and an alert raised shortly before this watcher started is pushed too,
        so a restart does not drop it. Each push is recorded, so a second start does not send it again. A
        closed alert gets its end notice only when its alert was pushed.
        """
        catch_up_since = self.started_at - timedelta(seconds=SOS_CATCH_UP_SECONDS)
        for change in changes:
            kind = change.type.name
            if kind not in {"ADDED", "MODIFIED"}:
                continue
            doc = change.document
            data = doc.to_dict() or {}
            tour_ref = doc.reference.parent.parent
            tour_id = tour_ref.id if tour_ref else str(data.get("tourId", ""))
            sender = str(data.get("senderEmail", "")).strip().lower()
            if not tour_id or "@" not in sender:
                continue
            if kind == "ADDED" and data.get("resolved") is not True:
                if self.is_seen(f"sos_added_{doc.id}"):
                    continue
                if not self._is_recent(data.get("createdAt"), catch_up_since):
                    continue
                self.engine.send_sos_alert(tour_id=tour_id, alert_id=doc.id, sender_email=sender)
            elif kind == "MODIFIED" and data.get("resolved") is True:
                if self.is_seen(f"sos_ended_{doc.id}"):
                    continue
                self.engine.send_sos_ended(tour_id=tour_id, alert_id=doc.id, sender_email=sender)

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
                elif status in {"answered", "ended", "declined", "missed"}:
                    # A call that stopped ringing: answered on one of the callee's
                    # phones, declined, missed or ended. The other phones stop
                    # ringing. Only a call young enough to still ring needs it, so
                    # the call history read at start-up sends nothing.
                    if not call_may_still_ring(data.get("createdAt")):
                        continue
                    if self.is_seen(f"call_end_{call_id}"):
                        continue
                    callee_id = str(data.get("calleeId", "")).strip()
                    if callee_id:
                        self.engine.send_call_ended_push(call_id, callee_id)

    def on_journey_snapshot(self, col_snapshot, changes, read_time):
        """Called when a member's arrival or departure is written (roadmap LJ-4.3).

        Each event is pushed once, to the other members of its tour. An event is only
        ever created, never changed, so an added document is the one to act on.
        """
        for change in changes:
            if change.type.name != "ADDED":
                continue
            doc = change.document
            if self.is_seen(doc.reference.path):
                continue
            data = doc.to_dict() or {}
            created_at = data.get("createdAt")
            if isinstance(created_at, datetime):
                if created_at.tzinfo is None:
                    created_at = created_at.replace(tzinfo=timezone.utc)
                if created_at < self.started_at:
                    continue
            kind = data.get("type")
            if kind not in ("arrive", "depart"):
                continue
            tour_ref = doc.reference.parent.parent
            tour_id = tour_ref.id if tour_ref else ""
            sender_email = str(data.get("email", "")).strip().lower()
            stop_id = str(data.get("stopId", "")).strip()
            if not tour_id or not sender_email or not stop_id:
                continue
            try:
                claimed = self._claim_event(doc.reference)
            except Exception as error:
                logger.warning("Journey event %s not claimed: %s", doc.reference.path, error)
                continue
            if not claimed:
                # Pushed before: by an earlier run, or by this one before a restart.
                continue
            self.engine.send_journey_event(
                tour_id=tour_id,
                event_id=doc.id,
                sender_email=sender_email,
                sender_name=self._member_name(tour_id, sender_email),
                stop_name=self._stop_name(tour_id, stop_id),
                kind=kind,
            )

    @staticmethod
    def _is_recent(stamp: Any, since: datetime) -> bool:
        """Whether a stored time is at or after `since`. A missing time counts as recent, so a push is not lost."""
        return stamp_is_recent(stamp, since)

    def _is_active_member(self, tour_id: str, email: str) -> bool:
        """Whether an email is an active member of a tour, by its membership row."""
        snapshot = self.engine._get_db().collection("memberships").document(f"{tour_id}__{email}").get()
        return bool(snapshot.exists) and (snapshot.to_dict() or {}).get("status") == "active"

    def _claim_key_in_transaction(self, key: str) -> bool:
        """Records that a study push was sent, under `key`, in a transaction. Returns False when it was
        already recorded, so a restart does not send it again."""
        from google.cloud import firestore

        db = self.engine._get_db()
        ref = db.collection(PUSH_CLAIMS).document(key)

        def claim(transaction: Any, ref_: Any) -> bool:
            if ref_.get(transaction=transaction).exists:
                return False
            transaction.create(ref_, {"sentAt": firestore.SERVER_TIMESTAMP})
            return True

        return firestore.transactional(claim)(db.transaction(), ref)

    def _safe_study_push(self, doc: Any, push: Callable[[Any, datetime], None], since: datetime) -> None:
        """Runs one study push. A bad document is logged and skipped, so it does not stop the listener."""
        try:
            push(doc, since)
        except Exception as error:
            logger.warning("Study push failed for %s: %s", doc.reference.path, error)

    def on_study_thread_snapshot(self, col_snapshot, changes, read_time):
        """A discussion was started. The members its body names with @ are told once each, except its author."""
        since = self.started_at - timedelta(seconds=STUDY_PUSH_WINDOW_SECONDS)
        for change in changes:
            if change.type.name == "ADDED":
                self._safe_study_push(change.document, self._push_thread_mentions, since)

    def on_study_reply_snapshot(self, col_snapshot, changes, read_time):
        """A member replied to a discussion question (Phase 2). The member who asked is pushed once. The path
        is checked, since other features keep `replies` collections too."""
        since = self.started_at - timedelta(seconds=STUDY_PUSH_WINDOW_SECONDS)
        for change in changes:
            if change.type.name == "ADDED":
                self._safe_study_push(change.document, self._push_study_reply, since)
                self._safe_study_push(change.document, self._push_reply_mentions, since)

    def _push_study_reply(self, doc: Any, since: datetime) -> None:
        # tours/{tour}/study_books/{book}/threads/{thread}/replies/{reply}
        parts = doc.reference.path.split("/")
        if len(parts) != 8 or parts[0] != "tours" or parts[2] != "study_books" or parts[4] != "threads" or parts[6] != "replies":
            return
        tour_id, book_id, thread_id, reply_id = parts[1], parts[3], parts[5], parts[7]
        data = doc.to_dict() or {}
        if not self._is_recent(data.get("createdAt"), since):
            return
        replier = str(data.get("createdByEmail", "")).strip().lower()
        thread = self.engine._get_db().document(f"tours/{tour_id}/study_books/{book_id}/threads/{thread_id}").get()
        if not thread.exists:
            return
        thread_data = thread.to_dict() or {}
        asker = str(thread_data.get("createdByEmail", "")).strip().lower()
        if not asker or asker == replier or not self._is_active_member(tour_id, asker):
            return
        if not self._claim_push(f"reply_{tour_id}_{book_id}_{thread_id}_{reply_id}"):
            return
        self.engine.send_study_reply(
            tour_id=tour_id,
            book_id=book_id,
            thread_id=thread_id,
            asker_email=asker,
            thread_title=str(thread_data.get("title", "")),
        )

    def on_study_pending_material_snapshot(self, col_snapshot, changes, read_time):
        """A member filed a material that waits for an admin's approval (Phase 3). The owners and admins are
        pushed once, except the member who filed it."""
        since = self.started_at - timedelta(seconds=STUDY_PUSH_WINDOW_SECONDS)
        for change in changes:
            if change.type.name == "ADDED":
                self._safe_study_push(change.document, self._push_pending_material, since)

    def on_study_reported_material_snapshot(self, col_snapshot, changes, read_time):
        """A material that has more than one report. The owners and admins are pushed once. A material
        already reported when the watcher starts is pushed too, unless it was pushed before."""
        for change in changes:
            if change.type.name in ("ADDED", "MODIFIED"):
                self._safe_study_push(change.document, self._push_repeated_report, self.started_at)

    def on_study_published_material_snapshot(self, col_snapshot, changes, read_time):
        """A material was published, or filed as published at once. The other members are pushed once. A
        publish with no stamp (from an earlier app) is not pushed: it has no time to judge by."""
        since = self.started_at - timedelta(seconds=STUDY_PUSH_WINDOW_SECONDS)
        for change in changes:
            if change.type.name in ("ADDED", "MODIFIED"):
                self._safe_study_push(change.document, self._push_published_material, since)

    @staticmethod
    def _material_ids(doc: Any) -> Optional[tuple]:
        """The tour and material ids of a study material, from its path, or None for any other document."""
        parts = doc.reference.path.split("/")
        if len(parts) != 4 or parts[0] != "tours" or parts[2] != "study_materials":
            return None
        return parts[1], parts[3]

    def _push_pending_material(self, doc: Any, since: datetime) -> None:
        ids = self._material_ids(doc)
        data = doc.to_dict() or {}
        if ids is None or data.get("status") != "pending" or not self._is_recent(data.get("createdAt"), since):
            return
        tour_id, material_id = ids
        uploader = str(data.get("createdByEmail", "")).strip().lower()
        admins = self.engine.get_active_tour_admins(tour_id, except_email=uploader)
        if not admins or not self._claim_push(f"material_review_{tour_id}_{material_id}"):
            return
        self.engine.send_study_material(
            tour_id=tour_id,
            book_id=str(data.get("bookId", "")),
            material_id=material_id,
            title=str(data.get("title", "")),
            emails=admins,
            pending=True,
        )

    def on_study_assignment_snapshot(self, col_snapshot, changes, read_time):
        """An assignment was added to a subject. The members are pushed once when it is shown, and the admins when it
        waits for approval. Nothing written before the watcher started is pushed."""
        since = self.started_at - timedelta(seconds=STUDY_PUSH_WINDOW_SECONDS)
        for change in changes:
            if change.type.name == "ADDED":
                self._safe_study_push(change.document, lambda doc, s: self._push_new_subject_post(doc, s, "assignment"), since)

    def on_study_paper_snapshot(self, col_snapshot, changes, read_time):
        """A past paper was added to a subject. The members are pushed once when it is shown, and the admins when it
        waits for approval."""
        since = self.started_at - timedelta(seconds=STUDY_PUSH_WINDOW_SECONDS)
        for change in changes:
            if change.type.name == "ADDED":
                self._safe_study_push(change.document, lambda doc, s: self._push_new_subject_post(doc, s, "paper"), since)

    def _push_new_subject_post(self, doc: Any, since: datetime, post: str) -> None:
        # tours/{tour}/study_subjects/{subject}/{assignments|papers}/{post}
        parts = doc.reference.path.split("/")
        collection = "assignments" if post == "assignment" else "papers"
        if len(parts) != 6 or parts[0] != "tours" or parts[2] != "study_subjects" or parts[4] != collection:
            return
        tour_id, subject_id, post_id = parts[1], parts[3], parts[5]
        data = doc.to_dict() or {}
        if not self._is_recent(data.get("createdAt"), since):
            return
        author = str(data.get("createdByEmail", "")).strip().lower()
        subject = self.engine._get_db().collection("tours").document(tour_id).collection("study_subjects").document(subject_id).get()
        subject_title = str((subject.to_dict() or {}).get("title", ""))
        title = str(data.get("title", ""))
        if data.get("shown") is True:
            emails = self.engine.get_active_tour_members(tour_id, except_email=author)
            kind, key = f"{post}.new", f"{post}_new_{tour_id}_{post_id}"
        else:
            emails = self.engine.get_active_tour_admins(tour_id, except_email=author)
            kind, key = f"{post}.review", f"{post}_review_{tour_id}_{post_id}"
        if not emails or not self._claim_push(key):
            return
        self.engine.send_study_subject(tour_id, subject_id, kind, title, subject_title, emails)

    def _push_thread_mentions(self, doc: Any, since: datetime) -> None:
        # tours/{tour}/study_books/{book}/threads/{thread}
        parts = doc.reference.path.split("/")
        if len(parts) != 6 or parts[0] != "tours" or parts[2] != "study_books" or parts[4] != "threads":
            return
        tour_id, book_id, thread_id = parts[1], parts[3], parts[5]
        data = doc.to_dict() or {}
        if not self._is_recent(data.get("createdAt"), since):
            return
        author = str(data.get("createdByEmail", "")).strip().lower()
        self._tell_mentioned(
            tour_id, book_id, thread_id, f"thread_{thread_id}", data.get("mentions"),
            skip={author}, title=str(data.get("title", "")),
        )

    def _push_reply_mentions(self, doc: Any, since: datetime) -> None:
        # tours/{tour}/study_books/{book}/threads/{thread}/replies/{reply}
        parts = doc.reference.path.split("/")
        if len(parts) != 8 or parts[0] != "tours" or parts[2] != "study_books" or parts[4] != "threads" or parts[6] != "replies":
            return
        tour_id, book_id, thread_id, reply_id = parts[1], parts[3], parts[5], parts[7]
        data = doc.to_dict() or {}
        if not self._is_recent(data.get("createdAt"), since):
            return
        thread = self.engine._get_db().document(f"tours/{tour_id}/study_books/{book_id}/threads/{thread_id}").get()
        if not thread.exists:
            return
        thread_data = thread.to_dict() or {}
        author = str(data.get("createdByEmail", "")).strip().lower()
        asker = str(thread_data.get("createdByEmail", "")).strip().lower()
        # The member who asked is already told of every reply, so a mention of them adds nothing.
        self._tell_mentioned(
            tour_id, book_id, thread_id, f"reply_{reply_id}", data.get("mentions"),
            skip={author, asker}, title=str(thread_data.get("title", "")),
        )

    def _tell_mentioned(self, tour_id: str, book_id: str, thread_id: str, claim_stem: str, mentions: Any,
                        skip: Set[str], title: str) -> None:
        """Pushes the members a discussion names, once each: the active members only, and not those in `skip`."""
        if not isinstance(mentions, list):
            return
        recipients: List[str] = []
        for raw in mentions:
            if not isinstance(raw, str):
                continue
            email = raw.strip().lower()
            if not email or email in skip or email in recipients:
                continue
            if not self._is_active_member(tour_id, email):
                continue
            if not self._claim_push(f"mention_{claim_stem}_{tour_id}_{email}"):
                continue
            recipients.append(email)
        if recipients:
            self.engine.send_study_mention(tour_id, book_id, thread_id, title, recipients)

    def _push_repeated_report(self, doc: Any, since: datetime) -> None:
        ids = self._material_ids(doc)
        data = doc.to_dict() or {}
        if ids is None or int(data.get("reportCount") or 0) < STUDY_REPEAT_REPORTS:
            return
        tour_id, material_id = ids
        admins = self.engine.get_active_tour_admins(tour_id)
        if not admins or not self._claim_push(f"material_reported_again_{tour_id}_{material_id}"):
            return
        self.engine.send_study_material(
            tour_id=tour_id,
            book_id=str(data.get("bookId", "")),
            material_id=material_id,
            title=str(data.get("title", "")),
            emails=admins,
            pending=False,
            kind="reported",
        )

    def _push_published_material(self, doc: Any, since: datetime) -> None:
        ids = self._material_ids(doc)
        data = doc.to_dict() or {}
        published_at = data.get("publishedAt")
        if ids is None or data.get("status") != "published" or not isinstance(published_at, datetime):
            return
        if not self._is_recent(published_at, since):
            return
        tour_id, material_id = ids
        uploader = str(data.get("createdByEmail", "")).strip().lower()
        publisher = str(data.get("publishedByEmail") or uploader).strip().lower()
        members = self.engine.get_active_tour_members(tour_id, except_email=publisher)
        if not members or not self._claim_push(f"material_shared_{tour_id}_{material_id}"):
            return
        self.engine.send_study_material(
            tour_id=tour_id,
            book_id=str(data.get("bookId", "")),
            material_id=material_id,
            title=str(data.get("title", "")),
            emails=members,
            pending=False,
        )

    def _claim_in_transaction(self, ref: Any) -> bool:
        """Records that a journey event was pushed, in a transaction. Returns False when
        it was already recorded, so a restart does not push it again."""
        from google.cloud import firestore

        db = self.engine._get_db()

        def claim(transaction: Any, ref_: Any) -> bool:
            snapshot = ref_.get(transaction=transaction)
            if not snapshot.exists or (snapshot.to_dict() or {}).get("pushedAt") is not None:
                return False
            transaction.update(ref_, {"pushedAt": firestore.SERVER_TIMESTAMP})
            return True

        return firestore.transactional(claim)(db.transaction(), ref)

    def _stop_name(self, tour_id: str, stop_id: str) -> str:
        """The stop's name from the tour's itinerary, or its id when it is not there."""
        try:
            tour = self.engine._get_db().collection("tours").document(tour_id).get()
            for stop in (tour.to_dict() or {}).get("stops") or []:
                if isinstance(stop, dict) and stop.get("id") == stop_id:
                    name = str(stop.get("name", "")).strip()
                    if name:
                        return name
        except Exception as error:
            logger.debug("Stop name not read for %s/%s: %s", tour_id, stop_id, error)
        return stop_id

    def _member_name(self, tour_id: str, email: str) -> str:
        """The member's display name in the tour, or a generic name."""
        try:
            member = (
                self.engine._get_db()
                .collection("memberships")
                .document(f"{tour_id}__{email}")
                .get()
            )
            name = str((member.to_dict() or {}).get("displayName", "")).strip()
            if name:
                return name
        except Exception as error:
            logger.debug("Member name not read for %s: %s", email, error)
        return "A member"

    def on_posts_snapshot(self, col_snapshot, changes, read_time):
        """Called when Moments posts are created in Firestore."""
        for change in changes:
            if change.type.name in {"ADDED", "MODIFIED"}:
                doc = change.document
                tour_ref = doc.reference.parent.parent
                tour_id = tour_ref.id if tour_ref else ""
                post_id = doc.id
                if not tour_id or self.is_seen(f"post_{tour_id}_{post_id}"):
                    continue
                data = doc.to_dict() or {}
                created_at = data.get("createdAt")
                if isinstance(created_at, datetime):
                    if created_at.tzinfo is None:
                        created_at = created_at.replace(tzinfo=timezone.utc)
                    if created_at < self.started_at:
                        continue
                author_email = str(data.get("authorEmail", "")).strip().lower()
                author_name = str(data.get("authorName", "A member")).strip()
                caption = str(data.get("caption", ""))
                is_reel = bool(data.get("isReel", False))
                image_url = data.get("coverUrl") or (data.get("images") or [None])[0]
                if author_email:
                    self.engine.send_post_notification(
                        tour_id=tour_id,
                        post_id=post_id,
                        author_email=author_email,
                        author_name=author_name,
                        caption=caption,
                        is_reel=is_reel,
                        image_url=image_url,
                    )

    def on_notices_snapshot(self, col_snapshot, changes, read_time):
        """Called when notices are posted in Firestore."""
        for change in changes:
            if change.type.name in {"ADDED", "MODIFIED"}:
                doc = change.document
                tour_ref = doc.reference.parent.parent
                tour_id = tour_ref.id if tour_ref else ""
                notice_id = doc.id
                if not tour_id or self.is_seen(f"notice_{tour_id}_{notice_id}"):
                    continue
                data = doc.to_dict() or {}
                created_at = data.get("createdAt")
                if isinstance(created_at, datetime):
                    if created_at.tzinfo is None:
                        created_at = created_at.replace(tzinfo=timezone.utc)
                    if created_at < self.started_at:
                        continue
                author_email = str(data.get("authorEmail", "")).strip().lower()
                title = str(data.get("title", ""))
                body = str(data.get("body", ""))
                priority = str(data.get("priority", "normal"))
                if author_email:
                    self.engine.send_notice_notification(
                        tour_id=tour_id,
                        notice_id=notice_id,
                        author_email=author_email,
                        title=title,
                        body=body,
                        priority=priority,
                    )

    def on_expenses_snapshot(self, col_snapshot, changes, read_time):
        """Called when expenses are added to Trip Ledger in Firestore."""
        for change in changes:
            if change.type.name in {"ADDED", "MODIFIED"}:
                doc = change.document
                tour_ref = doc.reference.parent.parent
                tour_id = tour_ref.id if tour_ref else ""
                expense_id = doc.id
                if not tour_id or self.is_seen(f"ledger_{tour_id}_{expense_id}"):
                    continue
                data = doc.to_dict() or {}
                created_at = data.get("createdAt")
                if isinstance(created_at, datetime):
                    if created_at.tzinfo is None:
                        created_at = created_at.replace(tzinfo=timezone.utc)
                    if created_at < self.started_at:
                        continue
                added_by = str(data.get("addedByEmail", "")).strip().lower()
                payer_name = str(data.get("payerName", "A member")).strip()
                title = str(data.get("title", "expense")).strip()
                amount_paisa = int(data.get("amountPaisa", 0))
                if added_by:
                    self.engine.send_ledger_notification(
                        tour_id=tour_id,
                        expense_id=expense_id,
                        added_by_email=added_by,
                        payer_name=payer_name,
                        title=title,
                        amount_paisa=amount_paisa,
                    )

    def _attach_listeners(self) -> None:
        """Attaches real-time Firestore listeners."""
        try:
            db = self.engine._get_db()
            logger.info("Attaching FirestoreNotificationWatcher listeners...")
            new_listeners = []
            sos_watch = db.collection_group("sos").on_snapshot(self.on_sos_snapshot)
            new_listeners.append(sos_watch)

            # Only calls from around the start onwards
            calls_since = self.started_at - timedelta(seconds=CALL_PUSH_WINDOW_SECONDS)
            calls_watch = (
                db.collection("calls")
                .where("createdAt", ">=", calls_since)
                .on_snapshot(self.on_call_snapshot)
            )
            new_listeners.append(calls_watch)

            journey_since = self.started_at - timedelta(seconds=JOURNEY_PUSH_WINDOW_SECONDS)
            journey_watch = (
                db.collection_group("journey_events")
                .where("createdAt", ">=", journey_since)
                .on_snapshot(self.on_journey_snapshot)
            )
            new_listeners.append(journey_watch)

            # Study replies and materials, from around the start onwards. Each push is recorded once.
            study_since = self.started_at - timedelta(seconds=STUDY_PUSH_WINDOW_SECONDS)
            reply_watch = (
                db.collection_group("replies")
                .where("createdAt", ">=", study_since)
                .on_snapshot(self.on_study_reply_snapshot)
            )
            new_listeners.append(reply_watch)
            thread_watch = (
                db.collection_group("threads")
                .where("createdAt", ">=", study_since)
                .on_snapshot(self.on_study_thread_snapshot)
            )
            new_listeners.append(thread_watch)
            pending_material_watch = (
                db.collection_group("study_materials")
                .where("createdAt", ">=", study_since)
                .on_snapshot(self.on_study_pending_material_snapshot)
            )
            new_listeners.append(pending_material_watch)
            published_material_watch = (
                db.collection_group("study_materials")
                .where("publishedAt", ">=", study_since)
                .on_snapshot(self.on_study_published_material_snapshot)
            )
            new_listeners.append(published_material_watch)
            reported_material_watch = (
                db.collection_group("study_materials")
                .where("reportCount", ">=", STUDY_REPEAT_REPORTS)
                .on_snapshot(self.on_study_reported_material_snapshot)
            )
            new_listeners.append(reported_material_watch)
            assignment_watch = (
                db.collection_group("assignments")
                .where("createdAt", ">=", study_since)
                .on_snapshot(self.on_study_assignment_snapshot)
            )
            new_listeners.append(assignment_watch)
            paper_watch = (
                db.collection_group("papers")
                .where("createdAt", ">=", study_since)
                .on_snapshot(self.on_study_paper_snapshot)
            )
            new_listeners.append(paper_watch)

            self.active_listeners = new_listeners
            logger.info("Successfully attached %d real-time Firestore listeners.", len(new_listeners))
        except Exception as e:
            logger.warning("Could not attach real-time Firestore listeners: %s", e)

    def _watchdog_loop(self) -> None:
        """Watchdog to ensure listeners remain active across intermittent connection drops."""
        while self._is_running:
            time.sleep(60)
            if not self._is_running:
                break
            if len(self.active_listeners) == 0:
                logger.info("Watchdog detected 0 active listeners; attempting reconnection...")
                self._attach_listeners()

    def start(self) -> None:
        """Start real-time Firestore listeners with watchdog thread."""
        if self._is_running:
            return
        self._is_running = True
        self._attach_listeners()
        self._watchdog = threading.Thread(target=self._watchdog_loop, daemon=True)
        self._watchdog.start()

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
