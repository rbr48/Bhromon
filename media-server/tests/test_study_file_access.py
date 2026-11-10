"""A study file is served once its material is published. Until then, and after a report hides it,
only the one who filed it and the tour's owners and admins may read it, even with a valid link."""

import pytest

import main
import media_access

SECRET = b"test-secret-of-at-least-32-bytes-long!!"
FILE = "0123456789abcdef0123456789abcdef.pdf"
PATH = f"/media/t1/study/{FILE}"
URL = f"{main.BASE_URL.rstrip('/')}/t1/study/{FILE}"


def link(path, uid, secret=SECRET):
    signature = media_access.signature_for(media_access.derive_key(secret, uid), path)
    return f"{path}?u={uid}&s={signature}"


@pytest.fixture
def enforcing(monkeypatch):
    monkeypatch.setattr(main, "MEDIA_ACCESS_SECRET", SECRET)
    monkeypatch.setattr(main, "MEDIA_ACCESS_ENFORCE", True)
    monkeypatch.setattr(main, "media_decisions", media_access.AccessDecisions())
    main._study_file_cache.clear()


def status_for(client, uid):
    raw = link(PATH, uid)
    return client.get("/internal/media-auth", headers={"X-Original-URI": raw}).status_code


def file_is_filed_as(client, status, by="alice@x.com"):
    main.backend.study_materials[URL] = [{"status": status, "createdByEmail": by}]


def test_a_published_material_is_served_to_every_member(enforcing, client):
    file_is_filed_as(client, "published")
    assert status_for(client, "uid-bob") == 200


def test_a_hidden_file_is_refused_to_other_members_with_a_valid_link(enforcing, client):
    file_is_filed_as(client, "hidden")
    assert status_for(client, "uid-bob") == 403


def test_a_hidden_file_stays_open_to_its_uploader_and_the_admins(enforcing, client):
    file_is_filed_as(client, "hidden")
    assert status_for(client, "uid-alice") == 200
    assert status_for(client, "uid-admin") == 200
    assert status_for(client, "uid-owner") == 200


def test_a_file_waiting_for_approval_is_refused_to_other_members(enforcing, client):
    file_is_filed_as(client, "pending")
    assert status_for(client, "uid-bob") == 403
    assert status_for(client, "uid-alice") == 200


def test_a_file_no_material_points_to_is_served_as_before(enforcing, client):
    assert status_for(client, "uid-bob") == 200


def test_a_record_with_no_status_is_refused_to_other_members(enforcing, client):
    main.backend.study_materials[URL] = [{"createdByEmail": "alice@x.com"}]
    assert status_for(client, "uid-bob") == 403


def test_the_state_of_a_file_follows_the_material_once_the_cache_expires(enforcing, client, monkeypatch):
    now = [0.0]
    monkeypatch.setattr(main.time, "monotonic", lambda: now[0])
    file_is_filed_as(client, "published")
    assert status_for(client, "uid-bob") == 200
    file_is_filed_as(client, "hidden")
    assert status_for(client, "uid-bob") == 200  # Remembered for a few seconds.
    now[0] = main.STUDY_FILE_CACHE_SECONDS + 1
    assert status_for(client, "uid-bob") == 403


def test_the_uploader_is_matched_without_regard_to_case(enforcing, client):
    file_is_filed_as(client, "hidden", by="Alice@X.com")
    assert status_for(client, "uid-alice") == 200


def test_a_file_outside_the_study_folder_is_not_affected(enforcing, client):
    main.backend.study_materials[f"{main.BASE_URL.rstrip('/')}/t1/posts/{FILE}"] = [
        {"status": "hidden", "createdByEmail": "alice@x.com"}
    ]
    raw = link(f"/media/t1/posts/{FILE}", "uid-bob")
    assert client.get("/internal/media-auth", headers={"X-Original-URI": raw}).status_code == 200


def test_a_failed_read_of_the_material_refuses_the_file(enforcing, client, monkeypatch):
    def broken(tour_id, url):
        raise RuntimeError("firestore is down")

    monkeypatch.setattr(main.backend, "study_material_records", broken)
    assert status_for(client, "uid-bob") == 403
