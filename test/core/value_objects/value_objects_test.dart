import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/core/value_objects/diary_visibility.dart';
import 'package:bhromon/core/value_objects/trip_mood.dart';
import 'package:bhromon/core/value_objects/weather_snapshot.dart';

void main() {
  group('DiaryVisibility Tests', () {
    test('returns correct Bangla display labels', () {
      expect(DiaryVisibility.private.label, 'শুধু আমি');
      expect(DiaryVisibility.friends.label, 'বন্ধুরা');
      expect(DiaryVisibility.community.label, 'সবাই');
    });

    test('returns correct English display labels', () {
      expect(DiaryVisibility.private.labelEn, 'Only Me');
      expect(DiaryVisibility.friends.labelEn, 'Friends');
      expect(DiaryVisibility.community.labelEn, 'Everyone');
    });

    test('returns correct UI icons', () {
      expect(DiaryVisibility.private.icon, '🔒');
      expect(DiaryVisibility.friends.icon, '👥');
      expect(DiaryVisibility.community.icon, '🌍');
    });

    test('determines synchronization logic properly', () {
      expect(DiaryVisibility.private.shouldSync, isFalse);
      expect(DiaryVisibility.friends.shouldSync, isTrue);
      expect(DiaryVisibility.community.shouldSync, isTrue);
    });

    test('determines public readability correctly', () {
      expect(DiaryVisibility.private.isPubliclyReadable, isFalse);
      expect(DiaryVisibility.friends.isPubliclyReadable, isFalse);
      expect(DiaryVisibility.community.isPubliclyReadable, isTrue);
    });
  });

  group('TripMood and TripTag Tests', () {
    test('TripMood labels and emojis', () {
      expect(TripMood.adventure.label, 'রোমাঞ্চ');
      expect(TripMood.adventure.emoji, '🏕️');
      expect(TripMood.peaceful.label, 'প্রশান্তি');
      expect(TripMood.peaceful.emoji, '🌿');
    });

    test('TripTag labels', () {
      expect(TripTag.solo.label, '#সোলো');
      expect(TripTag.budget.label, '#কম খরচ');
      expect(TripTag.nature.label, '#প্রকৃতি');
    });
  });

  group('WeatherSnapshot Tests', () {
    const weather = WeatherSnapshot(
      tempC: 28.4,
      emoji: '☀️',
      description: 'Clear sky',
      precipMm: 0.0,
      windKph: 12.0,
      weatherCode: 1000,
      isSafeToVisit: true,
    );

    test('serialization and deserialization', () {
      final json = weather.toJson();
      final decoded = WeatherSnapshot.fromJson(json);
      expect(decoded.tempC, 28.4);
      expect(decoded.emoji, '☀️');
      expect(decoded.description, 'Clear sky');
      expect(decoded.precipMm, 0.0);
      expect(decoded.windKph, 12.0);
      expect(decoded.weatherCode, 1000);
      expect(decoded.isSafeToVisit, isTrue);
    });

    test('extension display strings', () {
      expect(weather.shortDisplay, '☀️ 28°C');
      expect(weather.fullDisplay, '☀️ 28°C · Clear sky');
    });
  });
}
