import 'dart:math';

/// Offline Solar & Prayer Times Engine with Qibla compass bearing calculation.
///
/// Implements standard astronomical algorithms (University of Islamic Sciences,
/// Karachi convention - 18° twilight angle, standard for South Asia & Bangladesh).
class PrayerCalculator {
  const PrayerCalculator._();

  static const double _makkahLat = 21.422487;
  static const double _makkahLng = 39.826206;

  /// Calculates the Qibla direction in degrees clockwise from True North (0° - 360°).
  static double calculateQibla(double latitude, double longitude) {
    final latRad = _degToRad(latitude);
    final lngRad = _degToRad(longitude);
    final mLatRad = _degToRad(_makkahLat);
    final mLngRad = _degToRad(_makkahLng);

    final dLng = mLngRad - lngRad;
    final y = sin(dLng);
    final x = cos(latRad) * tan(mLatRad) - sin(latRad) * cos(dLng);
    final qiblaRad = atan2(y, x);
    final qiblaDeg = _radToDeg(qiblaRad);

    return (qiblaDeg + 360.0) % 360.0;
  }

  /// Calculates daily prayer times and Qibla direction for a given [date] and coordinates.
  ///
  /// [hanafiAsr]: If true, uses Hanafi school (shadow length 2x). Defaults to true (standard in BD).
  static PrayerSchedule calculate({
    required double latitude,
    required double longitude,
    required DateTime date,
    bool hanafiAsr = true,
  }) {
    final tzOffset = date.timeZoneOffset.inMinutes / 60.0;
    final julianDay = _julianDay(date.year, date.month, date.day);
    final d = julianDay - 2451545.0;

    // Mean anomaly and solar coordinates
    final m = _degToRad((357.5291 + 0.98560028 * d) % 360.0);
    final c = 1.9148 * sin(m) + 0.0200 * sin(2 * m) + 0.0003 * sin(3 * m);
    final l0 = (280.4665 + 0.98564736 * d) % 360.0;
    final lambdaSun = _degToRad((l0 + c) % 360.0);

    final epsilon = _degToRad(23.439 - 0.00000036 * d);
    final delta = asin(sin(epsilon) * sin(lambdaSun));
    final alpha = atan2(cos(epsilon) * sin(lambdaSun), cos(lambdaSun));

    // Equation of Time in hours
    final alphaDeg = (_radToDeg(alpha) + 360.0) % 360.0;
    final eot = (_degToRad(l0) - _degToRad(alphaDeg)) / _degToRad(15.0);

    // Solar noon (Dhuhr)
    final dhuhrHour = 12.0 + tzOffset - (longitude / 15.0) - eot;

    // Hour angle helper
    double? hourAngle(double altitude) {
      final latRad = _degToRad(latitude);
      final altRad = _degToRad(altitude);
      final cosOmega = (sin(altRad) - sin(latRad) * sin(delta)) /
          (cos(latRad) * cos(delta));
      if (cosOmega < -1.0 || cosOmega > 1.0) return null;
      return _radToDeg(acos(cosOmega));
    }

    // 18 degrees twilight angle for Karachi method
    final fajrAngle = hourAngle(-18.0) ?? 90.0;
    final sunriseAngle = hourAngle(-0.833) ?? 90.0;

    // Asr calculation
    final shadowFactor = hanafiAsr ? 2.0 : 1.0;
    final latRad = _degToRad(latitude);
    final asrAltRad = atan(1.0 / (shadowFactor + tan((latRad - delta).abs())));
    final asrAltDeg = _radToDeg(asrAltRad);
    final asrAngle = hourAngle(asrAltDeg) ?? 45.0;

    final maghribAngle = sunriseAngle;
    final ishaAngle = hourAngle(-18.0) ?? 90.0;

    DateTime toDate(double decimalHours) {
      final clamped = decimalHours % 24.0;
      final totalSeconds = (clamped * 3600).round();
      final h = (totalSeconds ~/ 3600) % 24;
      final m = (totalSeconds % 3600) ~/ 60;
      final s = totalSeconds % 60;
      return DateTime(date.year, date.month, date.day, h, m, s);
    }

    final fajr = toDate(dhuhrHour - (fajrAngle / 15.0));
    final sunrise = toDate(dhuhrHour - (sunriseAngle / 15.0));
    final dhuhr = toDate(dhuhrHour);
    final asr = toDate(dhuhrHour + (asrAngle / 15.0));
    final maghrib = toDate(dhuhrHour + (maghribAngle / 15.0));
    final isha = toDate(dhuhrHour + (ishaAngle / 15.0));
    final qibla = calculateQibla(latitude, longitude);

    return PrayerSchedule(
      fajr: fajr,
      sunrise: sunrise,
      dhuhr: dhuhr,
      asr: asr,
      maghrib: maghrib,
      isha: isha,
      qiblaBearing: qibla,
    );
  }

  static double _julianDay(int year, int month, int day) {
    if (month <= 2) {
      year -= 1;
      month += 12;
    }
    final a = (year / 100).floor();
    final b = 2 - a + (a / 4).floor();
    return (365.25 * (year + 4716)).floor() +
        (30.6001 * (month + 1)).floor() +
        day +
        b -
        1524.5;
  }

  static double _degToRad(double deg) => deg * (pi / 180.0);
  static double _radToDeg(double rad) => rad * (180.0 / pi);
}

class PrayerSchedule {
  final DateTime fajr;
  final DateTime sunrise;
  final DateTime dhuhr;
  final DateTime asr;
  final DateTime maghrib;
  final DateTime isha;
  final double qiblaBearing;

  const PrayerSchedule({
    required this.fajr,
    required this.sunrise,
    required this.dhuhr,
    required this.asr,
    required this.maghrib,
    required this.isha,
    required this.qiblaBearing,
  });

  /// Returns the next upcoming prayer or Fajr tomorrow if all have passed.
  ({String key, String defaultName, DateTime time, Duration remaining}) nextPrayer(
      [DateTime? now]) {
    final current = now ?? DateTime.now();

    final prayers = [
      (key: 'prayer_fajr', defaultName: 'Fajr', time: fajr),
      (key: 'prayer_sunrise', defaultName: 'Sunrise', time: sunrise),
      (key: 'prayer_dhuhr', defaultName: 'Dhuhr', time: dhuhr),
      (key: 'prayer_asr', defaultName: 'Asr', time: asr),
      (key: 'prayer_maghrib', defaultName: 'Maghrib', time: maghrib),
      (key: 'prayer_isha', defaultName: 'Isha', time: isha),
    ];

    for (final p in prayers) {
      if (p.time.isAfter(current)) {
        return (
          key: p.key,
          defaultName: p.defaultName,
          time: p.time,
          remaining: p.time.difference(current),
        );
      }
    }

    // After Isha: next is Fajr tomorrow
    final nextFajr = fajr.add(const Duration(days: 1));
    return (
      key: 'prayer_fajr',
      defaultName: 'Fajr',
      time: nextFajr,
      remaining: nextFajr.difference(current),
    );
  }
}
