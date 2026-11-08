"""Encrypted one-to-one chats on the chat service (E2EE_DESIGN.md, section 7).

An encrypted chat's messages are envelopes. The server stores them without text,
refuses text in them, and says only that a message came in a push.
"""

import base64
import sqlite3
from unittest.mock import MagicMock

import pytest

import chat
from chat import ChatDatabase
from e2ee_chat import (
    MAX_CIPHERTEXT_BYTES,
    EncryptedChats,
    EncryptionStatusUnknown,
    EnvelopeError,
    validate_envelope,
)
from notifications import NotificationEngine
from push_strings import push_text


def envelope(**changes):
    base = {"v": 1, "alg": "olm.v1", "from": "device-a", "to": "device-b", "type": 1, "ct": "AQID"}
    base.update(changes)
    return base


# ── Envelope validation ──────────────────────────────────────────────────────


def test_a_padded_envelope_is_accepted_and_returned_as_stored():
    good = envelope()
    assert validate_envelope(good) == good


def test_an_unpadded_ciphertext_is_accepted():
    assert validate_envelope(envelope(ct="AQI"))["ct"] == "AQI"


def test_the_ciphertext_size_limit_is_inclusive():
    at_limit = base64.urlsafe_b64encode(bytes(MAX_CIPHERTEXT_BYTES)).decode()
    assert validate_envelope(envelope(ct=at_limit))["ct"] == at_limit


def test_a_ciphertext_over_the_limit_is_refused():
    over = base64.urlsafe_b64encode(bytes(MAX_CIPHERTEXT_BYTES + 1)).decode()
    with pytest.raises(EnvelopeError):
        validate_envelope(envelope(ct=over))


@pytest.mark.parametrize(
    "changes",
    [
        {"v": 2},
        {"v": True},
        {"alg": "megolm.v1"},
        {"from": ""},
        {"from": "a b"},
        {"to": "x" * 65},
        {"type": 2},
        {"type": True},
        {"type": "1"},
        {"ct": None},
        {"ct": ""},
        {"ct": "A!B="},
        {"ct": "A"},
        {"ct": "AQID=="},
        {"ct": "AAAA="},
    ],
)
def test_a_malformed_field_is_refused(changes):
    with pytest.raises(EnvelopeError):
        validate_envelope(envelope(**changes))


def test_an_extra_or_missing_field_is_refused():
    with pytest.raises(EnvelopeError):
        validate_envelope({**envelope(), "extra": 1})
    without_ct = {key: value for key, value in envelope().items() if key != "ct"}
    with pytest.raises(EnvelopeError):
        validate_envelope(without_ct)


def test_an_envelope_that_is_not_an_object_is_refused():
    with pytest.raises(EnvelopeError):
        validate_envelope("AQID")


# ── The chat's encryption flag ───────────────────────────────────────────────


def test_the_flag_is_read_once_and_kept():
    reads = []

    def read(chat_id):
        reads.append(chat_id)
        return True

    chats = EncryptedChats(read)
    assert chats.is_encrypted("c1") is True
    assert chats.is_encrypted("c1") is True
    assert reads == ["c1"]


def test_a_missing_chat_is_plaintext_and_is_read_again():
    reads = []

    def read(chat_id):
        reads.append(chat_id)
        return None

    chats = EncryptedChats(read)
    assert chats.is_encrypted("c1") is False
    assert chats.is_encrypted("c1") is False
    assert len(reads) == 2


def test_an_unreadable_flag_is_refused_and_not_kept():
    attempts = []

    def read(chat_id):
        attempts.append(chat_id)
        if len(attempts) == 1:
            raise RuntimeError("firestore unavailable")
        return True

    chats = EncryptedChats(read)
    with pytest.raises(EncryptionStatusUnknown):
        chats.is_encrypted("c1")
    assert chats.is_encrypted("c1") is True
    assert len(attempts) == 2


def test_the_cache_is_bounded():
    reads = []

    def read(chat_id):
        reads.append(chat_id)
        return True

    chats = EncryptedChats(read, max_entries=2)
    for chat_id in ["a", "b", "c"]:
        chats.is_encrypted(chat_id)
    chats.is_encrypted("a")  # the oldest entry was dropped, so it is read again
    assert reads == ["a", "b", "c", "a"]


# ── Storage ──────────────────────────────────────────────────────────────────


@pytest.fixture
def temp_db(tmp_path):
    return ChatDatabase(tmp_path / "chat.db")


def test_an_envelope_is_stored_and_read_back_with_no_text(temp_db):
    temp_db.get_or_create_conversation("c1", ["uid-a", "uid-b"])
    temp_db.save_message({
        "id": "m1",
        "chatId": "c1",
        "senderId": "uid-a",
        "text": "",
        "type": "text",
        "envelope": envelope(),
        "createdAt": 1000,
    })
    [message] = temp_db.get_messages("c1", "uid-b")
    assert message["envelope"] == envelope()
    assert message["text"] == ""


def test_a_plaintext_message_has_no_envelope(temp_db):
    temp_db.get_or_create_conversation("c1", ["uid-a", "uid-b"])
    temp_db.save_message({"id": "m1", "chatId": "c1", "senderId": "uid-a", "text": "hi", "type": "text", "createdAt": 1000})
    [message] = temp_db.get_messages("c1", "uid-b")
    assert message["envelope"] is None
    assert message["text"] == "hi"


