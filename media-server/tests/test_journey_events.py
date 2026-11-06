"""Journey events on the VPS (roadmap LJ-4.3 and LJ-4.6): a member's arrival or
departure is pushed once to the other members of the tour, with the stop's name and
no position, and events older than thirty days are deleted."""

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace


from journey_cleanup import JOURNEY_EVENT_RETENTION, run_journey_event_cleanup
from notifications import FirestoreNotificationWatcher, NotificationEngine

TOUR = "t1"


class FakeSnap:
    def __init__(self, data):
        self._data = data
        self.exists = data is not None

    def to_dict(self):
        return dict(self._data or {})


class FakeDocRef:
    def __init__(self, db, path):
        self._db = db
        self.path = path

    def get(self, transaction=None):
        return FakeSnap(self._db.docs.get(self.path))

    def delete(self):
        if self._db.fail_deletes:
            raise RuntimeError("delete refused")
        self._db.docs.pop(self.path, None)


class FakeCollection:
    def __init__(self, db, name):
        self._db = db
        self._name = name

    def document(self, doc_id):
        return FakeDocRef(self._db, f"{self._name}/{doc_id}")


class FakeQuery:
    def __init__(self, db, threshold=None, limit=None):
        self._db = db
        self._threshold = threshold
        self._limit = limit

    def where(self, field, op, value):
        assert (field, op) == ("createdAt", "<")
        return FakeQuery(self._db, value, self._limit)

    def limit(self, n):
        return FakeQuery(self._db, self._threshold, n)

    def stream(self):
        matches = [
            SimpleNamespace(reference=FakeDocRef(self._db, path), id=path.rsplit("/", 1)[-1])
            for path, data in list(self._db.docs.items())
            if "journey_events/" in path and data["createdAt"] < self._threshold
        ]
        return iter(matches[: self._limit])


class FakeDb:
    def __init__(self, docs=None):
        self.docs = dict(docs or {})
        self.fail_deletes = False

    def collection(self, name):
        return FakeCollection(self, name)

    def collection_group(self, name):
        assert name == "journey_events"
        return FakeQuery(self)


class FakeEngine:
    def __init__(self, db):
        self.db = db
        self.calls = []
        self.stats = {"errors": 0}

    def _get_db(self):
        return self.db

    def send_journey_event(self, **kwargs):
        self.calls.append(kwargs)
        return {"status": "success"}


def _change(event_id, data, *, kind="ADDED", tour=TOUR):
    tour_ref = SimpleNamespace(id=tour)
    reference = SimpleNamespace(
        path=f"tours/{tour}/journey_events/{event_id}",
        parent=SimpleNamespace(parent=tour_ref),
    )
    document = SimpleNamespace(id=event_id, reference=reference, to_dict=lambda: dict(data))
    return SimpleNamespace(type=SimpleNamespace(name=kind), document=document)


def _event(stop="sajek", kind="arrive", email="rahim@x.com", **extra):
    data = {
        "type": kind,
        "stopId": stop,
        "email": email,
        "uid": "u-rahim",
        "createdAt": datetime.now(timezone.utc) + timedelta(seconds=1),
    }
    data.update(extra)
    return data


def _db(**extra):
    docs = {
        f"tours/{TOUR}": {"stops": [{"id": "sajek", "name": "Sajek"}]},
        f"memberships/{TOUR}__rahim@x.com": {"displayName": "Rahim"},
    }
    docs.update(extra)
    return FakeDb(docs)


def _watcher(engine, claimed=None):
    claimed = set() if claimed is None else claimed

    def claim(ref):
        if ref.path in claimed:
            return False
        claimed.add(ref.path)
        return True

    return FirestoreNotificationWatcher(engine, claim_event=claim)


def test_an_arrival_is_pushed_once_with_the_stop_name_and_the_sender():
    engine = FakeEngine(_db())
    watcher = _watcher(engine)

    watcher.on_journey_snapshot(None, [_change("sajek__rahim@x.com__arrive", _event())], None)
    watcher.on_journey_snapshot(None, [_change("sajek__rahim@x.com__arrive", _event())], None)

    assert engine.calls == [{
        "tour_id": TOUR,
        "event_id": "sajek__rahim@x.com__arrive",
        "sender_email": "rahim@x.com",
        "sender_name": "Rahim",
        "stop_name": "Sajek",
        "kind": "arrive",
    }]


def test_a_departure_is_pushed_as_a_departure():
    engine = FakeEngine(_db())
    watcher = _watcher(engine)
    watcher.on_journey_snapshot(None, [_change("sajek__rahim@x.com__depart", _event(kind="depart"))], None)
    assert [c["kind"] for c in engine.calls] == ["depart"]


def test_an_event_from_before_the_watcher_started_is_not_pushed():
    engine = FakeEngine(_db())
    watcher = _watcher(engine)
    old = _event(createdAt=watcher.started_at - timedelta(minutes=5))
    watcher.on_journey_snapshot(None, [_change("sajek__rahim@x.com__arrive", old)], None)
    assert engine.calls == []


