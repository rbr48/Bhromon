import 'package:bhromon/features/tour_group/domain/services/journey_alarm_ring.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2027, 1, 13, 22);

  AlarmRing ring({int maxRings = 10, int maxSnoozes = 3}) {
    return AlarmRing(maxRings: maxRings, maxSnoozes: maxSnoozes);
  }

  group('starting', () {
    test('an alarm that has not begun is idle and silent', () {
      final r = ring();
      expect(r.status, RingStatus.idle);
      expect(
        r.advance(t0.add(const Duration(minutes: 5))),
        RingSound.none,
      );
      expect(r.status, RingStatus.idle);
    });

    test('begin starts the first ring, and only once', () {
      final r = ring();
      expect(r.begin(t0), RingSound.start);
      expect(r.status, RingStatus.ringing);
      expect(r.ringsStarted, 1);
      expect(
        r.begin(t0.add(const Duration(seconds: 5))),
        RingSound.none,
      );
      expect(r.ringsStarted, 1);
    });
  });

  group('rings and pauses', () {
    test('a ring lasts 60 seconds, then the alarm waits 60 seconds', () {
      final r = ring()..begin(t0);
      expect(
        r.advance(t0.add(const Duration(seconds: 59))),
        RingSound.none,
      );
      expect(
        r.advance(t0.add(const Duration(seconds: 60))),
        RingSound.stop,
      );
      expect(r.status, RingStatus.waiting);
      expect(r.nextRingAt, t0.add(const Duration(seconds: 120)));
      expect(
        r.advance(t0.add(const Duration(seconds: 119))),
        RingSound.none,
      );
      expect(
        r.advance(t0.add(const Duration(seconds: 120))),
        RingSound.start,
      );
      expect(r.ringsStarted, 2);
    });

    test('after the last ring with no answer, the alarm expires', () {
      final r = ring(maxRings: 2)..begin(t0);
      r.advance(t0.add(const Duration(seconds: 60)));
      r.advance(t0.add(const Duration(seconds: 120)));
      expect(r.ringsStarted, 2);
      expect(
        r.advance(t0.add(const Duration(seconds: 180))),
        RingSound.stop,
      );
      expect(r.status, RingStatus.done);
      expect(r.end, RingEnd.expired);
    });
  });

  group('snooze', () {
    test('a snooze from a ring stops the sound and waits five minutes', () {
      final r = ring()..begin(t0);
      final now = t0.add(const Duration(seconds: 30));
      expect(r.snooze(now), RingSound.stop);
      expect(r.status, RingStatus.snoozed);
      expect(r.nextRingAt, now.add(const Duration(minutes: 5)));
      expect(
        r.advance(now.add(const Duration(minutes: 4, seconds: 59))),
        RingSound.none,
      );
      expect(
        r.advance(now.add(const Duration(minutes: 5))),
        RingSound.start,
      );
      expect(r.snoozesUsed, 1);
    });

    test('snoozes are capped at three', () {
      final r = ring()..begin(t0);
      var now = t0;
      for (var i = 0; i < 3; i++) {
        expect(r.snooze(now), isNotNull, reason: 'snooze ${i + 1}');
        now = now.add(const Duration(minutes: 5));
        r.advance(now);
      }
      expect(r.canSnooze, isFalse);
      expect(r.snooze(now), isNull);
      expect(r.snoozesUsed, 3);
    });

    test('a snooze after the alarm finished is refused', () {
      final r = ring()..begin(t0);
      r.dismiss();
      expect(r.snooze(t0), isNull);
    });
  });

  group('ending', () {
    test('dismiss stops a ringing alarm and records it', () {
      final r = ring()..begin(t0);
      expect(r.dismiss(), RingSound.stop);
      expect(r.status, RingStatus.done);
      expect(r.end, RingEnd.dismissed);
      expect(
        r.advance(t0.add(const Duration(hours: 1))),
        RingSound.none,
      );
    });

    test('I am awake ends a waiting alarm with no sound change', () {
      final r = ring()..begin(t0);
      r.advance(t0.add(const Duration(seconds: 60)));
      expect(r.imAwake(), RingSound.none);
      expect(r.end, RingEnd.awake);
    });

    test('ending twice keeps the first reason', () {
      final r = ring()..begin(t0);
      r.dismiss();
      expect(r.imAwake(), RingSound.none);
      expect(r.end, RingEnd.dismissed);
    });

    test('ending an alarm that has not begun is ignored', () {
      final r = ring();
      expect(r.dismiss(), RingSound.none);
      expect(r.status, RingStatus.idle);
    });
  });
}
