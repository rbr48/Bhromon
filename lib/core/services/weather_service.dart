import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:bhromon/app/di/injection.dart';
import 'package:bhromon/core/network/secure_network_client.dart';

/// Free weather data from Open-Meteo (no API key required)
class WeatherService {
  static const String _base = 'https://api.open-meteo.com/v1';

  /// Returns current weather for the given coordinates.
  /// Returns null on failure (graceful degradation).
  static Future<WeatherData?> getCurrentWeather(double lat, double lng) async {
    try {
      final uri = Uri.parse(
        '$_base/forecast?latitude=$lat&longitude=$lng'
        '&current=temperature_2m,precipitation,weathercode,windspeed_10m'
        '&timezone=Asia%2FDhaka',
      );
      final secureClient = getIt<SecureNetworkClient>();
      final res = await secureClient.dio.getUri<dynamic>(
        uri,
        options: Options(
          sendTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 6),
        ),
      );
      if (res.statusCode != 200) return null;
      final json = res.data is Map<String, dynamic>
          ? res.data as Map<String, dynamic>
          : jsonDecode(res.data.toString()) as Map<String, dynamic>;
      final current = json['current'] as Map<String, dynamic>;
      return WeatherData(
        tempC: (current['temperature_2m'] as num).toDouble(),
        precipMm: (current['precipitation'] as num).toDouble(),
        windKph: (current['windspeed_10m'] as num).toDouble(),
        code: (current['weathercode'] as num).toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  static String bestMonthsToVisit() {
    // Best = Nov–Feb (dry season in Bangladesh)
    return 'Nov – Feb (dry season)';
  }

  /// Flood risk level based on precipitation
  static FloodRisk floodRisk(double precipMm) {
    if (precipMm <= 5) return FloodRisk.none;
    if (precipMm <= 20) return FloodRisk.low;
    if (precipMm <= 50) return FloodRisk.medium;
    return FloodRisk.high;
  }
}

enum FloodRisk { none, low, medium, high }

class WeatherData {
  final double tempC;
  final double precipMm;
  final double windKph;
  final int code;

  const WeatherData({
    required this.tempC,
    required this.precipMm,
    required this.windKph,
    required this.code,
  });

  String get emoji {
    if (code == 0) return '☀️';
    if (code <= 3) return '⛅';
    if (code <= 49) return '🌫️';
    if (code <= 67) return '🌧️';
    if (code <= 77) return '❄️';
    if (code <= 82) return '🌦️';
    if (code <= 99) return '⛈️';
    return '🌤️';
  }

  String get description {
    if (code == 0) return 'Clear sky';
    if (code <= 3) return 'Partly cloudy';
    if (code <= 49) return 'Foggy';
    if (code <= 67) return 'Rainy';
    if (code <= 77) return 'Snowy';
    if (code <= 82) return 'Showers';
    if (code <= 99) return 'Thunderstorm';
    return 'Cloudy';
  }

  bool get isSafeToVisit => precipMm <= 20 && code < 80;
}
