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
  Future<void> record({
    required String writerUid,
    required String callerId,
    required String calleeId,
    required String callId,
    required bool isVideo,
    required String status,
    int? durationSeconds,
  }) async {
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
        ),
        SetOptions(merge: true),
      );
    await batch.commit();
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
Map<String, dynamic> callLogChatMeta({
  required String writerUid,
  required String callerId,
  required String calleeId,
}) =>
    {
      'participants': FieldValue.arrayUnion([callerId, calleeId]),
      'lastMessage': '📞 Call',
      'lastMessageType': 'call',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastMessageSenderId': writerUid,
    };
