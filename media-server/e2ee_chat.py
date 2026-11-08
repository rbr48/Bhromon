"""End-to-end encrypted one-to-one chats on the chat service (E2EE_DESIGN.md, section 7).

The server stores an encrypted chat's messages as envelopes and never their text.
It checks the shape and size of each envelope. It also reads whether a chat is
encrypted from the chat document in Firestore, not from the request: a client
must not be able to choose which rules apply to its own message.
"""

import base64
import binascii
import re
import threading
from collections import OrderedDict
from typing import Any, Callable, Dict, Optional

# The envelope format and algorithm the app writes (lib/features/chat/domain/e2ee).
ENVELOPE_VERSION = 1
ENVELOPE_ALGORITHM = "olm.v1"

# The largest ciphertext, in bytes, and its padded base64url length. The Dart
# side enforces the byte limit; the rules enforce the string length.
MAX_CIPHERTEXT_BYTES = 16 * 1024
MAX_CIPHERTEXT_CHARS = 21848

_ENVELOPE_FIELDS = frozenset({"v", "alg", "from", "to", "type", "ct"})
_DEVICE_ID = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
_CIPHERTEXT = re.compile(r"^[A-Za-z0-9_-]+={0,2}$")


class EnvelopeError(ValueError):
    """The envelope is not one this server accepts."""


class EncryptionStatusUnknown(RuntimeError):
    """The chat's encryption flag could not be read, so no message can be accepted."""


def _is_int_in(value: Any, allowed: tuple) -> bool:
    # bool is a subclass of int in Python, so it is refused explicitly.
    return type(value) is int and value in allowed


def _decoded_size(ciphertext: str) -> int:
    """The decoded length of canonical base64url. Padding must be the padding the length needs."""
    body = ciphertext.rstrip("=")
    padding = len(ciphertext) - len(body)
    if len(body) % 4 == 1:
        raise EnvelopeError("The ciphertext is not base64url.")
    if padding and (len(ciphertext) % 4 != 0 or padding != (-len(body)) % 4):
        raise EnvelopeError("The ciphertext is not base64url.")
    try:
        return len(base64.urlsafe_b64decode(body + "=" * ((-len(body)) % 4)))
    except (binascii.Error, ValueError) as exc:
        raise EnvelopeError("The ciphertext is not base64url.") from exc


def validate_envelope(envelope: Any) -> Dict[str, Any]:
    """Returns the envelope as it is stored, or raises EnvelopeError."""
    if not isinstance(envelope, dict):
        raise EnvelopeError("The envelope must be an object.")
    if set(envelope.keys()) != _ENVELOPE_FIELDS:
        raise EnvelopeError("The envelope has missing or unknown fields.")
    if not _is_int_in(envelope["v"], (ENVELOPE_VERSION,)):
        raise EnvelopeError("Unsupported envelope version.")
    if envelope["alg"] != ENVELOPE_ALGORITHM:
        raise EnvelopeError("Unsupported envelope algorithm.")
    for field in ("from", "to"):
        value = envelope[field]
        if not isinstance(value, str) or not _DEVICE_ID.match(value):
            raise EnvelopeError(f'"{field}" is not a device id.')
    if not _is_int_in(envelope["type"], (0, 1)):
        raise EnvelopeError("The message type must be 0 or 1.")
    ciphertext = envelope["ct"]
    if (
        not isinstance(ciphertext, str)
        or not ciphertext
        or len(ciphertext) > MAX_CIPHERTEXT_CHARS
        or not _CIPHERTEXT.match(ciphertext)
    ):
        raise EnvelopeError("The ciphertext is malformed.")
    size = _decoded_size(ciphertext)
    if size < 1 or size > MAX_CIPHERTEXT_BYTES:
        raise EnvelopeError("The ciphertext size is out of range.")
    return {
        "v": envelope["v"],
        "alg": envelope["alg"],
        "from": envelope["from"],
        "to": envelope["to"],
        "type": envelope["type"],
        "ct": ciphertext,
    }


def firestore_chat_flag(chat_id: str) -> Optional[bool]:
    """Reads chats/{chatId}.e2ee with the Admin SDK. None when the chat does not exist."""
    import firebase_admin
    from firebase_admin import firestore

    if not firebase_admin._apps:
        raise EncryptionStatusUnknown("The Firebase Admin SDK is not initialized.")
    snapshot = firestore.client().collection("chats").document(chat_id).get()
    if not snapshot.exists:
        return None
    return (snapshot.to_dict() or {}).get("e2ee") is True


class EncryptedChats:
    """Tells whether a chat is end-to-end encrypted.

    The flag is set when a chat is created and cannot change (firestore.rules), so an
    answer for a chat that exists is kept for the life of the process, up to a bound.
    A chat whose document does not exist yet is not kept, because it may be created next.
    A read that fails raises EncryptionStatusUnknown, and the caller refuses the message.
    """

    def __init__(
        self,
        read_flag: Callable[[str], Optional[bool]],
        max_entries: int = 10000,
    ) -> None:
        self._read_flag = read_flag
        self._max_entries = max_entries
        self._known: "OrderedDict[str, bool]" = OrderedDict()
        self._lock = threading.Lock()

    def is_encrypted(self, chat_id: str) -> bool:
        with self._lock:
            if chat_id in self._known:
                self._known.move_to_end(chat_id)
                return self._known[chat_id]
        try:
            flag = self._read_flag(chat_id)
        except EncryptionStatusUnknown:
            raise
        except Exception as exc:
            raise EncryptionStatusUnknown(str(exc)) from exc
        if flag is None:
            return False
        with self._lock:
            self._known[chat_id] = flag
            self._known.move_to_end(chat_id)
            while len(self._known) > self._max_entries:
                self._known.popitem(last=False)
        return flag
