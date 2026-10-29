"""Tests for call signaling, TURN credentials and the notify routes behind them."""

import base64
import hashlib
import hmac
import time
import uuid
from unittest.mock import MagicMock

import pytest
from starlette.websockets import WebSocketDisconnect

import chat
import main
from chat import CallOfferLimiter, build_ice_servers
from conftest import bearer

TURN_SECRET = "test-turn-secret"


@pytest.fixture
def fake_firebase(monkeypatch):
    """Lets the chat routes sign in with the same fake tokens the REST tests use."""
    uids = {"tok-alice": "uid-alice", "tok-bob": "uid-bob", "tok-eve": "uid-eve"}

    def verify(token):
        if token not in uids:
            raise ValueError("bad token")
        return uids[token]

    monkeypatch.setattr(chat, "verify_firebase_uid", verify)
    monkeypatch.setattr(chat, "call_offer_limiter", CallOfferLimiter())


def _signed_in(client, token):
    """A WebSocket session for `token`. Use it as a context manager."""
    return client.websocket_connect(f"/api/chat/ws?token={token}")


# ── TURN credentials ──────────────────────────────────────────────────────────


def test_ice_servers_need_a_signed_in_user(client, monkeypatch):
    monkeypatch.setenv("SOTTO_TURN_SECRET", TURN_SECRET)
    assert client.get("/api/chat/ice_servers").status_code == 401


def test_ice_servers_fail_closed_without_the_turn_secret(client, monkeypatch, fake_firebase):
    monkeypatch.delenv("SOTTO_TURN_SECRET", raising=False)
    res = client.get("/api/chat/ice_servers", headers=bearer("tok-alice"))
    assert res.status_code == 503
    assert "credential" not in res.text


def test_ice_servers_bind_the_credential_to_the_caller(client, monkeypatch, fake_firebase):
    monkeypatch.setenv("SOTTO_TURN_SECRET", TURN_SECRET)
    res = client.get("/api/chat/ice_servers", headers=bearer("tok-alice"))
    assert res.status_code == 200
    body = res.json()
    turn = next(server for server in body["iceServers"] if "username" in server)

    assert turn["username"] == f"{body['expiresAt']}:uid-alice"
    digest = hmac.new(TURN_SECRET.encode(), turn["username"].encode(), hashlib.sha1).digest()
    assert turn["credential"] == base64.b64encode(digest).decode("ascii")
    assert 3590 <= body["expiresAt"] - int(time.time()) <= 3600
    assert "openrelay" not in res.text
    assert TURN_SECRET not in res.text


def test_build_ice_servers_uses_the_coturn_shared_secret_format():
    body = build_ice_servers("uid-x", "s3cret", now=1_000)

    assert body["expiresAt"] == 1_000 + chat.ICE_CREDENTIAL_TTL_SECONDS
    stun, turn = body["iceServers"]
    assert all(url.startswith("stun:") for url in stun["urls"])
    assert turn["username"] == "4600:uid-x"
    assert all(url.startswith("turn:148.135.137.245:3478") for url in turn["urls"])


# ── Signaling relay ───────────────────────────────────────────────────────────


def test_an_offer_reaches_the_callee_and_is_acked(client, fake_firebase):
    with _signed_in(client, "tok-alice") as alice, _signed_in(client, "tok-bob") as bob:
        assert alice.receive_json()["type"] == "authenticated"
        assert bob.receive_json()["type"] == "authenticated"

        alice.send_json({
            "type": "call_signal",
            "callId": "c1",
            "recipientId": "uid-bob",
            "signalType": "offer",
            "callerId": "uid-eve",  # a claimed sender is ignored; the socket decides
            "payload": {"sdp": "v=0"},
            "isVideo": True,
            "callerName": "Alice",
            "avatarUrl": "http://insecure.example/a.png",
        })

        ring = bob.receive_json()
        assert ring["type"] == "call_signal"
        assert ring["callerId"] == "uid-alice"
        assert ring["signalType"] == "offer"
        assert ring["payload"] == {"sdp": "v=0"}
        assert ring["isVideo"] is True
        assert ring["callerName"] == "Alice"
        assert ring["avatarUrl"] is None  # only https avatars are passed on

        assert alice.receive_json() == {"type": "call_signal_ack", "callId": "c1", "delivered": True}


def test_the_app_can_sign_in_with_its_first_message(client, fake_firebase):
    with client.websocket_connect("/api/chat/ws") as ws:
        ws.send_json({"type": "auth", "token": "tok-alice"})
        assert ws.receive_json() == {"type": "authenticated", "uid": "uid-alice"}


def test_a_socket_that_does_not_sign_in_is_closed(client, fake_firebase):
    with pytest.raises(WebSocketDisconnect):
        with client.websocket_connect("/api/chat/ws") as ws:
            ws.send_json({"type": "auth", "token": "nope"})
            ws.receive_json()


@pytest.mark.parametrize(
    "message",
    [
        {"recipientId": "uid-bob", "signalType": "ring"},
        {"recipientId": "uid-bob", "signalType": ["offer"]},
        {"recipientId": "uid-alice", "signalType": "offer"},
        {"signalType": "offer"},
    ],
)
def test_malformed_signals_are_refused(client, fake_firebase, message):
    with _signed_in(client, "tok-alice") as alice:
        alice.receive_json()
        alice.send_json({"type": "call_signal", "callId": "c1", **message})
        reply = alice.receive_json()
        assert reply["type"] == "call_signal_error"
        assert reply["reason"] == "invalid"
        assert reply["callId"] == "c1"


