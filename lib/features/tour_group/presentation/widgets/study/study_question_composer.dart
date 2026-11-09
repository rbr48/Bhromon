import 'package:flutter/material.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../domain/models/study_quiz_models.dart';
import '../../../domain/services/study_quiz_rules.dart';

/// Asks for a quiz question: its kind, its text, its choices or answer, and its explanation. Returns the question
/// when it passes [questionProblem], or null when the member cancels. The caller saves it.
Future<StudyQuizQuestion?> showStudyQuestionComposer(
  BuildContext context,
) {
  return showDialog<StudyQuizQuestion>(
    context: context,
    builder: (_) => const _StudyQuestionComposer(),
  );
}

class _StudyQuestionComposer extends StatefulWidget {
  const _StudyQuestionComposer();

  @override
  State<_StudyQuestionComposer> createState() => _StudyQuestionComposerState();
}

class _StudyQuestionComposerState extends State<_StudyQuestionComposer> {
  final _text = TextEditingController();
  final _choices = TextEditingController();
  final _answer = TextEditingController();
  final _modelAnswer = TextEditingController();
  final _explanation = TextEditingController();
  StudyQuestionType _type = StudyQuestionType.single;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    _choices.dispose();
    _answer.dispose();
    _modelAnswer.dispose();
    _explanation.dispose();
    super.dispose();
  }

  /// The choices typed one a line, blank lines left out.
  List<String> get _choiceList => [
        for (final line in _choices.text.split('\n'))
          if (line.trim().isNotEmpty) line.trim(),
      ];

  void _save() {
    final l10n = context.l10n;
    final answerNumber = int.tryParse(_answer.text.trim());
    final answerIndex = switch (_type) {
      StudyQuestionType.single =>
        answerNumber == null ? null : answerNumber - 1,
      StudyQuestionType.trueFalse =>
        answerNumber == null ? null : answerNumber - 1,
      StudyQuestionType.explain => null,
    };
    final problem = questionProblem(
      type: _type,
      text: _text.text,
      explanation: _explanation.text,
      choices: _type == StudyQuestionType.single ? _choiceList : const [],
      answerIndex: answerIndex,
      modelAnswer: _modelAnswer.text,
    );
    if (problem != null) {
      setState(() => _error = l10n.translate(_problemKey(problem)));
      return;
    }
    Navigator.of(context).pop(
      StudyQuizQuestion(
        id: '',
        type: _type,
        text: _text.text.trim(),
        explanation: _explanation.text.trim(),
        choices: _type == StudyQuestionType.single ? _choiceList : const [],
        answerIndex: answerIndex,
        modelAnswer:
            _type == StudyQuestionType.explain ? _modelAnswer.text.trim() : '',
      ),
    );
  }

  String _problemKey(StudyQuestionProblem problem) => switch (problem) {
        StudyQuestionProblem.emptyText => 'study_quiz_error_text',
        StudyQuestionProblem.textTooLong => 'study_quiz_error_text_long',
        StudyQuestionProblem.choicesCount => 'study_quiz_error_choices',
        StudyQuestionProblem.emptyChoice => 'study_quiz_error_choices',
        StudyQuestionProblem.choiceTooLong => 'study_quiz_error_choice_long',
        StudyQuestionProblem.answerMissing => 'study_quiz_error_answer',
        StudyQuestionProblem.emptyModelAnswer => 'study_quiz_error_model',
        StudyQuestionProblem.answerTooLong => 'study_quiz_error_model_long',
        StudyQuestionProblem.emptyExplanation => 'study_quiz_error_explanation',
        StudyQuestionProblem.explanationTooLong =>
          'study_quiz_error_explanation_long',
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.translate('study_quiz_propose_title')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final type in StudyQuestionType.values)
                  ChoiceChip(
                    label: Text(l10n.translate('study_quiz_type_${type.name}')),
                    selected: _type == type,
                    onSelected: (_) => setState(() {
                      _type = type;
                      _error = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              maxLength: StudyQuizLimits.questionMax,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: l10n.translate('study_quiz_question_label'),
              ),
            ),
            if (_type == StudyQuestionType.single)
              TextField(
                controller: _choices,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: l10n.translate('study_quiz_choices_label'),
                  helperText: l10n.translate('study_quiz_choices_hint'),
                ),
              ),
            if (_type != StudyQuestionType.explain)
              TextField(
                controller: _answer,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.translate('study_quiz_answer_label'),
                  helperText: l10n.translate(
                    _type == StudyQuestionType.trueFalse
                        ? 'study_quiz_answer_hint_tf'
                        : 'study_quiz_answer_hint',
                  ),
                ),
              ),
            if (_type == StudyQuestionType.explain)
              TextField(
                controller: _modelAnswer,
                maxLines: 3,
                maxLength: StudyQuizLimits.answerMax,
                decoration: InputDecoration(
                  labelText: l10n.translate('study_quiz_model_label'),
                ),
              ),
            TextField(
              controller: _explanation,
              maxLines: 3,
              maxLength: StudyQuizLimits.explanationMax,
              decoration: InputDecoration(
                labelText: l10n.translate('study_quiz_explanation_label'),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.translate('study_cancel')),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(l10n.translate('study_save')),
        ),
      ],
    );
  }
}
