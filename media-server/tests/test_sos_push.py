"""Safety alerts on the VPS: who is pushed, once, and when the end is pushed.

A raised alert is pushed to the other active members of a tour that has SOS (a trip, a household, a mess or a
housing society), once, under the sender's name in the group. Restarts do not send it again, and an alert raised
shortly before a restart is still pushed. One sender's alerts are pushed once per window. The end of an alert is
pushed only when its alert was. The app's own request for a push is honoured only for its own, open, recent alert.
"""

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import MagicMock

import notifications
from notifications import FirestoreNotificationWatcher, NotificationEngine, PUSH_CLAIMS

TOUR = "mess1"
OFFICE = "office1"
SENDER = "ana@x.com"
MEMBERS = [
    ("ana@x.com", "member", "active", "Ana"),
    ("ben@x.com", "member", "active", "Ben"),
    ("cy@x.com", "admin", "active", "Cy"),
    ("zoe@x.com", "member", "left", "Zoe"),
]
NOW = datetime(2026, 11, 11, 12, 0, tzinfo=timezone.utc)


class FakeSnap:
    def __init__(self, data):
        self._data = data
        self.exists = data is not None

    def to_dict(self):
        return None if self._data is None else dict(self._data)


class FakeRef:
    def __init__(self, db, path):
        self._db = db
        self.path = path

    def get(self, transaction=None):
        return FakeSnap(self._db.docs.get(self.path))

    def collection(self, name):
        return FakeCollection(self._db, f"{self.path}/{name}")


class FakeQuery:
    def __init__(self, db, name, filters=()):
        self._db = db
        self._name = name
        self._filters = tuple(filters)

    def where(self, field, op, value):
        assert op == "=="
        return FakeQuery(self._db, self._name, self._filters + ((field, value),))

    def stream(self):
        found = []
        for path, data in self._db.docs.items():
            if path.rsplit("/", 1)[0] != self._name:
                continue
            if all(data.get(field) == value for field, value in self._filters):
                found.append(SimpleNamespace(to_dict=lambda data=data: dict(data)))
        return found


class FakeCollection:
    def __init__(self, db, name):
        self._db = db
        self._name = name

    def document(self, doc_id):
        return FakeRef(self._db, f"{self._name}/{doc_id}")

    def where(self, field, op, value):
        return FakeQuery(self._db, self._name).where(field, op, value)

    def stream(self):
        return FakeQuery(self._db, self._name).stream()


class FakeDb:
    def __init__(self, docs):
        self.docs = {path: dict(data) for path, data in docs.items()}

    def collection(self, name):
        return FakeCollection(self, name)

    def document(self, path):
        return FakeRef(self, path)


class Claims:
    """The push_claims records, kept in the fake database so the engine can read them back."""

    def __init__(self, db):
        self._db = db

    def __call__(self, key):
        path = f"{PUSH_CLAIMS}/{key}"
        if path in self._db.docs:
            return False
        self._db.docs[path] = {"sentAt": "now"}
        return True


class Engine(NotificationEngine):
    """Records each push instead of sending it."""

    def __init__(self, db):
        super().__init__()
        self._fake_db = db
        self.sent = []
        self.claim_once = Claims(db)

    def _get_db(self):
        return self._fake_db

    def get_uids_for_emails(self, emails):
        return [f"uid-{email}" for email in emails]

    def get_push_targets_for_uids(self, uids):
        return [(f"tok-{uid}", None, "en") for uid in uids]

    def send_multicast(self, targets, title, body, data, high_priority=False, sos_tag=None):
        self.sent.append({"tokens": sorted(t[0] for t in targets), "title": title, "data": data, "sos_tag": sos_tag})
        return len(targets)


def _docs(preset="mess"):
    docs = {f"tours/{TOUR}": {"name": "Block B mess", "kind": "family", "preset": preset}}
    docs[f"tours/{OFFICE}"] = {"name": "Sales team", "kind": "family", "preset": "office"}
    for email, role, status, name in MEMBERS:
        docs[f"memberships/{TOUR}__{email}"] = {"tourId": TOUR, "email": email, "role": role, "status": status, "displayName": name}
        docs[f"memberships/{OFFICE}__{email}"] = {"tourId": OFFICE, "email": email, "role": role, "status": status, "displayName": name}
    return docs


