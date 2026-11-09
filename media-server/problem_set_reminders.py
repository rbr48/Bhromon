"""Problem-set reminders: the day before a set is due, to each member who has not worked every problem in it.

A problem set is a named group of a subject's problems (tours/{id}/study_subjects/{id}/problem_sets/{id}), with an
optional due time, `dueAt`, the start of the day it is due. The reminder goes out 24 hours before `dueAt`, once: it is
claimed in a transaction (`reminderSentAt` on the set) before it is sent. It goes to the active members who have not
written a working for each shown problem of the set. A subject that is not listed, is archived, or has its problems
module off sends nothing. The job follows the session reminders (session_reminders.py).

An admin can give one member a due date of their own for a set (tours/{id}/study_subjects/{id}/problem_sets/{id}/
member_deadlines/{email}). That member is left out of the set's reminder and is reminded of their own date instead,
24 hours before it, once: the claim is `reminderSentAt` on that document, and a moved date clears it, so the reminder
goes out again for the new date.
"""

from __future__ import annotations

import logging
import threading
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict, Iterable, List, Optional, Set, Tuple

from push_strings import push_text

logger = logging.getLogger(__name__)

LEAD = timedelta(hours=24)
# Sets due within this window are read: a reminder is due about 24 hours before the due time.
LOOKAHEAD = LEAD + timedelta(hours=1)
POLL_SECONDS = 15 * 60
PUSH_ACTION = "problem_set"
SENT_FIELD = "reminderSentAt"
PROBLEMS_MODULE = "problems"
# A member's own due date for a set, a subcollection of the set keyed by the member's email.
DEADLINES = "member_deadlines"


def _moment(raw: Any) -> Optional[datetime]:
    """A stored time as an aware datetime. A naive value is taken as UTC."""
    if not isinstance(raw, datetime):
        return None
    if raw.tzinfo is None:
        return raw.replace(tzinfo=timezone.utc)
    return raw


def reminder_due(record: Dict[str, Any], now: datetime) -> bool:
    """Whether the reminder for a set is due at `now`: 24 hours or less before its due time, not yet before it
    passes, and not yet sent."""
    due = _moment(record.get("dueAt"))
    if due is None or record.get(SENT_FIELD) is not None:
        return False
    return due - LEAD <= now < due


def unfinished_members(
    members: Iterable[str],
    shown_problem_ids: List[str],
    solvers_by_problem: Dict[str, Set[str]],
) -> List[str]:
    """The members who have not written a working for every shown problem. A set with no shown problem asks for
    nothing, so no one is reminded of it."""
    if not shown_problem_ids:
        return []
    return [
        email
        for email in members
        if any(email not in solvers_by_problem.get(problem, set()) for problem in shown_problem_ids)
    ]


def problem_set_text(record: Dict[str, Any], language: Optional[str] = None) -> Tuple[str, str]:
    """The title and the body a member sees for a problem-set reminder, in their language."""
    raw_title = record.get("title")
    title = raw_title.strip() if isinstance(raw_title, str) else ""
    if not title:
        title = push_text(language, "problemset.untitled")
    return push_text(language, "problemset.head"), push_text(language, "problemset.day_before", title=title)


def claim_problem_set_reminder(
    transaction: Any, ref: Any, now: datetime
) -> Optional[Dict[str, Any]]:
    """Reads one set inside a transaction. When its reminder is due, records that it is sent and returns the set,
    or None when nothing is due."""
    snapshot = ref.get(transaction=transaction)
    if not snapshot.exists:
        return None
    record = snapshot.to_dict() or {}
    if not reminder_due(record, now):
        return None
    transaction.update(ref, {SENT_FIELD: now})
    return record


def _candidate_sets(db: Any, now: datetime) -> List[Any]:
    """The problem sets due within the lookahead window, from every study group."""
    query = (
        db.collection_group("problem_sets")
        .where("dueAt", ">=", now)
        .where("dueAt", "<=", now + LOOKAHEAD)
    )
    return list(query.stream())


def _candidate_deadlines(db: Any, now: datetime) -> List[Any]:
    """The members' own due dates within the lookahead window, from every study group."""
    query = (
        db.collection_group(DEADLINES)
        .where("dueAt", ">=", now)
        .where("dueAt", "<=", now + LOOKAHEAD)
    )
    return list(query.stream())


def _personal_deadline_emails(set_ref: Any) -> Set[str]:
    """The members an admin gave a due date of their own for this set. They are reminded of that date, not the set's."""
    return {doc.id for doc in set_ref.collection(DEADLINES).stream()}


def _subject_open_for_reminders(subject_ref: Any) -> bool:
    """A subject is listed, not archived, and has its problems module on."""
    subject = subject_ref.get()
    if not subject.exists:
        return False
    data = subject.to_dict() or {}
    if data.get("approval", "listed") != "listed" or data.get("archived") is True:
        return False
    module = subject_ref.collection("modules").document(PROBLEMS_MODULE).get()
    return module.exists and (module.to_dict() or {}).get("enabled") is True


