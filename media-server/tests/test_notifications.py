"""Unit tests for Bhromon VPS Notification Engine & Endpoints."""

from unittest.mock import MagicMock, patch


from notifications import (
    FirestoreNotificationWatcher,
    NotificationEngine,
    _preview_of,
)
import main


def test_preview_of_formatting():
    # Regular text
    assert _preview_of("Hello world") == "Hello world"

    # Truncation
    long_text = "a" * 150
    preview = _preview_of(long_text)
    assert len(preview) == 120
    assert preview.endswith("…")

    # Media fallbacks
    assert _preview_of("", attachments=[{"isVideo": True}]) == "🎬 Video"
    assert _preview_of("", attachments=[{"kind": "video"}]) == "🎬 Video"
    assert _preview_of("", attachments=[{"kind": "image"}]) == "📷 Photo"
    assert _preview_of("", kind="poll") == "📊 Poll"
    assert _preview_of("", kind="expense") == "💸 Expense"
    assert _preview_of("") == "New message"


def test_get_active_tour_members():
    mock_db = MagicMock()
    doc1 = MagicMock()
    doc1.to_dict.return_value = {"email": "alice@x.com", "status": "active"}
    doc2 = MagicMock()
    doc2.to_dict.return_value = {"email": "bob@x.com", "status": "active"}
    doc3 = MagicMock()
    doc3.to_dict.return_value = {"email": "sender@x.com", "status": "active"}

    query_mock = MagicMock()
    query_mock.where.return_value = query_mock
    query_mock.stream.return_value = [doc1, doc2, doc3]
    mock_db.collection.return_value = query_mock

    engine = NotificationEngine(db=mock_db)
    members = engine.get_active_tour_members("t1", except_email="sender@x.com")

    assert set(members) == {"alice@x.com", "bob@x.com"}
    assert "sender@x.com" not in members


def test_get_uids_for_emails():
    mock_auth = MagicMock()
    user1 = MagicMock()
    user1.uid = "uid1"
    user2 = MagicMock()
    user2.uid = "uid2"

    mock_auth.get_users.return_value.users = [user1, user2]

    engine = NotificationEngine(auth_mod=mock_auth)
    uids = engine.get_uids_for_emails(["a@x.com", "b@x.com"])

    assert uids == ["uid1", "uid2"]


def test_get_push_targets_for_uids():
    mock_db = MagicMock()
    user_ref = MagicMock()

    # Subcollection devices
    dev1 = MagicMock()
    dev1.to_dict.return_value = {"token": "fcm_token_1"}
    dev1.reference = MagicMock()
    user_ref.collection.return_value.stream.return_value = [dev1]

    # Legacy token doc
    legacy_doc = MagicMock()
    legacy_doc.exists = True
    legacy_doc.to_dict.return_value = {"token": "fcm_token_2"}
    user_ref.get.return_value = legacy_doc

    mock_db.collection.return_value.document.return_value = user_ref

    engine = NotificationEngine(db=mock_db)
    targets = engine.get_push_targets_for_uids(["uid1"])

    tokens = [t[0] for t in targets]
    assert "fcm_token_1" in tokens
    assert "fcm_token_2" in tokens


def test_send_multicast_with_dead_token_purge():
    mock_messaging = MagicMock()
    mock_resp = MagicMock()
    mock_resp.success_count = 1

    item1 = MagicMock()
    item1.success = True
    item1.exception = None

    item2 = MagicMock()
    item2.success = False
    item2.exception = MagicMock()
    item2.exception.code = "messaging/registration-token-not-registered"

    mock_resp.responses = [item1, item2]
    mock_messaging.send_each_for_multicast.return_value = mock_resp

    engine = NotificationEngine(messaging_mod=mock_messaging)

    ref1 = MagicMock()
    ref2 = MagicMock()
    targets = [("tok1", ref1), ("tok2", ref2)]

    count = engine.send_multicast(
        targets,
        title="Test",
        body="Body",
        data={"action": "test"},
    )

    assert count == 1
    ref2.delete.assert_called_once()
    assert engine.stats["dead_tokens_purged"] == 1


