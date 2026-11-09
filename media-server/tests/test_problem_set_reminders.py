"""Problem-set reminders: the day before a set is due, once, to each member who has not worked every shown problem."""

from datetime import datetime, timedelta, timezone

import problem_set_reminders as psr

DUE = datetime(2026, 11, 12, 0, 0, tzinfo=timezone.utc)
NOW = DUE - timedelta(hours=24)  # exactly the reminder time
SUBJECT = "tours/T1/study_subjects/S1"
SET_PATH = f"{SUBJECT}/problem_sets/SET1"


class FakeDb:
    """Documents by path, with the parts of the Firestore client the reminder job uses."""

    def __init__(self, docs):
        self.docs = {path: dict(data) for path, data in docs.items()}

    def collection_group(self, name):
        return FakeQuery(self, group=name)

    def transaction(self):
        return FakeTransaction(self)

    def collection(self, path):
        return FakeCollection(self, path)

    def document(self, path):
        return FakeRef(self, path)


class FakeTransaction:
    def __init__(self, db):
        self.db = db

    def update(self, ref, updates):
        self.db.docs[ref.path].update(updates)


class FakeSnapshot:
    def __init__(self, ref, data):
        self.reference = ref
        self._data = data

    @property
    def exists(self):
        return self._data is not None

    @property
    def id(self):
        return self.reference.id

    def to_dict(self):
        return None if self._data is None else dict(self._data)


class FakeRef:
    def __init__(self, db, path):
        self.db = db
        self.path = path

    @property
    def id(self):
        return self.path.split("/")[-1]

    @property
    def parent(self):
        return FakeCollection(self.db, self.path.rsplit("/", 1)[0])

    def get(self, transaction=None):
        return FakeSnapshot(self, self.db.docs.get(self.path))

    def collection(self, name):
        return FakeCollection(self.db, f"{self.path}/{name}")


class FakeCollection:
    def __init__(self, db, path):
        self.db = db
        self.path = path

    @property
    def parent(self):
        head = self.path.rsplit("/", 1)[0]
        return FakeRef(self.db, head) if "/" in head else None

    def document(self, doc_id):
        return FakeRef(self.db, f"{self.path}/{doc_id}")

    def where(self, field, op, value):
        return FakeQuery(self.db, parent=self.path, filters=((field, op, value),))

    def stream(self):
        return FakeQuery(self.db, parent=self.path).stream()


class FakeQuery:
    def __init__(self, db, group=None, parent=None, filters=()):
        self.db = db
        self.group = group
        self.parent = parent
        self.filters = tuple(filters)

    def where(self, field, op, value):
        return FakeQuery(self.db, self.group, self.parent, self.filters + ((field, op, value),))

    def stream(self):
        found = []
        for path, data in self.db.docs.items():
            parts = path.split("/")
            if self.group is not None:
                if len(parts) < 2 or parts[-2] != self.group:
                    continue
            elif path.rsplit("/", 1)[0] != self.parent:
                continue
            if all(_matches(data.get(field), op, value) for field, op, value in self.filters):
                found.append(FakeDoc(self.db, path, data))
        return found


class FakeDoc:
    def __init__(self, db, path, data):
        self.reference = FakeRef(db, path)
        self._data = dict(data)

    @property
    def id(self):
        return self.reference.id

    def to_dict(self):
        return dict(self._data)


def _matches(value, op, expected):
    if op == "==":
        return value == expected
    if value is None:
        return False
    if op == ">=":
        return value >= expected
    if op == "<=":
        return value <= expected
    raise AssertionError(f"unsupported op {op}")


class FakeEngine:
    """Records the pushes; the members of a tour, and a token per member."""

    def __init__(self, members_by_tour, failing_tours=()):
        self.members_by_tour = members_by_tour
        self.failing_tours = set(failing_tours)
        self.pushes = []

    def get_active_tour_members(self, tour_id, except_email=""):
        if tour_id in self.failing_tours:
            raise RuntimeError("members unavailable")
        return list(self.members_by_tour.get(tour_id, []))

    def get_uids_for_emails(self, emails):
        return [f"uid-{email}" for email in emails]

    def get_push_targets_for_uids(self, uids):
        return [(f"tok-{uid}", None, "en") for uid in uids]

    def send_localized(self, targets, make_text, data, high_priority=False):
        for token, _ref, language in targets:
            title, body = make_text(language)
            self.pushes.append({"token": token, "title": title, "body": body, "data": data})
        return len(targets)


def _tour(**overrides):
    """A tour with one listed subject, its problems module on, one due set and three problems in it."""
    subject = {"approval": "listed", "archived": False}
    subject.update(overrides.pop("subject", {}))
    docs = {
        SUBJECT: subject,
        f"{SUBJECT}/modules/problems": {"enabled": True},
        SET_PATH: {"title": "Week 3", "dueAt": DUE, "createdByEmail": "admin@x.com"},
        f"{SUBJECT}/problems/P1": {"setId": "SET1", "shown": True},
        f"{SUBJECT}/problems/P2": {"setId": "SET1", "shown": True},
        f"{SUBJECT}/problems/P3": {"setId": "SET1", "shown": False},
        f"{SUBJECT}/problems/P1/solutions/ana@x.com": {"text": "a"},
        f"{SUBJECT}/problems/P1/solutions/ben@x.com": {"text": "b"},
        f"{SUBJECT}/problems/P2/solutions/ana@x.com": {"text": "c"},
    }
    docs.update(overrides)
    return docs


MEMBERS = {"T1": ["ana@x.com", "ben@x.com", "cy@x.com"]}


