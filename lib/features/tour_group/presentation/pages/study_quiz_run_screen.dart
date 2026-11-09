import '../widgets/group_back_button.dart';
import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../../core/utils/app_logger.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/study_quiz_models.dart';
import '../../data/study_activity_log.dart';
import '../../domain/services/study_quiz_rules.dart';

import '../widgets/study/study_rich_text.dart';

/// Takes a quiz one question at a time. A choice or a true-or-false answer is marked as soon as it is picked. An
/// explain question shows its model answer, and the member marks their own work. At the end the score is saved as
/// the member's private record, and only if it saves does the screen say so.
class StudyQuizRunScreen extends StatefulWidget {
  const StudyQuizRunScreen({
    super.key,
    required this.tourId,
    required this.bookId,
    required this.quizId,
    required this.title,
    required this.questions,
    this.repository,
    this.activity,
  });

  /// Where a saved attempt is counted for the streak. Null in the app; tests pass one.
  final StudyActivityLog? activity;

  final String tourId;
  final String bookId;
  final String quizId;
  final String title;

  /// The approved questions, in the order they are asked. Never empty.
  final List<StudyQuizQuestion> questions;

  /// The data source. Null in the app, where the screen makes its own; tests pass one.
  final TourGroupRepository? repository;

  @override
  State<StudyQuizRunScreen> createState() => _StudyQuizRunScreenState();
}

