import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Text-to-Speech audio service for speaking headlines and articles aloud.
class NewsTtsService {
  static final NewsTtsService _instance = NewsTtsService._internal();
  factory NewsTtsService() => _instance;
  NewsTtsService._internal() {
    _initTts();
  }

  FlutterTts? _flutterTts;
  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String?> currentPlayingIdNotifier =
      ValueNotifier<String?>(null);

  bool _initialized = false;

  void _initTts() {
    if (_initialized) return;
    try {
      _flutterTts = FlutterTts();
      _flutterTts!.setStartHandler(() {
        isPlayingNotifier.value = true;
      });
      _flutterTts!.setCompletionHandler(() {
        isPlayingNotifier.value = false;
        currentPlayingIdNotifier.value = null;
      });
      _flutterTts!.setCancelHandler(() {
        isPlayingNotifier.value = false;
        currentPlayingIdNotifier.value = null;
      });
      _flutterTts!.setErrorHandler((msg) {
        isPlayingNotifier.value = false;
        currentPlayingIdNotifier.value = null;
      });
      _initialized = true;
    } catch (e) {
      debugPrint('NewsTtsService init warning: $e');
    }
  }

  /// Detects whether text contains Bengali characters.
  bool _isBengali(String text) {
    final regExp = RegExp(r'[\u0980-\u09FF]');
    return regExp.hasMatch(text);
  }

  /// Speaks the given text aloud. Tapping the same item while playing stops it.
  Future<void> speak({
    required String id,
    required String text,
    VoidCallback? onComplete,
  }) async {
    _initTts();
    if (_flutterTts == null) return;

    if (isPlayingNotifier.value && currentPlayingIdNotifier.value == id) {
      await stop();
      return;
    }

    try {
      await _flutterTts!.stop();

      final bool bengali = _isBengali(text);
      if (bengali) {
        await _flutterTts!.setLanguage('bn-BD');
      } else {
        await _flutterTts!.setLanguage('en-US');
      }

      await _flutterTts!.setSpeechRate(0.5);
      await _flutterTts!.setVolume(1.0);
      await _flutterTts!.setPitch(1.0);

      currentPlayingIdNotifier.value = id;
      isPlayingNotifier.value = true;

      final res = await _flutterTts!.speak(text);
      if (res != 1 && res != '1') {
        // Fallback for languages if bn-BD is not installed
        if (bengali) {
          await _flutterTts!.setLanguage('bn-IN');
          await _flutterTts!.speak(text);
        }
      }
    } catch (e) {
      debugPrint('NewsTtsService speak error: $e');
      isPlayingNotifier.value = false;
      currentPlayingIdNotifier.value = null;
    }
  }

  Future<void> stop() async {
    try {
      if (_flutterTts != null) {
        await _flutterTts!.stop();
      }
    } catch (_) {}
    isPlayingNotifier.value = false;
    currentPlayingIdNotifier.value = null;
  }

  void dispose() {
    stop();
    isPlayingNotifier.dispose();
    currentPlayingIdNotifier.dispose();
  }
}
