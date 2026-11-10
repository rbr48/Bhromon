import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/features/tour_group/domain/services/study_tts_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StudyTtsController.cleanTextForSpeech', () {
    test('cleans markdown symbols, tables, headings, and code blocks', () {
      const raw = '''
### প্রশ্ন ১ [মান: ১০ + ১০ = ২০]
**উত্তরাধিকার পরিকল্পনা (Succession Planning)** বলতে কী বুঝায়?
| Column A | Column B |
| --- | --- |
| Data 1 | Data 2 |

```dart
void test() {}
```
> গুরুত্বপূর্ণ পরামর্শ: ব্যাংকিং আইনে ধারা ১২ দ্রষ্টব্য।
''';

      final cleaned = StudyTtsController.cleanTextForSpeech(raw);
      expect(cleaned.contains('###'), isFalse);
      expect(cleaned.contains('[মান: ১০ + ১০ = ২০]'), isFalse);
      expect(cleaned.contains('**'), isFalse);
      expect(cleaned.contains('| Column A |'), isFalse);
      expect(cleaned.contains('void test()'), isFalse);
      expect(cleaned.contains('>'), isFalse);
      expect(cleaned.contains('উত্তরাধিকার পরিকল্পনা (Succession Planning)'),
          isTrue);
      expect(
          cleaned.contains(
              'গুরুত্বপূর্ণ পরামর্শ: ব্যাংকিং আইনে ধারা ১২ দ্রষ্টব্য।'),
          isTrue);
    });

    test('converts markdown links to plaintext text', () {
      const raw = 'Visit [Bangladesh Bank](https://bb.org.bd) for circulars.';
      final cleaned = StudyTtsController.cleanTextForSpeech(raw);
      expect(cleaned, 'Visit Bangladesh Bank for circulars.');
    });

    test('handles empty or whitespace markdown safely', () {
      expect(StudyTtsController.cleanTextForSpeech(''), '');
      expect(StudyTtsController.cleanTextForSpeech('   \n\n  '), '');
    });
  });

  group('StudyTtsController.isBengaliText', () {
    test('correctly identifies Bengali passages', () {
      expect(
          StudyTtsController.isBengaliText('ব্যাংকিং প্রফেশনাল পরীক্ষা ২০২৪'),
          isTrue);
      expect(
          StudyTtsController.isBengaliText('৯৬তম ব্যাংকিং ডিপ্লোমা'), isTrue);
    });

    test('correctly identifies English passages', () {
      expect(
          StudyTtsController.isBengaliText(
              'Laws and Practice of General Banking'),
          isFalse);
      expect(StudyTtsController.isBengaliText('Succession Planning in Banks'),
          isFalse);
    });
  });

  group('StudyTtsController Playlist and Playback Controls (Test Mode)', () {
    late StudyTtsController controller;

    setUp(() {
      controller = StudyTtsController(isTestMode: true);
    });

    tearDown(() {
      controller.dispose();
    });

    test('initializes with default stopped state and speed 1.0', () {
      expect(controller.stateNotifier.value, StudyAudioState.stopped);
      expect(controller.currentIndexNotifier.value, 0);
      expect(controller.speedNotifier.value, 1.0);
      expect(controller.sleepTimerRemainingNotifier.value, isNull);
    });

    test('loads tracks and manages playlist navigation', () async {
      final tracks = [
        const StudyAudioTrack(
          index: 0,
          title: 'Question 1',
          rawText: 'Raw 1',
          spokenText: 'Spoken 1',
          isBengali: false,
        ),
        const StudyAudioTrack(
          index: 1,
          title: 'Question 2',
          rawText: 'Raw 2',
          spokenText: 'Spoken 2',
          isBengali: true,
        ),
        const StudyAudioTrack(
          index: 2,
          title: 'Question 3',
          rawText: 'Raw 3',
          spokenText: 'Spoken 3',
          isBengali: false,
        ),
      ];

      controller.setTracks(tracks);
      expect(controller.totalTracks, 3);
      expect(controller.currentTrack?.title, 'Question 1');

      // Play track 0
      await controller.play();
      expect(controller.stateNotifier.value, StudyAudioState.playing);

      // Next track
      await controller.nextTrack();
      expect(controller.currentIndexNotifier.value, 1);
      expect(controller.currentTrack?.title, 'Question 2');
      expect(controller.currentTrack?.isBengali, isTrue);

      // Previous track
      await controller.previousTrack();
      expect(controller.currentIndexNotifier.value, 0);
      expect(controller.currentTrack?.title, 'Question 1');

      // Jump to track 2
      await controller.jumpToTrack(2);
      expect(controller.currentIndexNotifier.value, 2);

      // Pause
      await controller.pause();
      expect(controller.stateNotifier.value, StudyAudioState.paused);

      // Resume
      await controller.play();
      expect(controller.stateNotifier.value, StudyAudioState.playing);

      // Stop
      await controller.stop();
      expect(controller.stateNotifier.value, StudyAudioState.stopped);
    });

    test('updates speed and manages sleep timer', () async {
      await controller.setSpeed(1.25);
      expect(controller.speedNotifier.value, 1.25);

      controller.setSleepTimer(30);
      expect(controller.sleepTimerRemainingNotifier.value, 30);

      controller.setSleepTimer(null);
      expect(controller.sleepTimerRemainingNotifier.value, isNull);
    });

    test('buildTracksFromSections compiles valid tracks', () {
      final sections = [
        {
          'title': 'Part A',
          'rawText': '### Part A\nIntroduction to Banking Regulation',
        },
        {
          'title': 'প্রশ্ন ১',
          'rawText': '### প্রশ্ন ১\nব্যাংক আমানতের প্রকারভেদ ব্যাখ্যা করুন।',
        },
      ];

      final tracks = StudyTtsController.buildTracksFromSections(sections);
      expect(tracks.length, 2);
      expect(tracks[0].title, 'Part A');
      expect(tracks[0].isBengali, isFalse);
      expect(tracks[1].title, 'প্রশ্ন ১');
      expect(tracks[1].isBengali, isTrue);
    });
  });
}