def test_send_sos_alert():
    engine = NotificationEngine()
    engine.tour_allows_sos = MagicMock(return_value=True)
    engine.claim_once = MagicMock(return_value=True)
    engine.get_active_tour_members = MagicMock(return_value=["alice@x.com"])
    engine.get_uids_for_emails = MagicMock(return_value=["uid_alice"])
    engine.get_push_targets_for_uids = MagicMock(return_value=[("tok_alice", MagicMock(), "en")])
    engine.member_display_name = MagicMock(return_value="Leader")
    engine.send_multicast = MagicMock(return_value=1)

    res = engine.send_sos_alert(
        tour_id="t1",
        alert_id="a1",
        sender_email="me@x.com",
        sender_name="Someone else",
    )

    assert res["status"] == "success"
    assert res["devices_sent"] == 1
    assert engine.stats["sos_sent"] == 1
    # The name is the group's name for the sender, not the one passed in.
    title = engine.send_multicast.call_args.args[1]
    assert "Leader" in title
    assert "Someone else" not in title


def test_send_channel_message_notification():
    engine = NotificationEngine()
    engine.get_active_tour_members = MagicMock(return_value=["alice@x.com", "bob@x.com"])
    engine.get_uids_for_emails = MagicMock(return_value=["uid_alice"])
    engine.get_push_targets_for_uids = MagicMock(return_value=[("tok_alice", MagicMock(), "en")])
    engine.send_multicast = MagicMock(return_value=1)

    mock_db = MagicMock()
    mock_db.collection.return_value.document.return_value.collection.return_value.document.return_value.get.return_value.exists = False
    engine._get_db = MagicMock(return_value=mock_db)

    # Alice is mentioned; bob, who is not, hears about the message too.
    res = engine.send_channel_message_notification(
        tour_id="t1",
        channel_id="general",
        message_id="m1",
        sender_email="me@x.com",
        sender_name="Leader",
        text="Hello @alice@x.com",
        mentions=["alice@x.com"],
    )

    assert res["status"] == "success"
    assert res["recipients"] == 2
    engine.get_uids_for_emails.assert_called_with(["alice@x.com", "bob@x.com"])


def test_channel_message_without_mentions_reaches_every_other_member():
    engine = NotificationEngine()
    engine.get_active_tour_members = MagicMock(return_value=["alice@x.com", "bob@x.com"])
    engine.get_uids_for_emails = MagicMock(return_value=["uid_alice", "uid_bob"])
    engine.get_push_targets_for_uids = MagicMock(
        return_value=[("tok_alice", MagicMock(), "en"), ("tok_bob", MagicMock(), "en")]
    )
    engine.send_localized = MagicMock(return_value=2)

    mock_db = MagicMock()
    mock_db.collection.return_value.document.return_value.collection.return_value.document.return_value.get.return_value.exists = False
    engine._get_db = MagicMock(return_value=mock_db)

    res = engine.send_channel_message_notification(
        tour_id="t1",
        channel_id="food",
        message_id="m2",
        sender_email="me@x.com",
        sender_name="Leader",
        text="Lunch is at one",
        mentions=[],
    )

    assert res["status"] == "success"
    assert res["recipients"] == 2
    engine.get_uids_for_emails.assert_called_with(["alice@x.com", "bob@x.com"])
    # Ordinary messages are not high priority; the emergency channel is.
    assert engine.send_localized.call_args.kwargs["high_priority"] is False


def test_send_call_push():
    mock_messaging = MagicMock()
    mock_resp = MagicMock()
    mock_resp.success_count = 1
    mock_resp.responses = [MagicMock(success=True, exception=None)]
    mock_messaging.send_each_for_multicast.return_value = mock_resp

    mock_db = MagicMock()
    profile_doc = MagicMock()
    profile_doc.exists = True
    profile_doc.to_dict.return_value = {"displayName": "Alice Caller"}
    mock_db.collection.return_value.document.return_value.get.return_value = profile_doc

    engine = NotificationEngine(db=mock_db, messaging_mod=mock_messaging)
    engine.get_push_targets_for_uids = MagicMock(return_value=[("tok_bob", MagicMock(), "en")])

    res = engine.send_call_push(
        call_id="c_123",
        caller_id="uid_alice",
        callee_id="uid_bob",
        is_video=True,
    )

    assert res["status"] == "success"
    assert res["devices_sent"] == 1
    assert engine.stats["call_pushes_sent"] == 1

    # Verify data-only payload format for Android background handler
    mock_messaging.send_each_for_multicast.assert_called_once()
    kwargs = mock_messaging.MulticastMessage.call_args[1]
    data = kwargs["data"]
    assert data["action"] == "call"
    assert data["callId"] == "c_123"
    assert data["callerId"] == "uid_alice"
    assert data["callerName"] == "Alice Caller"
    assert data["isVideo"] == "true"
    # Ensure notification is not set (data-only for Android!)
    assert "notification" not in kwargs or kwargs.get("notification") is None


