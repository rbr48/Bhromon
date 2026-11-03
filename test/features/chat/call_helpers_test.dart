import 'package:bhromon/features/chat/data/call_notification_service.dart';
import 'package:bhromon/features/chat/data/call_signaling_service.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('candidateKey', () {
    test('the same candidate from the relay and from Firestore has one key',
        () {
      const line = 'candidate:1 1 udp 2 10.0.0.1 5000 typ host';

      expect(candidateKey(line, '0', 0), candidateKey(line, '0', 0));
    });

    test('a candidate for another media line is a different candidate', () {
      expect(candidateKey('c', '0', 0), isNot(candidateKey('c', '1', 1)));
    });

    test('a candidate without a media line still has a stable key', () {
      expect(candidateKey('c', null, null), candidateKey('c', null, null));
    });
  });

  group('IncomingCallRegistry', () {
    test('a call is claimed once within the window', () {
      final registry = IncomingCallRegistry(window: const Duration(minutes: 2));
      final start = DateTime(2026, 1, 1, 12);

      expect(registry.claim('call-1', start), isTrue);
      expect(registry.claim('call-1', start.add(const Duration(seconds: 30))),
          isFalse);
      expect(registry.claim('call-2', start), isTrue);
    });

    test('a call can be claimed again once the window has passed', () {
      final registry = IncomingCallRegistry(window: const Duration(minutes: 2));
      final start = DateTime(2026, 1, 1, 12);

      expect(registry.claim('call-1', start), isTrue);
      expect(registry.claim('call-1', start.add(const Duration(minutes: 3))),
          isTrue);
    });
  });

  group('CallSetupException', () {
    test('shows its message as text', () {
      const error = CallSetupException('Could not reach the call server.');

      expect(error.toString(), 'Could not reach the call server.');
    });
  });

  group('IncomingCallRegistry.isClaimed', () {
    test('reports a claim without making one', () {
      final registry = IncomingCallRegistry(window: const Duration(minutes: 2));
      final start = DateTime(2026, 1, 1, 12);

      expect(registry.isClaimed('call-1', start), isFalse);
      expect(registry.claim('call-1', start), isTrue);
      expect(registry.isClaimed('call-1', start), isTrue);
      expect(
          registry.isClaimed('call-1', start.add(const Duration(minutes: 3))),
          isFalse);
    });
  });

  group('acceptedSystemCalls', () {
    test('only calls the phone holds as answered are returned', () {
      const calls = [
        CallKitParams(
          id: 'ringing',
          nameCaller: 'Rina',
          extra: {'callId': 'ringing', 'callerId': 'u1'},
        ),
        CallKitParams(
          id: 'answered',
          nameCaller: 'Karim',
          type: 1,
          isAccepted: true,
          extra: {
            'callId': 'answered',
            'callerId': 'u2',
            'callerName': 'Karim Ahmed',
            'avatarUrl': 'https://example.com/a.jpg',
          },
        ),
      ];

      final accepted = acceptedSystemCalls(calls);

      expect(accepted, hasLength(1));
      expect(accepted.single.callId, 'answered');
      expect(accepted.single.callerId, 'u2');
      expect(accepted.single.callerName, 'Karim Ahmed');
      expect(accepted.single.avatarUrl, 'https://example.com/a.jpg');
      expect(accepted.single.isVideo, isTrue);
    });

    test('falls back to the phone call id and caller name', () {
      final accepted = acceptedSystemCalls(const [
        CallKitParams(id: 'c9', nameCaller: 'Mita', isAccepted: true),
      ]);

      expect(accepted.single.callId, 'c9');
      expect(accepted.single.callerName, 'Mita');
      expect(accepted.single.callerId, '');
      expect(accepted.single.isVideo, isFalse);
    });
  });
}
