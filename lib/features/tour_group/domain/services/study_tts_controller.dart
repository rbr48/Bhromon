import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../../core/utils/app_logger.dart';

/// Audio state for the study commute player.
enum StudyAudioState {
  stopped,
  playing,
  paused,
}

/// Represents a distinct audio track (question or section) for playback.
@immutable
class StudyAudioTrack {
  final int index;
  final String title;
  final String rawText;
  final String spokenText;
  final bool isBengali;

  const StudyAudioTrack({
    required this.index,
    required this.title,
    required this.rawText,
    required this.spokenText,
    required this.isBengali,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StudyAudioTrack &&
          runtimeType == other.runtimeType &&
          index == other.index &&
          title == other.title;

  @override
  int get hashCode => index.hashCode ^ title.hashCode;
}

/// Controller managing hands-free Text-to-Speech audio playback for commute study.
/// Pure native implementation using [FlutterTts] with zero external AI dependencies.
class StudyTtsController {
  final FlutterTts? _tts;
  final bool _isTestMode;

  StudyTtsController({FlutterTts? tts, bool isTestMode = false})
      : _tts = tts ?? (isTestMode ? null : FlutterTts()),
        _isTestMode = isTestMode {
    _initTts();
  }

  final ValueNotifier<StudyAudioState> stateNotifier =
      ValueNotifier<StudyAudioState>(StudyAudioState.stopped);
  final ValueNotifier<int> currentIndexNotifier = ValueNotifier<int>(0);
  final ValueNotifier<double> speedNotifier = ValueNotifier<double>(1.0);
  final ValueNotifier<int?> sleepTimerRemainingNotifier =
      ValueNotifier<int?>(null);

  List<StudyAudioTrack> _tracks = const [];
  List<StudyAudioTrack> get tracks => _tracks;
  int get totalTracks => _tracks.length;

  StudyAudioTrack? get currentTrack =>
      (_tracks.isNotEmpty && currentIndexNotifier.value < _tracks.length)
          ? _tracks[currentIndexNotifier.value]
          : null;

  Timer? _sleepTimer;
  bool _initialized = false;

  void _initTts() {
    if (_initialized || _tts == null) return;
    try {
      _tts.setStartHandler(() {
        stateNotifier.value = StudyAudioState.playing;
      });
      _tts.setCompletionHandler(() {
        _onTrackCompleted();
      });
      _tts.setCancelHandler(() {
        stateNotifier.value = StudyAudioState.stopped;
      });
      _tts.setPauseHandler(() {
        stateNotifier.value = StudyAudioState.paused;
      });
      _tts.setContinueHandler(() {
        stateNotifier.value = StudyAudioState.playing;
      });
      _tts.setErrorHandler((dynamic msg) {
        logWarning('StudyTtsController error: $msg');
        stateNotifier.value = StudyAudioState.stopped;
      });
      _initialized = true;
    } catch (e, st) {
      logWarning('StudyTtsController init warning', e, st);
    }
  }

  /// Sets the playlist tracks for playback.
  void setTracks(List<StudyAudioTrack> tracks) {
    stop();
    _tracks = List.unmodifiable(tracks);
    currentIndexNotifier.value = 0;
  }

  /// Cleans markdown and formatting artifacts to produce natural spoken text.
  static String cleanTextForSpeech(String markdown) {
    if (markdown.trim().isEmpty) return '';

    var text = markdown;

    // Remove code blocks
    text = text.replaceAll(RegExp(r'```[\s\S]*?```'), ' [Code snippet] ');
    text = text.replaceAll(RegExp(r'`[^`]+`'), '');

    // Convert markdown links [Text](url) to Text
    text = text.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\([^\)]+\)'),
      (match) => match.group(1) ?? '',
    );

    // Remove images ![alt](url)
    text = text.replaceAll(RegExp(r'!\[[^\]]*\]\([^\)]+\)'), '');

    // Strip markdown table rows: | cell | cell |
    text = text.replaceAll(RegExp(r'\|[^\n]+\|'), ' ');

    // Clean marks notation like [Marks: 5 + 5 = 10] or [মান: ১০]
    text = text.replaceAll(RegExp(r'\[(?:Marks|মান|পূর্ণমান)[\s\S]*?\]'), '');

    // Strip headings markdown tokens (#, ##, ###)
    text = text.replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '');

    // Strip bold/italics markers
    text = text.replaceAll(RegExp(r'\*\*|__|[\*_]'), '');

    // Strip blockquote markers
    text = text.replaceAll(RegExp(r'^>\s*', multiLine: true), '');

    // Strip horizontal rules
    text = text.replaceAll(RegExp(r'^[-*_]{3,}\s*$', multiLine: true), '');

    // Clean backslash escaped characters
    text = text.replaceAll(r'\[', '[').replaceAll(r'\]', ']');
    text = text.replaceAll(r'\(', '(').replaceAll(r'\)', ')');

