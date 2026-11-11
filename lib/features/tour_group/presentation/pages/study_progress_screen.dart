import 'package:bhromon/core/widgets/skeleton.dart';
import '../widgets/group_back_button.dart';
import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../../core/utils/app_logger.dart';
import '../../data/study_activity_log.dart';
import '../../data/study_flashcard_store.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/study_models.dart';
import '../../domain/models/study_thread_models.dart';
import '../../domain/services/study_chapter_rules.dart';
import '../../domain/services/study_flashcard_rules.dart';
import '../../domain/services/study_progress_rules.dart';
import '../widgets/study/study_progress_card.dart';

/// A member's own study record on one book, the streak they are on, and the group's totals as counts. Only the
/// record and the streak are the member's: they are read from their own marks, answers and attempts, and the
/// device's count of cards. The group part shows counts, never a name or a score.
class StudyProgressScreen extends StatefulWidget {
  const StudyProgressScreen({
    super.key,
    required this.tourId,
    required this.book,
    this.repository,
    this.store,
    this.activity,
    this.today,
  });

  final String tourId;
  final StudyBook book;

  /// The data source. Null in the app, where the screen makes its own; tests pass one.
  final TourGroupRepository? repository;

  /// The flashcards on this device. Null in the app; tests pass one.
  final StudyFlashcardStore? store;

  /// The study counted on this device. Null in the app; tests pass one.
  final StudyActivityLog? activity;

  /// The day the streak and the due cards are judged on. Null in the app, where it is today; tests pass one.
  final DateTime? today;

  @override
  State<StudyProgressScreen> createState() => _StudyProgressScreenState();
}