def test_send_call_push_email_resolution():
    mock_messaging = MagicMock()
    mock_resp = MagicMock()
    mock_resp.success_count = 1
    mock_resp.responses = [MagicMock(success=True, exception=None)]
    mock_messaging.send_each_for_multicast.return_value = mock_resp

    mock_db = MagicMock()
    mock_db.collection.return_value.document.return_value.get.return_value.exists = False

    engine = NotificationEngine(db=mock_db, messaging_mod=mock_messaging)
    engine.get_uids_for_emails = MagicMock(return_value=["uid_bob"])
    engine.get_push_targets_for_uids = MagicMock(return_value=[("tok_bob", MagicMock(), "en")])

    res = engine.send_call_push(
        call_id="c_124",
        caller_id="uid_alice",
        callee_id="bob@example.com",
        is_video=False,
    )

    assert res["status"] == "success"
    engine.get_uids_for_emails.assert_called_once_with(["bob@example.com"])
    engine.get_push_targets_for_uids.assert_called_once_with(["uid_bob"])


def test_send_call_ended_push():
    mock_messaging = MagicMock()
    mock_resp = MagicMock()
    mock_resp.success_count = 1
    mock_resp.responses = [MagicMock(success=True, exception=None)]
    mock_messaging.send_each_for_multicast.return_value = mock_resp

    engine = NotificationEngine(messaging_mod=mock_messaging)
    engine.get_push_targets_for_uids = MagicMock(return_value=[("tok_bob", MagicMock(), "en")])

    res = engine.send_call_ended_push(call_id="c_123", callee_id="uid_bob")
    assert res["status"] == "success"
    assert res["devices_sent"] == 1


def test_watcher_call_snapshot():
    engine = NotificationEngine()
    engine.send_call_push = MagicMock(return_value={"status": "success"})
    engine.send_call_ended_push = MagicMock(return_value={"status": "success"})

    watcher = FirestoreNotificationWatcher(engine)

    # Change 1: Call created
    doc1 = MagicMock()
    doc1.id = "call_abc"
    doc1.to_dict.return_value = {
        "status": "calling",
        "callerId": "uid_alice",
        "calleeId": "uid_bob",
        "isVideo": True,
        "callerName": "Alice",
    }
    change1 = MagicMock()
    change1.type.name = "ADDED"
    change1.document = doc1

    watcher.on_call_snapshot(None, [change1], None)
    engine.send_call_push.assert_called_once_with(
        call_id="call_abc",
        caller_id="uid_alice",
        callee_id="uid_bob",
        is_video=True,
        caller_name="Alice",
    )

    # Change 2: Call ended
    doc2 = MagicMock()
    doc2.id = "call_abc"
    doc2.to_dict.return_value = {
        "status": "ended",
        "calleeId": "uid_bob",
    }
    change2 = MagicMock()
    change2.type.name = "MODIFIED"
    change2.document = doc2

    watcher.on_call_snapshot(None, [change2], None)
    engine.send_call_ended_push.assert_called_once_with("call_abc", "uid_bob")


def test_firestore_watcher_deduplication():
    engine = NotificationEngine()
    watcher = FirestoreNotificationWatcher(engine)

    assert not watcher.is_seen("doc_1")
    assert watcher.is_seen("doc_1")


def test_api_health_endpoint(client):
    res = client.get("/health")
    assert res.status_code == 200
    data = res.json()
    assert data["status"] == "ok"
    assert "notifications" in data


