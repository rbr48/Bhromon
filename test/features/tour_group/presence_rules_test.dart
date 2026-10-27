import 'package:bhromon/features/tour_group/domain/services/presence_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 1, 2, 12);

  group('isOnlineAt', () {
    test('someone who has never been seen is not online', () {
      expect(isOnlineAt(null, now), isFalse);
    });

    test('someone refreshed within the stale window is online', () {
      expect(
          isOnlineAt(now.subtract(const Duration(seconds: 30)), now), isTrue);
      expect(isOnlineAt(now.subtract(kPresenceStaleAfter), now), isTrue);
    });

    test('someone who has gone quiet past the window is away', () {
      expect(
        isOnlineAt(
            now.subtract(kPresenceStaleAfter + const Duration(seconds: 1)),
            now),
        isFalse,
      );
    });

    test('the heartbeat is shorter than the stale window', () {
      expect(kPresenceHeartbeat < kPresenceStaleAfter, isTrue);
    });
  });
}