class _StudyProgressScreenState extends State<StudyProgressScreen> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();
  late final StudyFlashcardStore _store = widget.store ?? StudyFlashcardStore();
  late final StudyActivityLog _activity = widget.activity ?? StudyActivityLog();

  bool _loaded = false;
  bool _failed = false;
  StudyStreak _streak = const StudyStreak(current: 0, best: 0);
  StudyMyRecord? _record;
  int _cardsReviewed = 0;
  StudyGroupTotals? _totals;
  List<StudyChapter> _chapters = const [];
  List<({String id, String title})> _quizzes = const [];

  DateTime get _now => widget.today ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final tourId = widget.tourId;
      final bookId = widget.book.id;
      final chapters =
          await _repository.watchStudyChapters(tourId, bookId).first;
      final myReads = await _repository.watchMyReadMarks(tourId, bookId).first;
      final quizzes = await _repository.watchStudyQuizzes(tourId, bookId).first;
      final threads = await _repository.watchStudyThreads(tourId, bookId).first;
      // The member's own answers, and only the first replies in the three days after each question: both are
      // bounded per question, so the page does not read a large group's whole discussion.
      final myReplies = await _repository.loadMyReplies(
        tourId,
        bookId,
        [for (final thread in threads) thread.id],
      );
      final earlyReplies = await _repository.loadEarlyReplies(
        tourId,
        bookId,
        [
          for (final thread in threads)
            if (thread.createdAt != null)
              (id: thread.id, asked: thread.createdAt!),
        ],
      );
      final countedReads = await _repository.countCountedReads(
        tourId,
        bookId,
        [for (final chapter in chapters) chapter.id],
      );
      final quizzesTaken = await _repository.countMyQuizAttempts(
        tourId,
        bookId,
        [for (final quiz in quizzes) quiz.id],
      );
      final activeDays = await _activity.activeDays();
      final cardsReviewed = await _activity.cardsReviewed();
      final cards = await _store.loadAll();
      final dueToday = dueCards(
        [
          for (final card in cards)
            if (card.deckId == bookId) card
        ],
        _now,
      ).length;

      final email = _repository.currentEmail;
      var answersGiven = 0;
      final answerTimes = <DateTime>[];
      final questions = <({DateTime asked, DateTime? firstAnswer})>[];
      for (final thread in threads) {
        DateTime? firstAnswer;
        for (final reply in myReplies[thread.id] ?? const <StudyReply>[]) {
          final at = reply.createdAt;
          if (at == null) continue;
          answersGiven++;
          answerTimes.add(at);
        }
        for (final reply in earlyReplies[thread.id] ?? const <StudyReply>[]) {
          final at = reply.createdAt;
          if (at == null || reply.createdByEmail == thread.createdByEmail) {
            continue;
          }
          if (firstAnswer == null || at.isBefore(firstAnswer)) {
            firstAnswer = at;
          }
        }
        final asked = thread.createdAt;
        if (asked != null) {
          questions.add((asked: asked, firstAnswer: firstAnswer));
        }
      }
      final questionsAsked =
          threads.where((thread) => thread.createdByEmail == email).length;

      final readTimes = [
        for (final mark in myReads.values)
          if (mark.readAt != null) mark.readAt!,
      ];
      final streak = studyStreak(
        [...activeDays, ...readTimes, ...answerTimes],
        today: _now,
      );

      final totals = groupTotals(
        countedReads: countedReads,
        takersByQuiz: {for (final quiz in quizzes) quiz.id: quiz.takerCount},
        questions: questions,
      );

      if (!mounted) return;
      setState(() {
        _chapters = sortStudyChapters(chapters);
        _quizzes = [
          for (final quiz in quizzes) (id: quiz.id, title: quiz.title)
        ];
        _streak = streak;
        _cardsReviewed = cardsReviewed;
        _totals = totals;
        _record = StudyMyRecord(
          chaptersRead: myReads.length,
          quizzesTaken: quizzesTaken,
          cardsDue: dueToday,
          questionsAsked: questionsAsked,
          answersGiven: answersGiven,
        );
        _loaded = true;
        _failed = false;
      });
    } catch (error, stackTrace) {
      logWarning('The study progress could not be read', error, stackTrace);
      if (mounted) {
        setState(() {
          _loaded = true;
          _failed = true;
        });
      }
    }
  }

  void _makeCard() {
    final record = _record;
    if (record == null) return;
    showStudyProgressCardSheet(
      context,
      bookTitle: widget.book.title,
      weeks: _streak.current,
      chaptersRead: record.chaptersRead,
      cardsReviewed: _cardsReviewed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    return GroupPopScope(
      tourId: widget.tourId,
      child: Scaffold(
        backgroundColor: palette.background,
        appBar: AppBar(
          leading: GroupBackButton(tourId: widget.tourId),
          title: Text(
            l10n.translate('study_progress_title'),
            style: TextStyle(
                color: palette.text, fontWeight: FontWeight.bold, fontSize: 18),
          ),
          backgroundColor: palette.card,
          foregroundColor: palette.text,
          iconTheme: IconThemeData(color: palette.text),
          elevation: 0,
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    final l10n = context.l10n;
    final palette = context.forest;
    if (_failed) {
      return Center(
        child: Text(l10n.translate('study_failed'),
            style: TextStyle(color: palette.text70)),
      );
    }
    if (!_loaded) return const ListRowsSkeleton();
    final record = _record!;
    final totals = _totals!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _card(
          heading: l10n.translate('study_streak_heading'),
          children: [
            Text(
              _streak.current == 0
                  ? l10n.translate('study_streak_none')
                  : l10n.translate('study_streak_now', args: {
                      'weeks': l10n.number(_streak.current),
                    }),
              style: TextStyle(
                  color: palette.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.translate('study_streak_best', args: {
                'weeks': l10n.number(_streak.best),
              }),
              style: TextStyle(color: palette.text70),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.translate('study_streak_note'),
              style: TextStyle(color: palette.text54, fontSize: 12),
            ),
          ],
        ),
        _card(
          heading: l10n.translate('study_record_heading'),
          children: [
            _line('study_record_chapters', record.chaptersRead),
            _line('study_record_quizzes', record.quizzesTaken),
            _line('study_record_cards_due', record.cardsDue),
            _line('study_record_questions', record.questionsAsked),
            _line('study_record_answers', record.answersGiven),
            _line('study_record_cards_reviewed', _cardsReviewed),
          ],
        ),
        _card(
          heading: l10n.translate('study_group_heading'),
          children: [
            for (final chapter in _chapters)
              _text(l10n.translate('study_group_chapter_line', args: {
                'number': l10n.number(chapter.number),
                'title': chapter.title,
                'count': l10n.number(totals.chaptersCounted[chapter.id] ?? 0),
              })),
            for (final quiz in _quizzes)
              _text(l10n.translate('study_group_quiz_line', args: {
                'title': quiz.title,
                'count': l10n.number(totals.quizTakers[quiz.id] ?? 0),
              })),
            _text(l10n.translate('study_group_answered', args: {
              'answered': l10n.number(totals.questionsAnswered),
              'asked': l10n.number(totals.questionsAsked),
            })),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _makeCard,
          icon: const Icon(Icons.image_outlined),
          label: Text(l10n.translate('study_card_make')),
        ),
      ],
    );
  }

  Widget _card({required String heading, required List<Widget> children}) {
    final palette = context.forest;
    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              heading,
              style: TextStyle(
                  color: palette.accentText, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _line(String key, int count) {
    final l10n = context.l10n;
    final palette = context.forest;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(l10n.translate(key),
                style: TextStyle(color: palette.text)),
          ),
          Text(
            l10n.number(count),
            style: TextStyle(color: palette.text, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _text(String text) {
    final palette = context.forest;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: TextStyle(color: palette.text)),
    );
  }
}
