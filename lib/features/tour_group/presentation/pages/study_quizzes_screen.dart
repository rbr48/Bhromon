import '../widgets/group_back_button.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../../core/utils/app_logger.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/study_models.dart';
import '../../domain/models/study_quiz_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/study_chapter_rules.dart';
import '../widgets/study/study_learning_dialogs.dart';
import 'study_quiz_screen.dart';
import 'package:bhromon/core/theme/colors.dart';

/// The quizzes of one book, in chapter order. An admin writes a quiz on a chapter. Every member can open a quiz,
/// propose questions for it, and take it. The list shows how many members have taken each quiz, and nothing about
/// who or how well.
class StudyQuizzesScreen extends StatefulWidget {
  const StudyQuizzesScreen({
    super.key,
    required this.tourId,
    required this.book,
    this.repository,
  });

  final String tourId;
  final StudyBook book;

  /// The data source. Null in the app, where the screen makes its own; tests pass one.
  final TourGroupRepository? repository;

  @override
  State<StudyQuizzesScreen> createState() => _StudyQuizzesScreenState();
}

class _StudyQuizzesScreenState extends State<StudyQuizzesScreen> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();
  StreamSubscription<List<StudyQuiz>>? _quizSub;
  StreamSubscription<List<StudyChapter>>? _chapterSub;

  TourRole? _myRole;
  List<StudyQuiz> _quizzes = const [];
  List<StudyChapter> _chapters = const [];
  bool _loaded = false;
  bool _failed = false;

  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;

  @override
  void initState() {
    super.initState();
    _repository.myRole(widget.tourId).then((role) {
      if (mounted) setState(() => _myRole = role);
    }, onError: (Object _) {});
    _quizSub =
        _repository.watchStudyQuizzes(widget.tourId, widget.book.id).listen(
      (quizzes) {
        if (!mounted) return;
        setState(() {
          _quizzes = quizzes;
          _loaded = true;
          _failed = false;
        });
      },
      onError: (Object _) {
        if (mounted) setState(() => _failed = true);
      },
    );
    _chapterSub =
        _repository.watchStudyChapters(widget.tourId, widget.book.id).listen(
      (chapters) {
        if (mounted) setState(() => _chapters = sortStudyChapters(chapters));
      },
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    _quizSub?.cancel();
    _chapterSub?.cancel();
    super.dispose();
  }

  /// Runs one change and says how it went. A failure is logged and shown.
  Future<void> _run(Future<void> Function() change, String doneKey) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await change();
      messenger.showSnackBar(SnackBar(content: Text(l10n.translate(doneKey))));
    } catch (error, stackTrace) {
      logWarning('A study quiz change failed', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: AppColors.amber,
      ));
    }
  }

  Future<void> _addQuiz() async {
    final draft = await showStudyQuizEditor(context, chapters: _chapters);
    if (draft == null || !mounted) return;
    await _run(
      () => _repository.addStudyQuiz(
        widget.tourId,
        widget.book.id,
        chapterId: draft.chapterId,
        title: draft.title,
      ),
      'study_quiz_created',
    );
  }

  StudyChapter? _chapterFor(String chapterId) {
    for (final chapter in _chapters) {
      if (chapter.id == chapterId) return chapter;
    }
    return null;
  }

  /// The quizzes in chapter order, then by title. A quiz whose chapter is gone sorts last.
  List<StudyQuiz> get _orderedQuizzes {
    const unknown = 1 << 30;
    final numbers = {
      for (final chapter in _chapters) chapter.id: chapter.number
    };
    final ordered = [..._quizzes];
    ordered.sort((a, b) {
      final byChapter = (numbers[a.chapterId] ?? unknown)
          .compareTo(numbers[b.chapterId] ?? unknown);
      return byChapter != 0 ? byChapter : a.title.compareTo(b.title);
    });
    return ordered;
  }

  void _open(StudyQuiz quiz) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StudyQuizScreen(
        tourId: widget.tourId,
        book: widget.book,
        quiz: quiz,
        chapter: _chapterFor(quiz.chapterId),
        repository: _repository,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final canAdd = _isAdmin && _chapters.isNotEmpty;
    return GroupPopScope(
      tourId: widget.tourId,
      child: Scaffold(
        backgroundColor: palette.background,
        appBar: AppBar(
          leading: GroupBackButton(tourId: widget.tourId),
          title: Text(l10n.translate('study_quizzes_title'),
              style: TextStyle(
                  color: palette.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
          backgroundColor: palette.card,
          foregroundColor: palette.text,
          iconTheme: IconThemeData(color: palette.text),
          elevation: 0,
        ),
        floatingActionButton: canAdd
            ? FloatingActionButton.extended(
                onPressed: _addQuiz,
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.translate('study_quiz_add')),
              )
            : null,
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
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (_quizzes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.translate(_isAdmin && _chapters.isEmpty
                ? 'study_quizzes_need_chapter'
                : 'study_quizzes_empty'),
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.text70),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        for (final quiz in _orderedQuizzes) _quizCard(quiz),
      ],
    );
  }

  Widget _quizCard(StudyQuiz quiz) {
    final l10n = context.l10n;
    final palette = context.forest;
    final chapter = _chapterFor(quiz.chapterId);
    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(Icons.quiz_rounded, color: palette.accentText),
        title: Text(
          quiz.title,
          style: TextStyle(color: palette.text, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            if (chapter != null)
              l10n.translate('study_chapter_title_line', args: {
                'number': l10n.number(chapter.number),
                'title': chapter.title,
              }),
            l10n.translate('study_quiz_takers', args: {
              'count': l10n.number(quiz.takerCount),
            }),
          ].join(' · '),
          style: TextStyle(color: palette.text54),
        ),
        trailing: Icon(Icons.chevron_right_rounded, color: palette.text54),
        onTap: () => _open(quiz),
      ),
    );
  }
}
