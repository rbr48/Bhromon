"""Signed links for private media: the keys, the signatures, and who may read what."""

import pytest

import main
import media_access

SECRET = b"test-secret-of-at-least-32-bytes-long!!"
PATH = "/media/t1/posts/0123456789abcdef0123456789abcdef.jpg"
# Reference values. The Dart client's tests check the same numbers.
KEY_ALICE = "oJ1WRboA_XoAcNYlTsgzTVWOOKQNhYMybHxcuXMHph0"
KEY_BOB = "ZlxThxCyvI8dujMl819ebHGzv1sMBCzTv_78HdDx6RI"
SIG_ALICE_PATH = "6piNFezcCVn8Hdbk6KXFKcjVXuAqI_DHsixeQRqoDAY"


def link(path, uid, secret=SECRET):
    """The path with the query a signed link carries, made for `uid`."""
    signature = media_access.signature_for(media_access.derive_key(secret, uid), path)
    return f"{path}?u={uid}&s={signature}"


def signature_of(signed):
    return signed.split("&s=")[1]


@pytest.fixture
def enforcing(monkeypatch):
    monkeypatch.setattr(main, "MEDIA_ACCESS_SECRET", SECRET)
    monkeypatch.setattr(main, "MEDIA_ACCESS_ENFORCE", True)
    monkeypatch.setattr(main, "media_decisions", media_access.AccessDecisions())


def status_for(client, raw_uri):
    return client.get("/internal/media-auth", headers={"X-Original-URI": raw_uri}).status_code


def test_the_key_and_signature_match_the_reference_values():
    assert media_access.derive_key(SECRET, "uid-alice") == KEY_ALICE
    assert media_access.derive_key(SECRET, "uid-bob") == KEY_BOB
    assert media_access.signature_for(KEY_ALICE, PATH) == SIG_ALICE_PATH


def test_each_person_has_their_own_key_and_another_secret_gives_another_key():
    assert media_access.derive_key(SECRET, "uid-alice") != media_access.derive_key(SECRET, "uid-bob")
    other = b"another-secret-that-is-also-long-enough"
    assert media_access.derive_key(other, "uid-alice") != KEY_ALICE


def test_a_link_is_parsed_only_when_it_has_one_u_and_one_s():
    assert media_access.parse_link(f"{PATH}?u=uid-alice&s=abc") == (PATH, "uid-alice", "abc")
    assert media_access.parse_link(PATH) is None
    assert media_access.parse_link(f"{PATH}?u=uid-alice") is None
    assert media_access.parse_link(f"{PATH}?u=uid-alice&s=") is None
    assert media_access.parse_link(f"{PATH}?u=a&u=b&s=abc") is None
    assert media_access.parse_link(f"{PATH}?u=uid-alice&s=abc&x=1") is None


def test_a_signature_is_valid_only_for_its_path_and_person():
    assert media_access.signature_is_valid(SECRET, PATH, "uid-alice", SIG_ALICE_PATH)
    other_path = PATH.replace("0123", "fedc")
    assert not media_access.signature_is_valid(SECRET, other_path, "uid-alice", SIG_ALICE_PATH)
    assert not media_access.signature_is_valid(SECRET, PATH, "uid-bob", SIG_ALICE_PATH)
    assert not media_access.signature_is_valid(b"short", PATH, "uid-alice", SIG_ALICE_PATH)


def test_a_member_reads_a_file_of_their_tour_with_their_own_link(enforcing, client):
    assert status_for(client, link(PATH, "uid-alice")) == 200


def test_a_stranger_is_refused_even_with_a_valid_link(enforcing, client):
    assert status_for(client, link(PATH, "uid-eve")) == 403


def test_an_unsigned_request_is_refused_when_enforcing(enforcing, client):
    assert status_for(client, PATH) == 403


def test_a_link_opens_only_its_own_file(enforcing, client):
    other_file = PATH.replace("0123", "fedc")
    assert status_for(client, f"{PATH}?u=uid-alice&s={signature_of(link(other_file, 'uid-alice'))}") == 403


