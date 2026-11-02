/// Pure rules for deleting chat messages and whole chats.
///
/// They mirror the Firestore rules in `firestore.rules` (chats and messages).
/// Keep the two in step: a change here that the rules refuse would show the
/// person a delete that fails.
library;

/// How long a sender can delete a message for everyone, counted from the time it
/// was sent. This is the 60-hour tombstone window in the messages rule.
const Duration kDeleteForEveryoneWindow = Duration(hours: 60);

/// Whether [currentUid] can delete a message for everyone.
///
/// Only the sender can, while the message is within [kDeleteForEveryoneWindow]
/// of [sentAt], and only if it has not been deleted already. A message whose
/// time is not known yet (still being written) cannot be deleted for everyone.
bool canDeleteForEveryone({
  required String? senderId,
  required String currentUid,
  required DateTime? sentAt,
  required DateTime now,
  required bool alreadyDeleted,
}) {
  if (alreadyDeleted || currentUid.isEmpty) return false;
  if (senderId != currentUid) return false;
  if (sentAt == null) return false;
  return now.isBefore(sentAt.add(kDeleteForEveryoneWindow));
}

/// Whether a message sent at [sentAt] is hidden for a person who deleted the
/// chat at [clearedAt]. Messages sent up to that moment are hidden; newer ones
/// show. A message with no time yet is shown.
bool isMessageHiddenByCutoff({
  required DateTime? sentAt,
  required DateTime? clearedAt,
}) {
  if (clearedAt == null || sentAt == null) return false;
  return !sentAt.isAfter(clearedAt);
}

/// Whether a chat is hidden from the list of a person who deleted it at
/// [clearedAt]. It stays hidden until a message arrives after that moment, so
/// the chat comes back with the new message and its older history stays hidden.
bool isChatHiddenByCutoff({
  required DateTime? clearedAt,
  required DateTime? lastMessageAt,
}) {
  if (clearedAt == null) return false;
  if (lastMessageAt == null) return true;
  return !lastMessageAt.isAfter(clearedAt);
}
