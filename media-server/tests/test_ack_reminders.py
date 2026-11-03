"""Tests for the answer reminders: the timing rules, and a run against fake Firestore.

Nothing here reaches Firebase. The run is checked against a fake database, a fake push
engine, and a stand-in for the Firestore transaction.
"""

from datetime import datetime, timedelta, timezone

import ack_reminders as ar

NOW = datetime(2026, 11, 1, 12, 0, tzinfo=timezone.utc)


def _notice(**extra):
    record = {
        "title": "Bazar on Friday",
        "requireAck": True,
        "kind": "announcement",
        "authorEmail": "admin@x.com",
        "createdAt": NOW - timedelta(hours=3),
        "ackBy": [],
    }
    record.update(extra)
    return record


def test_a_notice_asks_for_an_answer_when_it_requires_one_or_is_a_roll_call():
    assert ar.asks_answer(_notice())
    assert ar.asks_answer(_notice(requireAck=False, kind="rollcall"))
    assert not ar.asks_answer(_notice(requireAck=False))
    assert not ar.asks_answer({})


def test_a_notice_is_archived_only_after_its_expiry():
    assert ar.is_archived(_notice(expiresAt=NOW - timedelta(minutes=1)), NOW)
    assert not ar.is_archived(_notice(expiresAt=NOW + timedelta(minutes=1)), NOW)
    assert not ar.is_archived(_notice(), NOW)


def test_the_members_still_waiting_ignore_case_repeats_and_answers():
    record = _notice(ackBy=["Alice@X.com"])
    members = ["alice@x.com", "BOB@x.com", "bob@x.com", "", "carol@x.com"]

    assert ar.waiting_emails(record, members) == ["bob@x.com", "carol@x.com"]


def test_a_malformed_answer_list_counts_as_no_answers():
    assert ar.waiting_emails(_notice(ackBy="alice@x.com"), ["alice@x.com"]) == ["alice@x.com"]


def test_no_reminder_comes_before_the_first_delay_after_posting():
    waiting = ["bob@x.com"]

    assert not ar.ack_reminder_due(_notice(createdAt=NOW - timedelta(hours=1)), NOW, waiting)
    assert ar.ack_reminder_due(_notice(createdAt=NOW - timedelta(hours=3)), NOW, waiting)


def test_nothing_is_due_when_everyone_has_answered_or_the_notice_is_archived():
    old = NOW - timedelta(hours=3)

    assert not ar.ack_reminder_due(_notice(createdAt=old), NOW, [])
    assert not ar.ack_reminder_due(
        _notice(createdAt=old, expiresAt=NOW - timedelta(minutes=5)), NOW, ["bob@x.com"]
    )


def test_a_notice_older_than_the_lookback_is_left_alone():
    too_old = NOW - ar.LOOKBACK - timedelta(hours=1)

    assert not ar.ack_reminder_due(_notice(createdAt=too_old), NOW, ["bob@x.com"])


def test_later_reminders_wait_the_gap_and_stop_at_the_limit():
    waiting = ["bob@x.com"]
    first_sent = NOW - timedelta(hours=1)
    record = _notice(ackReminderSentAt=first_sent, ackReminderCount=1)

    assert not ar.ack_reminder_due(record, NOW, waiting)
    assert ar.ack_reminder_due(
        _notice(ackReminderSentAt=NOW - ar.GAP, ackReminderCount=1), NOW, waiting
    )
    assert not ar.ack_reminder_due(
        _notice(ackReminderSentAt=NOW - ar.GAP, ackReminderCount=ar.MAX_REMINDERS),
        NOW,
        waiting,
    )


def test_a_roll_call_is_reminded_like_an_acknowledgement():
    roll_call = _notice(requireAck=False, kind="rollcall")

    assert ar.ack_reminder_due(roll_call, NOW, ["bob@x.com"])


def test_the_text_names_the_notice_and_counts_who_is_waiting():
    assert ar.ack_reminder_text(_notice(), 1) == (
        "Please answer: Bazar on Friday",
        "1 member has not answered yet. Tap to answer.",
    )
    assert ar.ack_reminder_text(_notice(title="  "), 3) == (
        "Please answer a notice",
        "3 members have not answered yet. Tap to answer.",
    )