def _shown_problems(subject_ref: Any, set_id: str) -> List[Any]:
    """The shown problems of a set, as document references."""
    return [
        doc.reference
        for doc in subject_ref.collection("problems")
        .where("setId", "==", set_id)
        .where("shown", "==", True)
        .stream()
    ]


def _solvers(problem_ref: Any) -> Set[str]:
    """The members who have written a working for a problem. A working's id is the member's email."""
    return {doc.id for doc in problem_ref.collection("solutions").stream()}


def run_problem_set_reminders(
    db: Any,
    engine: Any,
    now: datetime,
    transactional: Optional[Callable[[Callable[..., Any]], Callable[..., Any]]] = None,
) -> Dict[str, int]:
    """Sends the problem-set reminders that are due at `now`, once each.

    `transactional` wraps the claim in a Firestore transaction. Production uses
    google.cloud.firestore.transactional; tests pass a stand-in.
    """
    if now.tzinfo is None:
        raise ValueError("run_problem_set_reminders needs a timezone-aware datetime")
    if transactional is None:
        from google.cloud import firestore

        transactional = firestore.transactional
    claim = transactional(
        lambda transaction, ref: claim_problem_set_reminder(transaction, ref, now)
    )

    stats = {"due": 0, "deadlines": 0, "reminded": 0, "pushes": 0, "errors": 0}
    members_by_tour: Dict[str, List[str]] = {}
    for doc in _candidate_sets(db, now):
        stats["due"] += 1
        try:
            set_ref = doc.reference
            subject_ref = set_ref.parent.parent
            tour_id = subject_ref.parent.parent.id
            if not _subject_open_for_reminders(subject_ref):
                continue
            # Members and workings are read before the claim. If a read fails, the set stays due for the
            # next run, and nothing has been sent yet.
            if tour_id not in members_by_tour:
                members_by_tour[tour_id] = engine.get_active_tour_members(tour_id, "")
            members = members_by_tour[tour_id]
            problems = _shown_problems(subject_ref, set_ref.id)
            solvers = {problem.id: _solvers(problem) for problem in problems}
            # A member with a date of their own is reminded of that date instead, by the pass below.
            personal = _personal_deadline_emails(set_ref)
            recipients = unfinished_members(
                [email for email in members if email not in personal],
                [p.id for p in problems],
                solvers,
            )
            record = claim(db.transaction(), set_ref)
            if record is None:
                continue
            stats["reminded"] += 1
            if not recipients:
                continue
            targets = engine.get_push_targets_for_uids(engine.get_uids_for_emails(recipients))
            stats["pushes"] += engine.send_localized(
                targets,
                lambda language, record=record: problem_set_text(record, language),
                {
                    "action": PUSH_ACTION,
                    "tourId": tour_id,
                    "subjectId": subject_ref.id,
                    "setId": set_ref.id,
                },
                high_priority=True,
            )
        except Exception as error:  # One bad set must not stop the others.
            stats["errors"] += 1
            logger.error("Problem-set reminder failed for %s: %s", doc.reference.path, error)
    # A member's own due date for a set: the member is reminded of it once, if they have not worked every shown
    # problem. A date for a set that is gone, for a member who has left, or in a subject that is closed sends nothing.
    for doc in _candidate_deadlines(db, now):
        stats["deadlines"] += 1
        try:
            deadline_ref = doc.reference
            set_ref = deadline_ref.parent.parent
            subject_ref = set_ref.parent.parent
            tour_id = subject_ref.parent.parent.id
            email = deadline_ref.id
            if not _subject_open_for_reminders(subject_ref):
                continue
            set_snapshot = set_ref.get()
            if not set_snapshot.exists:
                continue
            if tour_id not in members_by_tour:
                members_by_tour[tour_id] = engine.get_active_tour_members(tour_id, "")
            if email not in members_by_tour[tour_id]:
                continue
            problems = _shown_problems(subject_ref, set_ref.id)
            solvers = {problem.id: _solvers(problem) for problem in problems}
            recipients = unfinished_members([email], [p.id for p in problems], solvers)
            record = claim(db.transaction(), deadline_ref)
            if record is None:
                continue
            stats["reminded"] += 1
            if not recipients:
                continue
            set_title = (set_snapshot.to_dict() or {}).get("title")
            targets = engine.get_push_targets_for_uids(engine.get_uids_for_emails(recipients))
            stats["pushes"] += engine.send_localized(
                targets,
                lambda language, title=set_title: problem_set_text({"title": title}, language),
                {
                    "action": PUSH_ACTION,
                    "tourId": tour_id,
                    "subjectId": subject_ref.id,
                    "setId": set_ref.id,
                },
                high_priority=True,
            )
        except Exception as error:  # One bad date must not stop the others.
            stats["errors"] += 1
            logger.error("Problem-set due date reminder failed for %s: %s", doc.reference.path, error)
    return stats


class ProblemSetReminderScheduler:
    """Runs the problem-set reminders every POLL_SECONDS in a background thread of the media server."""

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
        self._thread = threading.Thread(
            target=self._loop, name="problem-set-reminders", daemon=True
        )
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
                logger.exception("Problem-set reminder run failed")
