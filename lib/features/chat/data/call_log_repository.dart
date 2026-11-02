import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/call_log_entry.dart';

/// Writes a finished call into the chat between its two members, so the call
/// sits in the conversation with the other messages.
class CallLogRepository {
  CallLogRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Records a call. [writerUid] is the signed-in member and must be one of the
  /// two, as the rules only accept messages sent as oneself.
  ///
  /// A chat is opened only between two members of one tour, so when the two
  /// have never messaged, the first write is refused. It is then made again
  /// with [sharedTourId] and [memberEmails], which open the chat. They are not
  /// sent the first time, so an existing chat keeps the tour it already names.
  Future<void> record({
    required String writerUid,
    required String callerId,
    required String calleeId,
    required String callId,
    required bool isVideo,
    required String status,
    int? durationSeconds,
    String? sharedTourId,
    Map<String, String>? memberEmails,
  }) async {
    Future<void> write({required bool openChat}) {
      final chat =
          _firestore.collection('chats').doc(chatIdFor(callerId, calleeId));
      final batch = _firestore.batch()
        ..set(
          // A fixed id per call: if both sides ever write the log, it is one
          // message, not two.
          chat.collection('messages').doc('call_$callId'),
          callLogMessageData(
            writerUid: writerUid,
            callerId: callerId,
            calleeId: calleeId,
            callId: callId,
            isVideo: isVideo,
            status: status,
            durationSeconds: durationSeconds,
          ),
        )
        ..set(
          chat,
          callLogChatMeta(
            writerUid: writerUid,
            callerId: callerId,
            calleeId: calleeId,
            sharedTourId: openChat ? sharedTourId : null,
            memberEmails: openChat ? memberEmails : null,
          ),
          SetOptions(merge: true),
        );
      return batch.commit();
    }

    try {
      await write(openChat: false);
    } on FirebaseException catch (e) {
      final canOpen = sharedTourId != null &&
          memberEmails != null &&
          memberEmails.containsKey(callerId) &&
          memberEmails.containsKey(calleeId);
      if (e.code != 'permission-denied' || !canOpen) rethrow;
      await write(openChat: true);
    }
  }
}

/// The message for a call. It has no text, and the function that notifies on
/// new messages skips type `call`, so a call log never sends a push.
Map<String, dynamic> callLogMessageData({
  required String writerUid,
  required String callerId,
  required String calleeId,
  required String callId,
  required bool isVideo,
  required String status,
  int? durationSeconds,
}) =>
    {
      'senderId': writerUid,
      'type': 'call',
      'callId': callId,
      'callerId': callerId,
      'calleeId': calleeId,
      'isVideoCall': isVideo,
      'callStatus': status,
      if (durationSeconds != null && durationSeconds > 0)
        'durationSeconds': durationSeconds,
      'seen': true,
      'status': 'sent',
      'timestamp': FieldValue.serverTimestamp(),
    };

/// The chat's last-message fields for a call. Unread counts are left alone, so
/// a call does not count as a new message.
///
/// [sharedTourId] and [memberEmails] are set only to open a chat that does not
/// exist yet; the rules open a chat only between two members of one tour.
Map<String, dynamic> callLogChatMeta({
  required String writerUid,
  required String callerId,
  required String calleeId,
  String? sharedTourId,
  Map<String, String>? memberEmails,
}) =>
    {
      'participants': FieldValue.arrayUnion([callerId, calleeId]),
      if (sharedTourId != null && memberEmails != null) ...{
        'sharedTourId': sharedTourId,
        'memberEmails': {
          callerId: memberEmails[callerId],
          calleeId: memberEmails[calleeId],
        },
      },
      'lastMessage': '📞 Call',
      'lastMessageType': 'call',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastMessageSenderId': writerUid,
    };
