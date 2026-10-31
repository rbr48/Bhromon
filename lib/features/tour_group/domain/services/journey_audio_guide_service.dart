import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../../../core/utils/app_logger.dart';
import '../models/tour_activity_models.dart';

/// Text-To-Speech audio guide service for real-time journey checkpoints.
///
/// Announces checkpoint details, highlights, remaining distance, and notes
/// in Bengali or English for travelers on the go.
class JourneyAudioGuideService {
  static final JourneyAudioGuideService _instance =
      JourneyAudioGuideService._internal();
  factory JourneyAudioGuideService() => _instance;
  JourneyAudioGuideService._internal() {
    _initTts();
  }

  FlutterTts? _flutterTts;
  final ValueNotifier<bool> isSpeaking = ValueNotifier<bool>(false);
  final ValueNotifier<String?> currentCheckpointId =
      ValueNotifier<String?>(null);
  bool _initialized = false;

  void _initTts() {
    if (_initialized) return;
    try {
      _flutterTts = FlutterTts();
      _flutterTts!.setStartHandler(() {
        isSpeaking.value = true;
      });
      _flutterTts!.setCompletionHandler(() {
        isSpeaking.value = false;
        currentCheckpointId.value = null;
      });
      _flutterTts!.setCancelHandler(() {
        isSpeaking.value = false;
        currentCheckpointId.value = null;
      });
      _flutterTts!.setErrorHandler((msg) {
        isSpeaking.value = false;
        currentCheckpointId.value = null;
      });
      _initialized = true;
    } catch (e, st) {
      logWarning('JourneyAudioGuideService init warning', e, st);
    }
  }

  /// Announces the given checkpoint aloud in natural voice.
  /// Tapping the same checkpoint while it is playing stops it.
  Future<void> speakCheckpoint({
    required RouteCheckpoint checkpoint,
    String? kindLabel,
    bool isBengali = true,
  }) async {
    _initTts();
    if (_flutterTts == null) return;

    if (isSpeaking.value && currentCheckpointId.value == checkpoint.id) {
      await stop();
      return;
    }

    try {
      await _flutterTts!.stop();

      final String kindStr = kindLabel ?? checkpoint.kind.name;
      final String text;
      if (isBengali) {
        final buffer = StringBuffer('চেকপয়েন্ট: ${checkpoint.name}');
        if (kindStr.isNotEmpty) {
          buffer.write('। ধরণ: $kindStr');
        }
        if (checkpoint.kmFromStart > 0) {
          buffer.write('। দূরত্ব: ${checkpoint.kmFromStart} কিলোমিটার');
        }
        if (checkpoint.highlight.isNotEmpty) {
          buffer.write('। বিশেষ আকর্ষণ: ${checkpoint.highlight}');
        }
        if (checkpoint.notes.isNotEmpty) {
          buffer.write('। নোট: ${checkpoint.notes}');
        }
        text = buffer.toString();
        await _flutterTts!.setLanguage('bn-BD');
      } else {
        final buffer = StringBuffer('Checkpoint: ${checkpoint.name}');
        if (kindStr.isNotEmpty) {
          buffer.write('. Type: $kindStr');
        }
        if (checkpoint.kmFromStart > 0) {
          buffer.write('. Distance: ${checkpoint.kmFromStart} kilometers');
        }
        if (checkpoint.highlight.isNotEmpty) {
          buffer.write('. Highlight: ${checkpoint.highlight}');
        }
        if (checkpoint.notes.isNotEmpty) {
          buffer.write('. Note: ${checkpoint.notes}');
        }
        text = buffer.toString();
        await _flutterTts!.setLanguage('en-US');
      }

      await _flutterTts!.setSpeechRate(0.5);
      await _flutterTts!.setVolume(1.0);
      await _flutterTts!.setPitch(1.0);

      currentCheckpointId.value = checkpoint.id;
      isSpeaking.value = true;

      final res = await _flutterTts!.speak(text);
      if (res != 1 && res != '1' && isBengali) {
        await _flutterTts!.setLanguage('bn-IN');
        await _flutterTts!.speak(text);
      }
    } catch (e, st) {
      logWarning('JourneyAudioGuideService speak error', e, st);
      isSpeaking.value = false;
      currentCheckpointId.value = null;
    }
  }

  /// Stops current speech output immediately.
  Future<void> stop() async {
    try {
      if (_flutterTts != null) {
        await _flutterTts!.stop();
      }
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
    }
    isSpeaking.value = false;
    currentCheckpointId.value = null;
  }
}
