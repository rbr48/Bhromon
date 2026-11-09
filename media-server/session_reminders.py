"""Study session reminders: 24 hours before, to everyone; 30 minutes before, to those going.

A session is a reading meeting in a study group (tours/{id}/reading_sessions/{id}). Its members answer
going, maybe or cannot (rsvps/{email}). Each reminder is claimed in a Firestore transaction before it is
sent, so it goes out once even when two runs overlap. The job follows the answer-reminder job
(ack_reminders.py): it reads only the sessions that start soon, and a run that finds nothing due sends
nothing.
"""

from __future__ import annotations

import logging
import threading
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict, Iterable, List, Optional, Tuple

from push_strings import push_text

logger = logging.getLogger(__name__)

DAY_BEFORE = timedelta(hours=24)
SOON_BEFORE = timedelta(minutes=30)
# Sessions starting within this window are read: the 24-hour reminder is due about 24 hours ahead.
LOOKAHEAD = DAY_BEFORE + timedelta(hours=1)
POLL_SECONDS = 5 * 60
PUSH_ACTION = "session"

KIND_DAY = "day"
KIND_SOON = "soon"
SENT_FIELD = {KIND_DAY: "reminder24Sent", KIND_SOON: "reminder30Sent"}
GOING = "going"


def _moment(raw: Any) -> Optional[datetime]:
    """A stored time as an aware datetime. A naive value is taken as UTC."""
    if not isinstance(raw, datetime):
        return None
    if raw.tzinfo is None:
        return raw.replace(tzinfo=timezone.utc)
    return raw


def due_kinds(record: Dict[str, Any], now: datetime) -> List[str]:
    """Which reminders are due for a session at `now`, not yet sent. Empty once it has started."""
    starts = _moment(record.get("startsAt"))
    if starts is None or now >= starts:
        return []
    due: List[str] = []
    if record.get(SENT_FIELD[KIND_SOON]) is None and now >= starts - SOON_BEFORE:
        due.append(KIND_SOON)
    if record.get(SENT_FIELD[KIND_DAY]) is None and now >= starts - DAY_BEFORE:
        due.append(KIND_DAY)
    return due


def reminder_recipients(kind: str, members: Iterable[str], going: Iterable[str]) -> List[str]:
    """Everyone who is a member, for the 24-hour reminder; those going, for the 30-minute one."""
    members_list = list(members)
    if kind == KIND_SOON:
        allowed = set(going)
        return [email for email in members_list if email in allowed]
    return members_list


def session_reminder_text(
    record: Dict[str, Any], kind: str, language: Optional[str] = None
) -> Tuple[str, str]:
    """The title and the body a member sees for a session reminder, in their language."""
    raw_title = record.get("title")
    title = raw_title.strip() if isinstance(raw_title, str) else ""
    if not title:
        title = push_text(language, "session.untitled")
    head = push_text(language, "session.head")
    if kind == KIND_SOON:
        return head, push_text(language, "session.soon", title=title)
    return head, push_text(language, "session.day_before", title=title)


def _text_for(record: Dict[str, Any], kind: str) -> Callable[[Optional[str]], Tuple[str, str]]:
    return lambda language: session_reminder_text(record, kind, language)


def going_emails(session_ref: Any, members: Iterable[str]) -> List[str]:
    """The members who answered going. Read before the claim; the claim re-checks the reminder."""
    allowed = set(members)
    going: List[str] = []
    for doc in session_ref.collection("rsvps").stream():
        data = doc.to_dict() or {}
        if data.get("response") == GOING and doc.id in allowed:
            going.append(doc.id)
    return going