def _run(db, engine, now=NOW):
    return psr.run_problem_set_reminders(db, engine, now, transactional=lambda fn: fn)


# The timing rule.


def test_the_reminder_is_due_from_24_hours_before_the_due_time_until_it_passes():
    record = {"dueAt": DUE}
    assert psr.reminder_due(record, DUE - timedelta(hours=24))
    assert psr.reminder_due(record, DUE - timedelta(hours=1))
    assert not psr.reminder_due(record, DUE - timedelta(hours=25))
    assert not psr.reminder_due(record, DUE)


def test_a_sent_or_undated_set_is_not_due():
    assert not psr.reminder_due({"dueAt": DUE, "reminderSentAt": NOW}, NOW)
    assert not psr.reminder_due({"title": "No date"}, NOW)


# Who is reminded.


def test_a_member_who_has_not_worked_every_shown_problem_is_reminded():
    unfinished = psr.unfinished_members(
        ["ana@x.com", "ben@x.com", "cy@x.com"],
        ["P1", "P2"],
        {"P1": {"ana@x.com", "ben@x.com"}, "P2": {"ana@x.com"}},
    )
    assert unfinished == ["ben@x.com", "cy@x.com"]


def test_a_set_with_no_shown_problem_reminds_no_one():
    assert psr.unfinished_members(["ana@x.com"], [], {}) == []


def test_the_title_falls_back_to_a_plain_name_and_the_language_is_used():
    en = psr.problem_set_text({"title": "Week 3"}, "en")
    assert en[1] == "Week 3 is due tomorrow. Some problems are still unworked."
    untitled = psr.problem_set_text({"title": "  "}, "en")
    assert "your problem set" in untitled[1]
    assert psr.problem_set_text({"title": "Week 3"}, "bn")[0] != en[0]


# The run.


def test_the_run_reminds_only_the_members_still_to_work_and_marks_the_set_sent():
    db = FakeDb(_tour())
    engine = FakeEngine(MEMBERS)

    stats = _run(db, engine)

    assert stats["reminded"] == 1
    assert stats["errors"] == 0
    assert sorted(push["token"] for push in engine.pushes) == ["tok-uid-ben@x.com", "tok-uid-cy@x.com"]
    assert all(push["data"]["action"] == "problem_set" for push in engine.pushes)
    assert all(push["data"]["setId"] == "SET1" for push in engine.pushes)
    assert db.docs[SET_PATH]["reminderSentAt"] == NOW


def test_a_second_run_sends_nothing_for_the_same_set():
    db = FakeDb(_tour())
    engine = FakeEngine(MEMBERS)
    _run(db, engine)
    sent_once = len(engine.pushes)

    stats = _run(db, engine)

    assert stats["reminded"] == 0
    assert len(engine.pushes) == sent_once


def test_a_set_whose_members_have_all_worked_is_marked_but_sends_nothing():
    docs = _tour(**{
        f"{SUBJECT}/problems/P1/solutions/cy@x.com": {"text": "d"},
        f"{SUBJECT}/problems/P2/solutions/ben@x.com": {"text": "e"},
        f"{SUBJECT}/problems/P2/solutions/cy@x.com": {"text": "f"},
        f"{SUBJECT}/problems/P1/solutions/ben@x.com": {"text": "b"},
    })
    db = FakeDb(docs)
    engine = FakeEngine(MEMBERS)

    stats = _run(db, engine)

    assert stats["reminded"] == 1
    assert engine.pushes == []
    assert db.docs[SET_PATH]["reminderSentAt"] == NOW


def test_a_subject_that_is_not_listed_or_is_archived_sends_nothing_and_is_not_marked():
    for subject in ({"approval": "proposed"}, {"archived": True}):
        db = FakeDb(_tour(subject=subject))
        engine = FakeEngine(MEMBERS)
        stats = _run(db, engine)
        assert stats["reminded"] == 0, subject
        assert engine.pushes == [], subject
        assert "reminderSentAt" not in db.docs[SET_PATH], subject


def test_a_subject_whose_problems_module_is_off_sends_nothing():
    docs = _tour()
    docs[f"{SUBJECT}/modules/problems"] = {"enabled": False}
    db = FakeDb(docs)
    engine = FakeEngine(MEMBERS)

    stats = _run(db, engine)

    assert stats["reminded"] == 0
    assert engine.pushes == []


def test_a_set_due_much_later_is_not_read_yet():
    db = FakeDb(_tour(**{SET_PATH: {"title": "Later", "dueAt": DUE + timedelta(days=3)}}))
    engine = FakeEngine(MEMBERS)

    stats = _run(db, engine)

    assert stats["due"] == 0
    assert engine.pushes == []


def test_one_broken_tour_does_not_stop_the_others():
    docs = _tour()
    other = "tours/T2/study_subjects/S2"
    docs.update({
        other: {"approval": "listed", "archived": False},
        f"{other}/modules/problems": {"enabled": True},
        f"{other}/problem_sets/SET2": {"title": "Other", "dueAt": DUE},
        f"{other}/problems/Q1": {"setId": "SET2", "shown": True},
    })
    db = FakeDb(docs)
    engine = FakeEngine({"T1": MEMBERS["T1"], "T2": ["dee@x.com"]}, failing_tours=["T1"])

    stats = _run(db, engine)

    assert stats["errors"] == 1
    assert stats["reminded"] == 1
    assert [push["token"] for push in engine.pushes] == ["tok-uid-dee@x.com"]


def test_the_run_needs_a_timezone():
    try:
        _run(FakeDb({}), FakeEngine({}), now=datetime(2026, 11, 11))
    except ValueError:
        return
    raise AssertionError("a naive time must be refused")