def _setup(preset="mess"):
    db = FakeDb(_docs(preset))
    engine = Engine(db)
    watcher = FirestoreNotificationWatcher(engine, claim_push=Claims(db))
    watcher.started_at = NOW
    return db, engine, watcher


def _change(tour, alert_id, data, kind="ADDED"):
    reference = SimpleNamespace(parent=SimpleNamespace(parent=SimpleNamespace(id=tour)))
    document = SimpleNamespace(id=alert_id, reference=reference, to_dict=lambda: dict(data))
    return SimpleNamespace(type=SimpleNamespace(name=kind), document=document)


def _alert(sender=SENDER, at=NOW, **extra):
    data = {"senderEmail": sender, "senderName": "Admin", "resolved": False, "createdAt": at}
    data.update(extra)
    return data


def _freeze_clock(monkeypatch, when=NOW):
    monkeypatch.setattr(notifications.time, "time", lambda: when.timestamp())


def test_a_trip_household_mess_or_society_pushes_an_alert(monkeypatch):
    _freeze_clock(monkeypatch)
    db, engine, watcher = _setup("mess")
    watcher.on_sos_snapshot(None, [_change(TOUR, "a1", _alert())], None)

    assert len(engine.sent) == 1
    assert engine.sent[0]["tokens"] == ["tok-uid-ben@x.com", "tok-uid-cy@x.com"], "the sender and a leaver are not pushed"
    assert engine.sent[0]["sos_tag"] == "sos_a1"


def test_the_push_names_the_sender_as_the_group_knows_them_not_as_the_alert_says(monkeypatch):
    _freeze_clock(monkeypatch)
    db, engine, watcher = _setup("mess")
    watcher.on_sos_snapshot(None, [_change(TOUR, "a1", _alert(senderName="Admin"))], None)

    assert engine.sent[0]["title"].endswith("Ana") or "Ana" in engine.sent[0]["title"]
    assert "Admin" not in engine.sent[0]["title"]


def test_an_office_pushes_nothing(monkeypatch):
    _freeze_clock(monkeypatch)
    db, engine, watcher = _setup("office")
    watcher.on_sos_snapshot(None, [_change(OFFICE, "a1", _alert())], None)
    assert engine.sent == []


def test_a_repeated_delivery_does_not_push_again(monkeypatch):
    _freeze_clock(monkeypatch)
    db, engine, watcher = _setup("mess")
    change = _change(TOUR, "a1", _alert())
    watcher.on_sos_snapshot(None, [change], None)
    # A restart starts with an empty memory, but the claim it made is kept.
    restarted = FirestoreNotificationWatcher(engine, claim_push=Claims(db))
    restarted.started_at = NOW
    restarted.on_sos_snapshot(None, [change], None)

    assert len(engine.sent) == 1


def test_an_alert_raised_just_before_a_restart_is_still_pushed(monkeypatch):
    _freeze_clock(monkeypatch)
    db, engine, watcher = _setup("mess")
    watcher.started_at = NOW + timedelta(minutes=1)  # the watcher started a minute after the write
    watcher.on_sos_snapshot(None, [_change(TOUR, "a1", _alert(at=NOW - timedelta(seconds=30)))], None)
    assert len(engine.sent) == 1


def test_an_old_alert_is_not_pushed_on_start(monkeypatch):
    _freeze_clock(monkeypatch)
    db, engine, watcher = _setup("mess")
    watcher.on_sos_snapshot(None, [_change(TOUR, "old", _alert(at=NOW - timedelta(hours=1)))], None)
    assert engine.sent == []


def test_one_sender_pushes_one_alert_per_window(monkeypatch):
    _freeze_clock(monkeypatch)
    db, engine, watcher = _setup("mess")
    watcher.on_sos_snapshot(None, [_change(TOUR, "a1", _alert()), _change(TOUR, "a2", _alert())], None)

    assert len(engine.sent) == 1, "the second alert in the window is shown in the app, not pushed again"
    assert engine.send_sos_alert(TOUR, "a3", SENDER)["status"] == "rate_limited"