def test_api_notify_endpoints(client):
    # Test unauthenticated request
    res = client.post("/notify/sos", json={"tourId": "t1", "alertId": "a1"})
    assert res.status_code == 401

    # Test authenticated request with fake backend
    token_headers = {"Authorization": "Bearer tok-owner"}
    with patch.object(main.notification_engine, "push_own_sos", return_value={"status": "success", "devices_sent": 2}):
        res = client.post(
            "/notify/sos",
            json={"tourId": "t1", "alertId": "a1", "senderName": "Boss"},
            headers=token_headers,
        )
        assert res.status_code == 200
        assert res.json()["status"] == "success"

    # An alert that is not the caller's, or not there, is refused and nothing is pushed.
    with patch.object(main.notification_engine, "push_own_sos", return_value={"status": "refused", "reason": "not_sender"}):
        res = client.post("/notify/sos", json={"tourId": "t1", "alertId": "a1"}, headers=token_headers)
        assert res.status_code == 403

    with patch.object(main.notification_engine, "send_channel_message_notification", return_value={"status": "success"}):
        res = client.post(
            "/notify/channel",
            json={"tourId": "t1", "channelId": "emergency", "messageId": "m1"},
            headers=token_headers,
        )
        assert res.status_code == 200
        assert res.json()["status"] == "success"


def _call_change(call_id, data, kind="MODIFIED"):
    doc = MagicMock()
    doc.id = call_id
    doc.to_dict.return_value = data
    change = MagicMock()
    change.type.name = kind
    change.document = doc
    return change


def test_old_finished_calls_send_no_ring_stop_push():
    # The first snapshot after a start lists earlier calls. Those stopped ringing
    # long ago, so none of them may send a push.
    from datetime import datetime, timedelta, timezone

    engine = NotificationEngine()
    engine.send_call_ended_push = MagicMock(return_value={"status": "success"})
    watcher = FirestoreNotificationWatcher(engine)
    old = datetime.now(timezone.utc) - timedelta(days=30)
    changes = [
        _call_change(f"old_{i}", {"status": status, "calleeId": "uid_bob", "createdAt": old}, "ADDED")
        for i, status in enumerate(["ended", "declined", "missed", "answered"])
    ]
    watcher.on_call_snapshot(None, changes, None)
    engine.send_call_ended_push.assert_not_called()


def test_an_answered_call_stops_the_ring_on_the_callees_other_phones():
    from datetime import datetime, timezone

    engine = NotificationEngine()
    engine.send_call_ended_push = MagicMock(return_value={"status": "success"})
    watcher = FirestoreNotificationWatcher(engine)
    data = {"status": "answered", "calleeId": "uid_bob", "createdAt": datetime.now(timezone.utc)}
    watcher.on_call_snapshot(None, [_call_change("call_x", data)], None)
    # Ending it later sends nothing more: the ring already stopped.
    watcher.on_call_snapshot(None, [_call_change("call_x", {**data, "status": "ended"})], None)
    engine.send_call_ended_push.assert_called_once_with("call_x", "uid_bob")


def test_call_may_still_ring_only_while_it_is_young():
    from datetime import datetime, timedelta, timezone

    from notifications import call_may_still_ring

    now = datetime(2026, 1, 1, tzinfo=timezone.utc)
    assert call_may_still_ring(now - timedelta(seconds=30), now)
    assert not call_may_still_ring(now - timedelta(minutes=10), now)
    # Without a creation time a call is treated as recent, so it is never left ringing.
    assert call_may_still_ring(None, now)
    # A naive time is read as UTC.
    assert call_may_still_ring((now - timedelta(seconds=30)).replace(tzinfo=None), now)


def test_send_localized_splits_devices_by_language():
    engine = NotificationEngine()
    engine.send_multicast = MagicMock(return_value=1)
    targets = [
        ("tok_en", MagicMock(), "en"),
        ("tok_bn", MagicMock(), "bn"),
        ("tok_bn2", MagicMock(), "bn"),
    ]

    sent = engine.send_localized(
        targets,
        lambda lang: (f"title-{lang}", f"body-{lang}"),
        {"action": "chat"},
    )

    assert sent == 2
    calls = {c.args[1]: c.args for c in engine.send_multicast.call_args_list}
    assert calls["title-en"][0] == [("tok_en", targets[0][1])]
    assert [t for t, _ in calls["title-bn"][0]] == ["tok_bn", "tok_bn2"]
    assert calls["title-bn"][2] == "body-bn"


