"""Story cleanup: expired stories go, and only the files nothing else uses."""

from datetime import datetime, timedelta, timezone

import story_cleanup as sc

BASE = "https://bhromon.fun/media"
NOW = datetime(2026, 11, 1, 12, 0, tzinfo=timezone.utc)
OLD = NOW - timedelta(hours=25)
NEW = NOW - timedelta(hours=1)
FILE_A = "a" * 32 + ".jpg"  # A story's own file.
FILE_B = "b" * 32 + ".jpg"  # A post's file, also used by an old story.
FILE_C = "c" * 32 + ".jpg"  # A highlight's cover, also used by an old story.
FILE_D = "d" * 32 + ".jpg"  # A fresh story's file.


def _matches(data, field, op, value):
    actual = data.get(field)
    if op == "==":
        return actual == value
    if op == "<":
        return isinstance(actual, datetime) and actual < value
    if op == "array_contains":
        return isinstance(actual, list) and value in actual
    raise AssertionError(f"unexpected operator {op}")


class FakeQuery:
    def __init__(self, db, match_path, filters=(), limit=None):
        self._db = db
        self._match_path = match_path
        self._filters = tuple(filters)
        self._limit = limit

    def where(self, field, op, value):
        return FakeQuery(self._db, self._match_path, self._filters + ((field, op, value),), self._limit)

    def limit(self, count):
        return FakeQuery(self._db, self._match_path, self._filters, count)

    def stream(self):
        found = []
        for path, data in sorted(self._db.docs.items()):
            if not self._match_path(path):
                continue
            if all(_matches(data, field, op, value) for field, op, value in self._filters):
                found.append(FakeDoc(self._db, path, data))
        return found[: self._limit] if self._limit is not None else found


class FakeRef:
    def __init__(self, db, path):
        self._db = db
        self.path = path
        self.id = path.rsplit("/", 1)[-1]

    @property
    def parent(self):
        return FakeCollectionRef(self._db, self.path.rsplit("/", 1)[0])

    def delete(self):
        self._db.docs.pop(self.path, None)

    def collection(self, name):
        return FakeQuery(self._db, lambda path: path.rsplit("/", 1)[0] == f"{self.path}/{name}")


class FakeCollectionRef:
    def __init__(self, db, path):
        self._db = db
        self.path = path

    @property
    def parent(self):
        return FakeRef(self._db, self.path.rsplit("/", 1)[0])


class FakeCollectionRoot:
    def __init__(self, db, name):
        self._db = db
        self._name = name

    def document(self, doc_id):
        return FakeRef(self._db, f"{self._name}/{doc_id}")


class FakeDoc:
    def __init__(self, db, path, data):
        self.reference = FakeRef(db, path)
        self._data = data

    def to_dict(self):
        return dict(self._data)


class FakeDB:
    def __init__(self, docs):
        self.docs = dict(docs)

    def collection(self, name):
        return FakeCollectionRoot(self, name)

    def collection_group(self, name):
        return FakeQuery(self, lambda path: path.rsplit("/", 2)[-2] == name)


def seeded_db():
    return FakeDB({
        "tours/t1/stories/old": {"createdAt": OLD, "mediaUrl": f"{BASE}/t1/stories/{FILE_A}"},
        "tours/t1/stories/shared": {"createdAt": OLD, "mediaUrl": f"{BASE}/t1/posts/{FILE_B}"},
        "tours/t1/stories/covered": {"createdAt": OLD, "mediaUrl": f"{BASE}/t1/stories/{FILE_C}"},
        "tours/t1/stories/fresh": {"createdAt": NEW, "mediaUrl": f"{BASE}/t1/stories/{FILE_D}"},
        "tours/t1/posts/p1": {"images": [f"{BASE}/t1/posts/{FILE_B}"]},
        "tours/t1/highlights/h1": {"coverUrl": f"{BASE}/t1/stories/{FILE_C}"},
    })


def put_file(media_root, meta_root, folder, name):
    target = media_root / "t1" / folder / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(b"bytes")
    sidecar = meta_root / "t1" / folder / f"{name}.json"
    sidecar.parent.mkdir(parents=True, exist_ok=True)
    sidecar.write_text("{}", encoding="utf-8")


def files_on_disk(tmp_path):
    media = tmp_path / "media"
    return {p.name for p in media.rglob("*") if p.is_file()}


def run(db, tmp_path, *, purge=None, batch=sc.BATCH_SIZE, max_batches=sc.MAX_BATCHES_PER_RUN):
    media_root, meta_root = tmp_path / "media", tmp_path / "meta"
    for folder, name in [("stories", FILE_A), ("posts", FILE_B), ("stories", FILE_C), ("stories", FILE_D)]:
        put_file(media_root, meta_root, folder, name)
    purged = []
    stats = sc.run_story_cleanup(
        db, media_root, meta_root, NOW,
        base_url=BASE,
        purge=purge or purged.extend,
        batch=batch,
        max_batches=max_batches,
    )
    return stats, purged, media_root, meta_root