# ── The send route ───────────────────────────────────────────────────────────


@pytest.fixture
def pushes(monkeypatch):
    calls = []

    def record(**kwargs):
        calls.append(kwargs)
        return 1

    monkeypatch.setattr(chat.push_dispatcher, "send_push_to_uid", record)
    return calls


@pytest.fixture
def signed_in(monkeypatch):
    uids = {"tok-alice": "uid-alice", "tok-bob": "uid-bob"}

    def verify(token):
        if token not in uids:
            raise ValueError("bad token")
        return uids[token]

    monkeypatch.setattr(chat, "verify_firebase_uid", verify)


@pytest.fixture
def fresh_db(monkeypatch, tmp_path):
    db = ChatDatabase(tmp_path / "chat.db")
    monkeypatch.setattr(chat, "chat_db", db)
    return db


@pytest.fixture
def encrypted_chat(monkeypatch):
    monkeypatch.setattr(chat, "encrypted_chats", EncryptedChats(lambda chat_id: True))


@pytest.fixture
def plaintext_chat(monkeypatch):
    monkeypatch.setattr(chat, "encrypted_chats", EncryptedChats(lambda chat_id: False))


def _send(client, body):
    payload = {"chatId": "chat-1", "recipientId": "uid-bob", "senderName": "Alice", **body}
    return client.post("/api/chat/message", json=payload, headers={"Authorization": "Bearer tok-alice"})


def _stored_rows(db):
    conn = sqlite3.connect(db.db_path)
    try:
        return conn.execute("SELECT text, envelope FROM messages WHERE chat_id = 'chat-1'").fetchall()
    finally:
        conn.close()


def test_an_encrypted_message_is_stored_as_an_envelope_with_no_text(
    client, pushes, signed_in, fresh_db, encrypted_chat
):
    response = _send(client, {"text": "", "envelope": envelope()})

    assert response.status_code == 200
    assert response.json()["message"]["envelope"] == envelope()
    assert _stored_rows(fresh_db) == [("", '{"v": 1, "alg": "olm.v1", "from": "device-a", "to": "device-b", "type": 1, "ct": "AQID"}')]


def test_an_encrypted_message_pushes_only_that_a_message_came(
    client, pushes, signed_in, fresh_db, encrypted_chat
):
    _send(client, {"envelope": envelope()})

    [push] = pushes
    assert push["body"] == push_text(None, "preview.text")
    _, body_bn = push["localize"]("bn")
    assert body_bn == push_text("bn", "preview.text")


@pytest.mark.parametrize(
    "body",
    [
        {"text": "hi", "envelope": envelope()},
        {"envelope": None},
        {"envelope": envelope(v=2)},
        {"envelope": envelope(), "type": "image"},
        {"envelope": envelope(), "mediaUrl": "https://bhromon.fun/media/x.jpg"},
    ],
)
def test_an_encrypted_chat_refuses_text_and_malformed_envelopes(
    client, pushes, signed_in, fresh_db, encrypted_chat, body
):
    response = _send(client, body)

    assert response.status_code == 400
    assert _stored_rows(fresh_db) == []
    assert pushes == []


def test_a_plaintext_chat_refuses_an_envelope(client, pushes, signed_in, fresh_db, plaintext_chat):
    response = _send(client, {"envelope": envelope()})

    assert response.status_code == 400
    assert _stored_rows(fresh_db) == []


def test_a_plaintext_chat_still_takes_text_and_pushes_it(client, pushes, signed_in, fresh_db, plaintext_chat):
    response = _send(client, {"text": "hello"})

    assert response.status_code == 200
    assert _stored_rows(fresh_db) == [("hello", None)]
    assert pushes[0]["body"] == "hello"


def test_a_chat_whose_flag_cannot_be_read_is_refused(client, pushes, signed_in, fresh_db, monkeypatch):
    def unreadable(chat_id):
        raise RuntimeError("firestore unavailable")

    monkeypatch.setattr(chat, "encrypted_chats", EncryptedChats(unreadable))

    response = _send(client, {"text": "hello"})

    assert response.status_code == 503
    assert _stored_rows(fresh_db) == []


# ── The chat notification ────────────────────────────────────────────────────


def test_an_encrypted_chats_notification_never_shows_its_text():
    engine = NotificationEngine()
    engine.get_push_targets_for_uids = MagicMock(return_value=[("tok_en", MagicMock(), "en")])
    engine.get_language_for_uid = MagicMock(return_value="en")
    engine.send_multicast = MagicMock(return_value=1)
    mock_db = MagicMock()
    chat_doc = MagicMock()
    chat_doc.exists = True
    chat_doc.to_dict.return_value = {"participants": ["uid_sender", "uid_bob"]}
    profile_doc = MagicMock()
    profile_doc.exists = False
    mock_db.collection.return_value.document.return_value.get.side_effect = [chat_doc, profile_doc]
    engine._get_db = MagicMock(return_value=mock_db)

    engine.send_chat_notification(
        chat_id="c1",
        sender_id="uid_sender",
        text="a secret",
        message_type="text",
        encrypted=True,
    )

    body = engine.send_multicast.call_args.args[2]
    assert body == push_text("en", "preview.text")
    assert "secret" not in body
