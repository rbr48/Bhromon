import 'package:bhromon/features/chat/data/call_log_repository.dart';
import 'package:bhromon/features/chat/data/call_signaling_service.dart';
import 'package:bhromon/features/chat/domain/call_display.dart';
import 'package:bhromon/features/chat/domain/call_quality.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('callShouldRing', () {
    final now = DateTime(2026, 3, 1, 12);

    test('a fresh ringing call rings', () {
      expect(
        callShouldRing({
          'status': 'calling',
          'createdAt':
              Timestamp.fromDate(now.subtract(const Duration(seconds: 5))),
        }, now),
        isTrue,
      );
    });

    test('a call that was answered, declined or ended does not ring', () {
      for (final status in ['answered', 'declined', 'ended', 'missed']) {
        expect(callShouldRing({'status': status}, now), isFalse,
            reason: status);
      }
    });

    test('a missing call does not ring', () {
      expect(callShouldRing(null, now), isFalse);
    });

    test('a call still marked ringing long after its ring time does not ring',
        () {
      expect(
        callShouldRing({
          'status': 'calling',
          'createdAt':
              Timestamp.fromDate(now.subtract(const Duration(minutes: 5))),
        }, now),
        isFalse,
      );
    });
  });

  group('callMemberEmails', () {
    test('reads both members', () {
      expect(callMemberEmails({'u1': 'a@x.com', 'u2': 'b@x.com'}),
          {'u1': 'a@x.com', 'u2': 'b@x.com'});
    });

    test('is null when a member is missing or the value is not a map', () {
      expect(callMemberEmails({'u1': 'a@x.com'}), isNull);
      expect(callMemberEmails('nope'), isNull);
      expect(callMemberEmails(null), isNull);
    });
  });

  group('callLogChatMeta', () {
    test('leaves an existing chat\'s tour alone by default', () {
      final meta =
          callLogChatMeta(writerUid: 'u1', callerId: 'u1', calleeId: 'u2');
      expect(meta.containsKey('sharedTourId'), isFalse);
      expect(meta.containsKey('memberEmails'), isFalse);
    });

    test('names the tour and both emails when it opens a new chat', () {
      final meta = callLogChatMeta(
        writerUid: 'u1',
        callerId: 'u1',
        calleeId: 'u2',
        sharedTourId: 'tour1',
        memberEmails: {'u1': 'a@x.com', 'u2': 'b@x.com'},
      );
      expect(meta['sharedTourId'], 'tour1');
      expect(meta['memberEmails'], {'u1': 'a@x.com', 'u2': 'b@x.com'});
    });
  });

  group('callInitial', () {
    test('takes the first letter, upper-cased', () {
      expect(callInitial('alice'), 'A');
      expect(callInitial('  bob '), 'B');
    });

    test('never cuts an emoji or a Bengali letter in half', () {
      expect(callInitial('😀 Party'), '😀');
      expect(callInitial('শাহীন'), 'শ');
    });

    test('an empty name gives a question mark', () {
      expect(callInitial(''), '?');
      expect(callInitial('   '), '?');
    });
  });

  group('clampWithin', () {
    test('keeps a value inside the range', () {
      expect(clampWithin(5, 10, 100), 10);
      expect(clampWithin(150, 10, 100), 100);
      expect(clampWithin(50, 10, 100), 50);
    });

    test('a range smaller than the minimum gives the minimum, not an error',
        () {
      expect(clampWithin(50, 60, 20), 60);
    });
  });

  group('PacketLossMeter', () {
    test('rates only the packets since the previous reading', () {
      final meter = PacketLossMeter();
      expect(meter.lossSince(300, 700), isNull); // a bad start: 30% so far
      // The link recovered: no new losses in the next interval.
      expect(meter.lossSince(300, 1700), 0);
      // 10 lost out of the next 100.
      expect(meter.lossSince(310, 1790), closeTo(0.1, 1e-9));
    });

    test('starts over when a stream restarts its counters', () {
      final meter = PacketLossMeter();
      meter.lossSince(50, 1000);
      expect(meter.lossSince(0, 10), isNull);
      expect(meter.lossSince(1, 19), closeTo(0.1, 1e-9));
    });

    test('an interval with no packets has no figure', () {
      final meter = PacketLossMeter();
      meter.lossSince(5, 100);
      expect(meter.lossSince(5, 100), isNull);
    });
  });

  test('a negative loss count from WebRTC counts as none', () {
    final sample = callLinkSampleFromStats([
      {'type': 'inbound-rtp', 'packetsLost': -3, 'packetsReceived': 100},
    ]);
    expect(sample.lossRatio, 0);
    expect(sample.packetsLost, 0);
    expect(sample.packetsReceived, 100);
  });

  group('audioOutputKind', () {
    test('reads the outputs Android reports', () {
      expect(
          audioOutputKind('speaker', 'Speakerphone'), AudioOutputKind.speaker);
      expect(audioOutputKind('earpiece', 'Earpiece'), AudioOutputKind.earpiece);
      expect(audioOutputKind('bluetooth', 'Galaxy Buds'),
          AudioOutputKind.bluetooth);
      expect(audioOutputKind('wired-headset', 'Wired headset'),
          AudioOutputKind.headset);
    });

    test('an unknown output is other', () {
      expect(audioOutputKind('42', 'Car'), AudioOutputKind.other);
    });
  });

  test('the rebuild budget comes back after a reset', () {
    final policy = CallReconnectPolicy(maxAttempts: 1);
    expect(policy.startAttempt(), isTrue);
    expect(policy.startAttempt(), isFalse);
    policy.reset();
    expect(policy.startAttempt(), isTrue);
  });
}
