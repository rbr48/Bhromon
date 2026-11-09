"""POST /notify/notice/ping: only a tour's owner or admin may remind the waiting members."""

import pytest

import main
from ack_reminders import PingRefused
from conftest import bearer


@pytest.fixture
def ping(client, monkeypatch):
    calls = []
    outcome = {"result": {"waiting": 2, "pushes": 3}}

    def fake_send(db, engine, tour_id, notice_id, now):
        calls.append((tour_id, notice_id))
        if isinstance(outcome["result"], Exception):
            raise outcome["result"]
        return outcome["result"]

    monkeypatch.setattr(main, "send_ack_ping", fake_send)
    monkeypatch.setattr(main.backend, "_client", lambda: object(), raising=False)
    return client, calls, outcome


def _post(client, token, tour="t1", notice="n1"):
    headers = bearer(token) if token else {}
    return client.post(
        "/notify/notice/ping", json={"tourId": tour, "noticeId": notice}, headers=headers
    )


@pytest.mark.parametrize("token", ["tok-owner", "tok-admin"])
def test_an_owner_or_admin_pings_the_waiting_members(ping, token):
    client, calls, _ = ping

    response = _post(client, token)

    assert response.status_code == 200
    assert response.json() == {"waiting": 2, "pushes": 3}
    assert calls == [("t1", "n1")]


@pytest.mark.parametrize("token", ["tok-alice", "tok-eve"])
def test_a_member_or_an_outsider_cannot_ping(ping, token):
    client, calls, _ = ping

    assert _post(client, token).status_code == 403
    assert calls == []


def test_a_ping_without_a_token_is_refused(ping):
    client, calls, _ = ping

    assert _post(client, None).status_code == 401
    assert calls == []


def test_bad_ids_are_refused_before_anything_is_read(ping):
    client, calls, _ = ping

    assert _post(client, "tok-admin", tour="t1/../x").status_code == 400
    assert _post(client, "tok-admin", notice="n 1").status_code == 400
    assert calls == []


@pytest.mark.parametrize(
    "reason, code",
    [("not_found", 404), ("no_answer_needed", 409), ("archived", 409), ("nobody_waiting", 409)],
)
def test_a_refused_ping_says_why(ping, reason, code):
    client, _, outcome = ping
    outcome["result"] = PingRefused(reason)

    response = _post(client, "tok-admin")

    assert response.status_code == code
    assert response.json()["detail"]["reason"] == reason


def test_a_ping_too_soon_says_when_to_try_again(ping):
    client, _, outcome = ping
    outcome["result"] = PingRefused("too_soon", retry_after=600)

    response = _post(client, "tok-admin")

    assert response.status_code == 429
    assert response.headers["Retry-After"] == "600"
    assert response.json()["detail"] == {"reason": "too_soon", "retryAfter": 600}
