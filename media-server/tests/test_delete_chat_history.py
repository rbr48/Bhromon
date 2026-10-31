"""The VPS chat history cleanup: a dry run deletes nothing, --apply deletes, and a cutoff keeps newer chats."""

import sqlite3

import chat
import delete_chat_history


def _seed(path):
    db = chat.ChatDatabase(path)
    db.get_or_create_conversation(chat_id="old_ab", participants=["uid-a", "uid-b"])
    db.get_or_create_conversation(chat_id="old_ac", participants=["uid-a", "uid-c"])
    db.save_message({"chatId": "old_ab", "senderId": "uid-a", "text": "hi", "createdAt": 1000})
    db.save_message({"chatId": "old_ab", "senderId": "uid-b", "text": "hello", "createdAt": 2000})
    db.save_message({"chatId": "old_ac", "senderId": "uid-a", "text": "old", "createdAt": 1500})
    db.get_or_create_conversation(chat_id="new_ab", participants=["uid-a", "uid-b"])
    db.save_message({"chatId": "new_ab", "senderId": "uid-a", "text": "new", "createdAt": 9000})
    return db


def _counts(path):
    conn = sqlite3.connect(path)
    try:
        conversations = conn.execute("SELECT COUNT(*) FROM conversations").fetchone()[0]
        messages = conn.execute("SELECT COUNT(*) FROM messages").fetchone()[0]
        return conversations, messages
    finally:
        conn.close()


def test_a_dry_run_deletes_nothing(tmp_path, capsys):
    path = str(tmp_path / "chat.db")
    _seed(path)

    assert delete_chat_history.main(["--db", path]) == 0

    assert _counts(path) == (3, 4)
    assert "Dry run: 3 conversations and 4 messages" in capsys.readouterr().out


def test_apply_deletes_every_conversation_and_message(tmp_path, capsys):
    path = str(tmp_path / "chat.db")
    _seed(path)

    assert delete_chat_history.main(["--db", path, "--apply"]) == 0

    assert _counts(path) == (0, 0)
    assert "Deleted 3 conversations and 4 messages." in capsys.readouterr().out


def test_a_cutoff_keeps_conversations_created_after_it(tmp_path):
    path = str(tmp_path / "chat.db")
    db = _seed(path)
    # Seeding happens within one millisecond, so give each conversation its own time.
    conn = db._get_conn()
    for chat_id, created_at in [("old_ab", 1000), ("old_ac", 1500), ("new_ab", 9000)]:
        conn.execute("UPDATE conversations SET created_at = ? WHERE chat_id = ?", (created_at, chat_id))
    conn.commit()

    assert delete_chat_history.main(["--db", path, "--apply", "--before-ms", "5000"]) == 0

    conn = sqlite3.connect(path)
    try:
        remaining = [row[0] for row in conn.execute("SELECT chat_id FROM conversations")]
        messages = conn.execute("SELECT chat_id FROM messages").fetchall()
    finally:
        conn.close()
    assert remaining == ["new_ab"]
    assert messages == [("new_ab",)]