def test_an_oversized_signal_is_refused(client, fake_firebase):
    with _signed_in(client, "tok-alice") as alice:
        alice.receive_json()
        alice.send_json({
            "type": "call_signal",
            "callId": "c1",
            "recipientId": "uid-bob",
            "signalType": "candidate",
            "payload": {"candidate": "x" * (chat.MAX_CALL_SIGNAL_BYTES + 1)},
        })
        assert alice.receive_json()["reason"] == "too_large"


def test_offers_are_rate_limited_per_caller(client, fake_firebase, monkeypatch):
    monkeypatch.setattr(chat, "call_offer_limiter", CallOfferLimiter(limit=2, window_seconds=600))
    with _signed_in(client, "tok-alice") as alice:
        alice.receive_json()
        replies = []
        for index in range(3):
            alice.send_json({
                "type": "call_signal",
                "callId": f"c{index}",
                "recipientId": "uid-bob",
                "signalType": "offer",
                "payload": {},
            })
            replies.append(alice.receive_json())

    assert [reply["type"] for reply in replies] == ["call_signal_ack", "call_signal_ack", "call_signal_error"]
    assert replies[2]["reason"] == "rate_limited"


def test_an_offer_to_an_offline_callee_is_not_pushed_twice(client, fake_firebase, monkeypatch):
    # The Firestore call document (sendCallPushNotification) rings an offline callee.
    # The relay must not send a second push for the same call.
    push = MagicMock(return_value=1)
    monkeypatch.setattr(chat.push_dispatcher, "send_push_to_uid", push)
    with _signed_in(client, "tok-alice") as alice:
        alice.receive_json()
        alice.send_json({
            "type": "call_signal",
            "callId": "c1",
            "recipientId": "uid-bob",
            "signalType": "offer",
            "payload": {},
        })
        assert alice.receive_json() == {"type": "call_signal_ack", "callId": "c1", "delivered": False}
    push.assert_not_called()


# ── Offer limiter and conversation membership ─────────────────────────────────


def test_the_offer_limiter_forgets_offers_outside_its_window():
    limiter = CallOfferLimiter(limit=2, window_seconds=60)
    assert limiter.allow("u", now=0)
    assert limiter.allow("u", now=10)
    assert not limiter.allow("u", now=20)
    assert limiter.allow("u", now=61)  # the offer at t=0 has aged out
    assert limiter.allow("someone-else", now=20)  # limits are per caller


def test_participants_of_reports_members_or_nothing(tmp_path):
    db = chat.ChatDatabase(tmp_path / "chat.db")
    db.get_or_create_conversation("c1", ["uid-b", "uid-a", "uid-a"])

    assert db.participants_of("c1") == ["uid-a", "uid-b"]
    assert db.participants_of("missing") is None


# ── Notify routes ─────────────────────────────────────────────────────────────


def _conversation(participants):
    chat_id = f"chat-{uuid.uuid4().hex}"
    main.chat_db.get_or_create_conversation(chat_id, participants)
    return chat_id


def test_only_a_member_can_notify_a_chat_as_themselves(client, monkeypatch):
    send = MagicMock(return_value={"status": "success"})
    monkeypatch.setattr(main.notification_engine, "send_chat_notification", send)
    chat_id = _conversation(["uid-alice", "uid-bob"])
    body = {"chatId": chat_id, "senderId": "uid-alice", "text": "hi", "type": "text"}

    assert client.post("/notify/chat", json=body, headers=bearer("tok-alice")).status_code == 200
    assert client.post("/notify/chat", json=body, headers=bearer("tok-eve")).status_code == 403
    impersonated = {**body, "senderId": "uid-bob"}
    assert client.post("/notify/chat", json=impersonated, headers=bearer("tok-alice")).status_code == 403
    unknown = {**body, "chatId": "no-such-chat"}
    assert client.post("/notify/chat", json=unknown, headers=bearer("tok-alice")).status_code == 403
    assert send.call_count == 1


def test_notify_status_is_for_platform_admins_only(client):
    assert client.get("/notify/status").status_code == 401
    assert client.get("/notify/status", headers=bearer("tok-alice")).status_code == 403
    assert client.get("/notify/status", headers=bearer("tok-admin")).status_code == 200


def test_maintenance_is_for_platform_admins_only(client, monkeypatch):
    sweep = MagicMock(return_value={"status": "ok"})
    monkeypatch.setattr(main.notification_engine, "run_retention_sweep", sweep)

    assert client.post("/admin/maintenance", headers=bearer("tok-alice")).status_code == 403
    assert client.post("/admin/maintenance", headers=bearer("tok-admin")).status_code == 200
    assert sweep.call_count == 1


def test_the_legacy_key_is_not_accepted_on_notify_routes(client, monkeypatch):
    monkeypatch.setattr(main, "LEGACY_UPLOAD_KEY", "transition-key")
    res = client.post(
        "/notify/sos",
        json={"tourId": "t1", "alertId": "a1"},
        headers={"X-Upload-Key": "transition-key"},
    )
    assert res.status_code == 401
