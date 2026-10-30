import json
import os
import sys
import tempfile
from pathlib import Path

import pytest

# chat.py opens its database under MEDIA_META_ROOT as soon as it is imported, so
# point it at a scratch directory first, as the other test modules do.
os.environ.setdefault("MEDIA_META_ROOT", tempfile.mkdtemp(prefix="bhromon-test-meta-"))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import main  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

KEY = "purge-test-key"


@pytest.fixture
def roots(tmp_path, monkeypatch):
    media = tmp_path / "media"
    meta = tmp_path / "meta"
    media.mkdir()
    meta.mkdir()
    monkeypatch.setattr(main, "MEDIA_ROOT", media)
    monkeypatch.setattr(main, "META_ROOT", meta)
    monkeypatch.setattr(main, "PURGE_KEY", KEY)
    return media, meta


def save(media, meta, tour, folder, name, uploader):
    """Writes a file the way the upload route does: the file and its sidecar."""
    (media / tour / folder).mkdir(parents=True, exist_ok=True)
    (media / tour / folder / name).write_bytes(b"x")
    (meta / tour / folder).mkdir(parents=True, exist_ok=True)
    sidecar = meta / tour / folder / f"{name}.json"
    sidecar.write_text(json.dumps({"uploaderEmail": uploader}), encoding="utf-8")


def purge(body, key=KEY):
    headers = {} if key is None else {"X-Purge-Key": key}
    return TestClient(main.app).post("/purge", json=body, headers=headers)


def test_purging_is_off_until_a_key_is_configured(roots, monkeypatch):
    media, meta = roots
    save(media, meta, "tour_one", "posts", "a.jpg", "alice@x.com")
    monkeypatch.setattr(main, "PURGE_KEY", "")

    response = purge({"tourId": "tour_one"})

    assert response.status_code == 503
    assert (media / "tour_one" / "posts" / "a.jpg").exists()


def test_a_missing_or_wrong_key_is_refused(roots):
    media, meta = roots
    save(media, meta, "tour_one", "posts", "a.jpg", "alice@x.com")

    assert purge({"tourId": "tour_one"}, key=None).status_code == 401
    assert purge({"tourId": "tour_one"}, key="guess").status_code == 401
    assert (media / "tour_one" / "posts" / "a.jpg").exists()


def test_an_uploaders_files_go_and_everyone_elses_stay(roots):
    media, meta = roots
    save(media, meta, "tour_one", "posts", "alice1.jpg", "alice@x.com")
    save(media, meta, "tour_one", "stories", "alice2.mp4", "alice@x.com")
    save(media, meta, "tour_one", "posts", "bob.jpg", "bob@x.com")
    save(media, meta, "tour_one", "posts", "legacy.jpg", "legacy")

    response = purge({"tourId": "tour_one", "uploaderEmail": "Alice@X.com"})

    assert response.status_code == 200
    body = response.json()
    assert body["removed"] == 2
    assert sorted(body["paths"]) == ["posts/alice1.jpg", "stories/alice2.mp4"]
    assert not (media / "tour_one" / "posts" / "alice1.jpg").exists()
    assert not (meta / "tour_one" / "posts" / "alice1.jpg.json").exists()
    assert not (media / "tour_one" / "stories" / "alice2.mp4").exists()
    assert (media / "tour_one" / "posts" / "bob.jpg").exists()
    assert (media / "tour_one" / "posts" / "legacy.jpg").exists()


def test_a_whole_tour_goes_and_other_tours_stay(roots):
    media, meta = roots
    save(media, meta, "tour_one", "posts", "a.jpg", "alice@x.com")
    save(media, meta, "tour_one", "channels", "b.jpg", "bob@x.com")
    save(media, meta, "tour_two", "posts", "c.jpg", "alice@x.com")

    response = purge({"tourId": "tour_one"})

    assert response.status_code == 200
    body = response.json()
    assert body["removed"] == 2
    assert sorted(body["paths"]) == ["channels/b.jpg", "posts/a.jpg"]
    assert not (media / "tour_one").exists()
    assert not (meta / "tour_one").exists()
    assert (media / "tour_two" / "posts" / "c.jpg").exists()


def test_a_tour_with_no_files_is_not_an_error(roots):
    response = purge({"tourId": "tour_none", "uploaderEmail": "alice@x.com"})

    assert response.status_code == 200
    assert response.json() == {"removed": 0, "paths": []}


def test_a_tour_id_that_reaches_outside_the_media_folder_is_refused(roots):
    media, meta = roots
    save(media, meta, "tour_one", "posts", "a.jpg", "alice@x.com")

    response = purge({"tourId": "../tour_one"})

    assert response.status_code == 400
    assert (media / "tour_one" / "posts" / "a.jpg").exists()
