import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Result of processing and enhancing a QR image.
class EnhancedQrResult {
  const EnhancedQrResult({
    required this.bytes,
    required this.width,
    required this.height,
    required this.isAutoCropped,
    this.detectedProvider,
  });

  /// The final, cropped, contrast-enhanced and optimized JPEG image bytes.
  final Uint8List bytes;

  /// Width of the output image in pixels (typically 800).
  final int width;

  /// Height of the output image in pixels (typically 800).
  final int height;

  /// Whether the enhancer successfully detected a QR bounding box and auto-cropped it.
  final bool isAutoCropped;

  /// Inferred provider ('bkash', 'nagad', 'rocket', 'upay', 'cellfin', 'bank')
  /// detected from signature brand accent colors in the uploaded screenshot.
  final String? detectedProvider;
}

/// Intelligent on-device image processing for payment and Bangla QR codes.
///
/// Automatically:
/// 1. Bakes EXIF orientation.
/// 2. Analyzes high-contrast transition density to pinpoint the square QR matrix.
/// 3. Crops away phone status bars, navigation bars, and irrelevant app chrome.
/// 4. Adds a standard quiet zone (white border) required for 100% scan reliability.
/// 5. Normalizes contrast (crisp pure white background, deep dark modules).
/// 6. Auto-detects MFS provider (bKash, Nagad, Rocket, Upay, CellFin) from brand color accents.
/// 7. Compresses to an ultra-light ~60-100KB 800x800 JPEG for instant load on mobile/web.
class SmartQrEnhancer {
  const SmartQrEnhancer._();

  static const int targetDimension = 800;
  static const int outputQuality = 85;

  /// Processes raw image bytes and returns an enhanced, cropped, and optimized QR result.
  static EnhancedQrResult? process(Uint8List rawBytes) {
    try {
      var image = img.decodeImage(rawBytes);
      if (image == null) return null;

      image = img.bakeOrientation(image);

      final provider = _detectBrandProvider(image);
      final cropBox = _findQrBoundingBox(image);

      img.Image cropped;
      bool autoCropped = false;

      if (cropBox != null) {
        cropped = img.copyCrop(
          image,
          x: cropBox.x,
          y: cropBox.y,
          width: cropBox.width,
          height: cropBox.height,
        );
        autoCropped = true;
      } else {
        // Fallback: Center square crop
        final size = math.min(image.width, image.height);
        final startX = (image.width - size) ~/ 2;
        final startY = (image.height - size) ~/ 2;
        cropped = img.copyCrop(
          image,
          x: startX,
          y: startY,
          width: size,
          height: size,
        );
      }

      // Add quiet zone margin (white border)
      final padded = _addQuietZone(cropped, marginRatio: 0.08);

      // Contrast enhancement: Clean white background, deep dark modules
      final enhanced = _enhanceContrast(padded);

      // Resize to standard square resolution
      final resized = img.copyResize(
        enhanced,
        width: targetDimension,
        height: targetDimension,
        interpolation: img.Interpolation.linear,
      );

      final encoded = Uint8List.fromList(
        img.encodeJpg(resized, quality: outputQuality),
      );

      return EnhancedQrResult(
        bytes: encoded,
        width: targetDimension,
        height: targetDimension,
        isAutoCropped: autoCropped,
        detectedProvider: provider,
      );
    } catch (_) {
      return null;
    }
  }

