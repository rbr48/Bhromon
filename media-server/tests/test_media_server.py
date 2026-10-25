from pathlib import Path

import pytest

import main
from conftest import bearer

OBJECT = "0123456789abcdef0123456789abcdef"
PHOTO = {"file": ("photo.jpg", b"jpeg-bytes", "image/jpeg")}


def upload(client, token="tok-alice", tour="t1", folder="posts", object_id=OBJECT, **extra):
    data = {"tourId": tour, "folder": folder, **extra}
    if object_id is not None:
        data["objectId"] = object_id
    headers = bearer(token) if token else {}
    return client.post("/upload", files=PHOTO, data=data, headers=headers)


def test_upload_needs_a_token(client):
    assert upload(client, token=None).status_code == 401


def test_upload_rejects_an_unknown_token(client):
    assert upload(client, token="tok-forged").status_code == 401


def test_upload_rejects_someone_who_is_not_a_member(client):
    assert upload(client, token="tok-eve").status_code == 403


def test_upload_records_the_token_email_not_the_form_field(client, tmp_path):
    response = upload(client, uploaderEmail="someone-else@x.com")
    assert response.status_code == 200
    meta = main.read_meta("t1", "posts", f"{OBJECT}.jpg")
    assert meta["uploaderEmail"] == "alice@x.com"


def test_upload_returns_the_url_for_the_client_chosen_id(client):
    body = upload(client).json()
    assert body["url"].endswith(f"/t1/posts/{OBJECT}.jpg")
    assert body["filename"] == f"{OBJECT}.jpg"


def test_a_second_upload_with_the_same_id_is_refused(client):
    assert upload(client).status_code == 200
    assert upload(client).status_code == 409


def test_the_first_file_survives_a_refused_duplicate(client):
    upload(client)
    path = main.MEDIA_ROOT / "t1" / "posts" / f"{OBJECT}.jpg"
    assert path.read_bytes() == b"jpeg-bytes"
    client.post(
        "/upload",
        files={"file": ("photo.jpg", b"other", "image/jpeg")},
        data={"tourId": "t1", "folder": "posts", "objectId": OBJECT},
        headers=bearer("tok-alice"),
    )
    assert path.read_bytes() == b"jpeg-bytes"


@pytest.mark.parametrize(
    "overrides",
    [
        {"folder": "photos"},
        {"folder": "../etc"},
        {"tour": "../t1"},
        {"object_id": "not-hex"},
        {"object_id": "0123456789ABCDEF0123456789ABCDEF"},
    ],
)
def test_bad_folder_tour_or_object_id_is_refused(client, overrides):
    assert upload(client, **overrides).status_code == 400


@pytest.mark.parametrize("folder", ["covers", "reels", "stories", "channels"])
def test_every_folder_the_app_uses_is_accepted(client, folder):
    assert upload(client, folder=folder).status_code == 200


@pytest.mark.parametrize("name", ["photo.heic", "clip.3gp", "clip.mkv"])
def test_formats_the_app_accepts_are_stored(client, name):
    response = client.post(
        "/upload",
        files={"file": (name, b"bytes", "application/octet-stream")},
        data={"tourId": "t1", "folder": "posts", "objectId": OBJECT},
        headers=bearer("tok-alice"),
    )
    assert response.status_code == 200, response.text


def test_an_unsupported_extension_is_refused(client):
    response = client.post(
        "/upload",
        files={"file": ("evil.html", b"<script>", "text/html")},
        data={"tourId": "t1", "folder": "posts"},
        headers=bearer("tok-alice"),
    )
    assert response.status_code == 400


def test_an_oversized_file_is_refused_and_removed(client, monkeypatch):
    monkeypatch.setattr(main, "MAX_IMAGE_BYTES", 4)
    response = upload(client)
    assert response.status_code == 413
    assert not (main.MEDIA_ROOT / "t1" / "posts" / f"{OBJECT}.jpg").exists()


def test_the_uploader_can_delete_their_own_file(client):
    upload(client)
    response = client.delete(f"/media/t1/posts/{OBJECT}.jpg", headers=bearer("tok-alice"))
    assert response.json()["status"] == "deleted"


def test_another_member_cannot_delete_it(client):
    upload(client)
    response = client.delete(f"/media/t1/posts/{OBJECT}.jpg", headers=bearer("tok-bob"))
    assert response.status_code == 403
    assert (main.MEDIA_ROOT / "t1" / "posts" / f"{OBJECT}.jpg").exists()


def test_an_admin_can_delete_anyones_file(client):
    upload(client)
    response = client.delete(f"/media/t1/posts/{OBJECT}.jpg", headers=bearer("tok-admin"))
    assert response.json()["status"] == "deleted"


def test_a_file_without_metadata_can_only_be_deleted_by_an_admin(client):
    path = main.MEDIA_ROOT / "t1" / "posts" / f"{OBJECT}.jpg"
    path.parent.mkdir(parents=True)
    path.write_bytes(b"legacy")
    assert client.delete(f"/media/t1/posts/{OBJECT}.jpg", headers=bearer("tok-alice")).status_code == 403
    assert client.delete(f"/media/t1/posts/{OBJECT}.jpg", headers=bearer("tok-admin")).json()["status"] == "deleted"


def test_deleting_a_missing_file_is_not_an_error(client):
    response = client.delete(f"/media/t1/posts/{OBJECT}.jpg", headers=bearer("tok-alice"))
    assert response.status_code == 200
    assert response.json()["status"] == "not_found"


@pytest.mark.parametrize("name", ["../secret.jpg", "abc.jpg", f"{OBJECT}.html", ".."])
def test_delete_refuses_names_outside_the_upload_pattern(client, name):
    response = client.delete(f"/media/t1/posts/{name}", headers=bearer("tok-admin"))
    assert response.status_code in (400, 404)


def test_the_legacy_key_is_off_by_default(client):
    response = client.post(
        "/upload",
        files=PHOTO,
        data={"tourId": "t1", "folder": "posts"},
        headers={"X-Upload-Key": "anything"},
    )
    assert response.status_code == 401


def test_the_legacy_key_works_only_when_configured(client, monkeypatch):
    monkeypatch.setattr(main, "LEGACY_UPLOAD_KEY", "transition-key")
    ok = client.post(
        "/upload",
        files=PHOTO,
        data={"tourId": "t1", "folder": "posts"},
        headers={"X-Upload-Key": "transition-key"},
    )
    assert ok.status_code == 200
    wrong = client.post(
        "/upload",
        files=PHOTO,
        data={"tourId": "t1", "folder": "posts"},
        headers={"X-Upload-Key": "nope"},
    )
    assert wrong.status_code == 401


def test_no_shared_secret_is_written_into_the_source():
    source = Path(main.__file__).read_text(encoding="utf-8")
    assert "bhromon_vps_media_2026_sec" not in source
    assert "*" not in main.ALLOWED_ORIGINS
