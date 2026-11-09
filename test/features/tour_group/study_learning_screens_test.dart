import 'dart:async';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/study_flashcard_store.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/study_flashcard_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_glossary_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_quiz_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/pages/study_flashcards_screen.dart';
import 'package:bhromon/features/tour_group/presentation/pages/study_glossary_screen.dart';
import 'package:bhromon/features/tour_group/presentation/pages/study_quiz_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// The learning tools with fake data. An admin approves a proposed question and it joins the quiz. A member sees
// their own record. An approved term becomes a flashcard once. A due card is reviewed and its new box is saved.
// The rules behind these writes are tested on the emulator in functions/tests/study_learning_rules.test.js.

/// A value that tells its listeners when it changes, so a screen sees an approval at once.
class _Live<T> {
  _Live(this._value);

  T _value;
  final StreamController<T> _changes = StreamController<T>.broadcast();

  T get value => _value;

  set value(T next) {
    _value = next;
    _changes.add(next);
  }

  Stream<T> get stream => Stream<T>.multi((out) {
        out.add(_value);
        final sub = _changes.stream.listen(out.add);
        out.onCancel = sub.cancel;
      });
}

class _FakeQuizRepo extends TourGroupRepository {
  _FakeQuizRepo({
    required this.role,
    required List<StudyQuizQuestion> questions,
    this.attempt,
  }) : _questions = _Live(questions);

  final TourRole? role;
  final StudyQuizAttempt? attempt;
  final _Live<List<StudyQuizQuestion>> _questions;
  final List<String> calls = [];

  @override
  String get currentEmail => 'me@x.com';

  @override
  Future<TourRole?> myRole(String tourId) async => role;

  @override
  Stream<List<StudyQuiz>> watchStudyQuizzes(String tourId, String bookId) =>
      Stream.value(const [_quiz]);

  @override
  Stream<List<StudyChapter>> watchStudyChapters(String tourId, String bookId) =>
      Stream.value(const []);

  @override
  Stream<List<StudyQuizQuestion>> watchQuizQuestions(
    String tourId,
    String bookId,
    String quizId,
  ) =>
      _questions.stream;

  @override
  Stream<StudyQuizAttempt?> watchMyQuizAttempt(
    String tourId,
    String bookId,
    String quizId,
  ) =>
      Stream.value(attempt);

  @override
  Future<void> approveQuizQuestion(
    String tourId,
    String bookId,
    String quizId,
    String questionId,
  ) async {
    calls.add('approve $questionId');
    _questions.value = [
      for (final q in _questions.value)
        if (q.id == questionId)
          StudyQuizQuestion(
            id: q.id,
            type: q.type,
            text: q.text,
            explanation: q.explanation,
            choices: q.choices,
            answerIndex: q.answerIndex,
            approved: true,
            proposedByEmail: q.proposedByEmail,
          )
        else
          q,
    ];
  }
}

class _FakeGlossaryRepo extends TourGroupRepository {
  _FakeGlossaryRepo(this.terms);

  final List<StudyGlossaryTerm> terms;

  @override
  String get currentEmail => 'me@x.com';

  @override
  Future<TourRole?> myRole(String tourId) async => TourRole.member;

  @override
  Stream<List<StudyGlossaryTerm>> watchGlossary(String tourId, String bookId) =>
      Stream.value(terms);

  @override
  Stream<List<StudyChapter>> watchStudyChapters(String tourId, String bookId) =>
      Stream.value(const []);
}

/// Flashcards in memory, so a test can read what a screen saved.
class _FakeStore extends StudyFlashcardStore {
  final Map<String, StudyFlashcard> cards = {};

  @override
  Future<List<StudyFlashcard>> loadAll() async => cards.values.toList();

  @override
  Future<void> putAll(Iterable<StudyFlashcard> items) async {
    for (final card in items) {
      cards[card.id] = card;
    }
  }

  @override
  Future<void> delete(String id) async {
    cards.remove(id);
  }
}

const _book =
    StudyBook(id: 'b1', title: 'Anna Karenina', createdByEmail: 'admin@x.com');