class _StudyQuizRunScreenState extends State<StudyQuizRunScreen> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();

  int _index = 0;
  int _correct = 0;

  /// The choice picked on the current question, if any.
  int? _chosen;

  /// Whether the current question has been marked, so its explanation shows.
  bool _revealed = false;

  /// Whether an explain question's model answer is showing.
  bool _modelShown = false;

  bool _finished = false;
  bool _saving = false;
  bool _saveFailed = false;
  StudyQuizAttempt? _saved;

  StudyQuizQuestion get _question => widget.questions[_index];
  bool get _isLast => _index >= widget.questions.length - 1;

  void _pick(int choice) {
    if (_revealed) return;
    final right = isCorrectChoice(_question, choice);
    setState(() {
      _chosen = choice;
      _revealed = true;
      if (right) _correct++;
    });
  }

  void _selfMark({required bool right}) {
    if (_revealed) return;
    setState(() {
      _revealed = true;
      if (right) _correct++;
    });
  }

  void _next() {
    if (!_revealed) return;
    if (_isLast) {
      setState(() => _finished = true);
      _save();
      return;
    }
    setState(() {
      _index++;
      _chosen = null;
      _revealed = false;
      _modelShown = false;
    });
  }

  late final StudyActivityLog _activity = widget.activity ?? StudyActivityLog();

  /// Counts the saved attempt for the day. Best effort: the score is already saved, so a failure only logs.
  Future<void> _countAttempt() async {
    try {
      await _activity.recordQuiz(DateTime.now());
    } catch (error, stackTrace) {
      logWarning('A quiz attempt could not be counted', error, stackTrace);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      final attempt = await _repository.recordQuizAttempt(
        widget.tourId,
        widget.bookId,
        widget.quizId,
        correct: _correct,
        total: widget.questions.length,
      );
      await _countAttempt();
      if (!mounted) return;
      setState(() {
        _saved = attempt;
        _saving = false;
      });
    } catch (error, stackTrace) {
      logWarning('A quiz attempt could not be saved', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.forest;
    return GroupPopScope(
      tourId: widget.tourId,
      child: Scaffold(
        backgroundColor: palette.background,
        appBar: AppBar(
          leading: GroupBackButton(tourId: widget.tourId),
          title: Text(widget.title,
              style: TextStyle(
                  color: palette.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
          backgroundColor: palette.card,
          foregroundColor: palette.text,
          iconTheme: IconThemeData(color: palette.text),
          elevation: 0,
        ),
        body: SafeArea(child: _finished ? _resultView() : _questionView()),
      ),
    );
  }

  Widget _questionView() {
    final l10n = context.l10n;
    final palette = context.forest;
    final question = _question;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        LinearProgressIndicator(
          value: _index / widget.questions.length,
          color: palette.accentText,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.translate('study_quiz_run_progress', args: {
            'number': l10n.number(_index + 1),
            'total': l10n.number(widget.questions.length),
          }),
          style: TextStyle(color: palette.text54),
        ),
        const SizedBox(height: 12),
        Text(
          question.text,
          style: TextStyle(
              color: palette.text, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        ..._answerWidgets(question),
        if (_revealed) ..._feedback(question),
        if (_revealed) ...[
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _next,
            child: Text(l10n
                .translate(_isLast ? 'study_quiz_finish' : 'study_quiz_next')),
          ),
        ],
      ],
    );
  }

  List<Widget> _answerWidgets(StudyQuizQuestion question) {
    final l10n = context.l10n;
    return switch (question.type) {
      StudyQuestionType.single => [
          for (var i = 0; i < question.choices.length; i++)
            _choiceButton(question, i, question.choices[i]),
        ],
      StudyQuestionType.trueFalse => [
          _choiceButton(question, 0, l10n.translate('study_quiz_true')),
          _choiceButton(question, 1, l10n.translate('study_quiz_false')),
        ],
      StudyQuestionType.explain => _explainWidgets(question),
    };
  }

  Widget _choiceButton(StudyQuizQuestion question, int index, String label) {
    final palette = context.forest;
    final answer = question.answerIndex;
    Color side = palette.text24;
    if (_revealed) {
      if (index == answer) {
        side = palette.accentText;
      } else if (index == _chosen) {
        side = Colors.redAccent;
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton(
        onPressed: _revealed ? null : () => _pick(index),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          foregroundColor: palette.text,
          disabledForegroundColor: palette.text,
          side: BorderSide(color: side, width: _revealed ? 2 : 1),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(label, textAlign: TextAlign.start),
        ),
      ),
    );
  }

  List<Widget> _explainWidgets(StudyQuizQuestion question) {
    final l10n = context.l10n;
    final palette = context.forest;
    if (!_modelShown && !_revealed) {
      return [
        OutlinedButton(
          onPressed: () => setState(() => _modelShown = true),
          child: Text(l10n.translate('study_quiz_show_model')),
        ),
      ];
    }
    return [
      Card(
        color: palette.card,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.translate('study_quiz_model_heading'),
                style: TextStyle(
                    color: palette.accentText, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              StudyRichText(question.modelAnswer,
                  style: TextStyle(color: palette.text)),
            ],
          ),
        ),
      ),
      if (!_revealed) ...[
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _selfMark(right: false),
                child: Text(l10n.translate('study_quiz_not_yet')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: () => _selfMark(right: true),
                child: Text(l10n.translate('study_quiz_had_it_right')),
              ),
            ),
          ],
        ),
      ],
    ];
  }

  String? _choiceLabel(StudyQuizQuestion question, int? index) {
    if (index == null) return null;
    if (question.type == StudyQuestionType.trueFalse) {
      return context.l10n
          .translate(index == 0 ? 'study_quiz_true' : 'study_quiz_false');
    }
    if (index < 0 || index >= question.choices.length) return null;
    return question.choices[index];
  }

  /// The verdict on a choice, and the explanation of the question, once it has been marked.
  List<Widget> _feedback(StudyQuizQuestion question) {
    final l10n = context.l10n;
    final palette = context.forest;
    final chosen = _chosen;
    final right = chosen != null && isCorrectChoice(question, chosen);
    return [
      if (question.type != StudyQuestionType.explain)
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            right
                ? l10n.translate('study_quiz_correct')
                : l10n.translate('study_quiz_wrong', args: {
                    'answer':
                        _choiceLabel(question, question.answerIndex) ?? '',
                  }),
            style: TextStyle(
              color: right ? palette.accentText : Colors.redAccent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      if (question.explanation.isNotEmpty)
        Card(
          color: palette.card,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.translate('study_quiz_explanation_heading'),
                  style: TextStyle(
                      color: palette.accentText, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                StudyRichText(question.explanation,
                    style: TextStyle(color: palette.text)),
              ],
            ),
          ),
        ),
    ];
  }

  Widget _resultView() {
    final l10n = context.l10n;
    final palette = context.forest;
    final total = widget.questions.length;
    final percent = scorePercent(correct: _correct, total: total);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      children: [
        Text(
          l10n.translate('study_quiz_score', args: {
            'correct': l10n.number(_correct),
            'total': l10n.number(total),
            'percent': l10n.number(percent),
          }),
          textAlign: TextAlign.center,
          style: TextStyle(
              color: palette.text, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        if (_saving)
          const Center(child: CircularProgressIndicator())
        else if (_saveFailed) ...[
          Text(
            l10n.translate('study_quiz_not_saved'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.redAccent),
          ),
          const SizedBox(height: 8),
          Center(
            child: OutlinedButton(
              onPressed: _save,
              child: Text(l10n.translate('study_quiz_retry_save')),
            ),
          ),
        ] else if (_saved != null)
          Text(
            l10n.translate('study_quiz_saved'),
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.text70),
          ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.translate('study_done')),
        ),
      ],
    );
  }
}
