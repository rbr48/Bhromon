import os
import sys
import tempfile
from pathlib import Path

import pytest

# chat.py opens its database under MEDIA_META_ROOT as soon as it is imported, so
# point it at a scratch directory first. Without this, a machine with no /data
# (CI) cannot import the app at all.
os.environ.setdefault("MEDIA_META_ROOT", tempfile.mkdtemp(prefix="bhromon-test-meta-"))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import main  # noqa: E402


class FakeBackend:
    """Stands in for Firebase: tokens map to a uid and email, memberships map to roles."""

    def __init__(self):
        self.tokens = {
            "tok-owner": ("uid-owner", "owner@x.com"),
            "tok-admin": ("uid-admin", "admin@x.com"),
            "tok-alice": ("uid-alice", "alice@x.com"),
            "tok-bob": ("uid-bob", "bob@x.com"),
            "tok-eve": ("uid-eve", "eve@x.com"),
        }
        self.memberships = {
            "t1__owner@x.com": "owner",
            "t1__admin@x.com": "admin",
            "t1__alice@x.com": "member",
            "t1__bob@x.com": "member",
        }
        # Only regionExpert and pioneer are platform admins.
        self.tiers = {"uid-admin": "pioneer", "uid-alice": "explorer"}

    def identity_for_token(self, token):
        if token not in self.tokens:
            raise ValueError("bad token")
        return self.tokens[token]

    def tier_for_uid(self, uid):
        return self.tiers.get(uid)

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
