"""Session reminders: the 24-hour and 30-minute reminders go out once each, to the right people."""

from datetime import datetime, timedelta, timezone

import pytest

import session_reminders as sr

START = datetime(2026, 11, 10, 18, 0, tzinfo=timezone.utc)
MEMBERS = ["ana@x.com", "ben@x.com", "cy@x.com"]


class FakeDb:
    """Documents by path, with just enough of the Firestore client for the reminder job."""

    def __init__(self, docs):
        self.docs = {path: dict(data) for path, data in docs.items()}
        self.calls = []

    def collection_group(self, name):
        return FakeQuery(self, name)

    def transaction(self):
        return FakeTransaction(self)


class FakeQuery:
    def __init__(self, db, name, filters=()):
        self.db = db
        self.name = name
        self.filters = tuple(filters)

    def where(self, field, op, value):
        return FakeQuery(self.db, self.name, self.filters + ((field, op, value),))

    def stream(self):
        found = []
        for path, data in self.db.docs.items():
            parts = path.split("/")
            if len(parts) != 4 or parts[2] != self.name:
                continue
            if all(_matches(data.get(f), op, v) for f, op, v in self.filters):
                found.append(FakeDoc(self.db, path, data))
        return found


def _matches(value, op, expected):
    if value is None:
        return False
    if op == ">=":
        return value >= expected
    if op == "<=":
        return value <= expected
    raise AssertionError(f"unsupported op {op}")


class FakeDocRef:
    def __init__(self, db, path):
        self.db = db
        self.path = path

    @property
    def id(self):
        return self.path.split("/")[-1]

    @property
    def parent(self):
        return FakeCollectionRef(self.db, "/".join(self.path.split("/")[:-1]))

    def get(self, transaction=None):
        data = self.db.docs.get(self.path)
        return FakeSnapshot(data)

    def collection(self, name):
        return FakeCollectionRef(self.db, f"{self.path}/{name}")


class FakeCollectionRef:
    def __init__(self, db, path):
        self.db = db
        self.path = path

    @property
    def parent(self):
        return FakeDocRef(self.db, "/".join(self.path.split("/")[:-1]))

    def stream(self):
        found = []
        prefix = self.path + "/"
        for path, data in self.db.docs.items():
            if path.startswith(prefix) and "/" not in path[len(prefix):]:
                found.append(FakeDoc(self.db, path, data))
        return found


class FakeDoc:
    def __init__(self, db, path, data):
        self.db = db
        self.path = path
        self._data = data
        self.reference = FakeDocRef(db, path)

    @property
    def id(self):
        return self.path.split("/")[-1]

    def to_dict(self):
        return dict(self._data)


class FakeSnapshot:
    def __init__(self, data):
        self.exists = data is not None
        self._data = data

    def to_dict(self):
        return dict(self._data) if self._data is not None else None


class FakeTransaction:
    def __init__(self, db):
        self.db = db

    def update(self, ref, updates):
        self.db.docs[ref.path].update(updates)


class FakeEngine:
    def __init__(self, members):
        self.members = members
        self.sent = []

    def get_active_tour_members(self, tour_id, _unused):
        return list(self.members)

    def get_uids_for_emails(self, emails):
        return [email.upper() for email in emails]

    def get_push_targets_for_uids(self, uids):
        return list(uids)

    def record_inbox(self, uids, data, make_text):
        """Records the entries the module keeps in each member's list, for the assertions."""
        self.inbox_entries = getattr(self, "inbox_entries", []) + [(list(uids), dict(data))]
        return len(list(uids))

    def send_localized(self, targets, text_for, data, high_priority=False):
        self.sent.append({"targets": list(targets), "text": text_for("en"), "data": data})
        return len(targets)


def _session(starts=START, **extra):
    base = {"title": "Chapters 1 to 3", "startsAt": starts, "createdByEmail": "ana@x.com"}
    base.update(extra)
    return base


def _path(session_id="s1", tour="t1"):
    return f"tours/{tour}/reading_sessions/{session_id}"


def _rsvp(db, response, email, session_id="s1", tour="t1"):
    db.docs[f"tours/{tour}/reading_sessions/{session_id}/rsvps/{email}"] = {"response": response}


def _no_transaction(fn):
    return fn


# --- when a reminder is due ----------------------------------------------------------------------


def test_nothing_is_due_before_the_window_or_after_the_start():
    assert sr.due_kinds(_session(), START - timedelta(hours=25)) == []
    assert sr.due_kinds(_session(), START) == []
    assert sr.due_kinds(_session(), START + timedelta(minutes=5)) == []


def test_the_day_reminder_is_due_from_24_hours_before():
    assert sr.due_kinds(_session(), START - timedelta(hours=23)) == [sr.KIND_DAY]
    assert sr.due_kinds(_session(), START - timedelta(minutes=31)) == [sr.KIND_DAY]


def test_both_are_due_in_the_last_half_hour_when_neither_was_sent():
    assert sr.due_kinds(_session(), START - timedelta(minutes=29)) == [sr.KIND_SOON, sr.KIND_DAY]


def test_a_sent_reminder_is_not_due_again():
    record = _session(reminder24Sent=START - timedelta(hours=23))
    assert sr.due_kinds(record, START - timedelta(hours=2)) == []


