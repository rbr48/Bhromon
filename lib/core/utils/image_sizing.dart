import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Longest edge, in pixels, for photos picked or compressed for upload.
const double kMaxCaptureDimension = 2048;

/// Largest decode size we ever ask for; also bounds full-screen viewers.
const int kMaxDecodeDimension = 2048;

/// Pixels needed to show [logicalSize] sharply at [devicePixelRatio].
///
/// Without a decode size Flutter decodes a photo at its full resolution
/// (a 12 MP photo is ~48 MB of pixels) even for a 40 px avatar.
int decodeSizeFor(double logicalSize, double devicePixelRatio) {
  if (!logicalSize.isFinite || logicalSize <= 0) return kMaxDecodeDimension;
  return math.max(1,
      math.min(kMaxDecodeDimension, (logicalSize * devicePixelRatio).ceil()));
}

extension ImageDecodeSizing on BuildContext {
  /// Decode width for an image [logicalWidth] wide; pass `double.infinity`
  /// (or omit) for images that span the screen width.
  int decodeWidth([double logicalWidth = double.infinity]) {
    final media = MediaQuery.maybeOf(this);
    final dpr = media?.devicePixelRatio ?? 2.0;
    final width = logicalWidth.isFinite
        ? logicalWidth
        : (media?.size.width ?? kMaxDecodeDimension / dpr);
    return decodeSizeFor(width, dpr);
  }
}

/// [provider] decoded at most [width] pixels wide (aspect ratio kept).
ImageProvider<Object> sizedImage(ImageProvider<Object> provider, int width) =>
    ResizeImage.resizeIfNeeded(width, null, provider);
