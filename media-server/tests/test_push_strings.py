import pytest

from push_strings import (
    CHAT_PUSH_TEXT_LIMIT,
    DEFAULT_LANGUAGE,
    SUPPORTED_LANGUAGES,
    _TEXTS,
    call_alert,
    chat_preview,
    localized_number,
    normalize_language,
    push_text,
)


def test_both_languages_have_the_same_keys():
    keys = {lang: set(_TEXTS[lang]) for lang in SUPPORTED_LANGUAGES}
    assert keys["en"] == keys["bn"]


@pytest.mark.parametrize(
    "code, expected",
    [
        ("bn", "bn"),
        ("BN", "bn"),
        ("bn-BD", "bn"),
        ("bn_BD", "bn"),
        ("en", "en"),
        ("en-GB", "en"),
        ("fr", "en"),
        ("", "en"),
        (None, "en"),
    ],
)
def test_normalize_language(code, expected):
    assert normalize_language(code) == expected


def test_english_texts_are_unchanged():
    assert push_text("en", "preview.text") == "New message"
    assert push_text("en", "preview.voice") == "🎤 Voice message"
    assert push_text("en", "chat.title", sender="Rahim") == "New message from Rahim"
    assert push_text("en", "call.title", kind="Video") == "Incoming Video Call"


def test_bengali_texts_are_used_for_bengali_devices():
    assert push_text("bn", "preview.text") == "নতুন বার্তা"
    assert push_text("bn", "chat.title", sender="Rahim") == "Rahim থেকে নতুন বার্তা"
    assert push_text("bn", "channel.title", sender="Rahim", channel="general") == (
        "#general-এ Rahim"
    )


def test_an_unknown_language_gets_english():
    assert push_text("fr", "preview.text") == push_text(DEFAULT_LANGUAGE, "preview.text")
    assert push_text(None, "sos.body") == push_text("en", "sos.body")


def test_chat_preview_is_the_text_or_what_was_sent():
    assert chat_preview("en", "hi", "text") == "hi"
    assert chat_preview("en", "", "text") == "New message"
    assert chat_preview("en", "", "image") == "Sent a image"
    assert chat_preview("bn", "", "image") == "একটি image পাঠিয়েছেন"


def test_a_long_chat_message_is_cut_for_the_push():
    long_text = "ক" * 5000  # Bengali letters are three bytes each in UTF-8
    body = chat_preview("bn", long_text, "text")
    assert len(body) == CHAT_PUSH_TEXT_LIMIT
    assert body == long_text[: CHAT_PUSH_TEXT_LIMIT - 1] + "…"
    # Three copies of the body must fit in one FCM message of 4 KB.
    assert len(body.encode("utf-8")) * 3 < 4096


def test_a_chat_message_at_the_limit_is_sent_whole():
    text = "a" * CHAT_PUSH_TEXT_LIMIT
    assert chat_preview("en", text, "text") == text
    assert chat_preview("en", text + "a", "text") == "a" * (CHAT_PUSH_TEXT_LIMIT - 1) + "…"


def test_call_alert_in_both_languages():
    assert call_alert("en", True, "Rahim") == (
        "Incoming Video Call",
        "Rahim is calling you on Bhromon...",
    )
    assert call_alert("bn", False, "Rahim") == (
        "আসছে ভয়েস কল",
        "Rahim Bhromon-এ আপনাকে কল করছেন...",
    )


def test_numbers_use_bengali_digits_only_in_bengali():
    assert localized_number("bn", 12) == "১২"
    assert localized_number("bn-BD", 0) == "০"
    assert localized_number("en", 12) == "12"
    assert localized_number(None, 7) == "7"
    assert localized_number("fr", 3) == "3"