  /// Detects MFS brand accent colors in the uploaded screenshot or photo.
  static String? _detectBrandProvider(img.Image image) {
    int bkashPixels = 0; // Magenta / Pink: H ~ 330-350, S > 0.4, V > 0.4
    int nagadPixels = 0; // Orange / Amber: H ~ 20-42, S > 0.5, V > 0.5
    int rocketPixels = 0; // Violet / Purple: H ~ 280-310, S > 0.35, V > 0.35
    int upayPixels = 0; // Deep Blue: H ~ 200-230, S > 0.4, V > 0.3
    int cellfinPixels = 0; // Emerald Green: H ~ 140-165, S > 0.4, V > 0.3

    final sampleStep = math.max(1, (image.width * image.height) ~/ 25000);

    for (var y = 0; y < image.height; y += sampleStep) {
      for (var x = 0; x < image.width; x += sampleStep) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();

        // Convert RGB to HSV
        final hsv = _rgbToHsv(r, g, b);
        final h = hsv[0];
        final s = hsv[1];
        final v = hsv[2];

        if (s > 0.35 && v > 0.3) {
          if ((h >= 325 && h <= 355) && r > g && r > b) {
            bkashPixels++;
          } else if ((h >= 18 && h <= 45) && r > b) {
            nagadPixels++;
          } else if ((h >= 275 && h <= 315) && b > g) {
            rocketPixels++;
          } else if ((h >= 195 && h <= 235) && b > r) {
            upayPixels++;
          } else if ((h >= 135 && h <= 170) && g > r && g > b) {
            cellfinPixels++;
          }
        }
      }
    }

    const threshold = 18;
    if (bkashPixels >= threshold &&
        bkashPixels > nagadPixels &&
        bkashPixels > rocketPixels) {
      return 'bkash';
    }
    if (nagadPixels >= threshold &&
        nagadPixels > bkashPixels &&
        nagadPixels > rocketPixels) {
      return 'nagad';
    }
    if (rocketPixels >= threshold &&
        rocketPixels > bkashPixels &&
        rocketPixels > nagadPixels) {
      return 'rocket';
    }
    if (upayPixels >= threshold && upayPixels > bkashPixels) {
      return 'upay';
    }
    if (cellfinPixels >= threshold) {
      return 'cellfin';
    }

