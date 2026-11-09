import 'package:bhromon/features/tour_group/domain/models/study_flashcard_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_glossary_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_quiz_models.dart';
import 'package:bhromon/features/tour_group/domain/services/study_flashcard_rules.dart';
import 'package:bhromon/features/tour_group/domain/services/study_glossary_rules.dart';
import 'package:bhromon/features/tour_group/domain/services/study_quiz_rules.dart';
import 'package:flutter_test/flutter_test.dart';

// The pure rules of the learning tools: quiz questions and their checks, scoring and a member's record, the
// glossary, and the flashcards kept on the device. The rules that the database enforces are tested on the emulator
// in functions/tests/study_learning_rules.test.js.

StudyQuizQuestion _question({
  StudyQuestionType type = StudyQuestionType.single,
  List<String> choices = const ['Tolstoy', 'Dostoevsky'],
  int? answerIndex = 0,
  bool approved = true,
  String proposedByEmail = 'member@x.com',
}) {
  return StudyQuizQuestion(
    id: 'q',
    type: type,
    text: 'Who wrote the novel?',
    explanation: 'The novel is by Tolstoy.',
    choices: choices,
    answerIndex: answerIndex,
    modelAnswer: type == StudyQuestionType.explain ? 'A model answer' : '',
    approved: approved,
    proposedByEmail: proposedByEmail,
  );
}

StudyFlashcard _card({
  String id = 'c1',
  int box = 1,
  String dueOn = '2026-11-09',
  String? termId,
}) {
  return StudyFlashcard(
    id: id,
    deckId: 'b1',
    front: 'Front $id',
    back: 'Back $id',
    box: box,
    dueOn: dueOn,
    termId: termId,
  );
}

