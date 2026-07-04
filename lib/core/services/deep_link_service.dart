import 'package:share_plus/share_plus.dart';
import '../entities/location_pin.dart';

/// Deep link and sharing service for Bhromon pins
class DeepLinkService {
  static const String _baseUrl = 'https://app.bhromon.fun';

  /// Generates a shareable URL for a pin
  static String pinUrl(LocationPin pin) {
    final slug = pin.name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return '$_baseUrl/pin/$slug?id=${pin.pinId}';
  }

  /// Share a pin via native share sheet
  static Future<void> sharePin(LocationPin pin) async {
    final url = pinUrl(pin);
    final message = '🗺️ Check out ${pin.name} on Bhromon!\n'
        '📍 ${pin.district}, ${pin.division}\n'
        '${pin.description != null ? '${pin.description!.substring(0, pin.description!.length.clamp(0, 100))}...\n' : ''}'
        '\n$url\n\n'
        'Download Bhromon: $_baseUrl/downloads/bhromon-latest.apk';
    await SharePlus.instance.share(
        ShareParams(text: message, subject: 'Explore ${pin.name} on Bhromon'));
  }

  /// Share a trip log
  static Future<void> shareLog({
    required String title,
    required String pinName,
    required String district,
    required String logId,
  }) async {
    final url = '$_baseUrl/log/$logId';
    final message = '📖 Travel Log: "$title"\n'
        '📍 $pinName, $district\n\n'
        'Read it on Bhromon: $url';
    await SharePlus.instance.share(ShareParams(text: message, subject: title));
  }

  /// Parse a deep link and extract pin ID
  static String? extractPinId(Uri uri) {
    if (!uri.host.contains('bhromon')) return null;
    if (uri.path.startsWith('/pin/')) {
      return uri.queryParameters['id'];
    }
    return null;
  }
}
