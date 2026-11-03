"""The VoIP ring for a closed iPhone names the call in the phone's language."""

import json

import voip_push as vp


class _Response:
    def __init__(self, status_code):
        self.status_code = status_code
        self.text = ""


def _sender(tmp_path, bodies):
    key = tmp_path / "AuthKey.p8"
    key.write_text("placeholder: the tests replace the provider token")
    env = {"APNS_KEY_PATH": str(key), "APNS_KEY_ID": "KEYID", "APNS_TEAM_ID": "TEAMID"}

    def post(url, headers, content):
        bodies.append(json.loads(content))
        return _Response(200)

    sender = vp.VoipPushSender(env=env, post=post)
    sender._provider_token = lambda: "provider-token"
    return sender


def test_the_call_handle_is_in_the_devices_language(tmp_path):
    bodies = []
    sender = _sender(tmp_path, bodies)

    voice = sender.send_call(
        "tok", call_id="c1", caller_id="u1", caller_name="Asha", is_video=False, language="bn"
    )
    video = sender.send_call(
        "tok", call_id="c2", caller_id="u1", caller_name="Asha", is_video=True, language="bn-BD"
    )

    assert (voice, video) == ("sent", "sent")
    assert [body["handle"] for body in bodies] == ["Bhromon ভয়েস কল", "Bhromon ভিডিও কল"]


def test_the_call_handle_falls_back_to_english(tmp_path):
    bodies = []
    sender = _sender(tmp_path, bodies)

    sender.send_call("tok", call_id="c1", caller_id="u1", caller_name="Asha", is_video=False)
    sender.send_call(
        "tok", call_id="c2", caller_id="u1", caller_name="Asha", is_video=True, language="fr"
    )

    assert [body["handle"] for body in bodies] == ["Bhromon Voice Call", "Bhromon Video Call"]
