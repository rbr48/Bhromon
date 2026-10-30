"""People reach each other through the chat service only inside a tour they share."""

import pytest

import chat
from chat import chat_db
from conftest import bearer


@pytest.fixture
def signed_in(monkeypatch):
    uids = {"tok-alice": "uid-alice", "tok-bob": "uid-bob", "tok-eve": "uid-eve"}

    def verify(token):
        if token not in uids:
            raise ValueError("bad token")
        return uids[token]

    monkeypatch.setattr(chat, "verify_firebase_uid", verify)


@pytest.fixture
def pushes(monkeypatch):
    sent = []

    def record(**kwargs):
        sent.append(kwargs)
        return 1

    monkeypatch.setattr(chat.push_dispatcher, "send_push_to_uid", record)
    return sent


def message(recipient):
    return {"chatId": f"uid-alice_{recipient}", "recipientId": recipient, "text": "Bus at six"}


def test_a_member_of_the_same_tour_is_messaged(client, signed_in, pushes):
    response = client.post("/api/chat/message", json=message("uid-bob"), headers=bearer("tok-alice"))
    assert response.status_code == 200
    assert len(pushes) == 1


def test_someone_in_no_shared_tour_is_refused_and_not_pushed(client, signed_in, pushes):
    response = client.post("/api/chat/message", json=message("uid-eve"), headers=bearer("tok-alice"))
    assert response.status_code == 403
    assert pushes == []
    assert chat_db.participants_of("uid-alice_uid-eve") is None


def test_online_status_says_nothing_about_someone_outside_the_tour(client, signed_in, monkeypatch):
    monkeypatch.setattr(chat.ws_manager, "is_online", lambda uid: True)
    outsider = client.get("/api/chat/online_status/uid-eve", headers=bearer("tok-alice")).json()
    member = client.get("/api/chat/online_status/uid-bob", headers=bearer("tok-alice")).json()
    assert outsider["isOnline"] is False
    assert member["isOnline"] is True


def test_a_call_to_someone_outside_the_tour_is_refused(client, signed_in):
    with client.websocket_connect("/api/chat/ws?token=tok-alice") as alice:
        assert alice.receive_json()["type"] == "authenticated"
        alice.send_json({
            "type": "call_signal",
            "callId": "c9",
            "recipientId": "uid-eve",
            "signalType": "offer",
            "payload": {"sdp": "v=0"},
        })
        reply = alice.receive_json()
    assert reply == {"type": "call_signal_error", "callId": "c9", "signalType": "offer", "reason": "not_in_group"}


def test_the_ai_guide_can_always_be_messaged(client, signed_in, pushes):
    # The Guide is an assistant, not a person, so no shared tour is needed.
    response = client.post("/api/chat/message", json=message("bhromon_ai_advisor"), headers=bearer("tok-eve"))
    assert response.status_code == 200


def test_history_with_someone_outside_the_tour_is_closed(client, signed_in):
    chat_db.get_or_create_conversation(chat_id="uid-alice_uid-eve", participants=["uid-alice", "uid-eve"])
    response = client.get("/api/chat/messages/uid-alice_uid-eve", headers=bearer("tok-alice"))
    assert response.status_code == 403


def test_the_conversation_list_leaves_out_people_outside_the_tour(client, signed_in):
    chat_db.get_or_create_conversation(chat_id="uid-alice_uid-eve", participants=["uid-alice", "uid-eve"])
    chat_db.get_or_create_conversation(chat_id="uid-alice_uid-bob", participants=["uid-alice", "uid-bob"])
    response = client.get("/api/chat/conversations", headers=bearer("tok-alice"))
    ids = [conversation["chatId"] for conversation in response.json()["conversations"]]
    assert "uid-alice_uid-bob" in ids
    assert "uid-alice_uid-eve" not in ids
