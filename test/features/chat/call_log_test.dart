import 'package:bhromon/features/chat/data/call_log_repository.dart';
import 'package:bhromon/features/chat/domain/call_log_entry.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _call({
  bool video = false,
  String status = 'ended',
  int? duration,
}) =>
    {
      'callerId': 'ayesha',
      'calleeId': 'rafi',
      'isVideoCall': video,
      'callStatus': status,
      if (duration != null) 'durationSeconds': duration,
    };

void main() {
  group('chatIdFor', () {
    test('orders the two ids, as every chat screen does', () {
      expect(chatIdFor('rafi', 'ayesha'), 'ayesha_rafi');
      expect(chatIdFor('ayesha', 'rafi'), 'ayesha_rafi');
    });
  });

  group('how a call reads to each side', () {
    test(
        'a connected call is outgoing for the caller and incoming for the callee',
        () {
      final call = CallLogEntry.fromData(_call(duration: 192));

      expect(call.kindFor('ayesha'), CallLogKind.outgoing);
      expect(call.kindFor('rafi'), CallLogKind.incoming);
    });

    test('a connected video call keeps its video kind', () {
      final call = CallLogEntry.fromData(_call(video: true, duration: 60));

      expect(call.kindFor('ayesha'), CallLogKind.outgoingVideo);
      expect(call.kindFor('rafi'), CallLogKind.incomingVideo);
    });

    test(
        'an unanswered call is No answer for the caller and Missed for the callee',
        () {
      final call = CallLogEntry.fromData(_call());

      expect(call.connected, isFalse);
      expect(call.kindFor('ayesha'), CallLogKind.noAnswer);
      expect(call.kindFor('rafi'), CallLogKind.missed);
    });

    test('a declined call is declined for both sides', () {
      final call = CallLogEntry.fromData(_call(status: 'declined'));

      expect(call.kindFor('ayesha'), CallLogKind.declined);
      expect(call.kindFor('rafi'), CallLogKind.declined);
    });

    test('a zero-length call did not connect', () {
      final call = CallLogEntry.fromData(_call(duration: 0));

      expect(call.connected, isFalse);
    });
  });

  test('a call length splits into minutes and seconds', () {
    final parts = callDurationParts(192);

    expect(parts.minutes, 3);
    expect(parts.seconds, 12);
  });

  test('the call log message is a call with no text, sent as the writer', () {
    final data = callLogMessageData(
      writerUid: 'rafi',
      callerId: 'ayesha',
      calleeId: 'rafi',
      callId: 'call_1',
      isVideo: false,
      status: 'ended',
      durationSeconds: 192,
    );

    expect(data['type'], 'call');
    expect(data['senderId'], 'rafi');
    expect(data['callerId'], 'ayesha');
    expect(data['durationSeconds'], 192);
    expect(data.containsKey('text'), isFalse);
  });

  test('a call that never connected has no duration in its message', () {
    final data = callLogMessageData(
      writerUid: 'ayesha',
      callerId: 'ayesha',
      calleeId: 'rafi',
      callId: 'call_2',
      isVideo: true,
      status: 'missed',
    );

    expect(data.containsKey('durationSeconds'), isFalse);
    expect(data['isVideoCall'], isTrue);
  });
}
