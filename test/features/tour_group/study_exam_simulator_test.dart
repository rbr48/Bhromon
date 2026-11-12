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

/// Keeps attempts in memory. Tests choose whether a write succeeds, and see every write.
class _FakeExamAttemptStore extends StudyExamAttemptStore {
  _FakeExamAttemptStore({this.open, this.writesSucceed = true});

  /// The attempt still open for the paper, returned on load.
  final ExamAttempt? open;
  final bool writesSucceed;
  final List<ExamAttempt> writes = [];

  @override
  Future<bool> put(ExamAttempt attempt) async {
    writes.add(attempt);
    return writesSucceed;
  }

  @override
  Future<bool> saveAttempt(ExamAttempt attempt) => put(attempt);

  @override
  Future<ExamAttempt?> loadOpenFor({
    required String bookId,
    required String chapterId,
  }) async =>
      open;

  @override
  Future<List<ExamAttempt>> loadAll() async => const [];
}

Widget _buildTestApp(
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

const List<ExamQuestion> _twoQuestions = [
  ExamQuestion(
    id: 'q_1',
    number: 1,
    prompt: 'Question 1: Explain banker lien rights [Marks: 20]',
    marks: 20,
    modelAnswer: 'Lien is the right to retain goods until debt is discharged.',
  ),
  ExamQuestion(
    id: 'q_2',
    number: 2,
    prompt: 'Question 2: Types of crossed cheques [Marks: 20]',
    marks: 20,
    modelAnswer: 'General crossing and special crossing.',
  ),
];

void main() {
  group('StudyExamSimulatorExtractor', () {
    test('no question on the paper means the exam is not offered', () {
      expect(
        StudyExamSimulatorExtractor.extractQuestions(
          subjectTitle: 'Laws',
          markdownContent: 'Some text with no question headings.',
        ),
        isEmpty,
      );
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

      expect(attempt.questionStatus('q_1'), ExamQuestionStatus.answered);
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
      expect(revived.paperMarks, 100);
    });

    test('failing score (< 45%) is marked as not passed', () {
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
      final start = DateTime(2026, 11, 11, 9, 0);
      await tester.pumpWidget(
        _buildTestApp(
          StudyExamSimulatorScreen(
            tourId: 'tour_test',
            bookId: 'book_test',
            paperTitle: '97th BPE Exam Simulator',
            initialQuestions: _twoQuestions,
            initialDurationMinutes: 180,
            store: _FakeExamAttemptStore(),
            clock: () => start,
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

      // Verify Submit Button opens confirmation dialog with the answered count
      final submitButton = find.text('Submit Exam');
      expect(submitButton, findsOneWidget);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      expect(find.text('Submit Exam'), findsWidgets);
      expect(
        find.textContaining('Are you sure you want to submit your exam paper?'),
        findsOneWidget,
      );
      expect(find.textContaining('Answered 1 of 2 questions.'), findsOneWidget);
    });

    testWidgets('the selected question shows no checkmark of its own',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          StudyExamSimulatorScreen(
            tourId: 'tour_test',
            bookId: 'book_test',
            paperTitle: 'Paper',
            initialQuestions: _twoQuestions,
            store: _FakeExamAttemptStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Nothing is answered yet, so no tick shows, even on the selected question.
      expect(find.byIcon(Icons.check), findsNothing);
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    });

    testWidgets('a paper with no questions says so and offers no exam',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          StudyExamSimulatorScreen(
            tourId: 'tour_test',
            bookId: 'book_test',
            paperTitle: 'Paper',
            rawContent: 'Notes with no question heading in them.',
            store: _FakeExamAttemptStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining("This paper's text is not on this phone yet"),
        findsOneWidget,
      );
      expect(find.text('Submit Exam'), findsNothing);
    });

    testWidgets('the clock is the wall clock, so time away is not paused',
        (tester) async {
      var now = DateTime(2026, 11, 11, 9, 0);
      await tester.pumpWidget(
        _buildTestApp(
          StudyExamSimulatorScreen(
            tourId: 'tour_test',
            bookId: 'book_test',
            paperTitle: 'Paper',
            initialQuestions: _twoQuestions,
            store: _FakeExamAttemptStore(),
            clock: () => now,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('03:00:00'), findsOneWidget);

      // Half an hour passes while the screen is not ticking (the app was away).
      now = now.add(const Duration(minutes: 30));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('02:30:00'), findsOneWidget);
    });

    testWidgets('an open attempt for this paper resumes its drafts and time',
        (tester) async {
      final now = DateTime(2026, 11, 11, 9, 0);
      final open = ExamAttempt(
        id: 'att_open',
        tourId: 'tour_test',
        bookId: 'book_test',
        chapterId: '',
        paperTitle: 'Paper',
        durationMinutes: 180,
        startedAt: now.subtract(const Duration(hours: 1)),
        draftAnswers: const {'q_1': 'Resumed draft text'},
      );

      await tester.pumpWidget(
        _buildTestApp(
          StudyExamSimulatorScreen(
            tourId: 'tour_test',
            bookId: 'book_test',
            paperTitle: 'Paper',
            initialQuestions: _twoQuestions,
            store: _FakeExamAttemptStore(open: open),
            clock: () => now,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('02:00:00'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Resumed draft text',
      );
      expect(find.textContaining('Your exam is still running'), findsOneWidget);
    });

    testWidgets('an attempt whose time ran out while away is handed in on open',
        (tester) async {
      final now = DateTime(2026, 11, 11, 13, 0);
      final store = _FakeExamAttemptStore(
        open: ExamAttempt(
          id: 'att_expired',
          tourId: 'tour_test',
          bookId: 'book_test',
          chapterId: '',
          paperTitle: 'Paper',
          durationMinutes: 180,
          startedAt: now.subtract(const Duration(hours: 4)),
          draftAnswers: const {'q_1': 'Written before the time ended'},
        ),
      );

      await tester.pumpWidget(
        _buildTestApp(
          StudyExamSimulatorScreen(
            tourId: 'tour_test',
            bookId: 'book_test',
            paperTitle: 'Paper',
            initialQuestions: _twoQuestions,
            store: store,
            clock: () => now,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(store.writes.last.isCompleted, isTrue);
      expect(store.writes.last.draftAnswers['q_1'],
          'Written before the time ended');
      expect(find.text('Exam Review & Model Answers'), findsOneWidget);
    });

    testWidgets('a write that fails keeps the candidate on the paper',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          StudyExamSimulatorScreen(
            tourId: 'tour_test',
            bookId: 'book_test',
            paperTitle: 'Paper',
            initialQuestions: _twoQuestions,
            store: _FakeExamAttemptStore(writesSucceed: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('This could not be saved on this phone'),
        findsWidgets,
      );

      await tester.tap(find.text('Submit Exam'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Exam Review & Model Answers'), findsNothing);
      expect(find.text('Submit Exam'), findsWidgets);
    });

    testWidgets('leaving with an open attempt asks first', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          StudyExamSimulatorScreen(
            tourId: 'tour_test',
            bookId: 'book_test',
            paperTitle: 'Paper',
            initialQuestions: _twoQuestions,
            store: _FakeExamAttemptStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Leave the exam?'), findsOneWidget);
      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();
      expect(find.text('Leave the exam?'), findsNothing);
      expect(find.text('Submit Exam'), findsOneWidget);
    });

    testWidgets('the digits follow the language: Bengali digits in Bengali',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          StudyExamSimulatorScreen(
            tourId: 'tour_test',
            bookId: 'book_test',
            paperTitle: 'Paper',
            initialQuestions: _twoQuestions,
            store: _FakeExamAttemptStore(),
            clock: () => DateTime(2026, 11, 11, 9, 0),
          ),
          locale: const Locale('bn'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('০৩:০০:০০'), findsOneWidget);
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
        _buildTestApp(
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
      expect(find.text('NEEDS IMPROVEMENT (< 45%)'), findsOneWidget);

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

    testWidgets('the total is out of the paper and the pass is decided on it',
        (tester) async {
      // An 8 x 20 paper: 45 marks is 28% of 160, so it fails.
      final attempt = ExamAttempt(
        id: 'att_paper',
        tourId: 'tour_test',
        bookId: 'book_test',
        chapterId: 'chap_1',
        paperTitle: 'Paper',
        durationMinutes: 180,
        startedAt: DateTime(2026, 11, 10, 10, 0),
        isCompleted: true,
        paperMarks: 160,
        scores: const {'q_1': 45},
      );

      await tester.pumpWidget(
        _buildTestApp(
          StudyExamReviewScreen(
            attempt: attempt,
            questions: _twoQuestions,
            store: _FakeExamAttemptStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('45 / 160'), findsOneWidget);
      expect(find.text('28.1%'), findsOneWidget);
      expect(find.text('NEEDS IMPROVEMENT (< 45%)'), findsOneWidget);
    });
  });
}
