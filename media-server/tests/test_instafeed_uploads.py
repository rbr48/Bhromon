"""The uploads the instafeed makes: reel videos, their first-frame covers, and a repeat
of a reel after a dropped connection. Each is sent the way the app sends it: the file
named with its object id, the id as a form field, and the member's token."""

import pytest

from conftest import bearer

OBJECT = "0123456789abcdef0123456789abcdef"


def post_file(client, folder, extension, content_type, body=b"media-bytes", token="tok-alice"):
    return client.post(
        "/upload",
        files={"file": (f"{OBJECT}.{extension}", body, content_type)},
        data={
            "tourId": "t1",
            "folder": folder,
            "objectId": OBJECT,
            "uploaderEmail": "alice@x.com",
        },
        headers=bearer(token),
    )


@pytest.mark.parametrize(
    "extension, content_type",
    [
        ("mp4", "video/mp4"),
        ("mov", "video/quicktime"),
        ("3gp", "video/3gpp"),
        ("webm", "video/webm"),
        ("mkv", "video/x-matroska"),
    ],
)
def test_a_reel_from_the_camera_or_the_gallery_is_stored(client, extension, content_type):
    response = post_file(client, "reels", extension, content_type)
    assert response.status_code == 200
    assert response.json()["url"].endswith(f"/t1/reels/{OBJECT}.{extension}")


def test_the_first_frame_cover_is_stored_under_covers(client):
    response = post_file(client, "covers", "jpg", "image/jpeg")
    assert response.status_code == 200
    assert response.json()["url"].endswith(f"/t1/covers/{OBJECT}.jpg")


def test_a_repeat_of_the_same_reel_returns_the_same_url(client):
    first = post_file(client, "reels", "mp4", "video/mp4", body=b"same-reel")
    again = post_file(client, "reels", "mp4", "video/mp4", body=b"same-reel")
    assert first.status_code == 200
    assert again.status_code == 200
    assert again.json()["url"] == first.json()["url"]


def test_someone_who_is_not_a_member_cannot_post_a_reel(client):
    assert post_file(client, "reels", "mp4", "video/mp4", token="tok-eve").status_code == 403


def test_the_uploader_can_delete_their_own_reel(client):
    assert post_file(client, "reels", "mp4", "video/mp4").status_code == 200
    response = client.delete(f"/media/t1/reels/{OBJECT}.mp4", headers=bearer("tok-alice"))
    assert response.status_code == 200
    assert response.json()["status"] == "deleted"
