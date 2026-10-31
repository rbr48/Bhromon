"""Media spaces are as open as the people in them.

A chat space is open to its two people, and only while they share a tour. A user
space is open to its owner. The public spaces are open to any signed-in person.
"""

from conftest import bearer
import main

OBJECT = "0123456789abcdef0123456789abcdef"
PHOTO = {"file": ("photo.jpg", b"jpeg-bytes", "image/jpeg")}


def send(client, space, token="tok-alice", folder="chat_media"):
    return client.post(
        "/upload",
        files=PHOTO,
        data={"tourId": space, "folder": folder, "objectId": OBJECT},
        headers=bearer(token),
    )


def test_chat_media_goes_to_a_member_of_a_shared_tour(client):
    assert send(client, "chat_uid-alice_uid-bob").status_code == 200


def test_chat_media_is_refused_to_someone_in_no_shared_tour(client):
    assert send(client, "chat_uid-alice_uid-eve").status_code == 403


def test_chat_media_cannot_be_put_into_someone_elses_chat(client):
    assert send(client, "chat_uid-alice_uid-bob", token="tok-eve").status_code == 403


def test_the_old_shared_fallback_space_is_closed(client):
    assert send(client, "chat_direct").status_code == 403


def test_a_chat_space_must_name_the_caller(client):
    assert send(client, "chat_uid-bob_uid-carol").status_code == 403


def test_chat_partners_are_read_from_either_end_of_the_space_name():
    assert main.chat_partner_of("chat_uid-alice_uid-bob", "uid-alice") == "uid-bob"
    assert main.chat_partner_of("chat_uid-alice_uid-bob", "uid-bob") == "uid-alice"
    assert main.chat_partner_of("chat_uid_a_uid_b", "uid_a") == "uid_b"
    assert main.chat_partner_of("chat_uid_a_uid_b", "uid_b") == "uid_a"
    assert main.chat_partner_of("chat_uid-alice_uid-bob", "uid-carol") is None
    assert main.chat_partner_of("chat_uid-alice_uid-alice", "uid-alice") is None
    assert main.chat_partner_of("t1", "uid-alice") is None


def test_only_the_uploader_or_an_admin_removes_chat_media(client):
    send(client, "chat_uid-alice_uid-bob")
    path = f"/media/chat_uid-alice_uid-bob/chat_media/{OBJECT}.jpg"
    assert client.delete(path, headers=bearer("tok-bob")).status_code == 403
    assert client.delete(path, headers=bearer("tok-alice")).json()["status"] == "deleted"


def test_a_user_space_is_its_owners_alone(client):
    assert send(client, "user_uid-alice", folder="posts").status_code == 200
    assert send(client, "user_uid-bob", folder="posts").status_code == 403


def test_the_public_spaces_still_take_any_signed_in_person(client):
    assert send(client, "profiles", folder="avatars").status_code == 200