def test_a_naive_start_is_taken_as_utc():
    record = _session(starts=datetime(2026, 11, 10, 18, 0))
    assert sr.due_kinds(record, START - timedelta(hours=23)) == [sr.KIND_DAY]


# --- who is told, and once only ------------------------------------------------------------------


def test_the_day_reminder_goes_to_every_member():
    recipients = sr.reminder_recipients(sr.KIND_DAY, MEMBERS, going=["ana@x.com"])
    assert recipients == MEMBERS


def test_the_soon_reminder_goes_only_to_those_going_who_are_members():
    recipients = sr.reminder_recipients(
        sr.KIND_SOON, MEMBERS, going=["ben@x.com", "gone@x.com"]
    )
    assert recipients == ["ben@x.com"]


def test_claiming_the_day_reminder_marks_only_that_reminder():
    db = FakeDb({_path(): _session()})
    ref = FakeDocRef(db, _path())
    claimed = sr.claim_session_reminder(
        FakeTransaction(db), ref, START - timedelta(hours=23), [], MEMBERS
    )
    record, kind, recipients = claimed
    assert kind == sr.KIND_DAY
    assert recipients == MEMBERS
    assert db.docs[_path()]["reminder24Sent"] == START - timedelta(hours=23)
    assert "reminder30Sent" not in db.docs[_path()]


def test_the_soon_reminder_also_marks_the_day_one_when_it_was_not_sent():
    db = FakeDb({_path(): _session()})
    ref = FakeDocRef(db, _path())
    now = START - timedelta(minutes=10)
    _, kind, recipients = sr.claim_session_reminder(
        FakeTransaction(db), ref, now, ["ben@x.com"], MEMBERS
    )
    assert kind == sr.KIND_SOON
    assert recipients == ["ben@x.com"]
    assert db.docs[_path()]["reminder30Sent"] == now
    assert db.docs[_path()]["reminder24Sent"] == now


def test_a_claimed_reminder_is_not_claimed_again():
    db = FakeDb({_path(): _session()})
    ref = FakeDocRef(db, _path())
    now = START - timedelta(hours=23)
    assert sr.claim_session_reminder(FakeTransaction(db), ref, now, [], MEMBERS) is not None
    assert sr.claim_session_reminder(FakeTransaction(db), ref, now, [], MEMBERS) is None


# --- the run ---------------------------------------------------------------------------------------


def test_a_run_sends_the_day_reminder_once_to_every_member():
    db = FakeDb({_path(): _session()})
    engine = FakeEngine(MEMBERS)
    now = START - timedelta(hours=23)

    first = sr.run_session_reminders(db, engine, now, transactional=_no_transaction)
    second = sr.run_session_reminders(db, engine, now + timedelta(minutes=5), transactional=_no_transaction)

    assert first == {"due": 1, "reminded": 1, "pushes": 3, "errors": 0}
    assert second["reminded"] == 0
    assert len(engine.sent) == 1
    assert engine.sent[0]["targets"] == ["ANA@X.COM", "BEN@X.COM", "CY@X.COM"]
    assert engine.sent[0]["data"] == {"action": "session", "tourId": "t1", "sessionId": "s1"}


def test_the_soon_reminder_reaches_only_those_going():
    db = FakeDb({_path(): _session()})
    _rsvp(db, "going", "ben@x.com")
    _rsvp(db, "maybe", "cy@x.com")
    engine = FakeEngine(MEMBERS)

    stats = sr.run_session_reminders(
        db, engine, START - timedelta(minutes=10), transactional=_no_transaction
    )

    assert stats["reminded"] == 1
    assert engine.sent[0]["targets"] == ["BEN@X.COM"]


def test_a_session_outside_the_lookahead_is_not_read():
    db = FakeDb({_path(): _session(starts=START + timedelta(days=3))})
    stats = sr.run_session_reminders(
        db, FakeEngine(MEMBERS), START - timedelta(hours=1), transactional=_no_transaction
    )
    assert stats == {"due": 0, "reminded": 0, "pushes": 0, "errors": 0}


def test_one_bad_session_does_not_stop_the_others():
    db = FakeDb({_path("bad"): _session(), _path("good"): _session()})

    class FlakyEngine(FakeEngine):
        def get_active_tour_members(self, tour_id, unused):
            raise RuntimeError("members unavailable")

    stats = sr.run_session_reminders(
        db, FlakyEngine(MEMBERS), START - timedelta(hours=23), transactional=_no_transaction
    )
    assert stats["errors"] == 2
    assert stats["reminded"] == 0


def test_the_run_needs_a_timezone_aware_clock():
    with pytest.raises(ValueError):
        sr.run_session_reminders(
            FakeDb({}), FakeEngine(MEMBERS), datetime(2026, 11, 9, 12, 0), transactional=_no_transaction
        )


# --- the text --------------------------------------------------------------------------------------


def test_the_text_names_the_session_in_each_language():
    record = _session(title="Anna, chapters 1 to 3")
    _, english = sr.session_reminder_text(record, sr.KIND_DAY, "en")
    _, bengali = sr.session_reminder_text(record, sr.KIND_SOON, "bn")
    assert "Anna, chapters 1 to 3" in english and "24 hours" in english
    assert "Anna, chapters 1 to 3" in bengali and "৩০ মিনিট" in bengali


def test_an_untitled_session_still_reads_well():
    _, text = sr.session_reminder_text({"startsAt": START}, sr.KIND_SOON, "en")
    assert text.startswith("your session")
