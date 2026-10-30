"""Tests for removing a person's messages from the VPS chat store."""

import json
import os
import sys
import tempfile
from pathlib import Path

import pytest

# chat.py opens its database under MEDIA_META_ROOT as soon as it is imported, so
# point it at a scratch directory first, as the other test modules do.
os.environ.setdefault("MEDIA_META_ROOT", tempfile.mkdtemp(prefix="bhromon-test-meta-"))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import chat  # noqa: E402
import main  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

KEY = "chat-purge-test-key"
LEAVER = "uid_leaver"
LEAVER_EMAIL = "leaver@x.com"
PEER = "uid_friend"
PEER_EMAIL = "friend@x.com"
STRANGER = "uid_stranger"
SHARED = "uid_friend_uid_leaver"
OTHER = "uid_leaver_uid_stranger"
PHOTO_URL = "https://bhromon.fun/media/t1/chat_media/photo.jpg"
PHOTO_PATH = "t1/chat_media/photo.jpg"


@pytest.fixture
def db(tmp_path):
    return chat.ChatDatabase(tmp_path / "chat.db")


def message(db, chat_id, sender, text, created_at, **extra):
    msg = {
        "id": f"{sender}-{created_at}",
        "chatId": chat_id,
        "senderId": sender,
        "text": text,
        "type": "text",
        "createdAt": created_at,
    }
    msg.update(extra)
    return db.save_message(msg)


def seed(db):
    db.get_or_create_conversation(SHARED, [LEAVER, PEER], [LEAVER_EMAIL, PEER_EMAIL])
    message(db, SHARED, LEAVER, "hello", 1000)
    message(db, SHARED, PEER, "hi back", 2000, readBy=[PEER, LEAVER])
    message(
        db,
        SHARED,
        LEAVER,
        "",
        3000,
        type="image",
        mediaUrl=PHOTO_URL,
        mediaPath=PHOTO_PATH,
    )
    # A message sent under the leaver's email, before accounts were keyed by id.
    message(db, SHARED, LEAVER_EMAIL, "old", 500)
    db.set_reaction(SHARED, f"{LEAVER}-1000", PEER, "👍")
    db.set_reaction(SHARED, f"{PEER}-2000", LEAVER, "👍")

    db.get_or_create_conversation(OTHER, [LEAVER, STRANGER], [LEAVER_EMAIL])
    message(db, OTHER, LEAVER, "hi", 1500)


def rows(db, sql, *args):
    return db._get_conn().execute(sql, args).fetchall()


def test_the_leavers_messages_leave_the_shared_chat_and_the_peers_stay(db):
    seed(db)

    removed, refs = db.purge_member_messages({LEAVER, LEAVER_EMAIL}, {PEER, PEER_EMAIL})

    assert removed == 3
    assert sorted(refs) == sorted([PHOTO_URL, PHOTO_PATH])
    left = rows(db, "SELECT id, sender_id, read_by, reactions FROM messages WHERE chat_id = ?", SHARED)
    assert [row["sender_id"] for row in left] == [PEER]
    assert json.loads(left[0]["read_by"]) == [PEER]
    assert json.loads(left[0]["reactions"]) == {}


def test_the_chat_list_shows_the_newest_message_that_is_left(db):
    seed(db)

    db.purge_member_messages({LEAVER, LEAVER_EMAIL}, {PEER, PEER_EMAIL})

    conv = rows(db, "SELECT * FROM conversations WHERE chat_id = ?", SHARED)[0]
    assert conv["last_message"] == "hi back"
    assert conv["last_sender_id"] == PEER
    assert conv["last_message_time"] == 2000
    unread = json.loads(conv["unread_counts"])
    assert LEAVER not in unread
    assert PEER in unread


def test_a_quote_of_the_leavers_message_loses_its_text_and_name(db):
    seed(db)
    message(
        db,
        SHARED,
        PEER,
        "reply",
        4000,
        replyTo={
            "messageId": f"{LEAVER}-1000",
            "senderId": LEAVER,
            "senderName": "Leaver",
            "text": "hello",
            "type": "text",
        },
    )

    db.purge_member_messages({LEAVER, LEAVER_EMAIL}, {PEER, PEER_EMAIL})

    reply = rows(db, "SELECT reply_to FROM messages WHERE id = ?", f"{PEER}-4000")[0]
    quoted = json.loads(reply["reply_to"])
    assert quoted["messageId"] == f"{LEAVER}-1000"
    assert quoted["senderId"] == ""
    assert quoted["text"] == ""
    assert quoted["senderName"] == chat.FORMER_MEMBER_NAME


