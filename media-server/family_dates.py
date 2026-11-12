"""Family-date reminders, run by the media server on the VPS.

A family circle keeps dates: birthdays, bills, school days and medicine times. Each
Firestore document under tours/{tourId}/family_dates has a `nextOn` day and a
`remindOn` day, both YYYY-MM-DD. Once a day, at 07:00 in Dhaka, this module finds the
dates whose reminder day has come, pushes the reminder to the whole circle, and moves
each date on to its next occurrence. The move is a transaction, so a reminder goes
out once even when two runs overlap.

The rules mirror the app's family_date_rules.dart. The tests check the same examples,
so the app and the reminders agree on every date.
"""

from __future__ import annotations

import calendar
import logging
import re
import threading
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from typing import Any, Callable, Dict, List, Optional, Tuple

from push_strings import localized_number, push_text

logger = logging.getLogger("bhromon.family_dates")

# Asia/Dhaka is UTC+6 all year, with no daylight saving, so a fixed offset is exact.
DHAKA_OFFSET = timedelta(hours=6)
# Reminders go out from this hour, Dhaka time, once a day.
RUN_HOUR_DHAKA = 7
# A failed run is tried again after this long, on the same Dhaka day.
RETRY_AFTER = timedelta(minutes=10)
# How often the scheduler looks at the clock.
POLL_SECONDS = 60
# One run sends at most this many occurrences of one date. This bounds the loop.
MAX_STEPS = 10
# A reminder falls from 0 to this many days before its date, as the rules allow. Any
# other value is refused, so a bad record cannot push the date arithmetic out of range.
MAX_REMIND_DAYS = 30

RECURRENCES = ("once", "monthly", "yearly")
KIND_EMOJI = {
    "birthday": "🎂",
    "anniversary": "💍",
    "bill": "🧾",
    "school": "🎒",
    "medicine": "💊",
    "meeting": "🤝",
    "deadline": "⏳",
    "exam": "📝",
    "rent": "🏠",
    "maintenance": "🛠️",
    "installment": "💰",
    "payout": "🎁",
    "event": "🎉",
    "custom": "📅",
}

_DAY_KEY = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}")


def dhaka_day_key(now: datetime) -> str:
    """The Dhaka calendar day of an aware moment, as YYYY-MM-DD."""
    if now.tzinfo is None:
        raise ValueError("dhaka_day_key needs a timezone-aware datetime")
    return (now.astimezone(timezone.utc) + DHAKA_OFFSET).date().isoformat()


def _valid_day(raw: Any) -> Optional[str]:
    """The day as given when it is a real YYYY-MM-DD day, otherwise None."""
    if not isinstance(raw, str) or not _DAY_KEY.fullmatch(raw):
        return None
    try:
        date.fromisoformat(raw)
    except ValueError:
        return None
    return raw


def add_days(day: str, days: int) -> str:
    """The day `days` after `day`, as YYYY-MM-DD."""
    return (date.fromisoformat(day) + timedelta(days=days)).isoformat()


def days_between(start: str, end: str) -> int:
    """Whole calendar days from start to end. Negative when end is earlier."""
    return (date.fromisoformat(end) - date.fromisoformat(start)).days


def occurrence_on_or_after(start_on: str, recurrence: str, from_day: str) -> str:
    """The first occurrence on or after from_day.

    A monthly date keeps its day of the month, and a yearly date keeps its month and
    day. A day the month does not have (the 31st in April, 29 February in a common
    year) falls on that month's last day. A one-time date is always its start day.
    """
    if recurrence == "once":
        return start_on
    start = date.fromisoformat(start_on)
    origin = date.fromisoformat(from_day)
    for step in range(2):
        if recurrence == "monthly":
            year, month_index = divmod(origin.year * 12 + (origin.month - 1) + step, 12)
            month = month_index + 1
        else:
            year, month = origin.year + step, start.month
        day = min(start.day, calendar.monthrange(year, month)[1])
        candidate = date(year, month, day)
        if candidate >= origin:
            return candidate.isoformat()
    return start_on  # Unreachable for a valid start day: the second step always lands.


@dataclass(frozen=True)
class ReminderPlan:
    """What one run does with one date: the reminders to send and the new schedule."""

    days_left: List[int]
    next_on: str
    remind_on: Optional[str]


