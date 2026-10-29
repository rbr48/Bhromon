import 'package:bhromon/features/tour_group/domain/models/channel_models.dart';
import 'package:bhromon/features/tour_group/domain/models/date_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 1, 2, 12);

  /// A seat whose phone last refreshed it [age] ago.
  Map<String, dynamic> seen(Duration age) => {
        'email': 'x@x.com',
        'lastSeenAt': writeDate(now.subtract(age)),
      };

  group('isVoiceSeatLive', () {
    test('a seat refreshed within the stale limit is live', () {
      expect(isVoiceSeatLive(seen(Duration.zero), now: now), isTrue);
      expect(isVoiceSeatLive(seen(kVoiceSeatStaleAfter), now: now), isTrue);
    });

    test('a seat not refreshed for longer than the limit is not live', () {
      expect(
        isVoiceSeatLive(
          seen(kVoiceSeatStaleAfter + const Duration(seconds: 1)),
          now: now,
        ),
        isFalse,
      );
    });

    test('a seat with no heartbeat is not live', () {
      expect(isVoiceSeatLive(<String, dynamic>{}, now: now), isFalse);
    });
  });

  group('countSeatedVoiceParticipants', () {
    test('leaves out the person joining, whose old seat is replaced', () {
      final count = countSeatedVoiceParticipants(
        {'me@x.com': seen(Duration.zero), 'asha@x.com': seen(Duration.zero)},
        exceptEmail: 'me@x.com',
        now: now,
      );
      expect(count, 1);
    });

    test('counts seats that were refreshed recently', () {
      final count = countSeatedVoiceParticipants(
        {
          'asha@x.com': seen(const Duration(seconds: 45)),
          'babu@x.com': seen(const Duration(minutes: 2)),
        },
        exceptEmail: 'me@x.com',
        now: now,
      );
      expect(count, 2);
    });

    test('ignores a seat whose phone crashed and stopped refreshing', () {
      final count = countSeatedVoiceParticipants(
        {
          'asha@x.com': seen(const Duration(minutes: 4)),
          'babu@x.com': seen(const Duration(days: 2)),
        },
        exceptEmail: 'me@x.com',
        now: now,
      );
      expect(count, 0);
    });

    test('a room with the cap of other people is full for a newcomer', () {
      final seats = {
        for (var i = 0; i < kVoiceRoomMaxParticipants; i++)
          'p$i@x.com': seen(Duration.zero),
      };
      final count = countSeatedVoiceParticipants(
        seats,
        exceptEmail: 'me@x.com',
        now: now,
      );
      expect(count >= kVoiceRoomMaxParticipants, isTrue);
    });
  });
}
