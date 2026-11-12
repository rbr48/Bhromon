"""The in-app notification list on the VPS: what is kept, in which language, and how long it is kept."""

import inspect
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import MagicMock

import notifications
from notification_retention import BATCH_SIZE, RETENTION_DAYS, run_notification_retention
from notifications import NotificationEngine


def _engine_with_db():
    engine = NotificationEngine()
    db = MagicMock()
    batch = MagicMock()
    db.batch.return_value = batch
    engine._get_db = MagicMock(return_value=db)
    return engine, db, batch


def test_record_inbox_writes_one_entry_per_member_in_their_own_language():
    engine, db, batch = _engine_with_db()
    engine.get_language_for_uid = MagicMock(side_effect=lambda uid: {"u1": "bn", "u2": "en"}[uid])

    written = engine.record_inbox(
        ["u1", "u2", "u1", ""],
        {"action": "notice", "tourId": "t1", "noticeId": "n1"},
        lambda lang: (f"title-{lang}", "body"),
    )

    assert written == 2
    entries = [call.args[1] for call in batch.set.call_args_list]
    assert [e["title"] for e in entries] == ["title-bn", "title-en"]
    for entry in entries:
        assert entry["action"] == "notice"
        assert entry["tourId"] == "t1"
        assert entry["itemId"] == "n1"
        assert entry["read"] is False
        assert "timestamp" in entry
    batch.commit.assert_called_once()
    assert [c.args[0] for c in db.collection.return_value.document.call_args_list] == ["u1", "u2"]


def test_record_inbox_takes_the_item_from_the_first_key_present():
    engine, _, batch = _engine_with_db()
    engine.get_language_for_uid = MagicMock(return_value="en")

    engine.record_inbox(["u1"], {"action": "problem_set", "tourId": "t1", "subjectId": "s1", "setId": "set9"},
                        lambda lang: ("t", "b"))
    engine.record_inbox(["u1"], {"action": "journey", "tourId": "t1"}, lambda lang: ("t", "b"))

    first, second = [call.args[1] for call in batch.set.call_args_list]
    assert first["itemId"] == "set9"
    assert "itemId" not in second


def test_record_inbox_commits_in_batches_of_the_batch_size():
    engine, _, batch = _engine_with_db()
    engine.get_language_for_uid = MagicMock(return_value="en")
    uids = [f"u{i}" for i in range(BATCH_SIZE * 2 + 50)]

    written = engine.record_inbox(uids, {"action": "ledger", "tourId": "t1"}, lambda lang: ("t", "b"))

    assert written == len(uids)
    assert batch.set.call_count == len(uids)
    assert batch.commit.call_count == 3


def test_record_inbox_never_stops_the_push_when_the_list_cannot_be_written():
    engine = NotificationEngine()
    engine._get_db = MagicMock(side_effect=RuntimeError("no database"))

    assert engine.record_inbox(["u1"], {"action": "sos"}, lambda lang: ("t", "b")) == 0


def test_a_notice_is_kept_for_every_member_even_one_with_no_device():
    engine, _, batch = _engine_with_db()
    engine.is_seen = MagicMock(return_value=False)
    engine.get_active_tour_members = MagicMock(return_value=["a@x.com", "b@x.com"])
    engine.get_uids_for_emails = MagicMock(return_value=["u1", "u2"])
    engine.get_push_targets_for_uids = MagicMock(return_value=[])  # no registered device at all
    engine.send_localized = MagicMock(return_value=0)
    engine.get_language_for_uid = MagicMock(return_value="en")

    result = engine.send_notice_notification("t1", "n1", "author@x.com", title="Meeting", body="Tuesday")

    assert result["status"] == "success"
    entries = [call.args[1] for call in batch.set.call_args_list]
    assert len(entries) == 2
    assert all(e["action"] == "notice" and e["tourId"] == "t1" and e["itemId"] == "n1" for e in entries)


def test_chat_channel_likes_comments_posts_calls_and_broadcasts_are_not_kept_in_the_list():
    # Chat messages are written by the app itself; the rest are chatter, or every member at once.
    for name in (
        "send_chat_notification",
        "send_channel_message_notification",
        "send_post_notification",
        "send_comment_notification",
        "send_reaction_notification",
        "send_call_push",
        "send_call_ended_push",
        "send_broadcast_notification",
    ):
        source = inspect.getsource(getattr(NotificationEngine, name))
        assert "record_inbox" not in source, name


def test_the_daily_retention_run_deletes_entries_older_than_ninety_days():
    db = MagicMock()
    batch = MagicMock()
    db.batch.return_value = batch
    docs = [SimpleNamespace(reference=MagicMock()) for _ in range(3)]
    db.collection_group.return_value.where.return_value.limit.return_value.stream.return_value = docs
    now = datetime(2026, 11, 12, 4, 0, tzinfo=timezone.utc)

    result = run_notification_retention(db, now)

    assert result == {"deleted": 3, "errors": 0}
    db.collection_group.assert_called_once_with("notifications")
    db.collection_group.return_value.where.assert_called_once_with(
        "timestamp", "<", now - timedelta(days=RETENTION_DAYS)
    )
    assert batch.delete.call_count == 3
    batch.commit.assert_called_once()


def test_a_failed_retention_batch_is_counted_and_the_others_still_run():
    db = MagicMock()
    batch = MagicMock()
    db.batch.return_value = batch
    batch.commit.side_effect = [RuntimeError("quota"), None, None]
    refs = [SimpleNamespace(reference=MagicMock()) for _ in range(BATCH_SIZE * 2 + 100)]
    db.collection_group.return_value.where.return_value.limit.return_value.stream.return_value = refs
    now = datetime(2026, 11, 12, 4, 0, tzinfo=timezone.utc)

    result = run_notification_retention(db, now)

    assert result == {"deleted": BATCH_SIZE + 100, "errors": 1}
    assert batch.commit.call_count == 3


def test_the_retention_window_is_the_one_the_app_describes():
    assert RETENTION_DAYS == 90
    assert notifications.INBOX_BATCH_SIZE == BATCH_SIZE
