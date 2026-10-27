import 'package:bhromon/features/tour_group/domain/models/channel_models.dart';
import 'package:bhromon/features/tour_group/domain/models/date_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 1, 2, 12);

  Map<String, dynamic> seat(DateTime joinedAt) => {
        'email': 'x@x.com',
        'joinedAt': writeDate(joinedAt),
      };

  group('countSeatedVoiceParticipants', () {
    test('leaves out the person joining, whose old seat is replaced', () {
      final count = countSeatedVoiceParticipants(
        {'me@x.com': seat(now), 'asha@x.com': seat(now)},
        exceptEmail: 'me@x.com',
        now: now,
      );
      expect(count, 1);
    });

    test('counts seats joined recently', () {
      final count = countSeatedVoiceParticipants(
        {
          'asha@x.com': seat(now.subtract(const Duration(hours: 1))),
          'babu@x.com': seat(now.subtract(const Duration(hours: 11))),
        },
        exceptEmail: 'me@x.com',
        now: now,
      );
      expect(count, 2);
    });

    test('ignores seats older than the stale limit, such as a crashed phone',
        () {
      final count = countSeatedVoiceParticipants(
        {
          'asha@x.com': seat(now.subtract(const Duration(hours: 13))),
          'babu@x.com': seat(now.subtract(const Duration(days: 2))),
        },
        exceptEmail: 'me@x.com',
        now: now,
      );
      expect(count, 0);
    });

    test('counts a seat that has no join time', () {
      final count = countSeatedVoiceParticipants(
        {'asha@x.com': <String, dynamic>{}},
        exceptEmail: 'me@x.com',
        now: now,
      );
      expect(count, 1);
    });

    test('a room with the cap of other people is full for a newcomer', () {
      final seats = {
        for (var i = 0; i < kVoiceRoomMaxParticipants; i++)
          'p$i@x.com': seat(now),
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