void main() {
  group('quiz question checks', () {
    StudyQuestionProblem? check({
      StudyQuestionType type = StudyQuestionType.single,
      String text = 'A question?',
      String explanation = 'Because.',
      List<String> choices = const ['Yes', 'No'],
      int? answerIndex = 0,
      String modelAnswer = 'An answer',
    }) {
      return questionProblem(
        type: type,
        text: text,
        explanation: explanation,
        choices: choices,
        answerIndex: answerIndex,
        modelAnswer: modelAnswer,
      );
    }

    test(
        'a single-answer question needs its text, two to five choices and a right answer',
        () {
      expect(check(), isNull);
      expect(check(text: '   '), StudyQuestionProblem.emptyText);
      expect(check(text: 'x' * 301), isNull);
      expect(check(explanation: ''), StudyQuestionProblem.emptyExplanation);
      expect(check(choices: const ['Only one']),
          StudyQuestionProblem.choicesCount);
      expect(
        check(choices: const ['a', 'b', 'c', 'd', 'e', 'f']),
        StudyQuestionProblem.choicesCount,
      );
      expect(
          check(choices: const ['A', '  ']), StudyQuestionProblem.emptyChoice);
      expect(check(choices: ['A', 'x' * 151]), isNull);
      expect(check(answerIndex: null), StudyQuestionProblem.answerMissing);
      expect(check(answerIndex: 2), StudyQuestionProblem.answerMissing);
    });

    test('a true-or-false question takes only index 0 or 1 as its answer', () {
      StudyQuestionProblem? tf(int? answer) => check(
            type: StudyQuestionType.trueFalse,
            choices: const [],
            answerIndex: answer,
          );
      expect(tf(0), isNull);
      expect(tf(1), isNull);
      expect(tf(2), StudyQuestionProblem.answerMissing);
      expect(tf(null), StudyQuestionProblem.answerMissing);
    });

    test('an explain question needs a model answer within the limit', () {
      StudyQuestionProblem? explain(String answer) => check(
            type: StudyQuestionType.explain,
            choices: const [],
            answerIndex: null,
            modelAnswer: answer,
          );
      expect(explain('Because of the plot.'), isNull);
      expect(explain(''), StudyQuestionProblem.emptyModelAnswer);
      expect(explain('x' * 1001), isNull);
    });

    test(
        'a choice is right only when it is the answer index, and explain never is',
        () {
      final single = _question(answerIndex: 1);
      expect(isCorrectChoice(single, 1), isTrue);
      expect(isCorrectChoice(single, 0), isFalse);
      final explain =
          _question(type: StudyQuestionType.explain, answerIndex: null);
      expect(isCorrectChoice(explain, 0), isFalse);
    });
  });

  group('scoring and a member record', () {
    test(
        'the score is a whole percentage, rounded down and kept within 0 to 100',
        () {
      expect(scorePercent(correct: 0, total: 0), 0);
      expect(scorePercent(correct: 3, total: 4), 75);
      expect(scorePercent(correct: 1, total: 3), 33);
      expect(scorePercent(correct: 9, total: 3), 100);
      expect(scorePercent(correct: -2, total: 4), 0);
    });

    test('the first attempt sets the best and the last score', () {
      final first = nextAttempt(null, 60);
      expect(first.best, 60);
      expect(first.last, 60);
      expect(first.attempts, 1);
    });

    test(
        'a later attempt keeps the best score, replaces the last and counts up',
        () {
      final again = nextAttempt(
        const StudyQuizAttempt(best: 80, last: 80, attempts: 1),
        50,
      );
      expect(again.best, 80);
      expect(again.last, 50);
      expect(again.attempts, 2);

      final better = nextAttempt(
        const StudyQuizAttempt(best: 40, last: 40, attempts: 3),
        90,
      );
      expect(better.best, 90);
      expect(better.last, 90);
      expect(better.attempts, 4);
    });

    test('a score above 100 is kept at 100', () {
      expect(nextAttempt(null, 150).best, 100);
    });

    test('a stored record is read only when its scores and count are in range',
        () {
      final ok =
          StudyQuizAttempt.fromMap({'best': 70, 'last': 60, 'attempts': 2});
      expect(ok?.best, 70);
      expect(ok?.attempts, 2);
      expect(StudyQuizAttempt.fromMap({'best': 101, 'last': 1, 'attempts': 1}),
          isNull);
      expect(StudyQuizAttempt.fromMap({'best': 1, 'last': 1, 'attempts': 0}),
          isNull);
      expect(StudyQuizAttempt.fromMap({'best': 1, 'attempts': 1}), isNull);
    });
  });

  group('questions and who may change them', () {
    test('a quiz shows only the approved questions, in the order given', () {
      final shown = quizQuestions([
        _question(approved: true),
        _question(approved: false),
        _question(approved: true),
      ]);
      expect(shown, hasLength(2));
      expect(shown.every((q) => q.approved), isTrue);
    });

    test('only an admin approves a question', () {
      expect(canApproveQuestion(isAdmin: true), isTrue);
      expect(canApproveQuestion(isAdmin: false), isFalse);
    });

    test(
        'an admin removes any question; a member removes only their own proposal',
        () {
      final own = _question(approved: false, proposedByEmail: 'me@x.com');
      final theirs = _question(approved: false, proposedByEmail: 'other@x.com');
      final approved = _question(approved: true, proposedByEmail: 'me@x.com');

      expect(
          canRemoveQuestion(approved, viewerEmail: 'me@x.com', isAdmin: true),
          isTrue);
      expect(canRemoveQuestion(own, viewerEmail: 'me@x.com', isAdmin: false),
          isTrue);
      expect(canRemoveQuestion(theirs, viewerEmail: 'me@x.com', isAdmin: false),
          isFalse);
      expect(
          canRemoveQuestion(approved, viewerEmail: 'me@x.com', isAdmin: false),
          isFalse);
    });

    test('a question carries only the fields its kind uses', () {
      final single = _question().toFields();
      expect(single['choices'], ['Tolstoy', 'Dostoevsky']);
      expect(single['modelAnswer'], isNull);

      final tf = _question(type: StudyQuestionType.trueFalse, choices: const [])
          .toFields();
      expect(tf['choices'], isNull);
      expect(tf['answerIndex'], 0);

      final explain =
          _question(type: StudyQuestionType.explain, answerIndex: null)
              .toFields();
      expect(explain['choices'], isNull);
      expect(explain['answerIndex'], isNull);
      expect(explain['modelAnswer'], 'A model answer');
    });

    test('a damaged stored question is left out rather than read', () {
      expect(StudyQuizQuestion.fromMap('x', {'type': 'single', 'text': 'Q'}),
          isNull);
      expect(
        StudyQuizQuestion.fromMap(
            'x', {'type': 'essay', 'text': 'Q', 'explanation': 'E'}),
        isNull,
      );
      final read = StudyQuizQuestion.fromMap('x', {
        'type': 'single',
        'text': 'Q',
        'explanation': 'E',
        'choices': ['A', '  ', 'B'],
        'answerIndex': 1,
        'approved': 'yes',
      });
      expect(read?.choices, ['A', 'B']);
      expect(read?.approved, isFalse,
          reason: 'only a real true counts as approved');
    });

    test(
        'a quiz needs a title and a chapter to be read; takers default to zero',
        () {
      expect(StudyQuiz.fromMap('q', {'chapterId': 'c1'}), isNull);
      expect(StudyQuiz.fromMap('q', {'title': 'One', 'chapterId': ''}), isNull);
      final quiz = StudyQuiz.fromMap('q', {'title': 'One', 'chapterId': 'c1'});
      expect(quiz?.takerCount, 0);
    });
  });

  group('glossary', () {
    test('a term needs a word and a meaning, of any length', () {
      expect(termProblem(term: 'Vronsky', definition: 'The officer.'), isNull);
      expect(
          termProblem(term: ' ', definition: 'x'), StudyTermProblem.emptyTerm);
      expect(termProblem(term: 'x' * 81, definition: 'x'), isNull);
      expect(termProblem(term: 'a', definition: ''),
          StudyTermProblem.emptyDefinition);
      expect(termProblem(term: 'a', definition: 'x' * 501), isNull);
    });

    test('only approved terms are listed, sorted A to Z ignoring case', () {
      final terms = [
        const StudyGlossaryTerm(
            id: '1', term: 'bovary', definition: 'd', approved: true),
        const StudyGlossaryTerm(
            id: '2', term: 'Anna', definition: 'd', approved: true),
        const StudyGlossaryTerm(
            id: '3', term: 'Levin', definition: 'd', approved: false),
        const StudyGlossaryTerm(
            id: '4', term: 'Dolly', definition: 'd', approved: true),
      ];
      expect(
          approvedTerms(terms).map((t) => t.term), ['Anna', 'bovary', 'Dolly']);
    });

    test(
        'a term is approved only by an admin, and a member removes only their own proposal',
        () {
      expect(canApproveTerm(isAdmin: true), isTrue);
      expect(canApproveTerm(isAdmin: false), isFalse);

      const proposal = StudyGlossaryTerm(
        id: '1',
        term: 'Levin',
        definition: 'd',
        createdByEmail: 'me@x.com',
      );
      const approved = StudyGlossaryTerm(
        id: '2',
        term: 'Anna',
        definition: 'd',
        approved: true,
        createdByEmail: 'me@x.com',
      );
      expect(canRemoveTerm(proposal, viewerEmail: 'me@x.com', isAdmin: false),
          isTrue);
      expect(canRemoveTerm(approved, viewerEmail: 'me@x.com', isAdmin: false),
          isFalse);
      expect(canRemoveTerm(approved, viewerEmail: 'other@x.com', isAdmin: true),
          isTrue);
    });

    test(
        'a stored term with a blank chapter reads as belonging to the whole book',
        () {
      final term = StudyGlossaryTerm.fromMap('t', {
        'term': 'Anna',
        'definition': 'd',
        'chapterId': '  ',
      });
      expect(term?.chapterId, isNull);
    });
  });

  group('flashcards on the device', () {
    test(
        'a recalled card moves up one box, to the top at five; a missed card goes back to one',
        () {
      expect(nextLeitnerBox(1, recalled: true), 2);
      expect(nextLeitnerBox(5, recalled: true), 5);
      expect(nextLeitnerBox(3, recalled: false), 1);
    });

    test(
        'each box waits its interval, and an out-of-range box uses the nearest',
        () {
      expect(leitnerIntervalDays(1), 1);
      expect(leitnerIntervalDays(3), 4);
      expect(leitnerIntervalDays(5), 16);
      expect(leitnerIntervalDays(0), 1);
      expect(leitnerIntervalDays(9), 16);
    });

    test('the due day is counted in calendar days, across month ends', () {
      expect(dayKey(DateTime(2026, 3, 5)), '2026-03-05');
      expect(dueKeyAfterReview(DateTime(2026, 1, 31), 1), '2026-02-01');
      expect(dueKeyAfterReview(DateTime(2026, 11, 9, 23, 30), 5), '2026-11-25');
    });

    test('reviewing a card moves its box and sets when it is next due', () {
      final today = DateTime(2026, 11, 9);
      final knew = reviewCard(_card(box: 2), recalled: true, today: today);
      expect(knew.box, 3);
      expect(knew.dueOn, '2026-11-13');

      final missed = reviewCard(_card(box: 4), recalled: false, today: today);
      expect(missed.box, 1);
      expect(missed.dueOn, '2026-11-10');
    });

    test(
        'a card is due on its day and after it, and due cards come soonest first',
        () {
      final today = DateTime(2026, 11, 9);
      expect(isCardDue(_card(dueOn: '2026-11-09'), today), isTrue);
      expect(isCardDue(_card(dueOn: '2026-11-10'), today), isFalse);

      final due = dueCards([
        _card(id: 'late', dueOn: '2026-11-08'),
        _card(id: 'future', dueOn: '2026-11-12'),
        _card(id: 'early', dueOn: '2026-11-01'),
      ], today);
      expect(due.map((c) => c.id), ['early', 'late']);
    });

    test(
        'the Anki file quotes every field and doubles inner quotes, with no header',
        () {
      final csv = toAnkiCsv([
        const StudyFlashcard(
          id: '1',
          deckId: 'b1',
          front: 'Say "hi"',
          back: 'a, b',
          dueOn: '2026-11-09',
        ),
        const StudyFlashcard(
          id: '2',
          deckId: 'b1',
          front: 'Q2',
          back: 'A2',
          dueOn: '2026-11-09',
        ),
      ]);
      expect(csv, '"Say ""hi""","a, b"\n"Q2","A2"');
    });

    test(
        'a deck file round-trips, with new ids and the deck it is imported into',
        () {
      final cards = [_card(id: 'a', box: 3, termId: 't1'), _card(id: 'b')];
      var n = 0;
      final imported = deckFromJson(
        deckToJson(cards),
        deckId: 'b2',
        newId: () => 'new${++n}',
      );
      expect(imported, isNotNull);
      expect(imported!.map((c) => c.id), ['new1', 'new2']);
      expect(imported.every((c) => c.deckId == 'b2'), isTrue);
      expect(imported.first.front, cards.first.front);
      expect(imported.first.box, 3);
      expect(imported.first.termId, 't1');
    });

    test('a file that is not a deck of this format and version is refused', () {
      String newId() => 'x';
      expect(
          deckFromJson({'format': 'other', 'version': 1, 'cards': <Object>[]},
              deckId: 'b', newId: newId),
          isNull);
      expect(
          deckFromJson(
              {'format': kDeckFormat, 'version': 2, 'cards': <Object>[]},
              deckId: 'b', newId: newId),
          isNull);
      expect(
          deckFromJson({'format': kDeckFormat, 'version': 1, 'cards': 'nope'},
              deckId: 'b', newId: newId),
          isNull);
      expect(deckFromJson('not a map', deckId: 'b', newId: newId), isNull);
    });

    test('a damaged card in a deck file is left out and the rest are kept', () {
      final raw = {
        'format': kDeckFormat,
        'version': kDeckVersion,
        'cards': [
          {
            'id': 'ok',
            'deckId': 'b1',
            'front': 'F',
            'back': 'B',
            'box': 1,
            'dueOn': '2026-11-09'
          },
          {
            'id': 'bad',
            'deckId': 'b1',
            'front': 'F',
            'back': 'B',
            'box': 9,
            'dueOn': '2026-11-09'
          },
        ],
      };
      final imported = deckFromJson(raw, deckId: 'b2', newId: () => 'n');
      expect(imported, hasLength(1));
    });

    test(
        'a stored card is read only when its text, box and due day are valid, of any length',
        () {
      Map<String, dynamic> json(
              {String dueOn = '2026-11-09', int box = 1, String front = 'F'}) =>
          {
            'id': 'c',
            'deckId': 'b1',
            'front': front,
            'back': 'B',
            'box': box,
            'dueOn': dueOn,
          };
      expect(StudyFlashcard.fromJson(json()), isNotNull);
      expect(StudyFlashcard.fromJson(json(dueOn: '2026/11/09')), isNull);
      expect(StudyFlashcard.fromJson(json(box: 0)), isNull);
      expect(StudyFlashcard.fromJson(json(front: '   ')), isNull);
      expect(StudyFlashcard.fromJson(json(front: 'x' * 501)), isNotNull);
    });

    test('a card without a term leaves the term out of its stored form', () {
      expect(_card().toJson().containsKey('termId'), isFalse);
      expect(_card(termId: 't1').toJson()['termId'], 't1');
    });
  });
}