def test_a_link_cannot_be_given_to_another_person(enforcing, client):
    assert status_for(client, f"{PATH}?u=uid-bob&s={signature_of(link(PATH, 'uid-alice'))}") == 403


def test_a_chat_is_open_to_its_two_people_while_they_share_a_tour(enforcing, client):
    chat = "/media/chat_uid-alice_uid-bob/chat_media/0123456789abcdef0123456789abcdef.jpg"
    assert status_for(client, link(chat, "uid-alice")) == 200
    assert status_for(client, link(chat, "uid-bob")) == 200
    assert status_for(client, link(chat, "uid-eve")) == 403


def test_a_chat_with_someone_who_shares_no_tour_is_refused(enforcing, client):
    chat = "/media/chat_uid-alice_uid-eve/chat_media/0123456789abcdef0123456789abcdef.jpg"
    assert status_for(client, link(chat, "uid-alice")) == 403


def test_public_spaces_are_open_to_any_signed_in_person(enforcing, client):
    avatar = "/media/profiles/avatars/0123456789abcdef0123456789abcdef.jpg"
    assert status_for(client, link(avatar, "uid-eve")) == 200


def test_a_user_space_belongs_to_its_owner(enforcing, client):
    space = "/media/user_uid-bob/media/0123456789abcdef0123456789abcdef.jpg"
    assert status_for(client, link(space, "uid-alice")) == 403
    assert status_for(client, link(space, "uid-bob")) == 200


def test_an_unknown_folder_or_a_bad_name_is_refused_even_with_a_link(enforcing, client):
    unknown_folder = "/media/t1/nope/0123456789abcdef0123456789abcdef.jpg"
    assert status_for(client, link(unknown_folder, "uid-alice")) == 403
    assert status_for(client, link("/media/t1/posts/photo.jpg", "uid-alice")) == 403


def test_log_only_mode_serves_what_fails_the_check(client, monkeypatch):
    monkeypatch.setattr(main, "MEDIA_ACCESS_SECRET", SECRET)
    monkeypatch.setattr(main, "MEDIA_ACCESS_ENFORCE", False)
    monkeypatch.setattr(main, "media_decisions", media_access.AccessDecisions())
    assert status_for(client, PATH) == 200
    assert status_for(client, link(PATH, "uid-eve")) == 200


def test_with_no_secret_nothing_is_served_once_enforced(client, monkeypatch):
    monkeypatch.setattr(main, "MEDIA_ACCESS_SECRET", b"")
    monkeypatch.setattr(main, "MEDIA_ACCESS_ENFORCE", True)
    monkeypatch.setattr(main, "media_decisions", media_access.AccessDecisions())
    assert status_for(client, PATH) == 403


def test_a_person_who_leaves_a_tour_is_refused_once_the_remembered_answer_expires(client, monkeypatch):
    now = [0.0]
    monkeypatch.setattr(main, "MEDIA_ACCESS_SECRET", SECRET)
    monkeypatch.setattr(main, "MEDIA_ACCESS_ENFORCE", True)
    monkeypatch.setattr(main, "media_decisions", media_access.AccessDecisions(clock=lambda: now[0]))
    signed = link(PATH, "uid-alice")
    assert status_for(client, signed) == 200
    del main.backend.memberships["t1__alice@x.com"]
    assert status_for(client, signed) == 200  # Still remembered for a minute.
    now[0] = media_access.DECISION_SECONDS + 1
    assert status_for(client, signed) == 403


def test_the_access_key_goes_only_to_its_owner(client, monkeypatch):
    monkeypatch.setattr(main, "MEDIA_ACCESS_SECRET", SECRET)
    response = client.post("/access-key", headers={"Authorization": "Bearer tok-alice"})
    assert response.status_code == 200
    assert response.json() == {"uid": "uid-alice", "key": KEY_ALICE}
    assert client.post("/access-key").status_code == 401
    assert client.post("/access-key", headers={"Authorization": "Bearer bad"}).status_code == 401


def test_the_access_key_is_unavailable_without_a_secret(client, monkeypatch):
    monkeypatch.setattr(main, "MEDIA_ACCESS_SECRET", b"")
    assert client.post("/access-key", headers={"Authorization": "Bearer tok-alice"}).status_code == 503
