import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:bhromon/features/chat/data/chat_local_cache.dart';

/// The writes behind deleting messages and chats.
///
/// The rules in `firestore.rules` allow these writes: a participant can hide a
/// message for themselves (`deletedFor`), the sender can replace their own
/// message with a deleted note within the window, and a participant can change
/// the chat's metadata, including their own entry in `clearedAt`. Nothing here
/// deletes documents, because the rules do not allow it.
class ChatDeletionService {
  ChatDeletionService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Firestore allows up to 500 writes in a batch. The batches stay below that.
  static const int _batchSize = 400;

  CollectionReference<Map<String, dynamic>> _messages(String chatId) =>
      _db.collection('chats').doc(chatId).collection('messages');

  /// Hides [messageIds] for [uid] only ("Delete for me").
  Future<void> deleteForMe({
    required String chatId,
    required String uid,
    required Iterable<String> messageIds,
  }) async {
    for (final chunk in _chunks(messageIds)) {
      final batch = _db.batch();
      for (final id in chunk) {
        batch.update(_messages(chatId).doc(id), {
          'deletedFor': FieldValue.arrayUnion([uid]),
        });
      }
      await batch.commit();
    }
  }

  /// Replaces [messageIds] with a deleted note for everyone. Only the sender can
  /// do this, within the window. The caller checks that with
  /// `canDeleteForEveryone`, and the rules check it again.
  Future<void> deleteForEveryone({
    required String chatId,
    required Iterable<String> messageIds,
  }) async {
    for (final chunk in _chunks(messageIds)) {
      final batch = _db.batch();
      for (final id in chunk) {
        batch.update(_messages(chatId).doc(id), {
          'type': 'deleted',
          'text': 'This message was deleted',
          'isDeleted': true,
          'deletedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
  }

  /// Deletes the chat for [uid] only. Messages sent up to now disappear for them,
  /// and the chat leaves their list until a newer message arrives. The other
  /// person keeps the chat and its history.
  Future<void> deleteChatForMe({
    required String chatId,
    required String uid,
  }) async {
    await _db.collection('chats').doc(chatId).set({
      'clearedAt': {uid: FieldValue.serverTimestamp()},
      'unreadCounts': {uid: 0},
    }, SetOptions(merge: true));
    await ChatLocalCache().removeChat(chatId);
  }

  /// When [uid] deleted the chat, or null if they have not.
  static DateTime? clearedAtOf(Map<String, dynamic>? chat, String uid) {
    final cleared = chat?['clearedAt'];
    if (cleared is! Map) return null;
    return timestampOf(cleared[uid]);
  }

  /// The time of a value from Firestore or the offline cache, or null. The cache
  /// stores timestamps as ISO strings and the VPS feed may send milliseconds.
  static DateTime? timestampOf(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static List<List<String>> _chunks(Iterable<String> ids) {
    final all = ids.toSet().toList();
    return [
      for (var start = 0; start < all.length; start += _batchSize)
        all.skip(start).take(_batchSize).toList(),
    ];
  }
}