def test_chat_push_is_in_the_recipients_language():
    engine = NotificationEngine()
    engine.get_push_targets_for_uids = MagicMock(
        return_value=[("tok_bn", MagicMock(), "bn")]
    )
    engine.get_language_for_uid = MagicMock(return_value="bn")
    engine.send_multicast = MagicMock(return_value=1)
    mock_db = MagicMock()
    chat_doc = MagicMock()
    chat_doc.exists = True
    chat_doc.to_dict.return_value = {"participants": ["uid_sender", "uid_bn"]}
    profile_doc = MagicMock()
    profile_doc.exists = False
    mock_db.collection.return_value.document.return_value.get.side_effect = [
        chat_doc,
        profile_doc,
    ]
    engine._get_db = MagicMock(return_value=mock_db)

    engine.send_chat_notification(
        chat_id="c1",
        sender_id="uid_sender",
        text="hello",
        message_type="text",
    )

    title = engine.send_multicast.call_args.args[1]
    assert title.endswith("থেকে নতুন বার্তা")


def test_call_alert_is_in_the_callees_language():
    mock_messaging = MagicMock()
    mock_db = MagicMock()
    profile_doc = MagicMock()
    profile_doc.exists = True
    profile_doc.to_dict.return_value = {"displayName": "Rahim"}
    mock_db.collection.return_value.document.return_value.get.return_value = profile_doc
    engine = NotificationEngine(db=mock_db, messaging_mod=mock_messaging)
    engine.get_push_targets_for_uids = MagicMock(
        return_value=[("tok_bn", MagicMock(), "bn")]
    )

    engine.send_call_push(
        call_id="c_bn",
        caller_id="uid_rahim",
        callee_id="uid_bn",
        is_video=False,
        caller_name="Rahim",
    )

    alert = mock_messaging.ApsAlert.call_args.kwargs
    assert alert["title"] == "আসছে ভয়েস কল"
    assert alert["body"] == "Rahim Bhromon-এ আপনাকে কল করছেন..."


def test_send_post_notification():
    engine = NotificationEngine()
    engine.get_active_tour_members = MagicMock(return_value=["user1@test.com", "user2@test.com"])
    engine.get_uids_for_emails = MagicMock(return_value=["u1", "u2"])
    engine.get_push_targets_for_uids = MagicMock(return_value=[("tok1", MagicMock(), "en")])
    engine.send_localized = MagicMock(return_value=1)

    res = engine.send_post_notification(
        tour_id="tour_123",
        post_id="post_456",
        author_email="author@test.com",
        author_name="Shohag",
        caption="Exploring Cox's Bazar",
        is_reel=False,
    )

    assert res["status"] == "success"
    assert res["devices_sent"] == 1
    assert engine.stats["post_pushes_sent"] == 1

    # Deduplication test: sending again returns already_sent
    res_dup = engine.send_post_notification(
        tour_id="tour_123",
        post_id="post_456",
        author_email="author@test.com",
    )
    assert res_dup["status"] == "already_sent"


def test_send_comment_notification():
    engine = NotificationEngine()
    engine.get_uids_for_emails = MagicMock(return_value=["u_author"])
    engine.get_push_targets_for_uids = MagicMock(return_value=[("tok_author", MagicMock(), "bn")])
    engine.send_localized = MagicMock(return_value=1)

    res = engine.send_comment_notification(
        tour_id="tour_123",
        post_id="post_456",
        comment_id="comment_789",
        commenter_email="friend@test.com",
        commenter_name="Rahim",
        text="Great picture!",
        post_author_email="author@test.com",
    )

    assert res["status"] == "success"
    assert res["devices_sent"] == 1
    assert engine.stats["comment_pushes_sent"] == 1


def test_send_reaction_notification():
    engine = NotificationEngine()
    engine.get_uids_for_emails = MagicMock(return_value=["u_author"])
    engine.get_push_targets_for_uids = MagicMock(return_value=[("tok_author", MagicMock(), "en")])
    engine.send_localized = MagicMock(return_value=1)

    res = engine.send_reaction_notification(
        tour_id="tour_123",
        post_id="post_456",
        reactor_email="friend@test.com",
        reactor_name="Karim",
        reaction="like",
        post_author_email="author@test.com",
    )

    assert res["status"] == "success"
    assert res["devices_sent"] == 1
    assert engine.stats["reaction_pushes_sent"] == 1


