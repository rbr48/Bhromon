"""Reshares: a copy of a tour's file gets its own name, and both names share one copy of the bytes."""

import os

import main
from conftest import bearer

OBJECT = "0123456789abcdef0123456789abcdef"
PHOTO = {"file": ("photo.jpg", b"jpeg-bytes", "image/jpeg")}


def upload_photo(client, token="tok-alice", tour="t1", folder="posts"):
    data = {"tourId": tour, "folder": folder, "objectId": OBJECT}
    return client.post("/upload", files=PHOTO, data=data, headers=bearer(token))


def copy(client, source_url, token="tok-bob", tour="t1", folder="stories"):
    body = {"tourId": tour, "folder": folder, "sourceUrl": source_url}
    headers = bearer(token) if token else {}
    return client.post("/copy", json=body, headers=headers)


def original_url():
    return f"https://bhromon.fun/media/t1/posts/{OBJECT}.jpg"


def test_a_copy_gets_its_own_name_and_shares_the_bytes(client):
    upload_photo(client)
    response = copy(client, original_url())
    assert response.status_code == 200
    url = response.json()["url"]
    assert url != original_url()
    assert url.startswith("https://bhromon.fun/media/t1/stories/")
    original = main.MEDIA_ROOT / "t1" / "posts" / f"{OBJECT}.jpg"
    copied = main.MEDIA_ROOT / "t1" / "stories" / url.rsplit("/", 1)[1]
    assert copied.read_bytes() == b"jpeg-bytes"
    assert os.stat(original).st_ino == os.stat(copied).st_ino


def test_deleting_the_original_leaves_the_copy_intact(client):
    upload_photo(client)
    url = copy(client, original_url()).json()["url"]
    deleted = client.delete(
        f"/media/t1/posts/{OBJECT}.jpg", headers=bearer("tok-alice")
    )
    assert deleted.status_code == 200
    copied = main.MEDIA_ROOT / "t1" / "stories" / url.rsplit("/", 1)[1]
    assert copied.read_bytes() == b"jpeg-bytes"


def test_the_copy_belongs_to_the_person_who_made_it(client):
    upload_photo(client)
    url = copy(client, original_url(), token="tok-bob").json()["url"]
    filename = url.rsplit("/", 1)[1]
    meta = main.read_meta("t1", "stories", filename)
    assert meta["uploaderEmail"] == "bob@x.com"
    # Bob can remove his own copy; the original stays with Alice.
    removed = client.delete(f"/media/t1/stories/{filename}", headers=bearer("tok-bob"))
    assert removed.status_code == 200
    assert (main.MEDIA_ROOT / "t1" / "posts" / f"{OBJECT}.jpg").is_file()


def test_a_copy_keeps_the_extension_of_a_reel(client):
    clip = {"file": ("clip.mp4", b"video", "video/mp4")}
    reel_id = "fedcba9876543210fedcba9876543210"
    client.post(
        "/upload",
        files=clip,
        data={"tourId": "t1", "folder": "reels", "objectId": reel_id},
        headers=bearer("tok-alice"),
    )
    url = copy(client, f"https://bhromon.fun/media/t1/reels/{reel_id}.mp4").json()["url"]
    assert url.endswith(".mp4")


def test_a_copy_needs_a_token(client):
    upload_photo(client)
    assert copy(client, original_url(), token=None).status_code == 401


def test_only_members_of_the_tour_can_copy(client):
    upload_photo(client)
    assert copy(client, original_url(), token="tok-eve").status_code == 403


def test_only_media_of_the_same_tour_can_be_copied(client):
    upload_photo(client)
    other_tour = f"https://bhromon.fun/media/t2/posts/{OBJECT}.jpg"
    assert copy(client, other_tour).status_code == 400


def test_a_copy_refuses_paths_that_are_not_media_files(client):
    upload_photo(client)
    traversal = f"https://bhromon.fun/media/t1/posts/../{OBJECT}.jpg"
    assert copy(client, traversal).status_code == 400
    not_a_name = "https://bhromon.fun/media/t1/posts/photo.jpg"
    assert copy(client, not_a_name).status_code == 400


def test_a_copy_of_a_missing_file_is_not_found(client):
    assert copy(client, original_url()).status_code == 404


def test_a_copy_must_go_to_an_allowed_folder(client):
    upload_photo(client)
    assert copy(client, original_url(), folder="secret").status_code == 400
