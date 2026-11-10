import 'dart:io';

import 'package:bhromon/core/security/hive_encryption_service.dart';
import 'package:bhromon/features/tour_group/data/study_exam_attempt_store.dart';
import 'package:bhromon/features/tour_group/domain/models/study_exam_simulator_models.dart';
import 'package:bhromon/features/tour_group/domain/services/study_exam_simulator_rules.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import '../../../../helpers/perf_fixtures.dart';

void main() {
  group('StudyExamTimerRules', () {
    test('formats duration correctly as HH:mm:ss', () {
      expect(
        StudyExamTimerRules.formatDuration(const Duration(hours: 3)),
        '03:00:00',
      );
      expect(
        StudyExamTimerRules.formatDuration(
            const Duration(minutes: 45, seconds: 12)),
        '00:45:12',
      );
      expect(
        StudyExamTimerRules.formatDuration(const Duration(seconds: 9)),
        '00:00:09',
      );
      expect(
        StudyExamTimerRules.formatDuration(Duration.zero),
        '00:00:00',
      );
      expect(
        StudyExamTimerRules.formatDuration(const Duration(seconds: -10)),
        '00:00:00',
      );
    });

    test('determines alert state transitions accurately', () {
      // Normal (> 30 min)
      expect(
        StudyExamTimerRules.getAlertState(const Duration(minutes: 31)),
        ExamTimerAlertState.normal,
      );

      // Warning (<= 30 min and > 10 min)
      expect(
        StudyExamTimerRules.getAlertState(const Duration(minutes: 30)),
        ExamTimerAlertState.warning,
      );
      expect(
        StudyExamTimerRules.getAlertState(const Duration(minutes: 15)),
        ExamTimerAlertState.warning,
      );

      // Critical (<= 10 min and > 0s)
      expect(
        StudyExamTimerRules.getAlertState(const Duration(minutes: 10)),
        ExamTimerAlertState.critical,
      );
      expect(
        StudyExamTimerRules.getAlertState(const Duration(seconds: 30)),
        ExamTimerAlertState.critical,
      );

      // Expired (<= 0s)
      expect(
        StudyExamTimerRules.getAlertState(Duration.zero),
        ExamTimerAlertState.expired,
      );
      expect(
        StudyExamTimerRules.getAlertState(const Duration(seconds: -5)),
        ExamTimerAlertState.expired,
      );
    });
  });

  group('StudyExamSimulatorExtractor', () {
    const sampleExamText = '''
### প্রশ্ন ১ [মান: ১০ + ১০ = ২০]
১(ক) উত্তরাধিকার পরিকল্পনা কী?
১(খ) ব্যাংকিং খাতে এর প্রয়োজনীয়তা আলোচনা করুন।

### Question 2 [Marks: 20]
Explain the provisions of Section 45 of Bank Company Act 1991 regarding power of Bangladesh Bank.

### Question 3 [Marks: 15]
Discuss the differences between a Cheque and a Bill of Exchange under Negotiable Instruments Act 1881.
''';

    test('extracts questions with allocated marks, body and modules', () {
      final questions = StudyExamSimulatorExtractor.extractQuestions(
        subjectTitle: 'Laws & Practice of General Banking (LPGB)',
        markdownContent: sampleExamText,
      );

      expect(questions.length, 3);

      // Question 1
      expect(questions[0].number, 1);
      expect(questions[0].prompt, contains('প্রশ্ন ১'));
      expect(questions[0].marks, 20);
      expect(questions[0].modelAnswer, contains('উত্তরাধিকার পরিকল্পনা'));

      // Question 2
      expect(questions[1].number, 2);
      expect(questions[1].prompt, contains('Question 2'));
      expect(questions[1].marks, 20);
      expect(questions[1].moduleCode, 'A'); // Bank Company Act -> Module A
      expect(questions[1].modelAnswer, contains('Section 45'));

      // Question 3
      expect(questions[2].number, 3);
      expect(questions[2].marks, 15);
      expect(questions[2].moduleCode,
          'A'); // Negotiable Instruments Act -> Module A
    });

    test('generates standard 8-question fallback on blank markdown', () {
      final questions = StudyExamSimulatorExtractor.extractQuestions(
        subjectTitle: 'LPGB',
        markdownContent: '',
      );

      expect(questions.length, 8);
      expect(questions[0].number, 1);
      expect(questions[0].marks, 20);
      expect(questions[7].number, 8);
    });
  });

  group('ExamAttempt Model & Store', () {
    late Directory tempDir;
    late CountingSecureStorage storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('bhromon_exam_test_');
      Hive.init(tempDir.path);
      storage = CountingSecureStorage();
    });

    tearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    StudyExamAttemptStore store() => StudyExamAttemptStore(
          encryption: HiveEncryptionService.withStorage(storage),
        );

    final testAttempt = ExamAttempt(
      id: 'att_1',
      tourId: 't1',
      bookId: 'b1',
      chapterId: 'ch1',
      paperTitle: '99th BPE (Nov 2024)',
      durationMinutes: 180,
      startedAt: DateTime(2026, 11, 10, 10, 0),
      submittedAt: DateTime(2026, 11, 10, 12, 45),
      elapsedSeconds: 9900,
      isCompleted: true,
      draftAnswers: {
        'q_1':
            'Detailed answer outline discussing banking succession planning...',
        'q_2': 'Section 45 powers of central bank...',
      },
      scores: {
        'q_1': 16,
        'q_2': 18,
      },
      notes: 'Good performance on regulatory framework questions.',
    );

    test('calculates score totals, percentage, and pass status', () {
      expect(testAttempt.totalAwardedMarks, 34);
      expect(testAttempt.totalPossibleMarks, 100);
      expect(testAttempt.scorePercentage, 34.0);
      expect(testAttempt.isPassed, isFalse);

      final passingAttempt = testAttempt.copyWith(
        scores: {
          'q_1': 18,
          'q_2': 18,
          'q_3': 18,
        },
      );
      expect(passingAttempt.totalAwardedMarks, 54);
      expect(passingAttempt.scorePercentage, 54.0);
      expect(passingAttempt.isPassed, isTrue);
    });

    test('tracks per-question attempt status accurately', () {
      expect(testAttempt.questionStatus('q_1'), ExamQuestionStatus.answered);
      expect(testAttempt.questionStatus('q_2'), ExamQuestionStatus.inProgress);
      expect(testAttempt.questionStatus('q_3'), ExamQuestionStatus.unattempted);
    });

    test('round-trips through encrypted Hive store', () async {
      await store().put(testAttempt);

      final loaded = await store().loadForBook('b1');
      expect(loaded.length, 1);
      final read = loaded.first;

      expect(read.id, 'att_1');
      expect(read.paperTitle, '99th BPE (Nov 2024)');
      expect(read.durationMinutes, 180);
      expect(read.isCompleted, isTrue);
      expect(read.draftAnswers['q_1'], contains('succession planning'));
      expect(read.scores['q_1'], 16);
      expect(read.scores['q_2'], 18);
    });
  });
}