def plan_family_date_reminders(record: Dict[str, Any], today: str) -> Optional[ReminderPlan]:
    """The reminders a date is due at `today`, and its next schedule. None when nothing is due.

    A reminder is due once `remindOn` is today or earlier. Each occurrence gets at
    most one reminder, and an occurrence that has already passed gets none. A
    recurring date then moves to its next occurrence: the one after the date just
    handled, or the first one from today when this one has passed. A one-time date
    stops after its reminder.
    """
    start_on = _valid_day(record.get("startOn"))
    next_on = _valid_day(record.get("nextOn"))
    remind_on = _valid_day(record.get("remindOn"))
    remind_days = record.get("remindDays")
    recurrence = record.get("recurrence")
    if (
        start_on is None
        or next_on is None
        or remind_on is None
        or remind_on > today
        or type(remind_days) is not int  # A bool is not a day count.
        or not 0 <= remind_days <= MAX_REMIND_DAYS
        or recurrence not in RECURRENCES
    ):
        return None

    if recurrence == "once":
        reminders = [days_between(today, next_on)] if next_on >= today else []
        return ReminderPlan(days_left=reminders, next_on=next_on, remind_on=None)

    reminders: List[int] = []
    current = next_on
    for step in range(MAX_STEPS):
        if current >= today:
            reminders.append(days_between(today, current))
        from_day = add_days(current, 1) if current >= today else today
        current = occurrence_on_or_after(start_on, recurrence, from_day)
        remind = add_days(current, -remind_days)
        if remind > today or step + 1 >= MAX_STEPS:
            return ReminderPlan(days_left=reminders, next_on=current, remind_on=remind)
    return ReminderPlan(days_left=reminders, next_on=current, remind_on=None)  # Unreachable.


def family_date_reminder_text(
    record: Dict[str, Any], days_left: int, language: Optional[str] = None
) -> Tuple[str, str]:
    """The title and the body a member sees for a date that is `days_left` days away.

    The text is in the member's language. An unknown language gets English.
    """
    raw_title = record.get("title")
    title = raw_title.strip() if isinstance(raw_title, str) else ""
    kind = record.get("kind")
    emoji = KIND_EMOJI.get(kind if isinstance(kind, str) else "custom", KIND_EMOJI["custom"])
    if days_left <= 0:
        when = push_text(language, "family.today")
    elif days_left == 1:
        when = push_text(language, "family.tomorrow")
    else:
        when = push_text(language, "family.in_days", days=localized_number(language, days_left))
    name = title or push_text(language, "family.untitled")
    return f"{emoji} {name}", when


def _reminder_for(record: Dict[str, Any], days_left: int) -> Callable[[Optional[str]], Tuple[str, str]]:
    """The text for one reminder, as a function of the recipient's language."""
    return lambda language: family_date_reminder_text(record, days_left, language)


def claim_due_family_date(
    transaction: Any, ref: Any, today: str
) -> Optional[Tuple[Dict[str, Any], ReminderPlan]]:
    """Reads one date inside a transaction, and when a reminder is due, moves its schedule on.

    Returns the record and the plan to send, or None when nothing is due.
    """
    snapshot = ref.get(transaction=transaction)
    if not snapshot.exists:
        return None
    record = snapshot.to_dict() or {}
    plan = plan_family_date_reminders(record, today)
    if plan is None:
        return None
    transaction.update(ref, {"nextOn": plan.next_on, "remindOn": plan.remind_on})
    return record, plan


def _circle_targets(engine: Any, tour_id: str) -> Tuple[List[str], List[Tuple[str, Any]]]:
    """The uids and the push targets of every active member of a circle, the creator included.

    The date is for everyone in the circle, so the creator is not left out.
    """
    emails = engine.get_active_tour_members(tour_id, "")
    uids = engine.get_uids_for_emails(emails)
    return uids, engine.get_push_targets_for_uids(uids)


