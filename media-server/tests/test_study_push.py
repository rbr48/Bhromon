"""Study pushes on the VPS (discussion replies, Phase 2, and materials, Phase 3).

A reply to a discussion question is pushed once, to the member who asked it. A material that waits for approval is
pushed once, to the owners and admins; a material that is shared is pushed once, to the other members. Each push is
recorded, so a restart does not send it again, and nothing written before the watcher started is pushed.
"""

from datetime import timedelta
from types import SimpleNamespace

from notifications import FirestoreNotificationWatcher, NotificationEngine

TOUR = "t1"
BOOK = "b1"
THREAD = "th1"
THREAD_PATH = f"tours/{TOUR}/study_books/{BOOK}/threads/{THREAD}"
REPLY_PATH = f"{THREAD_PATH}/replies/r1"
MATERIAL = f"tours/{TOUR}/study_materials/m1"

# ana owns the group, cy is an admin, ben and dee are members, and zoe has left.
MEMBERS = [
    ("ana@x.com", "owner", "active"),
    ("cy@x.com", "admin", "active"),
    ("ben@x.com", "member", "active"),
    ("dee@x.com", "member", "active"),
    ("zoe@x.com", "member", "left"),
]


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


class FakeQuery:
    """Equality filters over one collection, which is all the membership reads use."""

    def __init__(self, db, name, filters=()):
        self._db = db
        self._name = name
        self._filters = tuple(filters)

    def where(self, field, op, value):
        assert op == "==", op
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


class CapturingEngine(NotificationEngine):
    """Records the pushes instead of sending them."""

    def __init__(self, db):
        super().__init__()
        self._fake_db = db
        self.pushes = []

    def _get_db(self):
        return self._fake_db

    def get_uids_for_emails(self, emails):
        return [f"uid-{email}" for email in emails]

    def get_push_targets_for_uids(self, uids):
        return [(f"tok-{uid}", None, "en") for uid in uids]

    def send_localized(self, targets, make_text, data, high_priority=False):
        for token, _ref, language in targets:
            title, body = make_text(language)
            self.pushes.append({"token": token, "title": title, "body": body, "data": data})
        return len(targets)


class Claims:
    """Stands in for the claim records: the first claim of a key succeeds, a repeat does not."""

    def __init__(self):
        self.keys = set()

    def __call__(self, key):
        if key in self.keys:
            return False
        self.keys.add(key)
        return True


def _memberships():
    return {
        f"memberships/{TOUR}__{email}": {"tourId": TOUR, "email": email, "role": role, "status": status}
        for email, role, status in MEMBERS
    }


def _setup(docs=None):
    engine = CapturingEngine(FakeDb({**_memberships(), **(docs or {})}))
    watcher = FirestoreNotificationWatcher(engine, claim_push=Claims())
    return engine, watcher


def _change(path, data, kind="ADDED"):
    document = SimpleNamespace(reference=SimpleNamespace(path=path), to_dict=lambda: dict(data))
    return SimpleNamespace(type=SimpleNamespace(name=kind), document=document)


def _thread(asker="ana@x.com", title="Why is the sum zero?"):
    return {THREAD_PATH: {"title": title, "createdByEmail": asker}}


def _material(status, **extra):
    data = {"title": "Chapter 3 notes", "bookId": BOOK, "status": status, "createdByEmail": "ben@x.com"}
    data.update(extra)
    return data


def _recipients(engine):
    return sorted(push["token"] for push in engine.pushes)


# Replies (Phase 2).


def test_a_reply_is_pushed_once_to_the_member_who_asked():
    engine, watcher = _setup(_thread())
    reply = _change(REPLY_PATH, {"createdByEmail": "ben@x.com", "createdAt": watcher.started_at})

    watcher.on_study_reply_snapshot(None, [reply], None)
    watcher.on_study_reply_snapshot(None, [reply], None)

    assert _recipients(engine) == ["tok-uid-ana@x.com"]
    push = engine.pushes[0]
    assert push["title"] == "New reply to your question"
    assert push["body"] == "New reply in Why is the sum zero?"
    assert push["data"] == {"action": "study_reply", "tourId": TOUR, "bookId": BOOK, "threadId": THREAD}


def test_a_reply_from_the_member_who_asked_is_not_pushed():
    engine, watcher = _setup(_thread())
    reply = _change(REPLY_PATH, {"createdByEmail": "ana@x.com", "createdAt": watcher.started_at})

    watcher.on_study_reply_snapshot(None, [reply], None)

    assert engine.pushes == []


def test_a_question_whose_member_has_left_is_not_pushed():
    engine, watcher = _setup(_thread(asker="zoe@x.com"))
    reply = _change(REPLY_PATH, {"createdByEmail": "ben@x.com", "createdAt": watcher.started_at})

    watcher.on_study_reply_snapshot(None, [reply], None)

    assert engine.pushes == []


def test_a_reply_outside_a_discussion_is_ignored():
    engine, watcher = _setup(_thread())
    other = _change(f"tours/{TOUR}/chats/c1/replies/r1", {"createdByEmail": "ben@x.com", "createdAt": watcher.started_at})

    watcher.on_study_reply_snapshot(None, [other], None)

    assert engine.pushes == []