const _quiz = StudyQuiz(
  id: 'q1',
  chapterId: 'c1',
  title: 'Chapter one',
  createdByEmail: 'admin@x.com',
);

const _proposal = StudyQuizQuestion(
  id: 'p1',
  type: StudyQuestionType.single,
  text: 'Who wrote it?',
  explanation: 'Tolstoy wrote it.',
  choices: ['Tolstoy', 'Dostoevsky'],
  answerIndex: 0,
  proposedByEmail: 'member@x.com',
);

const _approvedQuestion = StudyQuizQuestion(
  id: 'a1',
  type: StudyQuestionType.trueFalse,
  text: 'Anna is a novel.',
  explanation: 'It is a novel by Tolstoy.',
  answerIndex: 0,
  approved: true,
  proposedByEmail: 'admin@x.com',
);

const _term = StudyGlossaryTerm(
  id: 't1',
  term: 'Vronsky',
  definition: 'The officer Anna loves.',
  approved: true,
  createdByEmail: 'admin@x.com',
);

Future<void> _pump(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: page,
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an admin approves a proposed question and it joins the quiz',
      (tester) async {
    final repo = _FakeQuizRepo(
      role: TourRole.admin,
      questions: const [_proposal],
    );
    await _pump(
      tester,
      StudyQuizScreen(
        tourId: 't1',
        book: _book,
        quiz: _quiz,
        repository: repo,
      ),
    );

    expect(find.text('Proposed questions'), findsOneWidget);
    expect(find.text('Who wrote it?'), findsOneWidget);

    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    expect(repo.calls, ['approve p1']);
    expect(find.text('Proposed questions'), findsNothing);
    expect(find.text('Questions'), findsOneWidget);
    final take = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Take the quiz'),
    );
    expect(take.onPressed, isNotNull);
  });

  testWidgets('a member sees their own record on the quiz', (tester) async {
    final repo = _FakeQuizRepo(
      role: TourRole.member,
      questions: const [_approvedQuestion],
      attempt: const StudyQuizAttempt(best: 80, last: 60, attempts: 2),
    );
    await _pump(
      tester,
      StudyQuizScreen(
        tourId: 't1',
        book: _book,
        quiz: _quiz,
        repository: repo,
      ),
    );

    expect(find.text('Your record · only you can see it'), findsOneWidget);
    expect(find.text('Best 80% · Last 60% · Attempts 2'), findsOneWidget);
    expect(find.text('Propose a question'), findsOneWidget);
  });

  testWidgets('an approved term becomes a flashcard once', (tester) async {
    final store = _FakeStore();
    await _pump(
      tester,
      StudyGlossaryScreen(
        tourId: 't1',
        book: _book,
        repository: _FakeGlossaryRepo(const [_term]),
        store: store,
      ),
    );

    expect(find.text('Vronsky'), findsOneWidget);

    await tester.tap(find.byTooltip('Make a flashcard'));
    await tester.pumpAndSettle();
    expect(store.cards, hasLength(1));
    expect(store.cards.values.single.front, 'Vronsky');
    expect(store.cards.values.single.termId, 't1');

    await tester.tap(find.byTooltip('Make a flashcard'));
    await tester.pumpAndSettle();
    expect(find.text('This term already has a flashcard.'), findsOneWidget);
    expect(store.cards, hasLength(1));
  });

  testWidgets('a due card is reviewed and its new box is saved',
      (tester) async {
    final store = _FakeStore()
      ..cards['c1'] = const StudyFlashcard(
        id: 'c1',
        deckId: 'b1',
        front: 'Who is Anna?',
        back: 'A woman in a novel',
        dueOn: '2026-11-08',
      );
    await _pump(
      tester,
      StudyFlashcardsScreen(
        book: _book,
        store: store,
        today: DateTime(2026, 11, 9),
      ),
    );

    expect(find.text('1 due today · 1 cards'), findsOneWidget);

    await tester.tap(find.text('Review due cards'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show the answer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();

    expect(store.cards['c1']?.box, 2);
    expect(store.cards['c1']?.dueOn, '2026-11-11');
    expect(find.text('You reviewed 1 cards.'), findsOneWidget);
  });
}