def test_send_notice_notification():
    engine = NotificationEngine()
    engine.get_active_tour_members = MagicMock(return_value=["member1@test.com"])
    engine.get_uids_for_emails = MagicMock(return_value=["u_m1"])
    engine.get_push_targets_for_uids = MagicMock(return_value=[("tok_m1", MagicMock(), "bn")])
    engine.send_localized = MagicMock(return_value=1)

    res = engine.send_notice_notification(
        tour_id="tour_123",
        notice_id="notice_99",
        author_email="admin@test.com",
        title="Bus Departs at 6 AM",
        body="Please gather at the main gate.",
        priority="high",
    )

    assert res["status"] == "success"
    assert res["devices_sent"] == 1
    assert engine.stats["notice_pushes_sent"] == 1


def test_send_ledger_notification():
    engine = NotificationEngine()
    engine.get_active_tour_members = MagicMock(return_value=["m1@test.com", "m2@test.com"])
    engine.get_uids_for_emails = MagicMock(return_value=["u1", "u2"])
    engine.get_push_targets_for_uids = MagicMock(return_value=[("tok1", MagicMock(), "en")])
    engine.send_localized = MagicMock(return_value=1)

    res = engine.send_ledger_notification(
        tour_id="tour_123",
        expense_id="exp_01",
        added_by_email="payer@test.com",
        payer_name="Shohag",
        title="Lunch at Poushee",
        amount_paisa=250000,
    )

    assert res["status"] == "success"
    assert res["devices_sent"] == 1
    assert engine.stats["ledger_pushes_sent"] == 1


def test_send_bazar_duty_notification():
    engine = NotificationEngine()
    engine.get_uids_for_emails = MagicMock(return_value=["uid_alice", "uid_bob"])
    engine.get_push_targets_for_uids = MagicMock(return_value=[("tok_alice", MagicMock(), "en")])
    engine.send_localized = MagicMock(return_value=1)

    res = engine.send_bazar_duty_notification(
        tour_id="tour_mess",
        date_key="2026-11-09",
        assigned_emails=["alice@test.com", "bob@test.com"],
        note="Fish and vegetables",
        estimated_budget_paisa=50000,
    )

    assert res["status"] == "success"
    assert res["devices_sent"] == 1
    assert res["recipients"] == 2

    # Second call is deduplicated
    res2 = engine.send_bazar_duty_notification(
        tour_id="tour_mess",
        date_key="2026-11-09",
        assigned_emails=["alice@test.com"],
    )
    assert res2["status"] == "already_sent"


def test_send_broadcast_notification():
    engine = NotificationEngine()
    mock_db = MagicMock()
    doc1 = MagicMock()
    doc1.to_dict.return_value = {"token": "tok_global_1"}
    doc1.reference.collection.return_value.stream.return_value = []
    mock_db.collection.return_value.stream.return_value = [doc1]
    engine._get_db = MagicMock(return_value=mock_db)
    engine.send_multicast = MagicMock(return_value=1)

    res = engine.send_broadcast_notification(
        title="Server Maintenance",
        body="App update scheduled at midnight.",
    )

    assert res["status"] == "success"
    assert res["devices_sent"] == 1
    assert engine.stats["broadcast_pushes_sent"] == 1


def test_prune_stale_device_tokens():
    from chat import ChatDatabase
    import tempfile
    import os
    import time

    with tempfile.TemporaryDirectory() as tmpdir:
        db_path = os.path.join(tmpdir, "test_chat.db")
        chat_db = ChatDatabase(db_path)

        # Save an active token and a stale token
        now_ms = int(time.time() * 1000)
        old_ms = now_ms - (200 * 86400 * 1000)  # 200 days old

        conn = chat_db._get_conn()
        with conn:
            conn.execute(
                "INSERT INTO device_tokens (uid, device_id, token, email, platform, language, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                ("u1", "d1", "tok_active", "u1@test.com", "android", "en", now_ms),
            )
            conn.execute(
                "INSERT INTO device_tokens (uid, device_id, token, email, platform, language, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                ("u2", "d2", "tok_stale", "u2@test.com", "android", "en", old_ms),
            )

        assert chat_db.count_device_tokens() == 2

        pruned = chat_db.prune_stale_device_tokens(max_age_days=180)
        assert pruned == 1
        assert chat_db.count_device_tokens() == 1
        chat_db.close()