def test_the_answer_reminder_is_in_bengali_with_bengali_digits():
    assert ar.ack_reminder_text(_notice(title="Bazar"), 3, "bn") == (
        "উত্তর দিন: Bazar",
        "৩ জন সদস্য এখনও উত্তর দেয়নি। উত্তর দিতে ট্যাপ করুন।",
    )
    assert ar.ack_reminder_text(_notice(title="  "), 1, "bn") == (
        "একটি বিজ্ঞপ্তিতে উত্তর দিন",
        "একজন সদস্য এখনও উত্তর দেয়নি। উত্তর দিতে ট্যাপ করুন।",
    )


def test_an_unknown_language_gets_the_answer_reminder_in_english():
    assert ar.ack_reminder_text(_notice(title="Bazar"), 2, "fr") == (
        "Please answer: Bazar",
        "2 members have not answered yet. Tap to answer.",
    )


# --- a run, against fake Firestore and a fake push engine ----------------------------


class _Doc:
    def __init__(self, doc_id):
        self.id = doc_id


class _Coll:
    def __init__(self, parent_doc):
        self.parent = parent_doc


class FakeRef:
    def __init__(self, tour_id, notice_id, fields):
        self.path = f"tours/{tour_id}/notices/{notice_id}"
        self.fields = fields
        self.parent = _Coll(_Doc(tour_id))

    def get(self, transaction=None):
        return FakeSnapshot(self.fields)


class FakeSnapshot:
    def __init__(self, fields):
        self.exists = True
        self._fields = fields

    def to_dict(self):
        return dict(self._fields)


class FakeDocument:
    def __init__(self, tour_id, notice_id, fields):
        self.id = notice_id
        self.reference = FakeRef(tour_id, notice_id, fields)


class FakeTransaction:
    def update(self, ref, updates):
        ref.fields.update(updates)


class FakeQuery:
    def __init__(self, docs):
        self._docs = docs

    def where(self, field, op, value):
        assert op == "=="
        return FakeQuery([d for d in self._docs if d.reference.fields.get(field) == value])

    def stream(self):
        return list(self._docs)


class FakeDB:
    def __init__(self, docs):
        self._docs = docs

    def collection_group(self, name):
        assert name == "notices"
        return FakeQuery(self._docs)

    def transaction(self):
        return FakeTransaction()


class FakeEngine:
    def __init__(self, members_by_tour, languages=None):
        self._members = members_by_tour
        self._languages = dict(languages or {})
        self.pushes = []

    def get_active_tour_members(self, tour_id, except_email=""):
        return list(self._members[tour_id])

    def get_uids_for_emails(self, emails):
        return [f"uid-{email.split('@')[0]}" for email in emails]

    def get_push_targets_for_uids(self, uids):
        return [(f"tok-{uid}", None, self._languages.get(uid, "en")) for uid in uids]

    def send_localized(self, targets, make_text, data, high_priority=False):
        # The server's contract: one text per language, sent to that language's devices.
        for language in sorted({lang for _, _, lang in targets}):
            title, body = make_text(language)
            self.pushes.append({
                "targets": [token for token, _, lang in targets if lang == language],
                "title": title,
                "body": body,
                "data": data,
            })
        return len(targets)


def _no_transaction(fn):
    return lambda transaction, *args: fn(transaction, *args)


def test_a_run_reminds_only_the_members_who_have_not_answered():
    notice = _notice(ackBy=["alice@x.com"])
    db = FakeDB([FakeDocument("t1", "n1", notice)])
    engine = FakeEngine({"t1": ["alice@x.com", "bob@x.com", "carol@x.com"]})

    stats = ar.run_ack_reminders(db, engine, NOW, transactional=_no_transaction)

    assert stats == {"due": 1, "reminded": 1, "pushes": 2, "errors": 0}
    assert engine.pushes[0]["targets"] == ["tok-uid-bob", "tok-uid-carol"]
    assert engine.pushes[0]["data"] == {"action": "notice", "tourId": "t1", "noticeId": "n1"}
    assert notice["ackReminderCount"] == 1
    # A run inside the gap finds the reminder already sent and pushes nothing.
    again = ar.run_ack_reminders(db, engine, NOW + timedelta(hours=1), transactional=_no_transaction)
    assert again["reminded"] == 0
    assert len(engine.pushes) == 1


