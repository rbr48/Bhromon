"""Assignment reminders: the day before an assignment is due, to each member who has not finished it, once."""

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import assignment_reminders as ar

TOUR = "t1"
SUBJECT = "s1"
DUE = datetime(2026, 11, 12, tzinfo=timezone.utc)
NOW = DUE - timedelta(hours=20)
MEMBERS = ["ana@x.com", "ben@x.com", "dee@x.com"]


class Snap:
    def __init__(self, data):
        self._data = data
        self.exists = data is not None

    def to_dict(self):
        return None if self._data is None else dict(self._data)


class Node:
    """A document or collection in a fake store, with the parent and child calls the reminder uses."""

    def __init__(self, store, path):
        self._store = store
        self.path = path

    @property
    def id(self):
        return self.path.rsplit("/", 1)[-1]

    @property
    def parent(self):
        return Node(self._store, self.path.rsplit("/", 1)[0])

    def get(self, transaction=None):
        return Snap(self._store.docs.get(self.path))

    def collection(self, name):
        return Node(self._store, f"{self.path}/{name}")

    def document(self, doc_id):
        return Node(self._store, f"{self.path}/{doc_id}")


class FakeDb:
    def __init__(self, docs):
        self.docs = docs

    def collection_group(self, name):
        return FakeQuery(self, name)

    def document(self, path):
        return Node(self, path)


class FakeQuery:
    def __init__(self, db, name, filters=()):
        self._db = db
        self._name = name
        self._filters = tuple(filters)

    def where(self, field, op, value):
        return FakeQuery(self._db, self._name, self._filters + ((field, op, value),))

    def stream(self):
        found = []
        for path, data in self._db.docs.items():
            parts = path.split("/")
            if len(parts) < 2 or parts[-2] != self._name:
                continue
            if all(_matches(data.get(field), op, value) for field, op, value in self._filters):
                found.append(SimpleNamespace(reference=Node(self._db, path), to_dict=lambda data=data: dict(data)))
        return found


def _matches(actual, op, expected):
    if actual is None:
        return False
    return actual >= expected if op == ">=" else actual <= expected


class Engine:
    """Records the pushes instead of sending them."""

    def __init__(self, members):
        self.members = members
        self.pushes = []

    def get_active_tour_members(self, tour_id, except_email=""):
        return [m for m in self.members if m != except_email]

    def get_uids_for_emails(self, emails):
        return [f"uid-{e}" for e in emails]

    def get_push_targets_for_uids(self, uids):
        return [(f"tok-{uid}", None, "en") for uid in uids]

    def record_inbox(self, uids, data, make_text):
        """Records the entries the module keeps in each member's list, for the assertions."""
        self.inbox_entries = getattr(self, "inbox_entries", []) + [(list(uids), dict(data))]
        return len(list(uids))

    def send_localized(self, targets, make_text, data, high_priority=False):
        for token, _ref, language in targets:
            title, body = make_text(language)
            self.pushes.append({"token": token, "title": title, "body": body, "data": data})
        return len(targets)


def _store(assignment=None, subject=None, module_enabled=True, marks=None):
    subject_path = f"tours/{TOUR}/study_subjects/{SUBJECT}"
    docs = {
        subject_path: subject or {"title": "Physics 101", "approval": "listed", "archived": False},
        f"{subject_path}/modules/assignments": {"enabled": module_enabled},
        f"{subject_path}/assignments/a1": assignment or {
            "title": "Lab report 2",
            "dueAt": DUE,
            "shown": True,
            "createdByEmail": "ana@x.com",
        },
    }
    for email, done in (marks or {}).items():
        docs[f"{subject_path}/assignment_marks/{email}"] = {"done": done}
    return docs


def _claims():
    keys = set()

    def claim(key):
        if key in keys:
            return False
        keys.add(key)
        return True

    return claim


def test_a_reminder_is_due_in_the_day_before_its_due_time_only():
    shown = {"dueAt": DUE, "shown": True}
    assert ar.reminder_due(shown, DUE - timedelta(hours=24))
    assert ar.reminder_due(shown, NOW)
    assert not ar.reminder_due(shown, DUE - timedelta(hours=25))
    assert not ar.reminder_due(shown, DUE)
    assert not ar.reminder_due({"dueAt": DUE, "shown": False}, NOW)
    assert not ar.reminder_due({"shown": True}, NOW)


def test_a_moved_due_time_has_a_new_claim_key():
    assert ar.reminder_key(TOUR, "a1", DUE) != ar.reminder_key(TOUR, "a1", DUE + timedelta(days=1))


def test_the_members_who_have_not_finished_are_reminded_once_and_the_author_is_not_left_out():
    engine = Engine(MEMBERS)
    db = FakeDb(_store(marks={"ben@x.com": ["a1"]}))
    claim = _claims()

    stats = ar.run_assignment_due_reminders(db, engine, NOW, claim_key=claim)
    again = ar.run_assignment_due_reminders(db, engine, NOW, claim_key=claim)

    recipients = sorted(push["token"] for push in engine.pushes)
    assert recipients == ["tok-uid-ana@x.com", "tok-uid-dee@x.com"]
    assert engine.pushes[0]["title"] == "Assignment due tomorrow"
    assert engine.pushes[0]["body"] == "Lab report 2 in Physics 101 is due tomorrow."
    assert engine.pushes[0]["data"] == {"action": "study_subject", "tourId": TOUR, "subjectId": SUBJECT}
    assert stats["reminded"] == 1 and stats["pushes"] == 2
    assert again["reminded"] == 0


def test_a_waiting_assignment_an_archived_subject_or_a_switched_off_module_sends_nothing():
    waiting = _store(assignment={"title": "Lab", "dueAt": DUE, "shown": False, "createdByEmail": "ana@x.com"})
    for docs in (
        waiting,
        _store(subject={"title": "Old", "approval": "listed", "archived": True}),
        _store(module_enabled=False),
    ):
        engine = Engine(MEMBERS)
        ar.run_assignment_due_reminders(FakeDb(docs), engine, NOW, claim_key=_claims())
        assert engine.pushes == []


def test_nothing_is_due_outside_the_window():
    engine = Engine(MEMBERS)
    ar.run_assignment_due_reminders(FakeDb(_store()), engine, DUE - timedelta(days=3), claim_key=_claims())
    assert engine.pushes == []


def test_a_naive_time_is_refused():
    try:
        ar.run_assignment_due_reminders(FakeDb({}), Engine([]), datetime(2026, 11, 11))
    except ValueError:
        return
    raise AssertionError("a naive time should be refused")
