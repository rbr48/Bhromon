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
import '../../domain/services/study_quiz_rules.dart';
import '../widgets/study/study_learning_dialogs.dart';
import '../widgets/study/study_question_composer.dart';
import 'study_quiz_run_screen.dart';

import '../widgets/study/study_rich_text.dart';
import 'package:bhromon/core/theme/colors.dart';

/// One quiz. It shows the signed-in member's own record, which nobody else reads, and the questions an admin has
/// approved. Proposed questions are listed for everyone, with the actions each person may take: an admin approves
/// or removes any proposal, and a member withdraws their own while it waits.
class StudyQuizScreen extends StatefulWidget {
  const StudyQuizScreen({
    super.key,
    required this.tourId,
    required this.book,
    required this.quiz,
    this.chapter,
    this.repository,
  });

  final String tourId;
  final StudyBook book;
  final StudyQuiz quiz;

  /// The chapter the quiz covers, or null when it is no longer in the book.
  final StudyChapter? chapter;

  /// The data source. Null in the app, where the screen makes its own; tests pass one.
  final TourGroupRepository? repository;

  @override
  State<StudyQuizScreen> createState() => _StudyQuizScreenState();
}

class _StudyQuizScreenState extends State<StudyQuizScreen> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();
  StreamSubscription<List<StudyQuiz>>? _quizSub;
  StreamSubscription<List<StudyQuizQuestion>>? _questionSub;
  StreamSubscription<StudyQuizAttempt?>? _attemptSub;

  TourRole? _myRole;
  late StudyQuiz _quiz = widget.quiz;
  List<StudyQuizQuestion> _questions = const [];
  bool _loaded = false;
  bool _failed = false;
  StudyQuizAttempt? _attempt;
  bool _attemptLoaded = false;
  bool _attemptFailed = false;

  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;
  String get _email => _repository.currentEmail;

  List<StudyQuizQuestion> get _approved => quizQuestions(_questions);

  List<StudyQuizQuestion> get _proposals => [
        for (final question in _questions)
          if (!question.approved) question,
      ];

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
        for (final quiz in quizzes) {
          if (quiz.id == widget.quiz.id) {
            setState(() => _quiz = quiz);
            return;
          }
        }
      },
      onError: (Object _) {},
    );
    _questionSub = _repository
        .watchQuizQuestions(widget.tourId, widget.book.id, widget.quiz.id)
        .listen(
      (questions) {
        if (!mounted) return;
        setState(() {
          _questions = questions;
          _loaded = true;
          _failed = false;
        });
      },
      onError: (Object _) {
        if (mounted) setState(() => _failed = true);
      },
    );
    _attemptSub = _repository
        .watchMyQuizAttempt(widget.tourId, widget.book.id, widget.quiz.id)
        .listen(
      (attempt) {
        if (!mounted) return;
        setState(() {
          _attempt = attempt;
          _attemptLoaded = true;
          _attemptFailed = false;
        });
      },
      onError: (Object _) {
        if (!mounted) return;
        setState(() {
          _attemptLoaded = true;
          _attemptFailed = true;
        });
      },
    );
  }

  @override
  void dispose() {
    _quizSub?.cancel();
    _questionSub?.cancel();
    _attemptSub?.cancel();
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
      logWarning('A quiz question change failed', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: AppColors.amber,
      ));
    }
  }

  /// A member proposes a question; an admin's is added already approved.
  Future<void> _propose() async {
    final question = await showStudyQuestionComposer(context);
    if (question == null || !mounted) return;
    await _run(
      () => _repository.addQuizQuestion(
        widget.tourId,
        widget.book.id,
        _quiz.id,
        question: question,
        approved: _isAdmin,
      ),
      _isAdmin ? 'study_quiz_added' : 'study_quiz_proposed',
    );
  }

  Future<void> _approve(StudyQuizQuestion question) {
    return _run(
      () => _repository.approveQuizQuestion(
        widget.tourId,
        widget.book.id,
        _quiz.id,
        question.id,
      ),
      'study_quiz_approved',
    );
  }

  Future<void> _remove(StudyQuizQuestion question) async {
    final sure = await confirmStudyRemoval(context);
    if (!sure || !mounted) return;
    await _run(
      () => _repository.deleteQuizQuestion(
        widget.tourId,
        widget.book.id,
        _quiz.id,
        question.id,
      ),
      'study_quiz_removed',
    );
  }

  void _take() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StudyQuizRunScreen(
        tourId: widget.tourId,
        bookId: widget.book.id,
        quizId: _quiz.id,
        title: _quiz.title,
        questions: _approved,
        repository: _repository,
      ),
    ));
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
          title: Text(_quiz.title,
              style: TextStyle(
                  color: palette.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
          backgroundColor: palette.card,
          foregroundColor: palette.text,
          iconTheme: IconThemeData(color: palette.text),
          elevation: 0,
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _propose,
          icon: const Icon(Icons.add_rounded),
          label: Text(l10n.translate(
              _isAdmin ? 'study_quiz_add_question' : 'study_quiz_propose')),
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
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final approved = _approved;
    final proposals = _proposals;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        _header(),
        _recordCard(),
        FilledButton.icon(
          onPressed: approved.isEmpty ? null : _take,
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(l10n.translate('study_quiz_take')),
        ),
        if (approved.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.translate('study_quiz_none_approved'),
              style: TextStyle(color: palette.text54),
            ),
          ),
        if (approved.isNotEmpty)
          _heading(l10n.translate('study_quiz_questions_heading')),
        for (final question in approved) _questionTile(question),
        if (proposals.isNotEmpty)
          _heading(l10n.translate('study_quiz_proposals_heading')),
        for (final question in proposals) _questionTile(question),
      ],
    );
  }

  Widget _header() {
    final l10n = context.l10n;
    final palette = context.forest;
    final chapter = widget.chapter;
    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (chapter != null)
              Text(
                l10n.translate('study_chapter_title_line', args: {
                  'number': l10n.number(chapter.number),
                  'title': chapter.title,
                }),
                style: TextStyle(
                    color: palette.accentText, fontWeight: FontWeight.w600),
              ),
            const SizedBox(height: 4),
            Text(
              l10n.translate('study_quiz_takers', args: {
                'count': l10n.number(_quiz.takerCount),
              }),
              style: TextStyle(color: palette.text54),
            ),
          ],
        ),
      ),
    );
  }

  /// The member's own record. It is shown only to them: it is read from their own attempt.
  Widget _recordCard() {
    final l10n = context.l10n;
    final palette = context.forest;
    if (!_attemptLoaded) return const SizedBox.shrink();
    final attempt = _attempt;
    final line = _attemptFailed
        ? l10n.translate('study_failed')
        : attempt == null
            ? l10n.translate('study_quiz_record_none')
            : l10n.translate('study_quiz_record', args: {
                'best': l10n.number(attempt.best),
                'last': l10n.number(attempt.last),
                'attempts': l10n.number(attempt.attempts),
              });
    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.translate('study_quiz_record_heading'),
              style: TextStyle(color: palette.text54, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(line, style: TextStyle(color: palette.text)),
          ],
        ),
      ),
    );
  }

  Widget _heading(String text) {
    final palette = context.forest;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Text(
        text,
        style:
            TextStyle(color: palette.accentText, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _questionTile(StudyQuizQuestion question) {
    final l10n = context.l10n;
    final palette = context.forest;
    final canApprove =
        !question.approved && canApproveQuestion(isAdmin: _isAdmin);
    final canRemove = canRemoveQuestion(
      question,
      viewerEmail: _email,
      isAdmin: _isAdmin,
    );
    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title:
            StudyRichText(question.text, style: TextStyle(color: palette.text)),
        subtitle: Text(
          [
            l10n.translate('study_quiz_type_${question.type.name}'),
            if (!question.approved) l10n.translate('study_material_waiting'),
          ].join(' · '),
          style: TextStyle(color: palette.text54),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canApprove)
              TextButton(
                onPressed: () => _approve(question),
                child: Text(l10n.translate('study_approve')),
              ),
            if (canRemove)
              IconButton(
                tooltip: l10n.translate(question.approved || _isAdmin
                    ? 'study_remove'
                    : 'study_withdraw'),
                icon: Icon(Icons.delete_outline_rounded, color: palette.text54),
                onPressed: () => _remove(question),
              ),
          ],
        ),
      ),
    );
  }
}
