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
          const Duration(hours: 1, minutes: 45, seconds: 12),
        ),
        '01:45:12',
      );
      expect(
        StudyExamTimerRules.formatDuration(
            const Duration(minutes: 9, seconds: 5)),
        '00:09:05',
      );
      expect(StudyExamTimerRules.formatDuration(Duration.zero), '00:00:00');
      expect(
        StudyExamTimerRules.formatDuration(const Duration(seconds: -10)),
        '00:00:00',
      );
    });

    test('alert tiers: normal above 30 minutes, warning to 30, critical to 10',
        () {
      expect(
        StudyExamTimerRules.getAlertState(const Duration(hours: 2)),
        ExamTimerAlertState.normal,
      );
      expect(
        StudyExamTimerRules.getAlertState(const Duration(minutes: 30)),
        ExamTimerAlertState.warning,
      );
      expect(
        StudyExamTimerRules.getAlertState(const Duration(minutes: 10)),
        ExamTimerAlertState.critical,
      );
      expect(
        StudyExamTimerRules.getAlertState(const Duration(seconds: 45)),
        ExamTimerAlertState.critical,
      );
      expect(
        StudyExamTimerRules.getAlertState(Duration.zero),
        ExamTimerAlertState.expired,
      );
      expect(
        StudyExamTimerRules.getAlertState(const Duration(seconds: -5)),
        ExamTimerAlertState.expired,
      );
    });

    test('a warning is reported when the time left first falls to it', () {
      expect(
        StudyExamTimerRules.crossedWarning(
          const Duration(minutes: 31),
          const Duration(minutes: 29),
        ),
        ExamTimerWarning.thirtyMinutes,
      );
      // Already below 30 minutes: the 30 warning was reported before.
      expect(
        StudyExamTimerRules.crossedWarning(
          const Duration(minutes: 29),
          const Duration(minutes: 28),
        ),
        isNull,
      );
      expect(
        StudyExamTimerRules.crossedWarning(
          const Duration(minutes: 11),
          const Duration(minutes: 9),
        ),
        ExamTimerWarning.tenMinutes,
      );
      // A jump past the 30 mark still reports the more urgent 10 mark.
      expect(
        StudyExamTimerRules.crossedWarning(
          const Duration(minutes: 31),
          const Duration(minutes: 9),
        ),
        ExamTimerWarning.tenMinutes,
      );
      // A time that is already over reports no warning.
      expect(
        StudyExamTimerRules.crossedWarning(
          const Duration(minutes: 11),
          Duration.zero,
        ),
        isNull,
      );
    });
  });

  group('StudyExamSimulatorExtractor', () {
    const sample = '''
### প্রশ্ন ১ [মান: ১০ + ১০ = ২০]
১(ক) উত্তরাধিকার পরিকল্পনা কী?
১(খ) ব্যাংকিং খাতে এর প্রয়োজনীয়তা আলোচনা করুন।

### Question 2 [Marks: 20]
Explain the provisions of Section 45 of Bank Company Act 1991 regarding power of Bangladesh Bank.

### Question 3 [Marks: 15]
Discuss the differences between a Cheque and a Bill of Exchange under Negotiable Instruments Act 1881.
''';

    test('reads each question, its marks and its text from the paper', () {
      final questions = StudyExamSimulatorExtractor.extractQuestions(
        subjectTitle: 'Laws & Practice of General Banking',
        markdownContent: sample,
      );

      expect(questions.length, 3);
      expect(questions[0].number, 1);
      expect(questions[0].marks, 20);
      // No answer marker: the heading is the prompt and the text is the model answer.
      expect(questions[0].prompt, contains('প্রশ্ন ১'));
      expect(questions[0].modelAnswer, contains('উত্তরাধিকার পরিকল্পনা'));
      expect(questions[1].marks, 20);
      expect(questions[1].prompt, contains('Question 2'));
      expect(questions[1].modelAnswer, contains('Section 45'));
      expect(questions[2].number, 3);
      expect(questions[2].marks, 15);
    });

    test(
        'the text before an answer marker is the question, after it the answer',
        () {
      const markdown = '''
### Question 4 [Marks: 20]
Explain the general lien of a banker under the Contract Act.

**Answer:** A banker's general lien is the right to retain goods until the dues are paid (section 171).
''';

      final question = StudyExamSimulatorExtractor.extractQuestions(
        subjectTitle: 'Laws',
        markdownContent: markdown,
      ).single;

      expect(question.heading, 'Question 4 [Marks: 20]');
      expect(question.prompt, contains('Explain the general lien'));
      expect(question.prompt, isNot(contains('section 171')));
      expect(question.modelAnswer, startsWith("A banker's general lien"));
      expect(question.modelAnswer, isNot(contains('Explain the general lien')));
      expect(question.modelAnswer, isNot(contains('**')));
    });

    test('a word that begins like an answer marker is not split', () {
      final parts = StudyExamSimulatorExtractor.splitBody(
        'উত্তরাধিকার বলতে কী বোঝায়?\nব্যাখ্যা করুন।',
      );
      expect(parts.statement, isEmpty);
      expect(parts.answer, contains('উত্তরাধিকার বলতে কী বোঝায়?'));
    });

    test('a solution heading on its own line separates statement and answer',
        () {
      final parts = StudyExamSimulatorExtractor.splitBody(
        'Define a cheque.\n\nSolution\n\nA cheque is a bill payable on demand.',
      );
      expect(parts.statement, 'Define a cheque.');
      expect(parts.answer, 'A cheque is a bill payable on demand.');
    });

    test('Windows line endings read the same as Unix ones', () {
      final windows = sample.replaceAll('\n', '\r\n');

      final questions = StudyExamSimulatorExtractor.extractQuestions(
        subjectTitle: 'Laws',
        markdownContent: windows,
      );

      expect(questions.length, 3);
      expect(questions[2].marks, 15);
      expect(questions[1].modelAnswer, contains('Section 45'));
    });

    test('sub-parts under one number join one question', () {
      const markdown = '''
## Question 1 [Marks: 10]
(a) Define a cheque.

## Question 1 (b) [Marks: 10]
(b) Define a bill of exchange.
''';

      final questions = StudyExamSimulatorExtractor.extractQuestions(
        subjectTitle: 'Laws',
        markdownContent: markdown,
      );

      expect(questions.length, 1);
      expect(questions.single.marks, 10);
      expect(questions.single.heading, 'Question 1 [Marks: 10]');
      // With no answer marker, the text under the parts is the model answer.
      expect(questions.single.modelAnswer, contains('Define a cheque'));
      expect(
          questions.single.modelAnswer, contains('Define a bill of exchange'));
    });

    test('a paper with no question heading gives no questions', () {
      final questions = StudyExamSimulatorExtractor.extractQuestions(
        subjectTitle: 'Laws',
        markdownContent:
            '## Accounting ledger\n\nA note with no question in it.',
      );
      expect(questions, isEmpty);
    });

    test('every question of a long paper is kept', () {
      final markdown = [
        for (var n = 1; n <= 12; n++) '## Question $n [Marks: 20]\nText $n.',
      ].join('\n\n');

      final questions = StudyExamSimulatorExtractor.extractQuestions(
        subjectTitle: 'Laws',
        markdownContent: markdown,
      );

      expect(questions.length, 12);
      expect(questions.last.number, 12);
    });

    test('marks: a bracketed sum, Bengali digits, and no marks at all', () {
      expect(
        StudyExamSimulatorExtractor.parseMarks('Question 1 [Marks: 5 + 5]'),
        10,
      );
      expect(
        StudyExamSimulatorExtractor.parseMarks('Question 2 [Marks: ১৫]'),
        15,
      );
      expect(
        StudyExamSimulatorExtractor.parseMarks('প্রশ্ন ১ [মান: ১০ + ১০ = ২০]'),
        20,
      );
      expect(StudyExamSimulatorExtractor.parseMarks('Question 3'), isNull);
    });
  });

  group('ExamAttempt timing', () {
    final attempt = ExamAttempt(
      id: 'att_clock',
      tourId: 't1',
      bookId: 'b1',
      chapterId: 'ch1',
      paperTitle: 'Paper',
      durationMinutes: 180,
      startedAt: DateTime(2026, 11, 11, 9, 0),
    );

    test('the exam ends at its start plus its duration, on the wall clock', () {
      expect(attempt.endsAt, DateTime(2026, 11, 11, 12, 0));
      expect(
        attempt.remainingAt(DateTime(2026, 11, 11, 10, 30)),
        const Duration(minutes: 90),
      );
      expect(attempt.isOverAt(DateTime(2026, 11, 11, 11, 59)), isFalse);
      expect(attempt.isOverAt(DateTime(2026, 11, 11, 12, 0)), isTrue);
      expect(
        attempt.remainingAt(DateTime(2026, 11, 11, 13, 0)),
        Duration.zero,
      );
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

    test('the pass mark is 45 out of 100 in each subject (IBB clause 27)', () {
      expect(testAttempt.copyWith(scores: {'q_1': 44}).isPassed, isFalse);
      expect(testAttempt.copyWith(scores: {'q_1': 45}).isPassed, isTrue);
    });

    test('the percentage is out of the paper, not out of 100', () {
      // An 8 x 20 paper is 160 marks: 45 marks is 28%, which fails.
      final paper = testAttempt.copyWith(paperMarks: 160, scores: {'q_1': 45});
      expect(paper.totalPossibleMarks, 160);
      expect(paper.scorePercentage, closeTo(28.1, 0.1));
      expect(paper.isPassed, isFalse);
      // 72 of 160 is exactly 45%.
      expect(
        paper.copyWith(scores: {'q_1': 72}).isPassed,
        isTrue,
      );
      expect(
        paper.copyWith(scores: {'q_1': 71}).isPassed,
        isFalse,
      );
    });

    test('the pass decision is exact, not rounded to a tenth of a percent', () {
      // 98 of 218 is 44.95%, which rounds up to 45.0 but is below the mark.
      final close = testAttempt.copyWith(paperMarks: 218, scores: {'q_1': 98});
      expect(close.isPassed, isFalse);
      expect(close.copyWith(scores: {'q_1': 99}).isPassed, isTrue);
    });

    test('a question is answered once it has text, and unattempted otherwise',
        () {
      expect(testAttempt.questionStatus('q_1'), ExamQuestionStatus.answered);
      expect(testAttempt.questionStatus('q_2'), ExamQuestionStatus.answered);
      expect(testAttempt.questionStatus('q_3'), ExamQuestionStatus.unattempted);
      expect(
        testAttempt
            .copyWith(draftAnswers: {'q_3': '   '}).questionStatus('q_3'),
        ExamQuestionStatus.unattempted,
      );
      expect(
        testAttempt.answeredCount(['q_1', 'q_2', 'q_3']),
        2,
      );
    });

    test('a missing draft value is not read back as the word null', () {
      final revived = ExamAttempt.fromJson({
        'id': 'att_null',
        'startedAt': '2026-11-10T10:00:00.000',
        'draftAnswers': {'q_1': null, 'q_2': 'Kept'},
      });
      expect(revived, isNotNull);
      expect(revived!.draftAnswers, {'q_2': 'Kept'});
    });

    test('a score of the wrong type is left out, the rest still read', () {
      final revived = ExamAttempt.fromJson({
        'id': 'att_scores',
        'startedAt': '2026-11-10T10:00:00.000',
        'scores': {'q_1': 12, 'q_2': 'twelve'},
      });
      expect(revived!.scores, {'q_1': 12});
    });

    test('an attempt saved before paper marks were stored is out of 100', () {
      final legacy = ExamAttempt.fromJson({
        'id': 'att_old',
        'startedAt': '2026-11-10T10:00:00.000',
        'scores': {'q_1': 40},
      });
      expect(legacy!.paperMarks, 100);
      expect(legacy.isPassed, isFalse);
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

    test('one record that cannot be read does not hide the others', () async {
      final encryption = HiveEncryptionService.withStorage(storage);
      final s = StudyExamAttemptStore(encryption: encryption);
      await s.put(testAttempt);

      final box = await encryption.openEncryptedBox<dynamic>(
        StudyExamAttemptStore.boxName,
      );
      await box.put('bad_date', {'id': 'bad_date', 'startedAt': 'not a date'});
      await box.put('not_a_map', 'nonsense');

      final loaded = await s.loadAll();
      expect(loaded.map((a) => a.id), ['att_1']);
    });

    test('the open attempt of a paper is found, a handed-in one is not',
        () async {
      final s = store();
      await s.put(ExamAttempt(
        id: 'att_1',
        tourId: 't1',
        bookId: 'b1',
        chapterId: 'ch1',
        paperTitle: '99th BPE (Nov 2024)',
        durationMinutes: 180,
        startedAt: DateTime(2026, 11, 10, 10, 0),
      ));

      final open = await s.loadOpenFor(bookId: 'b1', chapterId: 'ch1');
      expect(open?.id, 'att_1');
      expect(await s.loadOpenFor(bookId: 'b1', chapterId: 'ch2'), isNull);
      // The attempt in the fixture is handed in: it is not open.
      await s.put(ExamAttempt(
        id: 'att_done',
        tourId: 't1',
        bookId: 'b1',
        chapterId: 'ch1',
        paperTitle: '99th BPE (Nov 2024)',
        durationMinutes: 180,
        startedAt: DateTime(2026, 11, 10, 8, 0),
        isCompleted: true,
        submittedAt: DateTime(2026, 11, 10, 10, 0),
      ));
      expect(
        (await s.loadOpenFor(bookId: 'b1', chapterId: 'ch1'))?.id,
        'att_1',
      );
    });

    test('without an encryption service nothing is written to disk', () async {
      final saved = await StudyExamAttemptStore().put(testAttempt);

      expect(saved, isFalse);
      expect(Hive.isBoxOpen(StudyExamAttemptStore.boxName), isFalse);
      final boxFile =
          File('${tempDir.path}/${StudyExamAttemptStore.boxName}.hive');
      expect(boxFile.existsSync(), isFalse);
      expect(await StudyExamAttemptStore().loadAll(), isEmpty);
    });
  });
}