def run_family_date_reminders(
    db: Any,
    engine: Any,
    today: str,
    transactional: Optional[Callable[[Callable[[Any, Any], Any]], Callable[[Any, Any], Any]]] = None,
) -> Dict[str, int]:
    """Sends the reminders due on `today`, once each, and moves those dates on.

    `transactional` wraps the claim in a Firestore transaction. Production uses
    google.cloud.firestore.transactional; tests pass a stand-in.
    """
    if transactional is None:
        from google.cloud import firestore

        transactional = firestore.transactional
    claim = transactional(lambda transaction, ref: claim_due_family_date(transaction, ref, today))

    stats = {"due": 0, "reminded": 0, "pushes": 0, "errors": 0}
    targets_by_tour: Dict[str, Tuple[List[str], List[Tuple[str, Any]]]] = {}
    due = db.collection_group("family_dates").where("remindOn", "<=", today).stream()
    for doc in due:
        stats["due"] += 1
        try:
            tour_id = doc.reference.parent.parent.id
            # The circle is read before its date is claimed. If the read fails, the date
            # stays due and the next run reminds about it; nothing has been sent yet.
            if tour_id not in targets_by_tour:
                targets_by_tour[tour_id] = _circle_targets(engine, tour_id)
            claimed = claim(db.transaction(), doc.reference)
            if claimed is None:
                continue
            record, plan = claimed
            if not plan.days_left:
                continue
            stats["reminded"] += 1
            uids, targets = targets_by_tour[tour_id]
            for days_left in plan.days_left:
                data = {"action": "family_date", "tourId": tour_id, "dateId": doc.id}
                make_text = _reminder_for(record, days_left)
                stats["pushes"] += engine.send_localized(targets, make_text, data, high_priority=True)
                engine.record_inbox(uids, data, make_text)
        except Exception as error:  # One bad date must not stop the others.
            stats["errors"] += 1
            logger.error("Family-date reminder failed for %s: %s", doc.reference.path, error)
    return stats


def is_run_due(
    now: datetime,
    last_run_day: Optional[str],
    retry_after: Optional[datetime],
    run_hour: int = RUN_HOUR_DHAKA,
) -> bool:
    """Whether the daily run should happen now.

    It is due from `run_hour` (07:00 Dhaka time by default), once per Dhaka day, and
    not before a retry is due.
    """
    if now.tzinfo is None:
        raise ValueError("is_run_due needs a timezone-aware datetime")
    if (now.astimezone(timezone.utc) + DHAKA_OFFSET).hour < run_hour:
        return False
    if last_run_day == dhaka_day_key(now):
        return False
    if retry_after is not None and now < retry_after:
        return False
    return True


class FamilyDateReminderScheduler:
    """Runs the reminders once a day, in a background thread of the media server.

    A run that finds nothing due does nothing, and a run that was missed (the server
    was down at 07:00) happens as soon as the server is up that day.
    """

    def __init__(
        self,
        engine: Any,
        *,
        clock: Optional[Callable[[], datetime]] = None,
        run: Optional[Callable[[str], Dict[str, int]]] = None,
        poll_seconds: float = POLL_SECONDS,
    ) -> None:
        self._engine = engine
        self._clock = clock or (lambda: datetime.now(timezone.utc))
        self._run = run or (lambda today: run_family_date_reminders(engine._get_db(), engine, today))
        self._poll_seconds = poll_seconds
        self._stop = threading.Event()
        self._thread: Optional[threading.Thread] = None
        self._last_run_day: Optional[str] = None
        self._retry_after: Optional[datetime] = None

    def start(self) -> None:
        if self._thread is not None and self._thread.is_alive():
            return
        self._stop.clear()
        self._thread = threading.Thread(target=self._loop, name="family-date-reminders", daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=5)

    def run_if_due(self) -> bool:
        """Runs the reminders when today's run is due. Returns True when a run happened."""
        now = self._clock()
        if not is_run_due(now, self._last_run_day, self._retry_after):
            return False
        today = dhaka_day_key(now)
        try:
            stats = self._run(today)
        except Exception as error:
            self._retry_after = now + RETRY_AFTER
            logger.error("Family-date reminder run failed; retrying after %s: %s", RETRY_AFTER, error)
            return False
        self._last_run_day = today
        self._retry_after = None
        logger.info("Family-date reminders for %s: %s", today, stats)
        return True

    def _loop(self) -> None:
        while not self._stop.is_set():
            try:
                self.run_if_due()
            except Exception:
                logger.exception("Family-date reminder scheduler error")
            self._stop.wait(self._poll_seconds)
