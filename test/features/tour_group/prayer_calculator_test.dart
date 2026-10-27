import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/features/tour_group/domain/services/prayer_calculator.dart';

void main() {
  group('PrayerCalculator', () {
    test('calculateQibla computes compass bearing towards Makkah accurately for Bangladesh', () {
      // Dhaka coordinates: 23.8103° N, 90.4125° E
      final qibla = PrayerCalculator.calculateQibla(23.8103, 90.4125);
      // Expected Qibla from Dhaka is ~277° (West-Northwest)
      expect(qibla, greaterThanOrEqualTo(270.0));
      expect(qibla, lessThanOrEqualTo(285.0));
    });

    test('calculate returns properly ordered prayer times for Dhaka', () {
      final date = DateTime(2026, 10, 27);
      final schedule = PrayerCalculator.calculate(
        latitude: 23.8103,
        longitude: 90.4125,
        date: date,
        hanafiAsr: true,
      );

      expect(schedule.fajr.isBefore(schedule.sunrise), isTrue);
      expect(schedule.sunrise.isBefore(schedule.dhuhr), isTrue);
      expect(schedule.dhuhr.isBefore(schedule.asr), isTrue);
      expect(schedule.asr.isBefore(schedule.maghrib), isTrue);
      expect(schedule.maghrib.isBefore(schedule.isha), isTrue);
    });

    test('Hanafi Asr is later than Shafi Asr', () {
      final date = DateTime(2026, 10, 27);
      final hanafi = PrayerCalculator.calculate(
        latitude: 23.8103,
        longitude: 90.4125,
        date: date,
        hanafiAsr: true,
      );
      final shafi = PrayerCalculator.calculate(
        latitude: 23.8103,
        longitude: 90.4125,
        date: date,
        hanafiAsr: false,
      );

      expect(hanafi.asr.isAfter(shafi.asr), isTrue);
    });

    test('nextPrayer identifies the correct upcoming prayer based on current time', () {
      final date = DateTime(2026, 10, 27);
      final schedule = PrayerCalculator.calculate(
        latitude: 23.8103,
        longitude: 90.4125,
        date: date,
      );

      // 1. Before Fajr (e.g. 03:00 AM)
      final earlyMorning = DateTime(2026, 10, 27, 3, 0);
      final next1 = schedule.nextPrayer(earlyMorning);
      expect(next1.key, equals('prayer_fajr'));

      // 2. Midday between Sunrise and Dhuhr (e.g. 10:00 AM)
      final midDay = DateTime(2026, 10, 27, 10, 0);
      final next2 = schedule.nextPrayer(midDay);
      expect(next2.key, equals('prayer_dhuhr'));

      // 3. Late night after Isha (e.g. 23:00 / 11:00 PM)
      final lateNight = DateTime(2026, 10, 27, 23, 0);
      final next3 = schedule.nextPrayer(lateNight);
      expect(next3.key, equals('prayer_fajr'));
      expect(next3.time.day, equals(28)); // Next day's Fajr
    });
  });
}
