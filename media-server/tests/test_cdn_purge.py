"""CDN purge: deleted media is cleared from the CDN's cache, in batches Cloudflare accepts."""

import logging

import cdn
import main
from conftest import bearer

OBJECT = "0123456789abcdef0123456789abcdef"
CONFIG = {"zoneId": "zone-1", "apiToken": "secret-token"}


class Recorder:
    """Stands in for the HTTP call to Cloudflare."""

    def __init__(self):
        self.calls = []

    def __call__(self, url, headers, body):
        self.calls.append((url, headers, body))


def upload_photo(client):
    return client.post(
        "/upload",
        files={"file": ("photo.jpg", b"jpeg-bytes", "image/jpeg")},
        data={"tourId": "t1", "folder": "posts", "objectId": OBJECT},
        headers=bearer("tok-alice"),
    )


def test_urls_are_split_into_batches_of_thirty():
    urls = [f"https://bhromon.fun/media/t1/posts/{n}.jpg" for n in range(65)]
    batches = cdn.chunk_urls(urls)
    assert [len(batch) for batch in batches] == [30, 30, 5]
    assert sum(batches, []) == urls


def test_paths_become_public_media_urls():
    assert cdn.media_urls_for(["t1/posts/a.jpg"]) == [
        "https://bhromon.fun/media/t1/posts/a.jpg"
    ]


def test_nothing_is_sent_without_a_zone_and_a_token():
    recorder = Recorder()
    assert cdn.purge_paths(["t1/posts/a.jpg"], lambda: None, send=recorder) == 0
    partial = {"zoneId": "zone-1"}
    assert cdn.purge_paths(["t1/posts/a.jpg"], lambda: partial, send=recorder) == 0
    assert recorder.calls == []


def test_a_purge_sends_the_media_urls_with_the_token():
    recorder = Recorder()
    sent = cdn.purge_paths(["t1/posts/a.jpg"], lambda: CONFIG, send=recorder)
    assert sent == 1
    url, headers, body = recorder.calls[0]
    assert url == "https://api.cloudflare.com/client/v4/zones/zone-1/purge_cache"
    assert headers["Authorization"] == "Bearer secret-token"
    assert body == {"files": ["https://bhromon.fun/media/t1/posts/a.jpg"]}


def test_the_zone_id_is_quoted_into_the_url():
    recorder = Recorder()
    odd = {"zoneId": "a/b", "apiToken": "token"}
    cdn.purge_paths(["t1/posts/a.jpg"], lambda: odd, send=recorder)
    assert "/zones/a%2Fb/purge_cache" in recorder.calls[0][0]


def test_deleting_a_file_purges_its_cached_copy(client, monkeypatch):
    sent = []
    monkeypatch.setattr(main, "read_cdn_config", lambda: CONFIG)
    monkeypatch.setattr(cdn, "post_json", lambda url, headers, body: sent.append(body))
    upload_photo(client)
    response = client.delete(f"/media/t1/posts/{OBJECT}.jpg", headers=bearer("tok-alice"))
    assert response.status_code == 200
    assert sent == [{"files": [f"https://bhromon.fun/media/t1/posts/{OBJECT}.jpg"]}]


def test_a_failed_purge_is_logged_and_the_delete_still_succeeds(client, monkeypatch, caplog):
    monkeypatch.setattr(main, "read_cdn_config", lambda: CONFIG)

    def refuse(url, headers, body):
        raise RuntimeError("cloudflare refused")

    monkeypatch.setattr(cdn, "post_json", refuse)
    upload_photo(client)
    with caplog.at_level(logging.ERROR):
        response = client.delete(f"/media/t1/posts/{OBJECT}.jpg", headers=bearer("tok-alice"))
    assert response.status_code == 200
    assert "CDN purge failed" in caplog.text
