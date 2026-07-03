import 'package:freezed_annotation/freezed_annotation.dart';

part 'weather_snapshot.freezed.dart';
part 'weather_snapshot.g.dart';

/// Immutable snapshot of weather conditions at the time a diary entry was created.
/// Auto-stamped using [WeatherService] on first block save.
@freezed
class WeatherSnapshot with _$WeatherSnapshot {
  const factory WeatherSnapshot({
    required double tempC,
    required String emoji,
    required String description,
    required double precipMm,
    required double windKph,
    required int weatherCode,
    @Default(false) bool isSafeToVisit,
  }) = _WeatherSnapshot;

  factory WeatherSnapshot.fromJson(Map<String, dynamic> json) =>
      _$WeatherSnapshotFromJson(json);

  factory WeatherSnapshot.fromWeatherData({
    required double tempC,
    required double precipMm,
    required double windKph,
    required int weatherCode,
    required String emoji,
    required String description,
    required bool isSafeToVisit,
  }) =>
      WeatherSnapshot(
        tempC: tempC,
        emoji: emoji,
        description: description,
        precipMm: precipMm,
        windKph: windKph,
        weatherCode: weatherCode,
        isSafeToVisit: isSafeToVisit,
      );
}

extension WeatherSnapshotDisplay on WeatherSnapshot {
  /// Short display string: "☀️ 28°C"
  String get shortDisplay => '$emoji ${tempC.toStringAsFixed(0)}°C';

  /// Full display string: "☀️ 28°C · Clear sky"
  String get fullDisplay => '$emoji ${tempC.toStringAsFixed(0)}°C · $description';
}
