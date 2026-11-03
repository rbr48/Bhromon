"""Push notification text in each supported language.

A push goes to a device in that device's language. The app sends its language
with the device token, and the server keeps it. A device with no language, or
one the server does not know, gets English.

Each key has an English and a Bengali text. The tests check that both
languages have the same keys, so a new key cannot be missing in one of them.
"""

from typing import Optional, Tuple

SUPPORTED_LANGUAGES = ("en", "bn")
DEFAULT_LANGUAGE = "en"

_TEXTS = {
    "en": {
        "preview.voice": "🎤 Voice message",
        "preview.video": "🎬 Video",
        "preview.photo": "📷 Photo",
        "preview.poll": "📊 Poll",
        "preview.expense": "💸 Expense",
        "preview.text": "New message",
        "sos.title": "🚨 SOS from {sender}",
        "sos.body": "Open Bhromon and check the Family Safety Hub.",
        "channel.title": "{sender} in #{channel}",
        "chat.title": "New message from {sender}",
        "call.title": "Incoming {kind} Call",
        "call.kind.voice": "Voice",
        "call.kind.video": "Video",
        "call.body": "{caller} is calling you on Bhromon...",
        "sender.default": "Explorer",
        "caller.default": "Member",
        "vps.title": "New Message",
        "vps.sent": "Sent a {type}",
    },
    "bn": {
        "preview.voice": "🎤 ভয়েস বার্তা",
        "preview.video": "🎬 ভিডিও",
        "preview.photo": "📷 ছবি",
        "preview.poll": "📊 পোল",
        "preview.expense": "💸 খরচ",
        "preview.text": "নতুন বার্তা",
        "sos.title": "🚨 {sender} থেকে SOS",
        "sos.body": "Bhromon খুলে Family Safety Hub দেখুন।",
        "channel.title": "#{channel}-এ {sender}",
        "chat.title": "{sender} থেকে নতুন বার্তা",
        "call.title": "আসছে {kind} কল",
        "call.kind.voice": "ভয়েস",
        "call.kind.video": "ভিডিও",
        "call.body": "{caller} Bhromon-এ আপনাকে কল করছেন...",
        "sender.default": "সদস্য",
        "caller.default": "সদস্য",
        "vps.title": "নতুন বার্তা",
        "vps.sent": "একটি {type} পাঠিয়েছেন",
    },
}


def normalize_language(code: Optional[str]) -> str:
    """'bn', 'bn-BD' and 'BN' all mean Bengali. Anything unknown is English."""
    if not code or not isinstance(code, str):
        return DEFAULT_LANGUAGE
    base = code.strip().lower().replace("_", "-").split("-")[0]
    return base if base in SUPPORTED_LANGUAGES else DEFAULT_LANGUAGE


def push_text(language: Optional[str], key: str, **params: str) -> str:
    """The text for [key] in [language], with the parameters filled in."""
    table = _TEXTS[normalize_language(language)]
    template = table.get(key) or _TEXTS[DEFAULT_LANGUAGE][key]
    return template.format(**params)


def chat_preview(language: Optional[str], text: Optional[str], message_type: Optional[str]) -> str:
    """The body of a chat push: the message text, or what was sent."""
    if text:
        return text
    if message_type and message_type != "text":
        return push_text(language, "vps.sent", type=message_type)
    return push_text(language, "preview.text")


def call_alert(language: Optional[str], is_video: bool, caller_name: str) -> Tuple[str, str]:
    """The title and body of an incoming call alert."""
    kind = push_text(language, "call.kind.video" if is_video else "call.kind.voice")
    return (
        push_text(language, "call.title", kind=kind),
        push_text(language, "call.body", caller=caller_name),
    )
