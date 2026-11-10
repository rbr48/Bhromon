import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_rich_text.dart';
import 'package:bhromon/features/tour_group/data/study_exam_attempt_store.dart';
import 'package:bhromon/features/tour_group/domain/models/study_exam_simulator_models.dart';
import 'package:bhromon/features/tour_group/domain/services/study_exam_simulator_rules.dart';
import 'package:bhromon/features/tour_group/presentation/pages/study_exam_review_screen.dart';
import 'package:bhromon/features/tour_group/presentation/pages/study_exam_simulator_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeExamAttemptStore extends StudyExamAttemptStore {
  @override
  Future<void> put(ExamAttempt attempt) async {}

  @override
  Future<void> saveAttempt(ExamAttempt attempt) async {}
}

void main() {
  Widget buildTestApp(
    Widget child, {
    Locale locale = const Locale('en'),
    ThemeData? theme,
  }) {
    return MaterialApp(
      locale: locale,
      theme: theme ?? ThemeData.light(),
      supportedLocales: const [Locale('en'), Locale('bn')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    );
  }

  group('StudyExamTimerRules', () {
    test('formatDuration converts durations into HH:mm:ss format accurately',
        () {
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
          const Duration(minutes: 9, seconds: 5),
        ),
        '00:09:05',
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

    test('getAlertState returns correct alert tiers for countdown progress',
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
        StudyExamTimerRules.getAlertState(const Duration(minutes: 25)),
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
  });

  group('StudyExamSimulatorExtractor', () {
    test('extracts structured questions and marks from past paper markdown',
        () {
      const markdown = '''
### প্রশ্ন ১ [মান: ২০]
১(ক) ব্যাংকার ও গ্রাহকের সম্পর্ক বলতে কী বোঝায়?
১(খ) সাধারণ ও বিশেষ সম্পর্কের বিস্তারিত ব্যাখ্যা দিন।
মডেল উত্তর ১।

### প্রশ্ন ২ [মান: (১০+১০) = ২০]
ব্যাংক ড্রাফট ও পে-অর্ডারের পার্থক্য আলোচনা করুন।
মডেল উত্তর ২।
''';

      final questions = StudyExamSimulatorExtractor.extractQuestions(
        subjectTitle: 'Laws & Practice of General Banking',
        markdownContent: markdown,
      );

      expect(questions.length, 2);
      expect(questions[0].number, 1);
      expect(questions[0].marks, 20);
      expect(questions[0].prompt, contains('প্রশ্ন ১'));
      expect(questions[0].modelAnswer, contains('মডেল উত্তর ১'));

      expect(questions[1].number, 2);
      expect(questions[1].marks, 20);
      expect(questions[1].prompt, contains('প্রশ্ন ২'));
      expect(questions[1].modelAnswer, contains('মডেল উত্তর ২'));
    });

    test('fallbackQuestions generates standard 8 questions for syllabus', () {
      final questions = StudyExamSimulatorExtractor.fallbackQuestions(
        'Laws & Practice of General Banking',
        count: 8,
      );

      expect(questions.length, 8);
      for (var i = 0; i < 8; i++) {
        expect(questions[i].number, i + 1);
        expect(questions[i].marks, 20);
        expect(questions[i].id, 'q_${i + 1}');
      }
    });
  });

  group('ExamAttempt & Scoring Models', () {
    test(
        'computes scores, percentage, pass/fail and question statuses correctly',
        () {
      final attempt = ExamAttempt(
        id: 'att_123',
        tourId: 'tour_abc',
        bookId: 'book_xyz',
        chapterId: 'chap_1',
        paperTitle: 'LPGB 97th BPE',
        durationMinutes: 180,
        startedAt: DateTime(2026, 11, 10, 10, 0),
        elapsedSeconds: 7200,
        draftAnswers: const {
          'q_1': 'Short note',
          'q_2':
              'Detailed analysis of Banker-Customer relationship under section 5 of the Bank Company Act 1991.',
          'q_3': '',
        },
        scores: const {
          'q_1': 12,
          'q_2': 18,
          'q_3': 15,
          'q_4': 10,
        },
      );

      expect(attempt.totalAwardedMarks, 55);
      expect(attempt.totalScore, 55);
      expect(attempt.totalMarks, 100);
      expect(attempt.scorePercentage, 55.0);
      expect(attempt.percentage, 55.0);
      expect(attempt.isPassed, isTrue);

      expect(attempt.questionStatus('q_1'), ExamQuestionStatus.inProgress);
      expect(attempt.questionStatus('q_2'), ExamQuestionStatus.answered);
      expect(attempt.questionStatus('q_3'), ExamQuestionStatus.unattempted);
      expect(attempt.questionStatus('q_99'), ExamQuestionStatus.unattempted);

      // JSON serialization round-trip
      final json = attempt.toJson();
      final revived = ExamAttempt.fromJson(json);
      expect(revived, isNotNull);
      expect(revived!.id, 'att_123');
      expect(revived.totalScore, 55);
      expect(revived.isPassed, isTrue);
    });

    test('failing score (< 50%) is marked as not passed', () {
      final attempt = ExamAttempt(
        id: 'att_fail',
        tourId: 'tour_abc',
        bookId: 'book_xyz',
        chapterId: 'chap_1',
        paperTitle: 'LPGB 97th BPE',
        durationMinutes: 180,
        startedAt: DateTime(2026, 1, 1),
        scores: const {'q_1': 10, 'q_2': 15, 'q_3': 15}, // 40 / 100
      );

      expect(attempt.totalScore, 40);
      expect(attempt.scorePercentage, 40.0);
      expect(attempt.isPassed, isFalse);
    });
  });

  group('StudyExamSimulatorScreen', () {
    testWidgets('renders HUD timer, question navigation, and scratchpad',
        (tester) async {
      final questions = [
        const ExamQuestion(
          id: 'q_1',
          number: 1,
          prompt: 'Question 1: Explain banker lien rights [Marks: 20]',
          marks: 20,
          modelAnswer:
              'Lien is the right to retain goods until debt is discharged.',
        ),
        const ExamQuestion(
          id: 'q_2',
          number: 2,
          prompt: 'Question 2: Types of crossed cheques [Marks: 20]',
          marks: 20,
          modelAnswer: 'General crossing and special crossing.',
        ),
      ];

      await tester.pumpWidget(
        buildTestApp(
          StudyExamSimulatorScreen(
            tourId: 'tour_test',
            bookId: 'book_test',
            paperTitle: '97th BPE Exam Simulator',
            initialQuestions: questions,
            initialDurationMinutes: 180,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Title & HUD timer
      expect(find.text('97th BPE Exam Simulator'), findsOneWidget);
      expect(find.text('03:00:00'), findsOneWidget);
      expect(find.byIcon(Icons.timer_outlined), findsWidgets);

      // Verify Question Prompt & Marks
      expect(find.text('Question 1: Explain banker lien rights [Marks: 20]'),
          findsOneWidget);
      expect(find.text('Marks: 20'), findsOneWidget);

      // Verify scratchpad editing
      final scratchpadFinder = find.byType(TextField);
      expect(scratchpadFinder, findsOneWidget);
      await tester.enterText(
          scratchpadFinder, 'Candidate draft outline for question 1.');
      await tester.pumpAndSettle();

      // Navigate to Next Question
      final nextButtonFinder = find.byTooltip('Next question');
      if (nextButtonFinder.evaluate().isNotEmpty) {
        await tester.tap(nextButtonFinder);
        await tester.pumpAndSettle();
        expect(find.text('Question 2: Types of crossed cheques [Marks: 20]'),
            findsOneWidget);
      }

      // Verify Submit Button opens confirmation dialog
      final submitButton = find.text('Submit Exam');
      expect(submitButton, findsOneWidget);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      expect(find.text('Submit Exam'), findsWidgets);
      expect(
        find.textContaining('Are you sure you want to submit your exam paper?'),
        findsOneWidget,
      );
    });
  });

  group('StudyExamReviewScreen', () {
    testWidgets(
        'renders score hero card, model answers, and interactive stepper',
        (tester) async {
      final questions = [
        const ExamQuestion(
          id: 'q_1',
          number: 1,
          prompt: 'Question 1: Explain banker lien rights [Marks: 20]',
          marks: 20,
          modelAnswer:
              'Lien is the right to retain goods until debt is discharged.',
        ),
      ];

      final attempt = ExamAttempt(
        id: 'att_review_test',
        tourId: 'tour_test',
        bookId: 'book_test',
        chapterId: 'chap_1',
        paperTitle: '97th BPE Exam',
        durationMinutes: 180,
        startedAt: DateTime(2026, 11, 10, 10, 0),
        elapsedSeconds: 5400, // 1h 30m
        isCompleted: true,
        draftAnswers: const {
          'q_1':
              'Candidate draft: Section 171 Contract Act 1872 gives general lien to bankers.',
        },
        scores: const {'q_1': 16},
      );

      await tester.pumpWidget(
        buildTestApp(
          StudyExamReviewScreen(
            attempt: attempt,
            questions: questions,
            store: _FakeExamAttemptStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Review Header & Time spent
      expect(find.text('Exam Review & Model Answers'), findsOneWidget);
      expect(find.textContaining('01:30:00'), findsOneWidget);

      // Verify Score card
      expect(find.text('16 / 100'), findsOneWidget);
      expect(find.text('16.0%'), findsOneWidget);
      expect(find.text('NEEDS IMPROVEMENT (< 50%)'), findsOneWidget);

      // Verify Candidate draft vs Model answer
      expect(
        find.textContaining('Candidate draft: Section 171 Contract Act 1872'),
        findsOneWidget,
      );
      expect(find.byType(ChatRichText), findsWidgets);

      // Interactive score stepper: increase marks
      final addIconFinder = find.byIcon(Icons.add_circle_outline_rounded);
      expect(addIconFinder, findsOneWidget);
      await tester.ensureVisible(addIconFinder);
      await tester.tap(addIconFinder);
      await tester.pumpAndSettle();

      expect(find.text('17 / 100'), findsOneWidget);
    });
  });
}
