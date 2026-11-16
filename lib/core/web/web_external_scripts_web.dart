import 'dart:js_interop';

import '../../core/utils/app_logger.dart';

@JS('bhromonLoadMapLibre')
external JSPromise<JSAny?>? _loadMapLibre();

@JS('bhromonLoadPdfJs')
external JSPromise<JSAny?>? _loadPdfJs();

@JS('bhromonLoadVideoTranscoder')
external JSPromise<JSBoolean>? _loadVideoTranscoder();

/// Lazily loads MapLibre GL JS/CSS once on Web when a map screen opens.
Future<void> ensureMapLibreLoaded() async {
  final promise = _loadMapLibre();
  if (promise == null) return;
  await promise.toDart;
}

/// Lazily loads PDF.js once on Web when a PDF viewer opens.
Future<void> ensurePdfJsLoaded() async {
  final promise = _loadPdfJs();
  if (promise == null) return;
  await promise.toDart;
}

/// Lazily loads the browser MP4 video transcoder module on Web.
Future<bool> ensureVideoTranscoderLoaded() async {
  final promise = _loadVideoTranscoder();
  if (promise == null) return false;
  try {
    final result = await promise.toDart;
    return result.toDart;
  } catch (e, st) {
    logWarning('Failed to load browser video transcoder module', e, st);
    return false;
  }
}