def test_expired_stories_are_deleted_and_fresh_ones_are_kept(tmp_path):
    db = seeded_db()
    run(db, tmp_path)
    assert "tours/t1/stories/old" not in db.docs
    assert "tours/t1/stories/shared" not in db.docs
    assert "tours/t1/stories/covered" not in db.docs
    assert "tours/t1/stories/fresh" in db.docs


def test_only_the_files_nothing_else_uses_are_removed(tmp_path):
    stats, purged, media_root, meta_root = run(seeded_db(), tmp_path)
    assert stats == {"expired": 3, "files_removed": 1, "files_kept": 2, "errors": 0}
    remaining = files_on_disk(tmp_path)
    assert FILE_A not in remaining  # The story's own file.
    assert FILE_B in remaining  # The post still uses it.
    assert FILE_C in remaining  # The highlight's cover.
    assert FILE_D in remaining  # A fresh story.
    assert not (meta_root / "t1" / "stories" / f"{FILE_A}.json").exists()


def test_the_cdn_copy_is_cleared_only_for_removed_files(tmp_path):
    _, purged, _, _ = run(seeded_db(), tmp_path)
    assert purged == [f"t1/stories/{FILE_A}"]


def test_a_run_handles_no_more_than_its_batch_limit(tmp_path):
    stats, _, _, _ = run(seeded_db(), tmp_path, batch=1, max_batches=1)
    assert stats["expired"] == 1


def test_a_run_goes_on_through_batches_until_none_are_left(tmp_path):
    db = seeded_db()
    stats, _, _, _ = run(db, tmp_path, batch=1)
    assert stats["expired"] == 3
    assert "tours/t1/stories/fresh" in db.docs


def test_a_file_whose_use_cannot_be_checked_is_kept(tmp_path, monkeypatch):
    def unreadable(db, tour_id, url):
        raise RuntimeError("firestore unavailable")

    monkeypatch.setattr(sc, "file_in_use", unreadable)
    stats, _, _, _ = run(seeded_db(), tmp_path)
    assert stats["files_removed"] == 0
    assert stats["files_kept"] == 3
    assert FILE_A in files_on_disk(tmp_path)


def test_a_legacy_or_foreign_url_is_never_touched(tmp_path):
    db = FakeDB({
        "tours/t1/stories/legacy": {
            "createdAt": OLD,
            "mediaUrl": "https://firebasestorage.googleapis.com/v0/b/x/o/tours%2Ft1%2Fa.jpg",
        },
    })
    stats, purged, _, _ = run(db, tmp_path)
    assert stats["files_removed"] == 0
    assert purged == []


def test_crafted_paths_cannot_reach_other_files(tmp_path):
    db = FakeDB({
        "tours/t1/stories/evil": {
            "createdAt": OLD,
            "mediaUrl": f"{BASE}/t1/stories/../../../../etc/passwd",
        },
        "tours/t1/stories/evil2": {
            "createdAt": OLD,
            "mediaUrl": f"{BASE}/t1/stories/..%2F..%2Fsecret.jpg",
        },
    })
    stats, _, _, _ = run(db, tmp_path)
    assert stats["expired"] == 2
    assert stats["files_removed"] == 0
    assert FILE_A in files_on_disk(tmp_path)


def test_a_file_of_another_tour_is_not_removed_by_this_tour_story(tmp_path):
    db = FakeDB({
        "tours/t1/stories/cross": {"createdAt": OLD, "mediaUrl": f"{BASE}/t2/stories/{FILE_A}"},
    })
    stats, _, _, _ = run(db, tmp_path)
    assert stats["files_removed"] == 0


def test_the_cleanup_runs_once_a_day_after_four_in_dhaka_and_retries_a_failure():
    class Clock:
        now = datetime(2026, 10, 31, 21, 59, tzinfo=timezone.utc)  # 03:59 in Dhaka

        def __call__(self):
            return self.now

    clock = Clock()
    calls = []

    def flaky(now):
        calls.append(now)
        if len(calls) == 1:
            raise RuntimeError("firestore unavailable")
        return {"expired": 0, "files_removed": 0, "files_kept": 0, "errors": 0}

    scheduler = sc.StoryCleanupScheduler(flaky, clock=clock)
    assert scheduler.run_if_due() is False  # Too early.
    clock.now = datetime(2026, 10, 31, 22, 0, tzinfo=timezone.utc)  # 04:00 in Dhaka
    assert scheduler.run_if_due() is False  # The run fails.
    clock.now = datetime(2026, 10, 31, 22, 5, tzinfo=timezone.utc)
    assert scheduler.run_if_due() is False  # Still waiting for the retry.
    clock.now = datetime(2026, 10, 31, 22, 11, tzinfo=timezone.utc)
    assert scheduler.run_if_due() is True  # The retry succeeds.
    clock.now = datetime(2026, 10, 31, 23, 0, tzinfo=timezone.utc)
    assert scheduler.run_if_due() is False  # Already ran today.
    assert len(calls) == 2
