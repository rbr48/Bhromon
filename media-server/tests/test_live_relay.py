"""The live journey relay (roadmap LJ-4.4): positions reach the other sharing
members of the same tour, a member is limited to one position every five seconds,
a silent member is disconnected after two minutes, and only signed-in members of
the tour get in."""

import asyncio
import json

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

import live
from live import LiveRelay, clean_reading


class FakeClock:
    def __init__(self):
        self.now = 1000.0

    def __call__(self):
        return self.now


class Sink:
    """What one member's socket receives, and how it was closed."""

    def __init__(self):
        self.inbox = []
        self.closed = None

    async def send(self, message):
        self.inbox.append(message)

    async def close(self, code, reason):
        self.closed = (code, reason)


def _join(relay, tour, uid):
    sink = Sink()
    member, replaced = relay.join(tour, uid, send=sink.send, close=sink.close)
    return member, sink


def _pos(lat=23.0, lng=90.5):
    return {"t": "pos", "lat": lat, "lng": lng, "acc": 5, "spd": 12, "ts": 1_700_000_000_000}


def test_clean_reading_keeps_a_plausible_fix_and_refuses_the_rest():
    fix = clean_reading({"lat": 23.7, "lng": 90.4, "acc": 8, "spd": 3, "ts": 5})
    assert fix == {"lat": 23.7, "lng": 90.4, "acc": 8.0, "spd": 3.0, "ts": 5}

    assert clean_reading({"lat": 100, "lng": 90}) is None
    assert clean_reading({"lat": 23, "lng": 181}) is None
    assert clean_reading({"lat": "23", "lng": 90}) is None
    assert clean_reading({"lat": True, "lng": 90}) is None
    assert clean_reading({"lat": float("nan"), "lng": 90}) is None
    assert clean_reading({"lng": 90}) is None
    # Out-of-range optional values are dropped, not the whole fix.
    kept = clean_reading({"lat": 23, "lng": 90, "acc": -4, "spd": 900})
    assert kept["acc"] is None and kept["spd"] is None


def test_positions_reach_the_other_sharing_members_of_the_same_tour_only():
    clock = FakeClock()
    relay = LiveRelay(clock=clock)
    alice, alice_sink = _join(relay, "t1", "alice")
    _, bob_sink = _join(relay, "t1", "bob")
    _, carol_sink = _join(relay, "t2", "carol")

    outcome = asyncio.run(relay.accept_position(alice, _pos()))

    assert outcome == "ok"
    assert bob_sink.inbox == [{"t": "pos", "uid": "alice", "lat": 23.0, "lng": 90.5,
                                "acc": 5.0, "spd": 12.0, "ts": 1_700_000_000_000}]
    assert alice_sink.inbox == [], "a member does not hear their own position"
    assert carol_sink.inbox == [], "another tour does not hear it"


def test_a_member_who_is_not_sharing_neither_sends_nor_hears():
    clock = FakeClock()
    relay = LiveRelay(clock=clock)
    alice, alice_sink = _join(relay, "t1", "alice")
    bob, bob_sink = _join(relay, "t1", "bob")
    relay.set_sharing(bob, False)

    assert asyncio.run(relay.accept_position(alice, _pos())) == "ok"
    assert bob_sink.inbox == [], "a member not sharing does not receive positions"

    assert asyncio.run(relay.accept_position(bob, _pos())) == "not_sharing"
    assert alice_sink.inbox == []


def test_one_position_per_interval_is_passed_on():
    clock = FakeClock()
    relay = LiveRelay(clock=clock)
    alice, _ = _join(relay, "t1", "alice")
    _, bob_sink = _join(relay, "t1", "bob")

    assert asyncio.run(relay.accept_position(alice, _pos())) == "ok"
    clock.now += MIN_INTERVAL - 1
    assert asyncio.run(relay.accept_position(alice, _pos())) == "rate"
    clock.now += 1
    assert asyncio.run(relay.accept_position(alice, _pos())) == "ok"
    assert len(bob_sink.inbox) == 2


def test_a_silent_member_is_disconnected_and_the_others_are_told():
    clock = FakeClock()
    relay = LiveRelay(clock=clock)
    alice, alice_sink = _join(relay, "t1", "alice")
    _, bob_sink = _join(relay, "t1", "bob")

    clock.now += live.STALE_AFTER_S + 1
    relay.touch(alice)  # alice is still here; bob is silent
    stale = asyncio.run(relay.sweep())

    assert [m.uid for m in stale] == ["bob"]
    assert alice_sink.inbox == [{"t": "left", "uid": "bob"}]
    assert relay.members("t1") == ["alice"]


