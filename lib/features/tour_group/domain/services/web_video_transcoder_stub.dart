import 'dart:typed_data';

import 'web_video_plan.dart';

/// Off the web there is no browser transcoder.
class WebVideoTranscoder {
  WebVideoTranscoder._();

  static bool get isSupported => false;

  static Future<WebVideoInfo?> probe(Uint8List bytes) async => null;

  static Future<Uint8List?> transcode(
    Uint8List bytes,
    WebVideoPass pass, {
    void Function(double progress)? onProgress,
  }) {
    throw UnsupportedError(
        'The browser video transcoder runs on the web only.');
  }

  static void cancel() {}
}