def claim_session_reminder(
    transaction: Any,
    ref: Any,
    now: datetime,
    going: List[str],
    members: List[str],
) -> Optional[Tuple[Dict[str, Any], str, List[str]]]:
    """Reads one session inside a transaction. When a reminder is due, records that it is sent.

    Returns the session, the reminder kind and its recipients, or None when nothing is due. When the
    30-minute reminder goes out and the 24-hour one has not, the 24-hour one is marked sent too, so a
    session created close to its start does not send both.
    """
    snapshot = ref.get(transaction=transaction)
    if not snapshot.exists:
        return None
    record = snapshot.to_dict() or {}
    due = due_kinds(record, now)
    if not due:
        return None
    kind = KIND_SOON if KIND_SOON in due else KIND_DAY
    updates = {SENT_FIELD[kind]: now}
    if kind == KIND_SOON and KIND_DAY in due:
        updates[SENT_FIELD[KIND_DAY]] = now
    transaction.update(ref, updates)
    return record, kind, reminder_recipients(kind, members, going)


def _candidate_sessions(db: Any, now: datetime) -> List[Any]:
    """The sessions that start within the lookahead window, from every study group."""
    query = (
        db.collection_group("reading_sessions")
        .where("startsAt", ">=", now)
        .where("startsAt", "<=", now + LOOKAHEAD)
    )
    return list(query.stream())


def run_session_reminders(
    db: Any,
    engine: Any,
    now: datetime,
    transactional: Optional[Callable[[Callable[..., Any]], Callable[..., Any]]] = None,
) -> Dict[str, int]:
    """Sends the session reminders that are due at `now`, once each.

    `transactional` wraps the claim in a Firestore transaction. Production uses
    google.cloud.firestore.transactional; tests pass a stand-in.
    """
    if now.tzinfo is None:
        raise ValueError("run_session_reminders needs a timezone-aware datetime")
    if transactional is None:
        from google.cloud import firestore

        transactional = firestore.transactional
    claim = transactional(
        lambda transaction, ref, going, members: claim_session_reminder(
            transaction, ref, now, going, members
        )
    )

    stats = {"due": 0, "reminded": 0, "pushes": 0, "errors": 0}
    members_by_tour: Dict[str, List[str]] = {}
    for doc in _candidate_sessions(db, now):
        stats["due"] += 1
        try:
            tour_id = doc.reference.parent.parent.id
            # The members and the answers are read before the claim. If a read fails, the session
            # stays due for the next run, and nothing has been sent yet.
            if tour_id not in members_by_tour:
                members_by_tour[tour_id] = engine.get_active_tour_members(tour_id, "")
            members = members_by_tour[tour_id]
            going = going_emails(doc.reference, members)
            claimed = claim(db.transaction(), doc.reference, going, members)
            if claimed is None:
                continue
            record, kind, recipients = claimed
            stats["reminded"] += 1
            targets = engine.get_push_targets_for_uids(engine.get_uids_for_emails(recipients))
            stats["pushes"] += engine.send_localized(
                targets,
                _text_for(record, kind),
                {"action": PUSH_ACTION, "tourId": tour_id, "sessionId": doc.id},
                high_priority=True,
            )
        except Exception as error:  # One bad session must not stop the others.
            stats["errors"] += 1
            logger.error("Session reminder failed for %s: %s", doc.reference.path, error)
    return stats


class SessionReminderScheduler:
    """Runs the session reminders every POLL_SECONDS in a background thread of the media server."""

    def __init__(
        self,
        run: Callable[[], Dict[str, int]],
        interval_seconds: int = POLL_SECONDS,
    ) -> None:
        self._run = run
        self._interval = interval_seconds
        self._stop = threading.Event()
        self._thread: Optional[threading.Thread] = None

    def start(self) -> None:
        if self._thread is not None and self._thread.is_alive():
            return
        self._stop.clear()
        self._thread = threading.Thread(target=self._loop, name="session-reminders", daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=5)

    def _loop(self) -> None:
        while not self._stop.wait(self._interval):
            try:
                self._run()
            except Exception:  # The loop keeps going; the next run tries again.
                logger.exception("Session reminder run failed")
