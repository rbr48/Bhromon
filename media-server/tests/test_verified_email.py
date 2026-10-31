"""Only a verified address counts. Anyone can register an address they do not own, so an
unverified one must not open a person's tours or their chats."""

import pytest
from firebase_admin import auth as firebase_auth

import main


class Account:
    def __init__(self, email, verified):
        self.email = email
        self.email_verified = verified


@pytest.fixture
def firebase(monkeypatch):
    """The real FirebaseBackend, with the Admin SDK answered by the test."""
    backend = main.FirebaseBackend()
    monkeypatch.setattr(backend, "_ensure_app", lambda: None)
    accounts = {}

    def get_user(uid):
        if uid not in accounts:
            raise ValueError(f"no account for {uid}")
        return accounts[uid]

    monkeypatch.setattr(firebase_auth, "get_user", get_user)
    return backend, accounts


def present_token(monkeypatch, claims):
    monkeypatch.setattr(
        firebase_auth,
        "verify_id_token",
        lambda token, clock_skew_seconds: dict(claims),
    )


def test_a_verified_address_on_the_token_is_used(firebase, monkeypatch):
    backend, _ = firebase
    present_token(monkeypatch, {"uid": "u1", "email": "Ann@X.com", "email_verified": True})
    assert backend.identity_for_token("token") == ("u1", "ann@x.com")


def test_an_unverified_address_is_refused(firebase, monkeypatch):
    backend, accounts = firebase
    present_token(monkeypatch, {"uid": "u1", "email": "ann@x.com", "email_verified": False})
    accounts["u1"] = Account("ann@x.com", verified=False)
    with pytest.raises(ValueError):
        backend.identity_for_token("token")


def test_a_token_older_than_its_account_is_checked_against_the_account(firebase, monkeypatch):
    backend, accounts = firebase
    present_token(monkeypatch, {"uid": "u1", "email": "ann@x.com", "email_verified": False})
    accounts["u1"] = Account("ann@x.com", verified=True)
    assert backend.identity_for_token("token") == ("u1", "ann@x.com")


def test_an_unverified_account_gives_no_email_for_sharing(firebase):
    backend, accounts = firebase
    accounts["u2"] = Account("bob@x.com", verified=False)
    assert backend.email_for_uid("u2") == ""
    # Nothing is remembered, so an address verified a moment later counts at once.
    accounts["u2"].email_verified = True
    assert backend.email_for_uid("u2") == "bob@x.com"
