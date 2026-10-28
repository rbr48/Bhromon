"""Tests for Bhromon VPS Chat & Notification Engine."""

import os
import shutil
import tempfile
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from chat import ChatDatabase, ChatWebSocketManager, PushNotificationDispatcher


@pytest.fixture
def temp_db():
    temp_dir = tempfile.mkdtemp()
    db_path = Path(temp_dir) / "test_chat.db"
    db = ChatDatabase(db_path)
    yield db
    shutil.rmtree(temp_dir, ignore_errors=True)


def test_device_tokens(temp_db):
    temp_db.register_device_token("user1", "fcm_token_123", device_id="dev1", email="user1@example.com", platform="android")
    tokens = temp_db.get_device_tokens("user1")
    assert len(tokens) == 1
    assert tokens[0]["token"] == "fcm_token_123"
    assert tokens[0]["platform"] == "android"

    # Update token
    temp_db.register_device_token("user1", "fcm_token_456", device_id="dev1", platform="web")
    tokens = temp_db.get_device_tokens("user1")
    assert len(tokens) == 1
    assert tokens[0]["token"] == "fcm_token_456"
    assert tokens[0]["platform"] == "web"

    # Delete token
    temp_db.delete_device_token("fcm_token_456")
    assert len(temp_db.get_device_tokens("user1")) == 0


def test_conversations_and_messages(temp_db):
    chat_id = "user1_user2"
    conv = temp_db.get_or_create_conversation(chat_id, ["user1", "user2"], ["u1@bhromon.fun", "u2@bhromon.fun"])
    assert conv["chatId"] == chat_id
    assert "user1" in conv["participants"]
    assert "user2" in conv["participants"]

    # Send message from user1
    msg1 = temp_db.save_message({
        "id": "msg_001",
        "chatId": chat_id,
        "senderId": "user1",
        "senderName": "User One",
        "text": "Hello User 2!",
        "type": "text",
        "createdAt": 1000,
    })
    assert msg1["id"] == "msg_001"

    # Verify conversation summary updated
    convs_u2 = temp_db.list_conversations("user2")
    assert len(convs_u2) == 1
    assert convs_u2[0]["lastMessage"] == "Hello User 2!"
    assert convs_u2[0]["unreadCounts"]["user2"] == 1
    assert convs_u2[0]["unreadCounts"]["user1"] == 0

    # User 2 marks messages as read
    updated_ids = temp_db.mark_read(chat_id, "user2")
    assert "msg_001" in updated_ids

    # Unread count should now be 0
    convs_u2 = temp_db.list_conversations("user2")
    assert convs_u2[0]["unreadCounts"]["user2"] == 0

    # Send a reply from user 2
    temp_db.save_message({
        "id": "msg_002",
        "chatId": chat_id,
        "senderId": "user2",
        "senderName": "User Two",
        "text": "Hi User 1, how are you?",
        "type": "text",
        "createdAt": 2000,
    })

    # Fetch messages
    messages = temp_db.get_messages(chat_id, "user1")
    assert len(messages) == 2
    assert messages[0]["id"] == "msg_001"
    assert messages[1]["id"] == "msg_002"


def test_reactions_and_deletion(temp_db):
    chat_id = "uA_uB"
    temp_db.get_or_create_conversation(chat_id, ["uA", "uB"])
    temp_db.save_message({
        "id": "m1",
        "chatId": chat_id,
        "senderId": "uA",
        "text": "Test message",
    })

    # Add reaction
    r = temp_db.set_reaction(chat_id, "m1", "uB", "❤️")
    assert "❤️" in r
    assert "uB" in r["❤️"]

    # Toggle reaction (removes it)
    r2 = temp_db.set_reaction(chat_id, "m1", "uB", "❤️")
    assert "❤️" not in r2

    # Delete for self
    temp_db.delete_message(chat_id, "m1", "uB", for_everyone=False)
    msgs_for_uB = temp_db.get_messages(chat_id, "uB")
    assert len(msgs_for_uB) == 0

    msgs_for_uA = temp_db.get_messages(chat_id, "uA")
    assert len(msgs_for_uA) == 1

    # Delete for everyone by sender
    temp_db.delete_message(chat_id, "m1", "uA", for_everyone=True)
    msgs_for_uA_after = temp_db.get_messages(chat_id, "uA")
    assert len(msgs_for_uA_after) == 0


@pytest.mark.asyncio
async def test_websocket_manager():
    mgr = ChatWebSocketManager()
    mock_ws = AsyncMock()

    await mgr.connect("user1", mock_ws)
    assert mgr.is_online("user1") is True
    assert mgr.is_online("user2") is False

    mgr.disconnect("user1", mock_ws)
    assert mgr.is_online("user1") is False


def test_push_notification_dispatch(temp_db):
    temp_db.register_device_token("target_user", "fcm_test_token_999")
    dispatcher = PushNotificationDispatcher(temp_db)

    with patch("firebase_admin._apps", True), patch("firebase_admin.messaging.send") as mock_send:
        sent = dispatcher.send_push_to_uid(
            recipient_uid="target_user",
            title="Incoming Chat",
            body="Hello there!",
            data={"chatId": "c1"},
        )
        assert sent == 1
        assert mock_send.call_count == 1