def test_a_member_who_uses_bengali_gets_the_answer_reminder_in_bengali():
    notice = _notice(ackBy=["alice@x.com"])
    db = FakeDB([FakeDocument("t1", "n1", notice)])
    engine = FakeEngine(
        {"t1": ["alice@x.com", "bob@x.com", "carol@x.com"]}, languages={"uid-bob": "bn"}
    )

    stats = ar.run_ack_reminders(db, engine, NOW, transactional=_no_transaction)

    assert stats == {"due": 1, "reminded": 1, "pushes": 2, "errors": 0}
    # Bengali first (sorted by language), then the English devices.
    assert engine.pushes[0] == {
        "targets": ["tok-uid-bob"],
        "title": "উত্তর দিন: Bazar on Friday",
        "body": "২ জন সদস্য এখনও উত্তর দেয়নি। উত্তর দিতে ট্যাপ করুন।",
        "data": {"action": "notice", "tourId": "t1", "noticeId": "n1"},
    }
    assert engine.pushes[1]["targets"] == ["tok-uid-carol"]
    assert engine.pushes[1]["title"] == "Please answer: Bazar on Friday"


def test_a_notice_is_reminded_twice_at_most_and_then_left_alone():
    notice = _notice(ackBy=[])
    db = FakeDB([FakeDocument("t1", "n1", notice)])
    engine = FakeEngine({"t1": ["bob@x.com"]})

    first = ar.run_ack_reminders(db, engine, NOW, transactional=_no_transaction)
    second = ar.run_ack_reminders(db, engine, NOW + ar.GAP, transactional=_no_transaction)
    third = ar.run_ack_reminders(db, engine, NOW + 2 * ar.GAP, transactional=_no_transaction)

    assert (first["reminded"], second["reminded"], third["reminded"]) == (1, 1, 0)
    assert notice["ackReminderCount"] == ar.MAX_REMINDERS


def test_a_notice_everyone_has_answered_sends_nothing():
    db = FakeDB([FakeDocument("t1", "n1", _notice(ackBy=["bob@x.com"]))])
    engine = FakeEngine({"t1": ["bob@x.com"]})

    stats = ar.run_ack_reminders(db, engine, NOW, transactional=_no_transaction)

    assert stats == {"due": 1, "reminded": 0, "pushes": 0, "errors": 0}
    assert engine.pushes == []


def test_one_bad_circle_does_not_stop_the_other_reminders():
    db = FakeDB([
        FakeDocument("broken", "n1", _notice()),
        FakeDocument("t2", "n2", _notice()),
    ])
    engine = FakeEngine({"t2": ["bob@x.com"]})

    stats = ar.run_ack_reminders(db, engine, NOW, transactional=_no_transaction)

    assert stats["errors"] == 1
    assert stats["reminded"] == 1
    assert engine.pushes[0]["data"]["noticeId"] == "n2"


def test_a_run_refuses_a_naive_time():
    try:
        ar.run_ack_reminders(FakeDB([]), FakeEngine({}), datetime(2026, 11, 1, 12, 0))
    except ValueError:
        return
    raise AssertionError("a naive time must be refused")


def test_the_manual_run_is_refused_when_no_key_is_configured(monkeypatch):
    from fastapi.testclient import TestClient

    import main

    monkeypatch.setattr(main, "ACK_REMINDER_RUN_KEY", "")
    response = TestClient(main.app).post(
        "/internal/ack-reminders/run", headers={"X-Ack-Reminder-Key": "anything"}
    )
    assert response.status_code == 503


def test_the_manual_run_needs_the_configured_key(monkeypatch):
    from fastapi.testclient import TestClient

    import main

    monkeypatch.setattr(main, "ACK_REMINDER_RUN_KEY", "secret-key")
    client = TestClient(main.app)
    assert client.post("/internal/ack-reminders/run").status_code == 401
    assert client.post(
        "/internal/ack-reminders/run", headers={"X-Ack-Reminder-Key": "wrong"}
    ).status_code == 401
