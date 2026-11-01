"""Reminders for notices that ask for an answer, run by the media server on the VPS.

A notice can ask every member to answer it: an acknowledgement (requireAck) or a roll
call. The app shows the open ones as "needs my reply". This module pushes a reminder
to the members who have still not answered, so a notice that people miss is not lost.

It follows notice_engine.dart. A notice needs an answer when it asks for one, it is not
archived (its expiry has not passed), and some member has not answered it.

Cadence for each notice. The first push went out when the notice was posted, so the
first reminder waits FIRST_DELAY. A later reminder waits at least GAP after the previous
one, and at most MAX_REMINDERS are sent. A notice posted longer ago than LOOKBACK is left
alone. Each reminder is claimed in a Firestore transaction, so two overlapping runs send
it once.

The media server runs this in AckReminderScheduler, a background thread, and an operator
can run it once through POST /internal/ack-reminders/run.
"""

from __future__ import annotations

import logging
import threading
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict, Iterable, List, Optional, Tuple

logger = logging.getLogger("bhromon.ack_reminders")

# The first reminder waits this long after the notice was posted.
FIRST_DELAY = timedelta(hours=2)
# Later reminders are at least this far apart.
GAP = timedelta(hours=12)
# At most this many reminders go out for one notice.
MAX_REMINDERS = 2
# A notice posted longer ago than this is not reminded about.
LOOKBACK = timedelta(days=14)
# How often the scheduler looks for reminders that are due.
POLL_SECONDS = 15 * 60
# The push opens the notice board, as a new notice's push does.
PUSH_ACTION = "notice"


def _moment(raw: Any) -> Optional[datetime]:
    """A stored time as an aware datetime, or None when the value is not a time."""
    if not isinstance(raw, datetime):
        return None
    return raw if raw.tzinfo is not None else raw.replace(tzinfo=timezone.utc)


def _count(raw: Any) -> int:
    """A reminder count as a whole number from zero; anything else reads as zero."""
    if isinstance(raw, bool) or not isinstance(raw, int) or raw < 0:
        return 0
    return raw


def asks_answer(record: Dict[str, Any]) -> bool:
    """Whether the notice asks its readers to answer: an acknowledgement or a roll call."""
    return record.get("requireAck") is True or record.get("kind") == "rollcall"


def is_archived(record: Dict[str, Any], now: datetime) -> bool:
    """Whether the notice has passed its expiry, so it sits in the archive."""
    expires = _moment(record.get("expiresAt"))
    return expires is not None and now > expires


def waiting_emails(record: Dict[str, Any], members: Iterable[str]) -> List[str]:
    """The members who have not answered, in the order given, without repeats."""
    raw_answers = record.get("ackBy")
    answers = raw_answers if isinstance(raw_answers, list) else []
    answered = {entry.strip().lower() for entry in answers if isinstance(entry, str)}
    waiting: List[str] = []
    for member in members:
        email = member.strip().lower()
        if email and email not in answered and email not in waiting:
            waiting.append(email)
    return waiting


def ack_reminder_due(record: Dict[str, Any], now: datetime, waiting: List[str]) -> bool:
    """Whether a reminder for this notice should go out now."""
    if not asks_answer(record) or not waiting or is_archived(record, now):
        return False
    posted = _moment(record.get("createdAt"))
    if posted is None or now - posted < FIRST_DELAY or now - posted > LOOKBACK:
        return False
    if _count(record.get("ackReminderCount")) >= MAX_REMINDERS:
        return False
    last = _moment(record.get("ackReminderSentAt"))
    return last is None or now - last >= GAP


def ack_reminder_text(record: Dict[str, Any], waiting_count: int) -> Tuple[str, str]:
    """The title and the body a member sees for a notice that still needs their answer."""
    raw_title = record.get("title")
    title = raw_title.strip() if isinstance(raw_title, str) else ""
    head = f"Please answer: {title}" if title else "Please answer a notice"
    if waiting_count == 1:
        return head, "1 member has not answered yet. Tap to answer."
    return head, f"{waiting_count} members have not answered yet. Tap to answer."


def claim_ack_reminder(
    transaction: Any, ref: Any, now: datetime, members: List[str]
) -> Optional[Tuple[Dict[str, Any], List[str]]]:
    """Reads one notice inside a transaction. When a reminder is due, records that it is sent.

    Returns the notice and the members still waiting, or None when nothing is due.
    """
    snapshot = ref.get(transaction=transaction)
    if not snapshot.exists:
        return None
    record = snapshot.to_dict() or {}
    waiting = waiting_emails(record, members)
    if not ack_reminder_due(record, now, waiting):
        return None
    transaction.update(
        ref,
        {
            "ackReminderSentAt": now,
            "ackReminderCount": _count(record.get("ackReminderCount")) + 1,
        },
    )
    return record, waiting


def _candidate_notices(db: Any) -> List[Any]:
    """The notices that ask for an answer: one query for each way of asking, merged by path."""
    found: Dict[str, Any] = {}
    queries = (
        db.collection_group("notices").where("requireAck", "==", True),
        db.collection_group("notices").where("kind", "==", "rollcall"),
    )
    for query in queries:
        for doc in query.stream():
            found.setdefault(doc.reference.path, doc)
    return list(found.values())


def run_ack_reminders(
    db: Any,
    engine: Any,
    now: datetime,
    transactional: Optional[Callable[[Callable[..., Any]], Callable[..., Any]]] = None,
) -> Dict[str, int]:
    """Sends the answer reminders that are due at `now`, once each.

    `transactional` wraps the claim in a Firestore transaction. Production uses
    google.cloud.firestore.transactional; tests pass a stand-in.
    """
    if now.tzinfo is None:
        raise ValueError("run_ack_reminders needs a timezone-aware datetime")
    if transactional is None:
        from google.cloud import firestore

        transactional = firestore.transactional
    claim = transactional(
        lambda transaction, ref, members: claim_ack_reminder(transaction, ref, now, members)
    )

    stats = {"due": 0, "reminded": 0, "pushes": 0, "errors": 0}
    members_by_tour: Dict[str, List[str]] = {}
    for doc in _candidate_notices(db):
        stats["due"] += 1
        try:
            tour_id = doc.reference.parent.parent.id
            # The members are read before the notice is claimed. If that read fails, the
            # notice stays due for the next run, and nothing has been sent yet.
            if tour_id not in members_by_tour:
                members_by_tour[tour_id] = engine.get_active_tour_members(tour_id, "")
            claimed = claim(db.transaction(), doc.reference, members_by_tour[tour_id])
            if claimed is None:
                continue
            record, waiting = claimed
            stats["reminded"] += 1
            title, body = ack_reminder_text(record, len(waiting))
            targets = engine.get_push_targets_for_uids(engine.get_uids_for_emails(waiting))
            stats["pushes"] += engine.send_multicast(
                targets,
                title,
                body,
                {"action": PUSH_ACTION, "tourId": tour_id, "noticeId": doc.id},
                high_priority=True,
            )
        except Exception as error:  # One bad notice must not stop the others.
            stats["errors"] += 1
            logger.error("Answer reminder failed for %s: %s", doc.reference.path, error)
    return stats


class AckReminderScheduler:
    """Runs the answer reminders every POLL_SECONDS in a background thread of the media server.

    A run that finds nothing due sends nothing, so a short poll costs little.
    """

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
        self._thread = threading.Thread(target=self._loop, name="ack-reminders", daemon=True)
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
                logger.exception("Answer reminder run failed")
