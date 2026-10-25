import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import main  # noqa: E402


class FakeBackend:
    """Stands in for Firebase: tokens map to emails, memberships map to roles."""

    def __init__(self):
        self.tokens = {
            "tok-owner": "owner@x.com",
            "tok-admin": "admin@x.com",
            "tok-alice": "alice@x.com",
            "tok-bob": "bob@x.com",
            "tok-eve": "eve@x.com",
        }
        self.memberships = {
            "t1__owner@x.com": "owner",
            "t1__admin@x.com": "admin",
            "t1__alice@x.com": "member",
            "t1__bob@x.com": "member",
        }

    def email_for_token(self, token):
        if token not in self.tokens:
            raise ValueError("bad token")
        return self.tokens[token]

    def role_for(self, tour_id, email):
        return self.memberships.get(f"{tour_id}__{email}")


@pytest.fixture
def client(tmp_path, monkeypatch):
    from fastapi.testclient import TestClient

    monkeypatch.setattr(main, "MEDIA_ROOT", tmp_path / "media")
    monkeypatch.setattr(main, "META_ROOT", tmp_path / "meta")
    monkeypatch.setattr(main, "LEGACY_UPLOAD_KEY", "")
    monkeypatch.setattr(main, "backend", FakeBackend())
    return TestClient(main.app)


def bearer(token):
    return {"Authorization": f"Bearer {token}"}