def test_a_member_is_kept_while_it_keeps_sending_heartbeats():
    clock = FakeClock()
    relay = LiveRelay(clock=clock)
    alice, _ = _join(relay, "t1", "alice")
    for _ in range(4):
        clock.now += live.STALE_AFTER_S / 2
        relay.touch(alice)
    assert asyncio.run(relay.sweep()) == []
    assert relay.members("t1") == ["alice"]


def test_leaving_tells_the_others_once_and_a_replaced_connection_leaves_quietly():
    clock = FakeClock()
    relay = LiveRelay(clock=clock)
    alice, _ = _join(relay, "t1", "alice")
    _, bob_sink = _join(relay, "t1", "bob")

    replacement, replaced = relay.join("t1", "alice", send=Sink().send, close=Sink().close)
    assert replaced is alice
    assert relay.leave(alice) == [], "the replaced connection is no longer a member"
    assert relay.members("t1") == ["alice", "bob"]

    others = relay.leave(replacement)
    assert [m.uid for m in others] == ["bob"]
    assert relay.leave(replacement) == [], "a member leaves only once"
    assert bob_sink.inbox == []


def test_a_full_tour_refuses_new_members(monkeypatch):
    monkeypatch.setattr(live, "MAX_MEMBERS_PER_TOUR", 2)
    relay = LiveRelay(clock=FakeClock())
    _join(relay, "t1", "a")
    _join(relay, "t1", "b")
    member, replaced = relay.join("t1", "c", send=Sink().send, close=Sink().close)
    assert member is None and replaced is None
    # A member who is already in can still reconnect on another phone.
    member, replaced = relay.join("t1", "a", send=Sink().send, close=Sink().close)
    assert member is not None and replaced is not None


MIN_INTERVAL = live.MIN_SEND_INTERVAL_S


# The socket itself, through the same route the app uses.


@pytest.fixture
def client(monkeypatch):
    relay = LiveRelay(clock=FakeClock())
    monkeypatch.setattr(live, "RELAY", relay)
    monkeypatch.setattr(live, "_identify", lambda token: ("uid-" + token, token + "@x.com"))
    monkeypatch.setattr(live, "_is_member", lambda tour, email: email == "member@x.com")
    app = FastAPI()
    app.include_router(live.router, prefix="/api")
    return TestClient(app)


def test_a_signed_in_member_of_the_tour_is_connected(client):
    with client.websocket_connect("/api/live/ws?tour=t1") as ws:
        ws.send_text(json.dumps({"t": "auth", "token": "member"}))
        assert ws.receive_json() == {"t": "ready"}


def test_a_tour_id_is_required(client):
    with client.websocket_connect("/api/live/ws?tour=") as ws:
        assert ws.receive_json() == {"t": "err", "code": "bad"}


def test_the_first_message_must_carry_a_token(client):
    with client.websocket_connect("/api/live/ws?tour=t1") as ws:
        ws.send_text(json.dumps({"t": "hello"}))
        assert ws.receive_json() == {"t": "err", "code": "auth"}


def test_a_token_that_does_not_verify_is_refused(client, monkeypatch):
    def reject(token):
        raise ValueError("expired")

    monkeypatch.setattr(live, "_identify", reject)
    with client.websocket_connect("/api/live/ws?tour=t1") as ws:
        ws.send_text(json.dumps({"t": "auth", "token": "old"}))
        assert ws.receive_json() == {"t": "err", "code": "auth"}


def test_someone_outside_the_tour_is_refused(client):
    with client.websocket_connect("/api/live/ws?tour=t1") as ws:
        ws.send_text(json.dumps({"t": "auth", "token": "stranger"}))
        assert ws.receive_json() == {"t": "err", "code": "forbidden"}


def test_a_failed_membership_lookup_is_retryable_not_a_refusal(client, monkeypatch):
    def broken(tour, email):
        raise RuntimeError("firestore unavailable")

    monkeypatch.setattr(live, "_is_member", broken)
    with client.websocket_connect("/api/live/ws?tour=t1") as ws:
        ws.send_text(json.dumps({"t": "auth", "token": "member"}))
        assert ws.receive_json() == {"t": "err", "code": "unavailable"}


def test_the_relay_keeps_nothing_on_disk(client, tmp_path, monkeypatch):
    # Positions stay in memory. The module writes no file.
    monkeypatch.chdir(tmp_path)
    with client.websocket_connect("/api/live/ws?tour=t1") as ws:
        ws.send_text(json.dumps({"t": "auth", "token": "member"}))
        assert ws.receive_json() == {"t": "ready"}
        ws.send_text(json.dumps(_pos()))
    assert list(tmp_path.iterdir()) == []
