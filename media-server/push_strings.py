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
        "journey.arrive.title": "{sender} reached {place}",
        "journey.depart.title": "{sender} left {place}",
        "journey.body": "Open Bhromon to see where the group is.",
        "channel.title": "{sender} in #{channel}",
        "chat.title": "New message from {sender}",
        "call.title": "Incoming {kind} Call",
        "call.kind.voice": "Voice",
        "call.kind.video": "Video",
        "call.handle.voice": "Bhromon Voice Call",
        "call.handle.video": "Bhromon Video Call",
        "family.untitled": "Family date",
        "family.today": "Today",
        "family.tomorrow": "Tomorrow",
        "family.in_days": "In {days} days",
        "ack.title": "Please answer: {title}",
        "ack.untitled": "Please answer a notice",
        "ack.waiting_one": "1 member has not answered yet. Tap to answer.",
        "session.head": "Study session",
        "session.untitled": "your session",
        "session.day_before": "{title} starts in 24 hours.",
        "session.soon": "{title} starts in 30 minutes.",
        "ack.waiting_many": "{count} members have not answered yet. Tap to answer.",
        "call.body": "{caller} is calling you on Bhromon...",
        "sender.default": "Explorer",
        "caller.default": "Member",
        "vps.title": "New Message",
        "vps.sent": "Sent a {type}",
        "post.photo.title": "{sender} shared a new photo",
        "post.reel.title": "{sender} shared a new reel",
        "post.photo.body": "📷 View photo in trip feed",
        "post.reel.body": "🎬 Watch reel in trip feed",
        "comment.title": "{sender} commented on your post",
        "comment.default": "Commented on your post",
        "reaction.like.title": "New like on your post ❤️",
        "reaction.like.body": "{sender} liked your photo",
        "notice.title": "📢 {title}",
        "notice.untitled": "📢 New notice from group",
        "notice.body": "{body}",
        "ledger.title": "💸 ৳{taka} expense recorded",
        "ledger.body": "{payer} paid ৳{taka} for {title}",
        "bazar.duty.title": "🛒 Bazar Duty Today",
        "bazar.duty.body": "You have bazar duty for your mess today.",
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
        "journey.arrive.title": "{sender} {place} পৌঁছেছেন",
        "journey.depart.title": "{sender} {place} ছেড়েছেন",
        "journey.body": "দল কোথায় আছে দেখতে Bhromon খুলুন।",
        "channel.title": "#{channel}-এ {sender}",
        "chat.title": "{sender} থেকে নতুন বার্তা",
        "call.title": "আসছে {kind} কল",
        "call.kind.voice": "ভয়েস",
        "call.kind.video": "ভিডিও",
        "call.handle.voice": "Bhromon ভয়েস কল",
        "call.handle.video": "Bhromon ভিডিও কল",
        "family.untitled": "পারিবারিক তারিখ",
        "family.today": "আজ",
        "family.tomorrow": "আগামীকাল",
        "family.in_days": "{days} দিন পরে",
        "ack.title": "উত্তর দিন: {title}",
        "ack.untitled": "একটি বিজ্ঞপ্তিতে উত্তর দিন",
        "ack.waiting_one": "একজন সদস্য এখনও উত্তর দেয়নি। উত্তর দিতে ট্যাপ করুন।",
        "session.head": "পড়ার আসর",
        "session.untitled": "আপনার আসর",
        "session.day_before": "{title} ২৪ ঘণ্টা পরে শুরু হবে।",
        "session.soon": "{title} ৩০ মিনিট পরে শুরু হবে।",
        "ack.waiting_many": "{count} জন সদস্য এখনও উত্তর দেয়নি। উত্তর দিতে ট্যাপ করুন।",
        "call.body": "{caller} Bhromon-এ আপনাকে কল করছেন...",
        "sender.default": "সদস্য",
        "caller.default": "সদস্য",
        "vps.title": "নতুন বার্তা",
        "vps.sent": "একটি {type} পাঠিয়েছেন",
        "post.photo.title": "{sender} নতুন ছবি শেয়ার করেছেন",
        "post.reel.title": "{sender} নতুন রিল শেয়ার করেছেন",
        "post.photo.body": "📷 ট্রিপ ফিডে ছবিটি দেখুন",
        "post.reel.body": "🎬 ট্রিপ ফিডে রিলটি দেখুন",
        "comment.title": "{sender} আপনার পোস্টে মন্তব্য করেছেন",
        "comment.default": "আপনার পোস্টে মন্তব্য করেছেন",
        "reaction.like.title": "আপনার পোস্টে নতুন লাইক ❤️",
        "reaction.like.body": "{sender} আপনার ছবিতে লাইক দিয়েছেন",
        "notice.title": "📢 {title}",
        "notice.untitled": "📢 গ্রুপের নতুন বিজ্ঞপ্তি",
        "notice.body": "{body}",
        "ledger.title": "💸 ৳{taka} খরচ যোগ করা হয়েছে",
        "ledger.body": "{payer} {title}-এর জন্য ৳{taka} পরিশোধ করেছেন",
        "bazar.duty.title": "🛒 আজকের বাজার দায়িত্ব",
        "bazar.duty.body": "আজ আপনার মেসের বাজার করার দায়িত্ব রয়েছে।",
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


_BENGALI_DIGITS = str.maketrans("0123456789", "০১২৩৪৫৬৭৮৯")


def localized_number(language: Optional[str], number: int) -> str:
    """The number written in the language's digits: Bengali digits in Bengali."""
    text = str(number)
    if normalize_language(language) == "bn":
        return text.translate(_BENGALI_DIGITS)
    return text


# A chat push carries at most this many characters of the message, as channel pushes
# do. FCM rejects a message over 4 KB, and the body is copied into three notification
# blocks, so a long message would never reach a phone whose app is closed.
CHAT_PUSH_TEXT_LIMIT = 120


def chat_preview(language: Optional[str], text: Optional[str], message_type: Optional[str]) -> str:
    """The body of a chat push: the message text, cut short, or what was sent."""
    if text:
        if len(text) > CHAT_PUSH_TEXT_LIMIT:
            return text[: CHAT_PUSH_TEXT_LIMIT - 1] + "…"
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