def test_an_event_already_claimed_is_not_pushed_again():
    engine = FakeEngine(_db())
    watcher = _watcher(engine, claimed={f"tours/{TOUR}/journey_events/sajek__rahim@x.com__arrive"})
    watcher.on_journey_snapshot(None, [_change("sajek__rahim@x.com__arrive", _event())], None)
    assert engine.calls == []


def test_only_added_events_with_a_known_type_and_stop_are_pushed():
    engine = FakeEngine(_db())
    watcher = _watcher(engine)
    watcher.on_journey_snapshot(None, [
        _change("a", _event(), kind="MODIFIED"),
        _change("b", _event(kind="wave")),
        _change("c", _event(stop="")),
        _change("d", _event(email="")),
    ], None)
    assert engine.calls == []


def test_names_fall_back_when_the_itinerary_or_the_member_has_none():
    db = FakeDb({f"tours/{TOUR}": {"stops": []}})
    engine = FakeEngine(db)
    watcher = _watcher(engine)
    watcher.on_journey_snapshot(None, [_change("sajek__rahim@x.com__arrive", _event())], None)
    assert engine.calls[0]["stop_name"] == "sajek"
    assert engine.calls[0]["sender_name"] == "A member"


def test_the_engine_pushes_each_language_its_own_text_and_skips_the_sender(monkeypatch):
    engine = NotificationEngine(db=None, auth_mod=None, messaging_mod=None)
    seen = {}
    monkeypatch.setattr(engine, "get_active_tour_members",
                        lambda tour_id, except_email="": seen.setdefault("except", except_email) and ["own@x.com"])
    monkeypatch.setattr(engine, "get_uids_for_emails", lambda emails: ["u1", "u2"])
    monkeypatch.setattr(engine, "get_push_targets_for_uids", lambda uids: [
        ("tok-en", None, "en"),
        ("tok-bn", None, "bn"),
    ])
    sent = []

    def fake_multicast(group, title, body, data, high_priority=False):
        sent.append((title, body, data))
        return len(group)

    monkeypatch.setattr(engine, "send_multicast", fake_multicast)

    result = engine.send_journey_event(
        tour_id=TOUR,
        event_id="sajek__rahim@x.com__arrive",
        sender_email="rahim@x.com",
        sender_name="Rahim",
        stop_name="Sajek",
        kind="arrive",
    )

    assert seen["except"] == "rahim@x.com", "the sender is not told"
    assert result["status"] == "success"
    titles = {title for title, _, _ in sent}
    assert "Rahim reached Sajek" in titles
    assert any("Sajek" in title and "পৌঁছেছেন" in title for title in titles)
    for _, body, data in sent:
        assert "lat" not in str(data).lower(), "no position is pushed"
        assert data["action"] == "journey" and data["tourId"] == TOUR


def test_an_unknown_kind_is_not_pushed():
    engine = NotificationEngine(db=None, auth_mod=None, messaging_mod=None)
    assert engine.send_journey_event(TOUR, "e", "a@x.com", "A", "S", "wave") == {"status": "ignored"}


def _old_event(path_id, days):
    return {
        "type": "arrive",
        "createdAt": datetime.now(timezone.utc) - timedelta(days=days),
    }


def test_events_older_than_the_retention_are_deleted_and_recent_ones_kept():
    now = datetime.now(timezone.utc)
    db = FakeDb({
        f"tours/{TOUR}/journey_events/old1": _old_event("old1", 40),
        f"tours/{TOUR}/journey_events/old2": _old_event("old2", 31),
        f"tours/{TOUR}/journey_events/fresh": _old_event("fresh", 1),
    })
    stats = run_journey_event_cleanup(db, now)
    assert stats == {"deleted": 2, "errors": 0}
    assert list(db.docs) == [f"tours/{TOUR}/journey_events/fresh"]
    assert JOURNEY_EVENT_RETENTION == timedelta(days=30)


def test_cleanup_works_in_batches_until_nothing_old_is_left():
    now = datetime.now(timezone.utc)
    docs = {f"tours/{TOUR}/journey_events/e{i}": _old_event(i, 60) for i in range(5)}
    db = FakeDb(docs)
    stats = run_journey_event_cleanup(db, now, batch=2, max_batches=10)
    assert stats["deleted"] == 5
    assert db.docs == {}


def test_a_failed_delete_stops_the_run_and_is_counted():
    now = datetime.now(timezone.utc)
    db = FakeDb({f"tours/{TOUR}/journey_events/e{i}": _old_event(i, 60) for i in range(3)})
    db.fail_deletes = True
    stats = run_journey_event_cleanup(db, now, batch=2, max_batches=10)
    assert stats["deleted"] == 0
    assert stats["errors"] >= 1
