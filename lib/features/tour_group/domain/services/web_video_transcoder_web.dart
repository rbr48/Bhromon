import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'web_video_plan.dart';

/// The browser transcoder in web/js/bhromon_video_transcoder.js. The module
/// loads before the app starts. If it did not load, the global is missing and
/// [isSupported] is false.
@JS('bhromonVideoTranscoder')
external _BrowserVideoTranscoder? get _api;

extension type _BrowserVideoTranscoder(JSObject _) implements JSObject {
  external JSBoolean isSupported();
  external JSPromise<JSString?> probe(JSUint8Array bytes);
  external JSPromise<JSUint8Array?> transcode(
    JSUint8Array bytes,
    JSString optionsJson,
    JSFunction onProgress,
  );
  external void cancel();
}

/// Shrinks a video in the browser. Off the web, see the stub.
class WebVideoTranscoder {
  WebVideoTranscoder._();

  static bool get isSupported => _api?.isSupported().toDart ?? false;

  static Future<WebVideoInfo?> probe(Uint8List bytes) async {
    final api = _api;
    if (api == null) return null;
    final json = await api.probe(bytes.toJS).toDart;
    if (json == null) return null;
    return WebVideoInfo.fromJson(
      jsonDecode(json.toDart) as Map<String, dynamic>,
    );
  }

  /// Returns the shrunk MP4, or null when [cancel] stopped it.
  static Future<Uint8List?> transcode(
    Uint8List bytes,
    WebVideoPass pass, {
    void Function(double progress)? onProgress,
  }) async {
    final api = _api;
    if (api == null) {
      throw StateError('The browser video transcoder did not load.');
    }
    final reportProgress =
        ((JSNumber progress) => onProgress?.call(progress.toDartDouble)).toJS;
    final output = await api
        .transcode(
          bytes.toJS,
          jsonEncode(pass.toJson()).toJS,
          reportProgress,
        )
        .toDart;
    return output?.toDart;
  }

  static void cancel() => _api?.cancel();
}
