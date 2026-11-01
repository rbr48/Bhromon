"""Storage and upload limits: a tour, a person within it, the free disk, and the upload rate."""

import json

import limits
import main
from conftest import bearer

OBJECT = "0123456789abcdef0123456789abcdef"
OTHER = "fedcba9876543210fedcba9876543210"


def upload(client, object_id=OBJECT, data=b"jpeg-bytes", token="tok-alice", folder="posts"):
    return client.post(
        "/upload",
        files={"file": ("photo.jpg", data, "image/jpeg")},
        data={"tourId": "t1", "folder": folder, "objectId": object_id},
        headers=bearer(token),
    )


def test_the_rate_limiter_allows_a_burst_then_refuses_until_a_minute_passes():
    now = [0.0]
    limiter = limits.RateLimiter(2, clock=lambda: now[0])
    assert limiter.allow("a") and limiter.allow("a")
    assert not limiter.allow("a")
    assert limiter.allow("b")  # Limits are per key.
    now[0] = 61.0
    assert limiter.allow("a")


def test_uploads_are_rate_limited_per_person(client, monkeypatch):
    monkeypatch.setattr(main, "upload_limiter", limits.RateLimiter(1))
    assert upload(client).status_code == 200
    assert upload(client, object_id=OTHER).status_code == 429


def test_a_tour_cannot_store_more_than_its_quota(client, monkeypatch):
    monkeypatch.setattr(limits, "TOUR_QUOTA_BYTES", 15)
    assert upload(client, object_id=OBJECT).status_code == 200  # 10 bytes
    assert upload(client, object_id=OTHER, token="tok-bob").status_code == 507


def test_one_person_cannot_use_more_than_their_share_of_a_tour(client, monkeypatch):
    monkeypatch.setattr(limits, "UPLOADER_QUOTA_BYTES", 15)
    assert upload(client, object_id=OBJECT, token="tok-alice").status_code == 200
    assert upload(client, object_id=OTHER, token="tok-alice").status_code == 507
    # Another member still has their own share.
    assert upload(client, object_id=OTHER, token="tok-bob").status_code == 200


def test_a_retry_of_a_file_already_stored_is_not_refused_by_the_quota(client, monkeypatch):
    monkeypatch.setattr(limits, "TOUR_QUOTA_BYTES", 10)
    assert upload(client).status_code == 200
    assert upload(client).status_code == 200  # Same bytes, already counted.


def test_the_disk_floor_refuses_uploads_when_the_disk_is_nearly_full(client, monkeypatch):
    monkeypatch.setattr(limits, "MIN_FREE_BYTES", 10**15)
    response = upload(client)
    assert response.status_code == 507
    assert "nearly full" in response.json()["detail"]


def test_the_sidecar_records_the_size_of_each_file(client):
    upload(client)
    meta = main.read_meta("t1", "posts", f"{OBJECT}.jpg")
    assert meta["bytes"] == len(b"jpeg-bytes")


def test_usage_counts_each_uploader_and_the_tour_total(client):
    upload(client, object_id=OBJECT, token="tok-alice")
    upload(client, object_id=OTHER, token="tok-bob", data=b"12345")
    total, by_uploader = limits.tour_usage(main.META_ROOT, main.MEDIA_ROOT, "t1")
    assert total == 15
    assert by_uploader == {"alice@x.com": 10, "bob@x.com": 5}


def test_a_file_saved_before_sidecars_recorded_sizes_is_counted_by_its_size_on_disk(client):
    upload(client)
    sidecar = main.meta_path_for("t1", "posts", f"{OBJECT}.jpg")
    legacy = {"uploaderEmail": "alice@x.com", "tourId": "t1", "folder": "posts"}
    sidecar.write_text(json.dumps(legacy), encoding="utf-8")
    total, _ = limits.tour_usage(main.META_ROOT, main.MEDIA_ROOT, "t1")
    assert total == len(b"jpeg-bytes")


def test_a_copy_counts_against_the_sharers_share(client, monkeypatch):
    monkeypatch.setattr(limits, "UPLOADER_QUOTA_BYTES", 15)
    upload(client, object_id=OBJECT, token="tok-alice")
    source = f"https://bhromon.fun/media/t1/posts/{OBJECT}.jpg"
    body = {"tourId": "t1", "folder": "stories", "sourceUrl": source}
    first = client.post("/copy", json=body, headers=bearer("tok-bob"))
    second = client.post("/copy", json=body, headers=bearer("tok-bob"))
    assert first.status_code == 200
    assert second.status_code == 507
