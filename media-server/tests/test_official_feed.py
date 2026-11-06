"""The official feed: the team publishes, and anyone signed in may read it."""

import io
from unittest.mock import MagicMock

import pytest

import main
from notifications import NotificationEngine


class FakeFirestore:
    """Records what is written to each document, as collection/document paths."""

    def __init__(self):
        self.writes = {}
        self._collection = None
        self._document = None

    def collection(self, name):
        self._collection = name
        return self

    def document(self, doc_id):
        self._document = doc_id
        return self

    def set(self, data):
        self.writes[(self._collection, self._document)] = data


def _part(name, content_type, size=2048, field="file"):
    return (field, (name, io.BytesIO(b"\x00" * size), content_type))


@pytest.fixture
def published(client, monkeypatch):
    firestore = FakeFirestore()
    monkeypatch.setattr(main.backend, "_client", lambda: firestore, raising=False)
    pushes = []

    def fake_push(topic, title, body, data):
        pushes.append((topic, title, body, data))
        return {"status": "success"}

    monkeypatch.setattr(main.notification_engine, "send_topic_push", fake_push)
    monkeypatch.setattr(main, "OFFICIAL_PUBLISH_KEY", "the-publish-key")
    return client, firestore, pushes


def test_the_publish_key_publishes_a_reel(published):
    client, firestore, pushes = published

    response = client.post(
        "/official/posts",
        files=[_part("reel.mp4", "video/mp4")],
        data={"caption": "  Welcome to Bhromon  ", "durationSeconds": "42"},
        headers={"X-Official-Key": "the-publish-key"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["videoUrl"] == f"https://bhromon.fun/media/official/reels/{body['id']}.mp4"
    stored = main.MEDIA_ROOT / "official" / "reels" / f"{body['id']}.mp4"
    assert stored.read_bytes() == b"\x00" * 2048
    entry = firestore.writes[("official_instafeed", body["id"])]
    assert entry["caption"] == "Welcome to Bhromon"
    assert entry["durationSeconds"] == 42
    assert entry["coverUrl"] is None
    assert entry["kind"] == "reel"
    assert pushes == [
        ("official_instafeed", "Bhromon", "Welcome to Bhromon", {"action": "official", "postId": body["id"]}),
    ]


def test_a_cover_is_stored_beside_the_reel(published):
    client, firestore, _pushes = published

    response = client.post(
        "/official/posts",
        files=[_part("reel.mp4", "video/mp4"), _part("cover.jpg", "image/jpeg", size=512, field="cover")],
        headers={"X-Official-Key": "the-publish-key"},
    )

    assert response.status_code == 200
    post_id = response.json()["id"]
    assert response.json()["coverUrl"] == f"https://bhromon.fun/media/official/covers/{post_id}.jpg"
    assert (main.MEDIA_ROOT / "official" / "covers" / f"{post_id}.jpg").exists()
    assert firestore.writes[("official_instafeed", post_id)]["coverUrl"] is not None


def test_nobody_without_the_key_or_an_admin_token_may_publish(published):
    client, firestore, pushes = published

    no_credentials = client.post("/official/posts", files=[_part("reel.mp4", "video/mp4")])
    ordinary_member = client.post(
        "/official/posts",
        files=[_part("reel.mp4", "video/mp4")],
        headers={"Authorization": "Bearer tok-alice"},
    )
    wrong_key = client.post(
        "/official/posts",
        files=[_part("reel.mp4", "video/mp4")],
        headers={"X-Official-Key": "guessed"},
    )

    assert no_credentials.status_code == 401
    assert ordinary_member.status_code == 403
    assert wrong_key.status_code == 401
    assert firestore.writes == {}
    assert pushes == []


def test_a_platform_admin_may_publish_with_a_token(published):
    client, firestore, _pushes = published

    response = client.post(
        "/official/posts",
        files=[_part("reel.mp4", "video/mp4")],
        headers={"Authorization": "Bearer tok-admin"},
    )

    assert response.status_code == 200
    assert ("official_instafeed", response.json()["id"]) in firestore.writes


def test_unsupported_file_types_are_refused(published):
    client, firestore, _pushes = published

    response = client.post(
        "/official/posts",
        files=[_part("notes.pdf", "application/pdf")],
        headers={"X-Official-Key": "the-publish-key"},
    )

    assert response.status_code == 400
    assert firestore.writes == {}


def test_an_image_is_published_as_an_image_post(published):
    client, firestore, pushes = published

    response = client.post(
        "/official/posts",
        files=[_part("photo.jpg", "image/jpeg")],
        data={"caption": "Official Photo"},
        headers={"X-Official-Key": "the-publish-key"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["imageUrl"] == f"https://bhromon.fun/media/official/images/{body['id']}.jpg"
    assert body["kind"] == "image"
    stored = main.MEDIA_ROOT / "official" / "images" / f"{body['id']}.jpg"
    assert stored.read_bytes() == b"\x00" * 2048
    entry = firestore.writes[("official_instafeed", body["id"])]
    assert entry["caption"] == "Official Photo"
    assert entry["kind"] == "image"
    assert entry["imageUrl"] == body["imageUrl"]
    assert entry["coverUrl"] == body["imageUrl"]
    assert pushes == [
        ("official_instafeed", "Bhromon", "Official Photo", {"action": "official", "postId": body["id"]}),
    ]


def test_a_cover_must_be_an_image(published):
    client, _firestore, _pushes = published

    response = client.post(
        "/official/posts",
        files=[_part("reel.mp4", "video/mp4"), _part("cover.pdf", "application/pdf", field="cover")],
        headers={"X-Official-Key": "the-publish-key"},
    )

    assert response.status_code == 400


def test_the_caption_has_a_limit(published):
    client, firestore, _pushes = published

    response = client.post(
        "/official/posts",
        files=[_part("reel.mp4", "video/mp4")],
        data={"caption": "x" * (main.MAX_OFFICIAL_CAPTION + 1)},
        headers={"X-Official-Key": "the-publish-key"},
    )

    assert response.status_code == 400
    assert firestore.writes == {}


def test_anyone_signed_in_may_read_the_official_space():
    alice = main.Caller(email="alice@x.com", uid="uid-alice")

    assert "official" in main.PUBLIC_OR_USER_SPACES
    assert main.can_read_space("official", alice) is True


def test_the_topic_push_goes_to_the_topic_subscribers():
    engine = NotificationEngine()
    messaging = MagicMock()
    messaging.send.return_value = "projects/x/messages/1"
    engine._get_messaging = MagicMock(return_value=messaging)

    result = engine.send_topic_push("official_instafeed", "Bhromon", "Hello", {"action": "official"})

    assert result == {"status": "success", "messageId": "projects/x/messages/1"}
    assert messaging.Message.call_args.kwargs["topic"] == "official_instafeed"
    assert messaging.Notification.call_args.kwargs == {"title": "Bhromon", "body": "Hello"}
