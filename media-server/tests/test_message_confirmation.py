"""A chat message is pushed unless the recipient's app confirms it on screen."""

import asyncio

import pytest

import chat

PUSH = {
    "recipient_uid": "uid-bob",
    "title": "Alice",
    "body": "See you at the bus stop",
    "data": {"action": "chat"},
    "image_url": None,
}


class FakeSocket:
    """Stands in for a WebSocket and records what the server writes to it."""

    def __init__(self):
        self.sent = []

    async def send_text(self, text):
        self.sent.append(text)


@pytest.fixture
def pushes(monkeypatch):
    calls = []

    def record(**kwargs):
        calls.append(kwargs)
        return 1

    monkeypatch.setattr(chat.push_dispatcher, "send_push_to_uid", record)
    return calls


@pytest.fixture
def short_wait(monkeypatch):
    monkeypatch.setattr(chat, "MESSAGE_ACK_SECONDS", 0.05)


@pytest.fixture
def signed_in(monkeypatch):
    uids = {"tok-alice": "uid-alice", "tok-bob": "uid-bob"}

    def verify(token):
        if token not in uids:
            raise ValueError("bad token")
        return uids[token]

    monkeypatch.setattr(chat, "verify_firebase_uid", verify)


@pytest.fixture
def connect():
    """Adds a socket for a user, and removes it after the test."""
    added = []

    def add(uid, socket, confirms=False):
        with chat.ws_manager._lock:
            chat.ws_manager._connections.setdefault(uid, set()).add(socket)
        if confirms:
            chat.ws_manager.mark_confirming(socket)
        added.append((uid, socket))
        return socket

    yield add
    for uid, socket in added:
        chat.ws_manager.disconnect(uid, socket)


def test_a_confirmation_from_the_recipient_cancels_the_push(pushes, short_wait):
    async def run():
        ack = chat.ws_manager.expect_ack("m-1", "uid-bob")
        chat.ws_manager.acknowledge("m-1", "uid-bob")
        await chat._push_unless_confirmed(ack, "m-1", PUSH)

    asyncio.run(run())

    assert pushes == []
    assert "m-1" not in chat.ws_manager._awaiting_ack


def test_without_a_confirmation_the_push_goes_out_after_the_wait(pushes, short_wait):
    async def run():
        ack = chat.ws_manager.expect_ack("m-2", "uid-bob")
        await chat._push_unless_confirmed(ack, "m-2", PUSH)

    asyncio.run(run())

    assert pushes == [PUSH]
    assert "m-2" not in chat.ws_manager._awaiting_ack


def test_only_the_recipient_can_confirm_a_message(pushes, short_wait):
    async def run():
        ack = chat.ws_manager.expect_ack("m-3", "uid-bob")
        chat.ws_manager.acknowledge("m-3", "uid-eve")
        await chat._push_unless_confirmed(ack, "m-3", PUSH)

    asyncio.run(run())

    assert pushes == [PUSH]


def test_a_socket_confirms_only_until_it_disconnects(connect):
    socket = connect("uid-bob", FakeSocket(), confirms=True)
    assert chat.ws_manager.recipient_confirms("uid-bob")

    chat.ws_manager.disconnect("uid-bob", socket)

    assert not chat.ws_manager.recipient_confirms("uid-bob")


def test_a_recipient_with_no_socket_is_pushed_at_once(client, pushes, signed_in):
    response = client.post(
        "/api/chat/message",
        json={"chatId": "chat-1", "recipientId": "uid-bob", "text": "hi", "senderName": "Alice"},
        headers={"Authorization": "Bearer tok-alice"},
    )

    assert response.status_code == 200
    assert len(pushes) == 1
    assert pushes[0]["recipient_uid"] == "uid-bob"


def test_a_socket_that_cannot_confirm_keeps_the_old_behaviour(client, pushes, signed_in, connect):
    socket = connect("uid-bob", FakeSocket())

    response = client.post(
        "/api/chat/message",
        json={"chatId": "chat-1", "recipientId": "uid-bob", "text": "hi", "senderName": "Alice"},
        headers={"Authorization": "Bearer tok-alice"},
    )

    assert response.status_code == 200
    assert pushes == []
    assert len(socket.sent) == 1


def test_a_confirming_recipient_is_not_pushed_once_it_confirms(pushes, short_wait, connect):
    connect("uid-bob", FakeSocket(), confirms=True)
    request = chat.SendMessageRequest(chatId="chat-1", recipientId="uid-bob", text="hi", senderName="Alice")

    async def run():
        result = await chat.send_message(request, uid="uid-alice")
        chat.ws_manager.acknowledge(result["message"]["id"], "uid-bob")
        await asyncio.sleep(0.2)

    asyncio.run(run())

    assert pushes == []


def test_a_confirming_recipient_is_pushed_when_it_stays_silent(pushes, short_wait, connect):
    socket = connect("uid-bob", FakeSocket(), confirms=True)
    request = chat.SendMessageRequest(chatId="chat-1", recipientId="uid-bob", text="hi", senderName="Alice")

    async def run():
        await chat.send_message(request, uid="uid-alice")
        assert pushes == []  # the push waits for the confirmation window
        await asyncio.sleep(0.2)

    asyncio.run(run())

    assert len(pushes) == 1
    assert len(socket.sent) == 1