def test_an_old_reply_or_one_to_a_missing_question_is_not_pushed():
    engine, watcher = _setup(_thread())
    old = _change(REPLY_PATH, {"createdByEmail": "ben@x.com", "createdAt": watcher.started_at - timedelta(days=1)})
    gone = _change(
        f"tours/{TOUR}/study_books/{BOOK}/threads/gone/replies/r1",
        {"createdByEmail": "ben@x.com", "createdAt": watcher.started_at},
    )

    watcher.on_study_reply_snapshot(None, [old, gone], None)

    assert engine.pushes == []


def test_a_question_with_no_title_is_named_plainly():
    engine, watcher = _setup(_thread(title="   "))
    reply = _change(REPLY_PATH, {"createdByEmail": "ben@x.com", "createdAt": watcher.started_at})

    watcher.on_study_reply_snapshot(None, [reply], None)

    assert engine.pushes[0]["body"] == "New reply in your question"


# Materials (Phase 3).


def test_a_material_waiting_for_approval_is_pushed_once_to_the_admins_but_not_its_uploader():
    engine, watcher = _setup()
    filed = _change(MATERIAL, _material("pending", createdAt=watcher.started_at))

    watcher.on_study_pending_material_snapshot(None, [filed], None)
    watcher.on_study_pending_material_snapshot(None, [filed], None)

    # The owner and the admin. Not ben, who filed it, nor dee, who is a member and cannot approve.
    assert _recipients(engine) == ["tok-uid-ana@x.com", "tok-uid-cy@x.com"]
    assert engine.pushes[0]["title"] == "Study material to review"
    assert engine.pushes[0]["body"] == "Chapter 3 notes is waiting for your approval."
    assert engine.pushes[0]["data"]["action"] == "study_material"


def test_a_material_that_is_not_pending_or_is_old_is_not_offered_for_approval():
    engine, watcher = _setup()
    published = _change(MATERIAL, _material("published", createdAt=watcher.started_at))
    old = _change(MATERIAL, _material("pending", createdAt=watcher.started_at - timedelta(days=1)))

    watcher.on_study_pending_material_snapshot(None, [published, old], None)

    assert engine.pushes == []


def test_a_published_material_is_pushed_once_to_the_other_members_not_its_publisher():
    engine, watcher = _setup()
    published = _material("published", publishedAt=watcher.started_at, publishedByEmail="ana@x.com")
    change = _change(MATERIAL, published, kind="MODIFIED")

    watcher.on_study_published_material_snapshot(None, [change], None)
    watcher.on_study_published_material_snapshot(None, [change], None)

    # ben filed it and dee and cy are members. ana published it, and zoe has left.
    assert _recipients(engine) == ["tok-uid-ben@x.com", "tok-uid-cy@x.com", "tok-uid-dee@x.com"]
    assert engine.pushes[0]["title"] == "New study material"
    assert engine.pushes[0]["body"] == "Chapter 3 notes is now shared with the group."


def test_a_material_an_admin_publishes_at_once_reaches_the_members_but_not_the_admin():
    engine, watcher = _setup()
    filed = _material("published", publishedAt=watcher.started_at, publishedByEmail="cy@x.com", createdByEmail="cy@x.com")

    watcher.on_study_published_material_snapshot(None, [_change(MATERIAL, filed)], None)

    assert _recipients(engine) == ["tok-uid-ana@x.com", "tok-uid-ben@x.com", "tok-uid-dee@x.com"]


def test_a_restored_material_is_not_shared_a_second_time():
    engine, watcher = _setup()
    first = _material("published", publishedAt=watcher.started_at, publishedByEmail="ana@x.com")
    later = _material(
        "published",
        publishedAt=watcher.started_at + timedelta(seconds=5),
        publishedByEmail="ana@x.com",
    )

    watcher.on_study_published_material_snapshot(None, [_change(MATERIAL, first, kind="MODIFIED")], None)
    watcher.on_study_published_material_snapshot(None, [_change(MATERIAL, later, kind="MODIFIED")], None)

    assert len(engine.pushes) == 3  # ben, cy and dee, once each


def test_a_publish_from_before_the_watcher_started_is_not_pushed():
    engine, watcher = _setup()
    old = _material("published", publishedAt=watcher.started_at - timedelta(days=1), publishedByEmail="ana@x.com")

    watcher.on_study_published_material_snapshot(None, [_change(MATERIAL, old, kind="MODIFIED")], None)

    assert engine.pushes == []


def test_an_edit_that_is_not_a_publish_is_not_pushed_and_neither_is_a_hidden_material():
    engine, watcher = _setup()
    renamed = _material(
        "published",
        title="Renamed",
        publishedAt=watcher.started_at - timedelta(days=1),
        publishedByEmail="ana@x.com",
    )
    hidden = _material("hidden", publishedAt=watcher.started_at, publishedByEmail="ana@x.com")
    unstamped = _material("published")  # a publish from an earlier app has no time to judge by

    watcher.on_study_published_material_snapshot(
        None,
        [
            _change(MATERIAL, renamed, kind="MODIFIED"),
            _change(MATERIAL, hidden, kind="MODIFIED"),
            _change(MATERIAL, unstamped, kind="MODIFIED"),
        ],
        None,
    )

    assert engine.pushes == []
