// The messages a chat keeps on the phone, made ready to show before the server answers, and the
// comparison that tells whether a message changed. Pure Dart apart from Firestore's Timestamp,
// which is a plain value.

import 'package:cloud_firestore/cloud_firestore.dart';

/// The fields the cache stores as ISO text and the chat reads as a [Timestamp].
const Set<String> kCachedTimestampFields = {
  'timestamp',
  'editedAt',
  'openedAt',
  'deliveredAt',
  'readAt',
  'seenAt',
};

/// One cached message with its time fields turned back into [Timestamp]s. A value that is not
/// a valid time is left out, so a bad entry shows without a time rather than failing.
Map<String, dynamic> restoreCachedMessage(Map<String, dynamic> cached) {
  final restored = <String, dynamic>{};
  cached.forEach((key, value) {
    if (kCachedTimestampFields.contains(key) && value is String) {
      final time = DateTime.tryParse(value);
      if (time != null) restored[key] = Timestamp.fromDate(time);
    } else if (value is Map) {
      restored[key] = Map<String, dynamic>.from(value);
    } else {
      restored[key] = value;
    }
  });
  return restored;
}

/// The newest [limit] cached messages, newest first, restored for the chat to show. A message
/// with no id or no time is left out: it cannot be placed in the conversation.
List<Map<String, dynamic>> newestCachedMessages(
  List<Map<String, dynamic>> cached, {
  required int limit,
}) {
  final restored = <Map<String, dynamic>>[];
  for (final message in cached) {
    final id = message['id'];
    if (id is! String || id.isEmpty) continue;
    final ready = restoreCachedMessage(message);
    if (ready['timestamp'] is! Timestamp) continue;
    restored.add(ready);
  }
  restored.sort((a, b) =>
      (b['timestamp'] as Timestamp).compareTo(a['timestamp'] as Timestamp));
  return restored.length > limit ? restored.sublist(0, limit) : restored;
}

/// Whether two message values are the same, through nested maps and lists. A message bubble is
/// drawn again only when this says its data changed.
bool messageDataEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!messageDataEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!messageDataEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
