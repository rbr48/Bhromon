import 'package:bhromon/features/tour_group/domain/services/journey_trip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2027, 1, 13, 20);

  group('starting and ending', () {
    test('start makes a trip active, with sharing off', () {
      final life = JourneyTripLifecycle();
      final trip = life.start(id: 'trip-1', tourId: 'tour-1', now: t0);
      expect(life.active, same(trip));
      expect(trip.sharing, isFalse);
      expect(trip.startedAt, t0);
    });

    test('a second start returns the running trip unchanged', () {
      final life = JourneyTripLifecycle();
      final first = life.start(id: 'trip-1', tourId: 'tour-1', now: t0);
      final second = life.start(
        id: 'trip-2',
        tourId: 'tour-2',
        now: t0.add(const Duration(hours: 1)),
      );
      expect(second.id, 'trip-1');
      expect(identical(second, first), isTrue);
    });

    test('end returns the trip and clears it', () {
      final life = JourneyTripLifecycle()
        ..start(id: 'trip-1', tourId: 'tour-1', now: t0);
      expect(life.end()?.id, 'trip-1');
      expect(life.active, isNull);
      expect(life.end(), isNull);
    });
  });

  group('readings and sharing', () {
    test('a reading counts only while a trip runs', () {
      final life = JourneyTripLifecycle();
      expect(life.recordReading(t0), isFalse);
      life.start(id: 'trip-1', tourId: 'tour-1', now: t0);
      final later = t0.add(const Duration(hours: 5));
      expect(life.recordReading(later), isTrue);
      expect(life.active!.lastReadingAt, later);
    });

    test('sharing can be switched only on a running trip', () {
      final life = JourneyTripLifecycle();
      expect(life.setSharing(on: true), isFalse);
      life.start(id: 'trip-1', tourId: 'tour-1', now: t0);
      expect(life.setSharing(on: true), isTrue);
      expect(life.active!.sharing, isTrue);
      expect(life.setSharing(on: false), isTrue);
      expect(life.active!.sharing, isFalse);
    });
  });

  group('the idle limit', () {
    test('a trip stays live just under 36 hours without a reading', () {
      final life = JourneyTripLifecycle()
        ..start(id: 'trip-1', tourId: 'tour-1', now: t0);
      final justUnder = t0.add(const Duration(hours: 35, minutes: 59));
      expect(life.endIfIdle(justUnder), isNull);
      expect(life.active, isNotNull);
    });

    test('a trip ends itself at 36 hours without a reading', () {
      final life = JourneyTripLifecycle()
        ..start(id: 'trip-1', tourId: 'tour-1', now: t0);
      final ended = life.endIfIdle(t0.add(const Duration(hours: 36)));
      expect(ended?.id, 'trip-1');
      expect(life.active, isNull);
    });

    test('a reading resets the idle clock', () {
      final life = JourneyTripLifecycle()
        ..start(id: 'trip-1', tourId: 'tour-1', now: t0);
      life.recordReading(t0.add(const Duration(hours: 30)));
      expect(life.endIfIdle(t0.add(const Duration(hours: 36))), isNull);
      expect(life.endIfIdle(t0.add(const Duration(hours: 66))), isNotNull);
    });

    test('nothing ends when no trip runs', () {
      expect(JourneyTripLifecycle().endIfIdle(t0), isNull);
    });
  });

  group('restoring and storing', () {
    test('a restored trip still applies the idle rule', () {
      final life = JourneyTripLifecycle()
        ..restore(JourneyTrip(
          id: 'trip-1',
          tourId: 'tour-1',
          startedAt: t0,
          lastReadingAt: t0,
        ));
      expect(life.active, isNotNull);
      expect(life.endIfIdle(t0.add(const Duration(hours: 40))), isNotNull);
    });

    test('a trip survives a round trip through its map', () {
      final trip = JourneyTrip(
        id: 'trip-1',
        tourId: 'tour-1',
        startedAt: t0,
        lastReadingAt: t0.add(const Duration(minutes: 5)),
        sharing: true,
      );
      final back = JourneyTrip.fromMap(trip.toMap());
      expect(back, isNotNull);
      expect(back!.id, 'trip-1');
      expect(back.tourId, 'tour-1');
      expect(back.startedAt, t0);
      expect(back.lastReadingAt, t0.add(const Duration(minutes: 5)));
      expect(back.sharing, isTrue);
    });

    test('a damaged map is ignored rather than thrown', () {
      expect(JourneyTrip.fromMap({'id': 'x'}), isNull);
      expect(
        JourneyTrip.fromMap({
          'id': 1,
          'tourId': 't',
          'startedAt': 1,
          'lastReadingAt': 1,
          'sharing': false,
        }),
        isNull,
      );
    });
  });
}
