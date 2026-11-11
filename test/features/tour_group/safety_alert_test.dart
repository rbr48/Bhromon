import 'package:bhromon/features/tour_group/domain/models/safety_alert_models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SafetyAlert', () {
    final now = DateTime(2026, 10, 25, 12);

    SafetyAlert raisedAt(DateTime? at, {bool resolved = false}) {
      return SafetyAlert.fromMap('a1', {
        'senderEmail': 'Mem@X.com',
        'senderName': 'Rahim',
        'resolved': resolved,
        'createdAt': at == null ? null : Timestamp.fromDate(at),
      });
    }

    test('reads the sender with the email case-folded', () {
      final alert = raisedAt(now);
      expect(alert.senderEmail, 'mem@x.com');
      expect(alert.senderName, 'Rahim');
    });

    test('keeps the location when one was sent, and has none otherwise', () {
      final withLocation = SafetyAlert.fromMap('a2', {
        'senderEmail': 'mem@x.com',
        'latitude': 23.4,
        'longitude': 92.3,
      });
      expect(withLocation.latitude, 23.4);
      expect(withLocation.longitude, 92.3);

      final without = raisedAt(now);
      expect(without.latitude, isNull);
      expect(without.longitude, isNull);
    });

    test('a fresh alert is open', () {
      expect(raisedAt(now.subtract(const Duration(minutes: 5))).isOpenAt(now),
          isTrue);
    });

    test('an alert older than the window is no longer open', () {
      expect(raisedAt(now.subtract(const Duration(hours: 7))).isOpenAt(now),
          isFalse);
    });

    test('the window edge closes the alert, the minute before keeps it open',
        () {
      expect(
        raisedAt(now.subtract(kSafetyAlertWindow - const Duration(minutes: 1)))
            .isOpenAt(now),
        isTrue,
      );
      expect(raisedAt(now.subtract(kSafetyAlertWindow)).isOpenAt(now), isFalse);
    });

    test('a resolved alert is closed whatever its age', () {
      expect(raisedAt(now, resolved: true).isOpenAt(now), isFalse);
    });

    test('an alert whose server time is still pending counts as open', () {
      expect(raisedAt(null).isOpenAt(now), isTrue);
    });
  });

  group('reading alerts that may be malformed', () {
    test('a text latitude is left out, and the alert is kept', () {
      final alert = SafetyAlert.fromMap('a1', {
        'senderEmail': 'ana@x.com',
        'senderName': 'Ana',
        'resolved': false,
        'latitude': 'north',
        'longitude': 90.4,
      });
      expect(alert.latitude, isNull);
      expect(alert.longitude, 90.4);
      expect(alert.senderEmail, 'ana@x.com');
    });

    test('a coordinate outside the earth is left out', () {
      final alert = SafetyAlert.fromMap('a1', {
        'senderEmail': 'ana@x.com',
        'latitude': 23.8,
        'longitude': 200,
      });
      expect(alert.latitude, 23.8);
      expect(alert.longitude, isNull);
    });

    test('a name that is not text reads as no name, so the default shows', () {
      final alert = SafetyAlert.fromMap('a1', {
        'senderEmail': 'ana@x.com',
        'senderName': 42,
      });
      expect(alert.senderName, 'সদস্য');
    });

    test('a resolved flag that is not a boolean reads as open', () {
      final alert = SafetyAlert.fromMap('a1', {
        'senderEmail': 'ana@x.com',
        'resolved': 'true',
      });
      expect(alert.resolved, isFalse);
    });

    test('one bad document does not hide the others in a snapshot', () {
      final alerts = parseSafetyAlerts([
        const MapEntry(
            'good', {'senderEmail': 'ana@x.com', 'senderName': 'Ana'}),
        const MapEntry('no-sender', {'senderName': 'Ghost', 'latitude': 'x'}),
        const MapEntry('bad-type', {'senderEmail': 42, 'senderName': 'Odd'}),
        const MapEntry('good-2', {'senderEmail': 'bob@x.com', 'latitude': 'x'}),
      ]);
      expect(alerts.map((a) => a.id), ['good', 'good-2']);
    });

    test('an empty snapshot gives an empty list', () {
      expect(parseSafetyAlerts(const []), isEmpty);
    });
  });

  group('BatteryTelemetry', () {
    test('parses telemetry and flags low and critical battery accurately', () {
      final healthy = BatteryTelemetry.fromMap({
        'email': 'Alice@Example.com',
        'name': 'Alice',
        'batteryLevel': 65,
        'isCharging': true,
        'latitude': 23.81,
        'longitude': 90.41,
      });

      expect(healthy.email, equals('alice@example.com'));
      expect(healthy.name, equals('Alice'));
      expect(healthy.batteryLevel, equals(65));
      expect(healthy.isCharging, isTrue);
      expect(healthy.isLowBattery, isFalse);
      expect(healthy.isCriticalBattery, isFalse);

      final low = BatteryTelemetry.fromMap({
        'email': 'bob@example.com',
        'name': 'Bob',
        'batteryLevel': 18,
        'isCharging': false,
      });
      expect(low.isLowBattery, isTrue);
      expect(low.isCriticalBattery, isFalse);

      final critical = BatteryTelemetry.fromMap({
        'email': 'charlie@example.com',
        'name': 'Charlie',
        'batteryLevel': 8,
        'isCharging': false,
      });
      expect(critical.isLowBattery, isTrue);
      expect(critical.isCriticalBattery, isTrue);
    });

    test('serializes to Map correctly', () {
      final t = BatteryTelemetry(
        email: 'User@Test.com',
        name: 'Tester',
        batteryLevel: 45,
        isCharging: true,
        latitude: 21.42,
        longitude: 39.82,
        updatedAt: DateTime(2026, 10, 27, 10),
      );

      final map = t.toMap();
      expect(map['email'], equals('user@test.com'));
      expect(map['name'], equals('Tester'));
      expect(map['batteryLevel'], equals(45));
      expect(map['isCharging'], isTrue);
      expect(map['latitude'], equals(21.42));
      expect(map['longitude'], equals(39.82));
      expect(map['updatedAt'], isA<Timestamp>());
    });
  });
}
