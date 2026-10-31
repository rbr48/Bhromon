import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../core/utils/app_logger.dart';

/// Reads a notice aloud on the device. Only one notice is read at a time: tapping
/// the notice that is being read stops it, and tapping another one switches to it.
///
/// [playingId] holds the notice being read, or null, so each card can show
/// whether it is the one playing. Speech is optional: when the voice engine is
/// missing or fails, the notice simply is not read.
class NoticeReadAloud {
  NoticeReadAloud._();

  static final NoticeReadAloud instance = NoticeReadAloud._();

  final ValueNotifier<String?> playingId = ValueNotifier<String?>(null);

  FlutterTts? _tts;
  bool _ready = false;

  void _ensureReady() {
    if (_ready) return;
    _ready = true;
    try {
      final tts = FlutterTts();
      tts.setCompletionHandler(() => playingId.value = null);
      tts.setCancelHandler(() => playingId.value = null);
      tts.setErrorHandler((_) => playingId.value = null);
      _tts = tts;
    } catch (e, st) {
      logWarning('NoticeReadAloud init warning', e, st);
    }
  }

  /// Reads [text] for the notice [id]. Tapping the notice that is playing stops it.
  Future<void> speak({
    required String id,
    required String text,
    required bool bengali,
  }) async {
    _ensureReady();
    final tts = _tts;
    if (tts == null) return;
    if (playingId.value == id) {
      await stop();
      return;
    }
    try {
      await tts.stop();
      await tts.setLanguage(bengali ? 'bn-BD' : 'en-US');
      await tts.setSpeechRate(0.5);
      await tts.setVolume(1.0);
      await tts.setPitch(1.0);
      playingId.value = id;
      final result = await tts.speak(text);
      // Some phones lack the bn-BD voice. bn-IN is the fallback that usually exists.
      if (bengali && result != 1 && result != '1') {
        await tts.setLanguage('bn-IN');
        await tts.speak(text);
      }
    } catch (e, st) {
      logWarning('NoticeReadAloud speak error', e, st);
      playingId.value = null;
    }
  }

  /// Stops reading at once.
  Future<void> stop() async {
    try {
      await _tts?.stop();
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
    }
    playingId.value = null;
  }
}
