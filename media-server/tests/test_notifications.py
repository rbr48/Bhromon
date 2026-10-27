"""Unit tests for Bhromon VPS Notification Engine & Endpoints."""

from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

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
    engine.get_active_tour_members = MagicMock(return_value=["alice@x.com"])
    engine.get_uids_for_emails = MagicMock(return_value=["uid_alice"])
    engine.get_push_targets_for_uids = MagicMock(return_value=[("tok_alice", MagicMock())])
    engine.send_multicast = MagicMock(return_value=1)

    res = engine.send_sos_alert(
        tour_id="t1",
        alert_id="a1",
        sender_email="me@x.com",
        sender_name="Leader",
    )

    assert res["status"] == "success"
    assert res["devices_sent"] == 1
    assert engine.stats["sos_sent"] == 1


def test_send_channel_message_notification():
    engine = NotificationEngine()
    engine.get_active_tour_members = MagicMock(return_value=["alice@x.com", "bob@x.com"])
    engine.get_uids_for_emails = MagicMock(return_value=["uid_alice"])
    engine.get_push_targets_for_uids = MagicMock(return_value=[("tok_alice", MagicMock())])
    engine.send_multicast = MagicMock(return_value=1)

    mock_db = MagicMock()
    mock_db.collection.return_value.document.return_value.collection.return_value.document.return_value.get.return_value.exists = False
    engine._get_db = MagicMock(return_value=mock_db)

    # Mentions alice only
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
    assert res["recipients"] == 1


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
    with patch.object(main.notification_engine, "send_sos_alert", return_value={"status": "success", "devices_sent": 2}):
        res = client.post(
            "/notify/sos",
            json={"tourId": "t1", "alertId": "a1", "senderName": "Boss"},
            headers=token_headers,
        )
        assert res.status_code == 200
        assert res.json()["status"] == "success"

    with patch.object(main.notification_engine, "send_channel_message_notification", return_value={"status": "success"}):
        res = client.post(
            "/notify/channel",
            json={"tourId": "t1", "channelId": "emergency", "messageId": "m1"},
            headers=token_headers,
        )
        assert res.status_code == 200
        assert res.json()["status"] == "success"
