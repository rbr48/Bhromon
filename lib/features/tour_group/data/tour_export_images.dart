import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;

/// A picture ready for the PDF, with its size in pixels for the layout.
class TourExportPhoto {
  const TourExportPhoto({
    required this.image,
    required this.width,
    required this.height,
  });

  final pw.MemoryImage image;
  final int width;
  final int height;
}

/// Downloads, shrinks and caches the pictures the PDF shows. Each one goes in
/// as a JPEG at most [maxWidth] pixels wide, which keeps a long trip's file a
/// sensible size. A picture that cannot be fetched or read is skipped rather
/// than failing the whole export.
class TourExportImages {
  TourExportImages({http.Client? client}) : _client = client ?? http.Client();

  static const int maxWidth = 1000;
  static const int jpegQuality = 78;
  static const int _parallel = 4;

  final http.Client _client;
  final Map<String, Future<TourExportPhoto?>> _pending = {};
  final Map<String, TourExportPhoto> _ready = {};

  /// The picture at [url] once it has been [prefetch]ed, or null when it could
  /// not be made.
  TourExportPhoto? ready(String url) => _ready[url];

  /// Releases the connections the downloads used. Call once the PDF is built.
  void close() => _client.close();

  /// Fetches [urls], a few at a time, so the pictures are ready before the PDF
  /// is laid out. [onProgress] reports how many of the unique urls are done.
  Future<void> prefetch(
    Iterable<String> urls, {
    void Function(int done, int total)? onProgress,
  }) async {
    final unique = urls.where((url) => url.isNotEmpty).toSet().toList();
    var done = 0;
    for (var i = 0; i < unique.length; i += _parallel) {
      final chunk = unique.skip(i).take(_parallel).toList();
      await Future.wait(chunk.map(_load));
      done += chunk.length;
      onProgress?.call(done, unique.length);
    }
  }

  Future<TourExportPhoto?> _load(String url) {
    return _pending.putIfAbsent(url, () async {
      final photo = await _fetch(url);
      if (photo != null) _ready[url] = photo;
      return photo;
    });
  }

  Future<TourExportPhoto?> _fetch(String url) async {
    try {
      final response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 25));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        return null;
      }
      final codec = await ui.instantiateImageCodec(
        response.bodyBytes,
        targetWidth: maxWidth,
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();
      final picture = frame.image;
      final width = picture.width;
      final height = picture.height;
      final pixels =
          await picture.toByteData(format: ui.ImageByteFormat.rawRgba);
      picture.dispose();
      codec.dispose();
      if (pixels == null) return null;
      final jpeg = await compute(
        _encodeJpeg,
        _Pixels(pixels.buffer.asUint8List(), width, height),
      );
      return TourExportPhoto(
        image: pw.MemoryImage(jpeg),
        width: width,
        height: height,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Raw RGBA pixels, handed to the isolate that encodes them.
class _Pixels {
  const _Pixels(this.rgba, this.width, this.height);

  final Uint8List rgba;
  final int width;
  final int height;
}

Uint8List _encodeJpeg(_Pixels pixels) {
  final source = img.Image.fromBytes(
    width: pixels.width,
    height: pixels.height,
    bytes: pixels.rgba.buffer,
    numChannels: 4,
  );
  return img.encodeJpg(source, quality: TourExportImages.jpegQuality);
}