def test_a_chat_with_someone_outside_the_tour_is_untouched(db):
    seed(db)

    db.purge_member_messages({LEAVER, LEAVER_EMAIL}, {PEER, PEER_EMAIL})

    assert [row["text"] for row in rows(db, "SELECT text FROM messages WHERE chat_id = ?", OTHER)] == ["hi"]
    conv = rows(db, "SELECT last_message FROM conversations WHERE chat_id = ?", OTHER)[0]
    assert conv["last_message"] == "hi"


def test_nobody_named_removes_nothing(db):
    seed(db)

    assert db.purge_member_messages(set(), {PEER}) == (0, [])
    assert len(rows(db, "SELECT id FROM messages WHERE chat_id = ?", SHARED)) == 4


@pytest.fixture
def media(tmp_path, monkeypatch):
    media_root = tmp_path / "media"
    meta_root = tmp_path / "meta"
    media_root.mkdir()
    meta_root.mkdir()
    monkeypatch.setattr(main, "MEDIA_ROOT", media_root)
    monkeypatch.setattr(main, "META_ROOT", meta_root)
    monkeypatch.setattr(main, "PURGE_KEY", KEY)
    monkeypatch.setattr(main, "BASE_URL", "https://bhromon.fun/media")
    return media_root, meta_root


def body(**extra):
    request = {
        "uid": LEAVER,
        "email": LEAVER_EMAIL,
        "peerUids": [PEER],
        "peerEmails": [PEER_EMAIL],
        "mediaUrls": [],
    }
    request.update(extra)
    return request


def test_the_endpoint_needs_the_purge_key(db, media, monkeypatch):
    monkeypatch.setattr(main, "chat_db", db)
    client = TestClient(main.app)

    assert client.post("/purge/chat", json=body()).status_code == 401
    assert client.post("/purge/chat", json=body(), headers={"X-Purge-Key": "guess"}).status_code == 401

    monkeypatch.setattr(main, "PURGE_KEY", "")
    assert client.post("/purge/chat", json=body(), headers={"X-Purge-Key": KEY}).status_code == 503


def test_the_endpoint_needs_someone_to_purge(db, media, monkeypatch):
    monkeypatch.setattr(main, "chat_db", db)
    response = TestClient(main.app).post(
        "/purge/chat",
        json={"peerUids": [PEER]},
        headers={"X-Purge-Key": KEY},
    )
    assert response.status_code == 400


def test_the_endpoint_removes_the_messages_and_the_files_they_used(db, media, monkeypatch):
    media_root, meta_root = media
    monkeypatch.setattr(main, "chat_db", db)
    seed(db)
    (media_root / "t1" / "chat_media").mkdir(parents=True)
    (media_root / "t1" / "chat_media" / "photo.jpg").write_bytes(b"x")
    (meta_root / "t1" / "chat_media").mkdir(parents=True)
    (meta_root / "t1" / "chat_media" / "photo.jpg.json").write_text("{}", encoding="utf-8")

    response = TestClient(main.app).post(
        "/purge/chat",
        json=body(mediaUrls=["https://bhromon.fun/media/t1/chat_media/gone.jpg"]),
        headers={"X-Purge-Key": KEY},
    )

    assert response.status_code == 200
    assert response.json() == {"messages": 3, "files": 1}
    assert not (media_root / "t1" / "chat_media" / "photo.jpg").exists()
    assert not (meta_root / "t1" / "chat_media" / "photo.jpg.json").exists()


@pytest.mark.parametrize(
    "reference",
    [
        "https://bhromon.fun/media/../../etc/passwd",
        "https://bhromon.fun/media/../secret.txt",
        "../secret.txt",
        "https://example.com/t1/chat_media/photo.jpg",
    ],
)
def test_a_reference_outside_the_media_folder_removes_nothing(media, tmp_path, reference):
    media_root, _meta_root = media
    secret = tmp_path / "secret.txt"
    secret.write_text("keep me", encoding="utf-8")

    assert main.remove_media_file(reference) == 0
    assert secret.read_text(encoding="utf-8") == "keep me"
