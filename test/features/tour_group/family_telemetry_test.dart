import 'package:bhromon/features/tour_group/domain/models/safety_alert_models.dart';
import 'package:bhromon/features/tour_group/domain/services/family_telemetry_publisher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceBattery', () {
    test('a level from 0 to 100 is kept with the charging state', () {
      final b = DeviceBattery.reading(level: 64, isCharging: true);
      expect(b.level, 64);
      expect(b.isCharging, isTrue);
      expect(DeviceBattery.reading(level: 0, isCharging: false).level, 0);
      expect(DeviceBattery.reading(level: 100, isCharging: false).level, 100);
    });

    test('a missing or out-of-range level is unknown, never a number', () {
      expect(DeviceBattery.reading(level: null, isCharging: true),
          DeviceBattery.unknown);
      expect(DeviceBattery.reading(level: -1, isCharging: false),
          DeviceBattery.unknown);
      expect(DeviceBattery.reading(level: 101, isCharging: false),
          DeviceBattery.unknown);
      expect(DeviceBattery.unknown.level, isNull);
    });

    test('readings compare by value, so unchanged ones are not written', () {
      expect(DeviceBattery.reading(level: 40, isCharging: false),
          DeviceBattery.reading(level: 40, isCharging: false));
      expect(
        DeviceBattery.reading(level: 40, isCharging: false) ==
            DeviceBattery.reading(level: 40, isCharging: true),
        isFalse,
      );
    });
  });

  group('FamilyTelemetryPublisher', () {
    late List<FamilyTelemetryWrite> writes;
    late List<Object> errors;
    late FamilyTelemetryPublisher publisher;
    final t0 = DateTime(2026, 10, 31, 10);

    setUp(() {
      writes = [];
      errors = [];
      publisher = FamilyTelemetryPublisher(
        sink: (write) async => writes.add(write),
        onError: (error, _) => errors.add(error),
      );
    });

    test('a new battery reading is written once, and an equal one is not',
        () async {
      final battery = DeviceBattery.reading(level: 70, isCharging: false);
      await publisher.onBattery(battery, t0);
      await publisher.onBattery(battery, t0.add(const Duration(seconds: 5)));

      expect(writes, hasLength(1));
      expect(writes.single.battery.level, 70);
      expect(writes.single.sharing, isFalse);
      expect(writes.single.latitude, isNull);
    });

    test('a position is ignored while the place is not shared', () async {
      await publisher.onFix(const PositionFix(23.8, 90.4), t0);
      expect(writes, isEmpty);
    });

    test(
        'turning sharing on writes at once, and the place follows the next fix',
        () async {
      await publisher.setSharingLocation(true, t0);
      expect(writes.single.sharing, isTrue);
      expect(writes.single.latitude, isNull, reason: 'no fix yet');

      // A fix straight after the switch waits out the minimum gap.
      await publisher.onFix(const PositionFix(23.8103, 90.4125),
          t0.add(const Duration(seconds: 20)));
      expect(writes, hasLength(2));
      expect(writes.last.latitude, 23.8103);
      expect(writes.last.longitude, 90.4125);
    });

    test(
        'positions are throttled to one write per minimum gap, and the last one waits',
        () async {
      await publisher.setSharingLocation(true, t0);
      await publisher.onFix(const PositionFix(1, 1), t0);
      final afterFirst = writes.length;

      // Inside the gap: held back.
      await publisher.onFix(
          const PositionFix(2, 2), t0.add(const Duration(seconds: 5)));
      expect(writes.length, afterFirst);

      // A tick after the gap writes the waiting position.
      await publisher.tick(t0.add(const Duration(seconds: 16)));
      expect(writes.last.latitude, 2);
    });

    test('a heartbeat refreshes an unchanged record only when it is due',
        () async {
      await publisher.onBattery(
          DeviceBattery.reading(level: 80, isCharging: false), t0);
      final count = writes.length;

      await publisher.tick(t0.add(const Duration(minutes: 1)));
      expect(writes.length, count, reason: 'not due yet');

      await publisher.tick(t0.add(const Duration(minutes: 2)));
      expect(writes.length, count + 1);
    });

    test('turning sharing off clears the stored place and ignores later fixes',
        () async {
      await publisher.setSharingLocation(true, t0);
      await publisher.onFix(const PositionFix(23.8, 90.4), t0);

      await publisher.setSharingLocation(
          false, t0.add(const Duration(minutes: 1)));
      final off = writes.last;
      expect(off.sharing, isFalse);
      expect(off.latitude, isNull);
      expect(off.longitude, isNull);

      final count = writes.length;
      await publisher.onFix(
          const PositionFix(1, 1), t0.add(const Duration(minutes: 2)));
      expect(writes.length, count);
      expect(publisher.isSharingLocation, isFalse);
    });

    test(
        'reset writes "not sharing" with the battery read, clearing a place left '
        'from an earlier visit in one write', () async {
      final battery = DeviceBattery.reading(level: 33, isCharging: true);
      await publisher.reset(battery, t0);
      expect(writes, hasLength(1));
      expect(writes.single.sharing, isFalse);
      expect(writes.single.latitude, isNull);
      expect(writes.single.battery, battery);
    });

    test('stop ends sharing, and does nothing when it was not sharing',
        () async {
      await publisher.stop(t0);
      expect(writes, isEmpty);

      await publisher.setSharingLocation(true, t0);
      await publisher.stop(t0.add(const Duration(minutes: 1)));
      expect(writes.last.sharing, isFalse);
    });

    test('a failed write is reported and does not stop later writes', () async {
      var fail = true;
      final flaky = FamilyTelemetryPublisher(
        sink: (write) async {
          if (fail) throw StateError('offline');
          writes.add(write);
        },
        onError: (error, _) => errors.add(error),
      );

      await flaky.onBattery(
          DeviceBattery.reading(level: 50, isCharging: false), t0);
      expect(errors.single, isA<StateError>());
      expect(writes, isEmpty);

      fail = false;
      await flaky.tick(t0.add(const Duration(minutes: 2)));
      expect(writes, hasLength(1));
    });
  });

  group('locationStatusAt', () {
    final now = DateTime(2026, 10, 31, 12);

    BatteryTelemetry record({
      bool sharing = true,
      double? latitude = 23.8,
      double? longitude = 90.4,
      Duration? age,
    }) {
      return BatteryTelemetry(
        email: 'a@example.com',
        name: 'A',
        sharing: sharing,
        latitude: latitude,
        longitude: longitude,
        updatedAt: age == null ? null : now.subtract(age),
      );
    }

    test('a place updated within six minutes is live', () {
      expect(locationStatusAt(record(age: const Duration(minutes: 5)), now),
          LocationStatus.live);
    });

    test('an older place is shown as last known, up to twelve hours', () {
      expect(locationStatusAt(record(age: const Duration(minutes: 30)), now),
          LocationStatus.lastKnown);
      expect(locationStatusAt(record(age: const Duration(hours: 11)), now),
          LocationStatus.lastKnown);
    });

    test('a place older than twelve hours is not shown', () {
      expect(locationStatusAt(record(age: const Duration(hours: 13)), now),
          LocationStatus.off);
    });

    test('nothing is shown when the member is not sharing', () {
      expect(
        locationStatusAt(
            record(sharing: false, age: const Duration(minutes: 1)), now),
        LocationStatus.off,
      );
    });

    test('nothing is shown without coordinates or a time', () {
      expect(
        locationStatusAt(
            record(latitude: null, age: const Duration(minutes: 1)), now),
        LocationStatus.off,
      );
      expect(locationStatusAt(record(), now), LocationStatus.off);
    });

    test('a clock slightly ahead of this phone still counts as live', () {
      expect(locationStatusAt(record(age: const Duration(minutes: -2)), now),
          LocationStatus.live);
    });
  });

  group('BatteryTelemetry.fromMap for the family record', () {
    test(
        'an unknown battery is null, not a default, and an out-of-range one too',
        () {
      expect(
          BatteryTelemetry.fromMap({'email': 'a@x.com', 'name': 'A'})
              .batteryLevel,
          isNull);
      expect(
        BatteryTelemetry.fromMap({
          'email': 'a@x.com',
          'name': 'A',
          'batteryLevel': 250,
        }).batteryLevel,
        isNull,
      );
    });

    test('the sharing flag is read, and defaults to off', () {
      expect(
          BatteryTelemetry.fromMap({'email': 'a@x.com', 'name': 'A'}).sharing,
          isFalse);
      expect(
        BatteryTelemetry.fromMap({
          'email': 'a@x.com',
          'name': 'A',
          'sharing': true,
        }).sharing,
        isTrue,
      );
    });

    test('an unknown battery is never flagged as low', () {
      final t = BatteryTelemetry.fromMap({'email': 'a@x.com', 'name': 'A'});
      expect(t.isLowBattery, isFalse);
      expect(t.isCriticalBattery, isFalse);
    });
  });
}