    // Collapse multiple blank lines or excess spaces
    text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return text.trim();
  }

  /// Detects whether text primarily contains Bengali characters.
  static bool isBengaliText(String text) {
    final bnMatches = RegExp(r'[\u0980-\u09FF]').allMatches(text).length;
    final enMatches = RegExp(r'[a-zA-Z]').allMatches(text).length;
    return bnMatches >= enMatches && bnMatches > 0;
  }

  /// Compiles a list of [StudyAudioTrack] items from raw markdown sections.
  static List<StudyAudioTrack> buildTracksFromSections(
    List<Map<String, String>> sections,
  ) {
    final tracks = <StudyAudioTrack>[];
    for (int i = 0; i < sections.length; i++) {
      final s = sections[i];
      final title = s['title'] ?? 'Section ${i + 1}';
      final raw = s['rawText'] ?? '';
      final spoken = cleanTextForSpeech(raw);
      if (spoken.isEmpty) continue;

      tracks.add(
        StudyAudioTrack(
          index: tracks.length,
          title: title,
          rawText: raw,
          spokenText: spoken,
          isBengali: isBengaliText(spoken),
        ),
      );
    }
    return tracks;
  }

  /// Starts or resumes playback of the current track.
  Future<void> play() async {
    if (_tracks.isEmpty) return;

    if (stateNotifier.value == StudyAudioState.paused && _tts != null) {
      try {
        stateNotifier.value = StudyAudioState.playing;
        // Some platforms don't support resume; speaking current track ensures consistency
        await _speakTrack(currentIndexNotifier.value);
        return;
      } catch (e, st) {
        logWarning('StudyTtsController resume failed', e, st);
      }
    }

    await _speakTrack(currentIndexNotifier.value);
  }

  /// Pauses playback.
  Future<void> pause() async {
    if (stateNotifier.value != StudyAudioState.playing) return;
    try {
      if (_tts != null) {
        await _tts.pause();
      }
      stateNotifier.value = StudyAudioState.paused;
    } catch (e, st) {
      logWarning('StudyTtsController pause error', e, st);
      stateNotifier.value = StudyAudioState.paused;
    }
  }

  /// Stops playback completely.
  Future<void> stop() async {
    try {
      if (_tts != null) {
        await _tts.stop();
      }
    } catch (e, st) {
      logWarning('StudyTtsController stop error', e, st);
    }
    stateNotifier.value = StudyAudioState.stopped;
  }

  /// Skips to the next track.
  Future<void> nextTrack() async {
    if (_tracks.isEmpty) return;
    final next = currentIndexNotifier.value + 1;
    if (next < _tracks.length) {
      currentIndexNotifier.value = next;
      if (stateNotifier.value == StudyAudioState.playing) {
        await _speakTrack(next);
      }
    } else {
      await stop();
    }
  }

  /// Skips to the previous track.
  Future<void> previousTrack() async {
    if (_tracks.isEmpty) return;
    final prev = currentIndexNotifier.value - 1;
    if (prev >= 0) {
      currentIndexNotifier.value = prev;
      if (stateNotifier.value == StudyAudioState.playing) {
        await _speakTrack(prev);
      }
    }
  }

  /// Jumps to a specific track by index.
  Future<void> jumpToTrack(int index) async {
    if (index < 0 || index >= _tracks.length) return;
    currentIndexNotifier.value = index;
    await _speakTrack(index);
  }

  /// Changes the speech rate: 0.75x, 1.0x, 1.25x, 1.5x.
  Future<void> setSpeed(double speed) async {
    speedNotifier.value = speed;
    if (_tts != null) {
      try {
        // Map 1.0x to FlutterTts standard rate (0.5 on Android/iOS)
        final ttsRate = (0.5 * speed).clamp(0.2, 1.0);
        await _tts.setSpeechRate(ttsRate);
      } catch (e, st) {
        logWarning('StudyTtsController setSpeed error', e, st);
      }
    }
  }

  /// Sets or clears the commute sleep timer (in minutes).
  void setSleepTimer(int? minutes) {
    _sleepTimer?.cancel();
    _sleepTimer = null;

    if (minutes == null || minutes <= 0) {
      sleepTimerRemainingNotifier.value = null;
      return;
    }

    sleepTimerRemainingNotifier.value = minutes;
    _sleepTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      final current = sleepTimerRemainingNotifier.value ?? 0;
      if (current <= 1) {
        timer.cancel();
        _sleepTimer = null;
        sleepTimerRemainingNotifier.value = null;
        stop();
      } else {
        sleepTimerRemainingNotifier.value = current - 1;
      }
    });
  }

  Future<void> _speakTrack(int index) async {
    if (index < 0 || index >= _tracks.length) {
      await stop();
      return;
    }

    final track = _tracks[index];
    stateNotifier.value = StudyAudioState.playing;

    if (_isTestMode || _tts == null) {
      // In tests or mock mode, state updates immediately without native TTS call
      return;
    }

    try {
      await _tts.stop();

      // Configure language based on track content
      final lang = track.isBengali ? 'bn-BD' : 'en-US';
      await _tts.setLanguage(lang);

      final ttsRate = (0.5 * speedNotifier.value).clamp(0.2, 1.0);
      await _tts.setSpeechRate(ttsRate);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);

      final result = await _tts.speak(track.spokenText);
      // Fallback for Bengali voice
      if (track.isBengali && result != 1 && result != '1') {
        await _tts.setLanguage('bn-IN');
        await _tts.speak(track.spokenText);
      }
    } catch (e, st) {
      logWarning('StudyTtsController speak error', e, st);
      stateNotifier.value = StudyAudioState.stopped;
    }
  }

  void _onTrackCompleted() {
    if (currentIndexNotifier.value + 1 < _tracks.length) {
      nextTrack();
    } else {
      stateNotifier.value = StudyAudioState.stopped;
    }
  }

  void dispose() {
    _sleepTimer?.cancel();
    stop();
    stateNotifier.dispose();
    currentIndexNotifier.dispose();
    speedNotifier.dispose();
    sleepTimerRemainingNotifier.dispose();
  }
}
