"""A message the phone retries is saved once: the repeat gets the first message back."""

import sqlite3

import pytest

import chat
from chat import ChatDatabase


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


def _count(db, chat_id):
    conn = sqlite3.connect(db.db_path)
    try:
        return conn.execute("SELECT COUNT(*) FROM messages WHERE chat_id = ?", (chat_id,)).fetchone()[0]
    finally:
        conn.close()


def _send(client, token, client_message_id=None, text="hi", recipient="uid-bob"):
    body = {"chatId": "chat-1", "recipientId": recipient, "text": text, "senderName": "Alice"}
    if client_message_id is not None:
        body["clientMessageId"] = client_message_id
    return client.post("/api/chat/message", json=body, headers={"Authorization": f"Bearer {token}"})


def test_a_retry_with_the_same_client_id_gets_the_first_message_back(client, pushes, signed_in, fresh_db):
    first = _send(client, "tok-alice", "c-1")
    retry = _send(client, "tok-alice", "c-1")

    assert first.status_code == 200
    assert retry.status_code == 200
    assert retry.json()["duplicate"] is True
    assert retry.json()["message"]["id"] == first.json()["message"]["id"]
    assert retry.json()["message"]["clientMessageId"] == "c-1"


def test_a_retry_is_neither_saved_nor_pushed_again(client, pushes, signed_in, fresh_db):
    _send(client, "tok-alice", "c-2")
    _send(client, "tok-alice", "c-2")

    assert _count(fresh_db, "chat-1") == 1
    assert len(pushes) == 1
    assert pushes[0]["recipient_uid"] == "uid-bob"


def test_the_client_id_is_scoped_to_the_sender(client, pushes, signed_in, fresh_db):
    alice = _send(client, "tok-alice", "same-id", recipient="uid-bob")
    bob = _send(client, "tok-bob", "same-id", recipient="uid-alice")

    assert alice.status_code == 200
    assert bob.status_code == 200

    assert alice.json()["message"]["id"] != bob.json()["message"]["id"]
    assert _count(fresh_db, "chat-1") == 2


def test_sends_without_a_client_id_are_never_treated_as_retries(client, pushes, signed_in, fresh_db):
    first = _send(client, "tok-alice")
    second = _send(client, "tok-alice")

    assert first.json()["message"]["id"] != second.json()["message"]["id"]
    assert "duplicate" not in second.json()
    assert _count(fresh_db, "chat-1") == 2


def test_save_message_once_returns_the_saved_message_for_a_repeat(tmp_path):
    db = ChatDatabase(tmp_path / "chat.db")
    message = {"chatId": "chat-9", "senderId": "uid-alice", "text": "hi", "clientMessageId": "x-1"}

    saved, created = db.save_message_once(dict(message))
    again, created_again = db.save_message_once(dict(message))

    assert created is True
    assert created_again is False
    assert again["id"] == saved["id"]
    assert _count(db, "chat-9") == 1


def test_a_database_from_before_the_client_id_column_is_upgraded(tmp_path):
    path = tmp_path / "old.db"
    conn = sqlite3.connect(path)
    conn.executescript(
        """
        CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            chat_id TEXT NOT NULL,
            sender_id TEXT NOT NULL,
            sender_name TEXT,
            sender_avatar TEXT,
            text TEXT,
            type TEXT DEFAULT 'text',
            media_url TEXT,
            media_path TEXT,
            thumbnail_url TEXT,
            reply_to TEXT,
            reactions TEXT,
            read_by TEXT,
            status TEXT DEFAULT 'sent',
            metadata TEXT,
            created_at INTEGER NOT NULL,
            deleted_for TEXT
        );
        INSERT INTO messages (id, chat_id, sender_id, text, created_at)
            VALUES ('old-1', 'chat-old', 'uid-alice', 'before the upgrade', 1);
        """
    )
    conn.commit()
    conn.close()

    db = ChatDatabase(path)

    columns = {row[1] for row in sqlite3.connect(path).execute("PRAGMA table_info(messages)")}
    assert "client_id" in columns
    assert _count(db, "chat-old") == 1
    saved, created = db.save_message_once(
        {"chatId": "chat-old", "senderId": "uid-alice", "text": "after", "clientMessageId": "n-1"}
    )
    assert created is True
    assert saved["clientMessageId"] == "n-1"