def test_the_end_is_pushed_once_and_only_for_an_alert_that_was_pushed(monkeypatch):
    _freeze_clock(monkeypatch)
    db, engine, watcher = _setup("mess")
    watcher.on_sos_snapshot(None, [_change(TOUR, "a1", _alert()), _change(TOUR, "a2", _alert())], None)
    # a2 was not pushed (rate limited), so its end is not pushed either.
    watcher.on_sos_snapshot(None, [_change(TOUR, "a2", _alert(resolved=True), kind="MODIFIED")], None)
    assert len(engine.sent) == 1

    ended = _change(TOUR, "a1", _alert(resolved=True), kind="MODIFIED")
    watcher.on_sos_snapshot(None, [ended], None)
    watcher.on_sos_snapshot(None, [ended], None)
    assert len(engine.sent) == 2
    assert engine.sent[1]["sos_tag"] == "sos_a1", "the end shares the alert's tag, so it replaces it on the phone"
    assert "over" in engine.sent[1]["title"].lower() or "শেষ" in engine.sent[1]["title"]


def test_the_app_can_ask_for_its_own_alert_only(monkeypatch):
    # The endpoint checks the alert against the real clock, so these alerts are written against it.
    real_now = datetime.now(timezone.utc)
    _freeze_clock(monkeypatch)
    db, engine, watcher = _setup("mess")
    db.docs[f"tours/{TOUR}/sos/mine"] = _alert(at=real_now)
    db.docs[f"tours/{TOUR}/sos/theirs"] = _alert(sender="ben@x.com", at=real_now)
    db.docs[f"tours/{TOUR}/sos/closed"] = _alert(resolved=True, at=real_now)
    db.docs[f"tours/{TOUR}/sos/stale"] = _alert(at=real_now - timedelta(hours=1))

    assert engine.push_own_sos(TOUR, "nothing", SENDER) == {"status": "refused", "reason": "no_alert"}
    assert engine.push_own_sos(TOUR, "theirs", SENDER) == {"status": "refused", "reason": "not_sender"}
    assert engine.push_own_sos(TOUR, "closed", SENDER) == {"status": "refused", "reason": "resolved"}
    assert engine.push_own_sos(TOUR, "stale", SENDER) == {"status": "refused", "reason": "too_old"}
    assert engine.sent == [], "nothing is pushed for a refused request"

    assert engine.push_own_sos(TOUR, "mine", SENDER)["status"] == "success"
    assert len(engine.sent) == 1


def test_the_app_cannot_push_an_alert_in_a_tour_without_sos(monkeypatch):
    _freeze_clock(monkeypatch)
    db, engine, watcher = _setup("mess")
    db.docs[f"tours/{OFFICE}/sos/mine"] = _alert(at=datetime.now(timezone.utc))
    assert engine.push_own_sos(OFFICE, "mine", SENDER) == {"status": "refused", "reason": "not_allowed"}
    assert engine.sent == []


def test_the_sos_push_goes_on_the_sos_channel_and_is_time_sensitive_on_iphones():
    engine = NotificationEngine()
    messaging = MagicMock()
    messaging.send_each_for_multicast.return_value = SimpleNamespace(success_count=1, responses=[])
    engine._get_messaging = lambda: messaging

    engine.send_multicast([("tok", None)], "SOS from Ana", "Open Bhromon", {"action": "sos"}, high_priority=True, sos_tag="sos_a1")

    assert messaging.AndroidNotification.call_args.kwargs == {"channel_id": "bhromon_sos", "tag": "sos_a1"}
    assert messaging.AndroidConfig.call_args.kwargs["collapse_key"] == "sos_a1"
    assert messaging.APNSConfig.call_args.kwargs["headers"]["apns-collapse-id"] == "sos_a1"
    aps = messaging.Aps.call_args.kwargs
    assert aps["sound"] == "default"
    assert aps["custom_data"] == {"interruption-level": "time-sensitive"}


def test_other_pushes_keep_their_channel_and_have_no_sos_options():
    engine = NotificationEngine()
    messaging = MagicMock()
    messaging.send_each_for_multicast.return_value = SimpleNamespace(success_count=1, responses=[])
    engine._get_messaging = lambda: messaging

    engine.send_multicast([("tok", None)], "Notice", "Body", {"action": "notice"}, high_priority=True)

    assert messaging.AndroidConfig.call_args.kwargs == {"priority": "high"}
    assert not messaging.AndroidNotification.called
    assert messaging.MulticastMessage.call_args.kwargs["apns"] is None
