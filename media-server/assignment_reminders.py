"""Assignment reminders: the day before an assignment is due, to each member who has not finished it.

An assignment is an item in a subject's list (tours/{id}/study_subjects/{id}/assignments/{id}) with an optional due
time, `dueAt`, the start of its due day. A shown assignment is reminded 24 hours before `dueAt`, once, to the active
members who have not marked it finished. Each member's finished ids are in tours/{id}/study_subjects/{id}/
assignment_marks/{email}, a list. A waiting assignment (not shown) is not reminded. A subject that is not listed, is
archived, or has its assignments module off sends nothing.

The reminder is claimed in push_claims before it is sent, so a restart does not send it again. The claim is keyed by
the due time, so a moved due time is reminded again for its new date. The job follows problem_set_reminders.py.
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict, Iterable, List, Optional, Set, Tuple

from problem_set_reminders import ProblemSetReminderScheduler
from push_strings import push_text

logger = logging.getLogger(__name__)

LEAD = timedelta(hours=24)
# Assignments due within this window are read: a reminder is due about 24 hours before the due time.
LOOKAHEAD = LEAD + timedelta(hours=1)
POLL_SECONDS = 15 * 60
PUSH_ACTION = "study_subject"
MODULE = "assignments"
# The ids of the assignments a member has finished, one document per member.
MARKS = "assignment_marks"
CLAIMS = "push_claims"


def _moment(raw: Any) -> Optional[datetime]:
    """A stored time as an aware datetime. A naive value is taken as UTC."""
    if not isinstance(raw, datetime):
        return None
    if raw.tzinfo is None:
        return raw.replace(tzinfo=timezone.utc)
    return raw


def reminder_due(record: Dict[str, Any], now: datetime) -> bool:
    """Whether an assignment's reminder is due at `now`: it is shown, and `now` is 24 hours or less before its due
    time and before the time passes."""
    due = _moment(record.get("dueAt"))
    if due is None or record.get("shown") is not True:
        return False
    return due - LEAD <= now < due


def reminder_key(tour_id: str, assignment_id: str, due: datetime) -> str:
    """The claim key of an assignment's reminder for one due time. A moved due time has a new key."""
    return f"assignment_due_{tour_id}_{assignment_id}_{due.astimezone(timezone.utc):%Y%m%d%H%M}"


def unfinished_members(
    members: Iterable[str],
    assignment_id: str,
    finished_by_member: Dict[str, Set[str]],
) -> List[str]:
    """The members who have not marked the assignment finished."""
    return [
        email
        for email in members
        if assignment_id not in finished_by_member.get(email, set())
    ]


def assignment_due_text(
    title: str, subject_title: str, language: Optional[str] = None
) -> Tuple[str, str]:
    """The title and the body a member sees for an assignment that is due tomorrow, in their language."""
    shown_title = title.strip() or push_text(language, "study.assignment.untitled")
    shown_subject = subject_title.strip() or push_text(language, "study.subject.untitled")
    return (
        push_text(language, "study.assignment.due.head"),
        push_text(language, "study.assignment.due.body", title=shown_title, subject=shown_subject),
    )


def _candidate_assignments(db: Any, now: datetime) -> List[Any]:
    """The assignments due within the lookahead window, from every study group."""
    query = (
        db.collection_group("assignments")
        .where("dueAt", ">=", now)
        .where("dueAt", "<=", now + LOOKAHEAD)
    )
    return list(query.stream())


def _subject_open(subject_ref: Any) -> bool:
    """A subject is listed, not archived, and has its assignments module on."""
    subject = subject_ref.get()
    if not subject.exists:
        return False
    data = subject.to_dict() or {}
    if data.get("approval", "listed") != "listed" or data.get("archived") is True:
        return False
    module = subject_ref.collection("modules").document(MODULE).get()
    return module.exists and (module.to_dict() or {}).get("enabled") is True


def _finished_by_member(subject_ref: Any, members: Iterable[str]) -> Dict[str, Set[str]]:
    """The finished ids of each member, from their own marks."""
    finished: Dict[str, Set[str]] = {}
    for email in members:
        marks = subject_ref.collection(MARKS).document(email).get()
        done = (marks.to_dict() or {}).get("done") if marks.exists else None
        finished[email] = {str(item) for item in done} if isinstance(done, list) else set()
    return finished


def firestore_claim(db: Any, key: str) -> bool:
    """Records a reminder as sent, in a transaction. False when it was already recorded."""
    from google.cloud import firestore

    ref = db.collection(CLAIMS).document(key)

    def claim(transaction: Any, ref_: Any) -> bool:
        if ref_.get(transaction=transaction).exists:
            return False
        transaction.create(ref_, {"sentAt": firestore.SERVER_TIMESTAMP})
        return True

    return firestore.transactional(claim)(db.transaction(), ref)


def run_assignment_due_reminders(
    db: Any,
    engine: Any,
    now: datetime,
    claim_key: Optional[Callable[[str], bool]] = None,
) -> Dict[str, int]:
    """Sends the assignment reminders that are due at `now`, once each.

    `claim_key` records a reminder as sent and returns False when it was already recorded. Production uses a
    Firestore transaction; tests pass a stand-in.
    """
    if now.tzinfo is None:
        raise ValueError("run_assignment_due_reminders needs a timezone-aware datetime")
    claim = claim_key or (lambda key: firestore_claim(db, key))

    stats = {"due": 0, "reminded": 0, "pushes": 0, "errors": 0}
    members_by_tour: Dict[str, List[str]] = {}
    for doc in _candidate_assignments(db, now):
        stats["due"] += 1
        try:
            parts = doc.reference.path.split("/")
            if len(parts) != 6 or parts[0] != "tours" or parts[2] != "study_subjects" or parts[4] != "assignments":
                continue
            record = doc.to_dict() or {}
            if not reminder_due(record, now):
                continue
            subject_ref = doc.reference.parent.parent
            tour_id = parts[1]
            if not _subject_open(subject_ref):
                continue
            if tour_id not in members_by_tour:
                members_by_tour[tour_id] = engine.get_active_tour_members(tour_id, "")
            members = members_by_tour[tour_id]
            finished = _finished_by_member(subject_ref, members)
            recipients = unfinished_members(members, doc.reference.id, finished)
            due = _moment(record.get("dueAt"))
            if due is None or not claim(reminder_key(tour_id, doc.reference.id, due)):
                continue
            stats["reminded"] += 1
            if not recipients:
                continue
            subject = subject_ref.get()
            subject_title = str((subject.to_dict() or {}).get("title", ""))
            title = str(record.get("title", ""))
            targets = engine.get_push_targets_for_uids(engine.get_uids_for_emails(recipients))
            stats["pushes"] += engine.send_localized(
                targets,
                lambda language, title=title, subject_title=subject_title: assignment_due_text(
                    title, subject_title, language
                ),
                {"action": PUSH_ACTION, "tourId": tour_id, "subjectId": subject_ref.id},
                high_priority=True,
            )
        except Exception as error:  # One bad assignment must not stop the others.
            stats["errors"] += 1
            logger.error("Assignment reminder failed for %s: %s", doc.reference.path, error)
    return stats


class AssignmentReminderScheduler(ProblemSetReminderScheduler):
    """Runs the assignment reminders every POLL_SECONDS in a background thread of the media server."""

    thread_name = "assignment-reminders"
