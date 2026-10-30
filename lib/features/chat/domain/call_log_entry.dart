/// How a call looks in the chat it belongs to.
enum CallLogKind {
  outgoing,
  incoming,
  outgoingVideo,
  incomingVideo,
  missed,
  noAnswer,
  declined
}

/// A call as the chat stores it: who placed it, how it ended and how long it lasted.
class CallLogEntry {
  const CallLogEntry({
    required this.callerId,
    required this.calleeId,
    required this.isVideo,
    required this.status,
    this.durationSeconds,
  });

  /// Reads the fields the call log writes. See `CallLogRepository`.
  factory CallLogEntry.fromData(Map<String, dynamic> data) => CallLogEntry(
        callerId: (data['callerId'] as String?) ?? '',
        calleeId: (data['calleeId'] as String?) ?? '',
        isVideo: data['isVideoCall'] == true,
        status: (data['callStatus'] as String?) ?? 'ended',
        durationSeconds: (data['durationSeconds'] as num?)?.toInt(),
      );

  final String callerId;
  final String calleeId;
  final bool isVideo;
  final String status;
  final int? durationSeconds;

  /// True when the call connected, so it has a length to show.
  bool get connected => (durationSeconds ?? 0) > 0;

  /// The entry as [uid] sees it. The caller sees "No answer" where the callee
  /// sees "Missed".
  CallLogKind kindFor(String uid) {
    final outgoing = callerId == uid;
    if (status == 'declined') return CallLogKind.declined;
    if (connected) {
      if (isVideo) {
        return outgoing ? CallLogKind.outgoingVideo : CallLogKind.incomingVideo;
      }
      return outgoing ? CallLogKind.outgoing : CallLogKind.incoming;
    }
    return outgoing ? CallLogKind.noAnswer : CallLogKind.missed;
  }
}

/// The chat id of two members. Every screen builds it the same way.
String chatIdFor(String a, String b) => ([a, b]..sort()).join('_');

/// Minutes and seconds of a call's length.
({int minutes, int seconds}) callDurationParts(int totalSeconds) =>
    (minutes: totalSeconds ~/ 60, seconds: totalSeconds % 60);
