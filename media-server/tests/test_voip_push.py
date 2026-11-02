"""Tests for Apple VoIP pushes, which ring a closed iPhone."""

import json
from types import SimpleNamespace

import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

from voip_push import VoipPushSender


@pytest.fixture
def key_file(tmp_path):
    key = ec.generate_private_key(ec.SECP256R1())
    pem = key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    )
    path = tmp_path / "AuthKey.p8"
    path.write_bytes(pem)
    return path, key.public_key()


def _sender(key_path, post, now=1_000_000.0):
    env = {
        "APNS_KEY_PATH": str(key_path),
        "APNS_KEY_ID": "KEY123",
        "APNS_TEAM_ID": "TEAM456",
        "APNS_BUNDLE_ID": "com.example.app",
    }
    return VoipPushSender(env=env, clock=lambda: now, post=post)


def test_nothing_is_sent_without_a_key():
    calls = []
    sender = VoipPushSender(env={}, post=lambda *a, **k: calls.append(a))
    assert sender.send_call("tok", call_id="c1", caller_id="u1", caller_name="A", is_video=False) == "skipped"
    assert calls == []


def test_a_call_is_pushed_to_the_voip_topic_with_a_signed_token(key_file):
    path, public_key = key_file
    sent = {}

    def post(url, headers, content):
        sent.update(url=url, headers=headers, body=json.loads(content))
        return SimpleNamespace(status_code=200, text="")

    result = _sender(path, post).send_call(
        "abcd", call_id="c1", caller_id="u1", caller_name="Alice", is_video=True
    )

    assert result == "sent"
    assert sent["url"] == "https://api.push.apple.com/3/device/abcd"
    assert sent["headers"]["apns-topic"] == "com.example.app.voip"
    assert sent["headers"]["apns-push-type"] == "voip"
    assert sent["headers"]["apns-priority"] == "10"
    token = sent["headers"]["authorization"].split(" ", 1)[1]
    claims = jwt.decode(token, public_key, algorithms=["ES256"])
    assert claims["iss"] == "TEAM456"
    assert jwt.get_unverified_header(token)["kid"] == "KEY123"
    assert sent["body"]["id"] == "c1"
    assert sent["body"]["nameCaller"] == "Alice"
    assert sent["body"]["extra"] == {"callId": "c1", "callerId": "u1", "callerName": "Alice", "isVideo": True}


def test_the_provider_token_is_reused_within_its_lifetime(key_file):
    path, _ = key_file
    tokens = []

    def post(url, headers, content):
        tokens.append(headers["authorization"])
        return SimpleNamespace(status_code=200, text="")

    sender = _sender(path, post)
    sender.send_call("a", call_id="c1", caller_id="u1", caller_name="A", is_video=False)
    sender.send_call("b", call_id="c2", caller_id="u1", caller_name="A", is_video=False)
    assert tokens[0] == tokens[1]


@pytest.mark.parametrize(
    "status, text, expected",
    [(410, "", "dead"), (400, '{"reason":"BadDeviceToken"}', "dead"), (500, "", "failed")],
)
def test_refusals_are_reported(key_file, status, text, expected):
    path, _ = key_file
    sender = _sender(path, lambda url, headers, content: SimpleNamespace(status_code=status, text=text))
    assert sender.send_call("a", call_id="c1", caller_id="u1", caller_name="A", is_video=False) == expected


def test_a_network_error_is_a_failure(key_file):
    path, _ = key_file

    def post(url, headers, content):
        raise OSError("unreachable")

    assert _sender(path, post).send_call("a", call_id="c1", caller_id="u1", caller_name="A", is_video=False) == "failed"
