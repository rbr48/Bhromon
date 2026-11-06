// How the one-to-one chats list is ordered. Pure Dart, so the order is tested without Firestore.

/// The order of the one-to-one chats list. It opens on [recent].
enum ChatListSort {
  /// The chat with the newest message first. A chat with no message time goes last.
  recent,

  /// The other person's name, A to Z. A chat with no stored name goes last.
  name,
}

/// What the sort needs to know about one chat row.
class ChatListRow {
  const ChatListRow({
    required this.chatId,
    required this.lastMessageAt,
    required this.otherName,
  });

  final String chatId;

  /// When the last message was sent, or null when the chat has none yet.
  final DateTime? lastMessageAt;

  /// The other person's name as the chat stores it, or null when it stores none.
  final String? otherName;
}

/// Returns [items] in [sort] order and leaves the input unchanged. Rows that tie are
/// ordered by the newest message, then by chat id, so the order is the same on every
/// rebuild.
List<T> sortChatRows<T>(
  Iterable<T> items,
  ChatListSort sort,
  ChatListRow Function(T item) rowOf,
) {
  final rows = [for (final item in items) (item: item, row: rowOf(item))];
  rows.sort((a, b) => compareChatRows(a.row, b.row, sort));
  return [for (final pair in rows) pair.item];
}

/// Orders two chat rows for [sort]. A negative result puts [a] first.
int compareChatRows(ChatListRow a, ChatListRow b, ChatListSort sort) {
  if (sort == ChatListSort.name) {
    final byName = _compareNamesAscending(a.otherName, b.otherName);
    if (byName != 0) return byName;
  }
  final byTime = _compareNewestFirst(a.lastMessageAt, b.lastMessageAt);
  if (byTime != 0) return byTime;
  return a.chatId.compareTo(b.chatId);
}

int _compareNewestFirst(DateTime? a, DateTime? b) {
  if (a == null || b == null) {
    if (a == null && b == null) return 0;
    return a == null ? 1 : -1;
  }
  return b.compareTo(a);
}

int _compareNamesAscending(String? a, String? b) {
  final left = a?.trim().toLowerCase() ?? '';
  final right = b?.trim().toLowerCase() ?? '';
  if (left.isEmpty || right.isEmpty) {
    if (left.isEmpty && right.isEmpty) return 0;
    return left.isEmpty ? 1 : -1;
  }
  return left.compareTo(right);
}
