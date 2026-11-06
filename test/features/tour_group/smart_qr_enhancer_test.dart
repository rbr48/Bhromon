import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:bhromon/features/tour_group/domain/services/smart_qr_enhancer.dart';

void main() {
  group('SmartQrEnhancer Unit Tests', () {
    test('returns null when given invalid or empty bytes', () {
      final result = SmartQrEnhancer.process(Uint8List(0));
      expect(result, isNull);

      final invalidResult =
          SmartQrEnhancer.process(Uint8List.fromList([1, 2, 3, 4]));
      expect(invalidResult, isNull);
    });

    test(
        'processes and square-crops a synthetic image with high-contrast QR patterns',
        () {
      // Create a 600x1000 simulated phone screenshot: white card with black alternating stripes in the center
      final canvas = img.Image(width: 600, height: 1000);
      img.fill(canvas, color: img.ColorRgb8(240, 240, 240));

      // Draw a simulated QR code in the middle (x: 100 to 500, y: 300 to 700)
      for (var y = 300; y < 700; y += 10) {
        for (var x = 100; x < 500; x += 10) {
          final isBlack = ((x ~/ 10) + (y ~/ 10)) % 2 == 0;
          final color = isBlack
              ? img.ColorRgb8(10, 10, 10)
              : img.ColorRgb8(250, 250, 250);
          img.fillRect(canvas,
              x1: x, y1: y, x2: x + 9, y2: y + 9, color: color);
        }
      }

      final pngBytes = Uint8List.fromList(img.encodePng(canvas));
      final result = SmartQrEnhancer.process(pngBytes);

      expect(result, isNotNull);
      expect(result!.width, equals(SmartQrEnhancer.targetDimension));
      expect(result.height, equals(SmartQrEnhancer.targetDimension));
      expect(result.bytes.isNotEmpty, isTrue);
      expect(result.isAutoCropped, isTrue);
    });

    test('detects bKash provider from magenta brand accents', () {
      // Create a simulated bKash screenshot with magenta header
      final canvas = img.Image(width: 500, height: 800);
      img.fill(canvas, color: img.ColorRgb8(255, 255, 255));

      // Draw bKash magenta bar at top: RGB(226, 19, 110)
      img.fillRect(
        canvas,
        x1: 0,
        y1: 0,
        x2: 499,
        y2: 120,
        color: img.ColorRgb8(226, 19, 110),
      );

      final pngBytes = Uint8List.fromList(img.encodePng(canvas));
      final result = SmartQrEnhancer.process(pngBytes);

      expect(result, isNotNull);
      expect(result!.detectedProvider, equals('bkash'));
    });

    test('detects Nagad provider from orange brand accents', () {
      // Create a simulated Nagad screenshot with orange header
      final canvas = img.Image(width: 500, height: 800);
      img.fill(canvas, color: img.ColorRgb8(255, 255, 255));

      // Draw Nagad orange bar: RGB(247, 147, 30)
      img.fillRect(
        canvas,
        x1: 0,
        y1: 0,
        x2: 499,
        y2: 120,
        color: img.ColorRgb8(247, 147, 30),
      );

      final pngBytes = Uint8List.fromList(img.encodePng(canvas));
      final result = SmartQrEnhancer.process(pngBytes);

      expect(result, isNotNull);
      expect(result!.detectedProvider, equals('nagad'));
    });
  });
}
