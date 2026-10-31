"""Closing an account removes what the person left on the media server and in the chat service."""

import json

import pytest

import main
from chat import chat_db

KEY = "purge-test-key"


@pytest.fixture(autouse=True)
def purge_key(monkeypatch):
    monkeypatch.setattr(main, "PURGE_KEY", KEY)


def save(tour, folder, filename, uploader):
    path = main.MEDIA_ROOT / tour / folder / filename
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"bytes")
    sidecar = main.META_ROOT / tour / folder / f"{filename}.json"
    sidecar.parent.mkdir(parents=True, exist_ok=True)
    sidecar.write_text(json.dumps({"uploaderEmail": uploader, "tourId": tour, "folder": folder}))
    return path


def erase(client, uid, email, key=KEY):
    headers = {"X-Purge-Key": key} if key else {}
    return client.post("/purge/account", json={"uid": uid, "email": email}, headers=headers)


def test_the_files_the_person_uploaded_go_in_every_space_and_others_stay(client):
    alice_tour = save("t1", "posts", "a.jpg", "alice@x.com")
    bob_tour = save("t1", "posts", "b.jpg", "bob@x.com")
    alice_chat = save("chat_uid-alice_uid-bob", "chat_media", "c.jpg", "alice@x.com")
    alice_avatar = save("profiles", "avatars", "d.jpg", "alice@x.com")

    response = erase(client, "uid-alice", "Alice@X.com")

    assert response.status_code == 200
    assert response.json()["files"] == 3
    assert not alice_tour.exists()
    assert not alice_chat.exists()
    assert not alice_avatar.exists()
    assert bob_tour.exists()


def test_repeating_the_call_is_harmless(client):
    save("t1", "posts", "a.jpg", "alice@x.com")
    assert erase(client, "uid-alice", "alice@x.com").json()["files"] == 1
    again = erase(client, "uid-alice", "alice@x.com")
    assert again.status_code == 200
    assert again.json()["files"] == 0


def test_the_purge_key_is_required(client, monkeypatch):
    assert erase(client, "uid-alice", "alice@x.com", key=None).status_code == 401
    assert erase(client, "uid-alice", "alice@x.com", key="guess").status_code == 401
    monkeypatch.setattr(main, "PURGE_KEY", "")
    assert erase(client, "uid-alice", "alice@x.com").status_code == 503


def test_a_uid_and_an_email_are_required(client):
    assert erase(client, "../uid", "alice@x.com").status_code == 400
    assert erase(client, "uid-alice", "not-an-email").status_code == 400


def test_the_chat_service_forgets_the_person_and_keeps_the_others_messages(client):
    chat_id = "acct-x_acct-y"
    chat_db.get_or_create_conversation(chat_id, ["acct-x", "acct-y"], ["x@acct.test", "y@acct.test"])
    for message_id, sender, created_at in [("erase-m1", "acct-x", 1000), ("erase-m2", "acct-y", 2000)]:
        chat_db.save_message({
            "id": message_id,
            "chatId": chat_id,
            "senderId": sender,
            "senderName": sender,
            "text": f"from {sender}",
            "type": "text",
            "createdAt": created_at,
        })
    chat_db.register_device_token("acct-x", "erase-token", device_id="erase-dev", email="x@acct.test")

    response = erase(client, "acct-x", "x@acct.test")

    assert response.status_code == 200
    assert response.json()["chat"]["messages"] == 1
    assert chat_db.get_device_tokens("acct-x") == []
    assert chat_db.participants_of(chat_id) == ["acct-y"]
    assert [m["id"] for m in chat_db.get_messages(chat_id, "acct-y")] == ["erase-m2"]