    return null;
  }

  /// Locates the square QR code bounding box within an arbitrary screenshot or photo.
  static _Box? _findQrBoundingBox(img.Image image) {
    final width = image.width;
    final height = image.height;

    // Minimum sensible QR size is 15% of the shortest image side
    final minQrSize = (math.min(width, height) * 0.18).toInt();

    // 1. Compute horizontal transition counts across scanlines
    final stepY = math.max(1, height ~/ 200);
    final rowTransitions = <int, int>{};

    for (var y = 0; y < height; y += stepY) {
      int transitions = 0;
      bool? wasDark;
      for (var x = 0; x < width; x += 3) {
        final pixel = image.getPixel(x, y);
        final lum = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
        final isDark = lum < 128;
        if (wasDark != null && isDark != wasDark) {
          transitions++;
        }
        wasDark = isDark;
      }
      rowTransitions[y] = transitions;
    }

    // Filter rows with significant high frequency pattern (QR modules have high transition density)
    final denseRows = rowTransitions.entries
        .where((e) => e.value >= 16)
        .map((e) => e.key)
        .toList();

    if (denseRows.length < 15) return null;

    final minY = denseRows.first;
    final maxY = denseRows.last;
    final estimatedH = maxY - minY;

    if (estimatedH < minQrSize) return null;

    // 2. Compute vertical transition counts within the identified vertical window
    final stepX = math.max(1, width ~/ 200);
    final colTransitions = <int, int>{};

    for (var x = 0; x < width; x += stepX) {
      int transitions = 0;
      bool? wasDark;
      for (var y = minY; y <= maxY; y += 3) {
        final pixel = image.getPixel(x, y);
        final lum = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
        final isDark = lum < 128;
        if (wasDark != null && isDark != wasDark) {
          transitions++;
        }
        wasDark = isDark;
      }
      colTransitions[x] = transitions;
    }

    final denseCols = colTransitions.entries
        .where((e) => e.value >= 16)
        .map((e) => e.key)
        .toList();

    if (denseCols.length < 15) return null;

    final minX = denseCols.first;
    final maxX = denseCols.last;
    final estimatedW = maxX - minX;

    if (estimatedW < minQrSize) return null;

    // Ensure roughly square aspect ratio (0.68 to 1.45)
    final ratio = estimatedW / estimatedH;
    if (ratio < 0.65 || ratio > 1.48) return null;

    // Center and make into a 1:1 square
    final boxSize = math.max(estimatedW, estimatedH);
    final centerX = (minX + maxX) ~/ 2;
    final centerY = (minY + maxY) ~/ 2;

    var startX = centerX - (boxSize ~/ 2);
    var startY = centerY - (boxSize ~/ 2);

    // Clamp inside image bounds
    if (startX < 0) startX = 0;
    if (startY < 0) startY = 0;
    if (startX + boxSize > width) startX = math.max(0, width - boxSize);
    if (startY + boxSize > height) startY = math.max(0, height - boxSize);

    final finalSize =
        math.min(boxSize, math.min(width - startX, height - startY));
    return _Box(x: startX, y: startY, width: finalSize, height: finalSize);
  }

  /// Adds a clean, pure white quiet zone border around the QR code.
  static img.Image _addQuietZone(img.Image src, {double marginRatio = 0.08}) {
    final margin = (src.width * marginRatio).round();
    final newWidth = src.width + (margin * 2);
    final newHeight = src.height + (margin * 2);

    final canvas = img.Image(width: newWidth, height: newHeight);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));

    img.compositeImage(
      canvas,
      src,
      dstX: margin,
      dstY: margin,
    );

    return canvas;
  }

  /// Enhances contrast with adaptive dynamic range normalization.
  /// Converts off-white paper backgrounds to crisp pure white and QR modules to deep black,
  /// while suppressing uneven indoor desk/table shadows.
  static img.Image _enhanceContrast(img.Image src) {
    final result = img.Image.from(src);

    // Sample luminances to compute min and max percentiles
    final step = math.max(1, (src.width * src.height) ~/ 2000);
    final samples = <double>[];
    for (int i = 0; i < src.width * src.height; i += step) {
      final p = src.getPixel(i % src.width, i ~/ src.width);
      samples.add(0.299 * p.r + 0.587 * p.g + 0.114 * p.b);
    }
    samples.sort();

    final p10 =
        samples.isNotEmpty ? samples[(samples.length * 0.10).toInt()] : 30.0;
    final p90 =
        samples.isNotEmpty ? samples[(samples.length * 0.90).toInt()] : 220.0;
    final range = math.max(20.0, p90 - p10);

    for (final pixel in result) {
      final lum = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
      final normalized = ((lum - p10) / range).clamp(0.0, 1.0);

      if (normalized > 0.65) {
        // Pure crisp white background
        pixel.r = 255;
        pixel.g = 255;
        pixel.b = 255;
      } else if (normalized < 0.35) {
        // Deep crisp dark module
        pixel.r = 15;
        pixel.g = 23;
        pixel.b = 42;
      } else {
        // Smooth transition
        final factor = (normalized - 0.35) / 0.30;
        pixel.r = (15 + factor * (255 - 15)).round();
        pixel.g = (23 + factor * (255 - 23)).round();
        pixel.b = (42 + factor * (255 - 42)).round();
      }
    }

    return result;
  }

  static List<double> _rgbToHsv(double r, double g, double b) {
    r /= 255.0;
    g /= 255.0;
    b /= 255.0;

    final max = math.max(r, math.max(g, b));
    final min = math.min(r, math.min(g, b));
    final delta = max - min;

    double h = 0;
    if (delta > 0.00001) {
      if (max == r) {
        h = 60 * (((g - b) / delta) % 6);
      } else if (max == g) {
        h = 60 * (((b - r) / delta) + 2);
      } else {
        h = 60 * (((r - g) / delta) + 4);
      }
      if (h < 0) h += 360;
    }

    final s = max == 0 ? 0.0 : delta / max;
    final v = max;

    return [h, s, v];
  }
}

class _Box {
  const _Box({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final int x;
  final int y;
  final int width;
  final int height;
}
