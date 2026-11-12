import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../chat/presentation/widgets/chat_rich_text.dart';
import '../../data/study_exam_attempt_store.dart';
import '../../domain/models/study_exam_simulator_models.dart';
import '../../domain/services/study_exam_simulator_rules.dart';
import '../widgets/group_back_button.dart';

/// Screen presenting the candidate's completed exam attempt,
/// side-by-side comparison with examiner model answers,
/// and interactive self-scoring marks allocation.
class StudyExamReviewScreen extends StatefulWidget {
  final ExamAttempt attempt;
  final List<ExamQuestion> questions;

  const StudyExamReviewScreen({
    super.key,
    required this.attempt,
    required this.questions,
    this.store,
  });

  final StudyExamAttemptStore? store;

  @override
  State<StudyExamReviewScreen> createState() => _StudyExamReviewScreenState();
}

class _StudyExamReviewScreenState extends State<StudyExamReviewScreen> {
  late ExamAttempt _attempt;
  late final Map<String, int> _scores;

  @override
  void initState() {
    super.initState();
    _attempt = widget.attempt;
    _scores = Map.of(_attempt.scores);
  }

  /// The paper's digits in the current language.
  String _digitsOf(String text) {
    final l10n = context.l10n;
    return text.replaceAllMapped(
      RegExp('[0-9]'),
      (match) => l10n.number(int.parse(match.group(0)!)),
    );
  }

  void _updateScore(String questionId, int newScore) {
    setState(() {
      _scores[questionId] = newScore;
      _attempt = _attempt.copyWith(scores: Map.unmodifiable(_scores));
    });
    // The awarded marks are kept on this phone. A save that fails is said so, not hidden.
    unawaited((widget.store ?? StudyExamAttemptStore.instance)
        .saveAttempt(_attempt)
        .then((saved) {
      if (!saved && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.translate('study_exam_save_failed')),
          ),
        );
      }
    }));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;

    final totalScore = _attempt.totalScore;
    final totalMarks = _attempt.totalMarks;
    final percentage = _attempt.percentage;
    final isPassed = _attempt.isPassed;

    final duration = Duration(seconds: _attempt.elapsedSeconds);
    final formattedTime = StudyExamTimerRules.formatDuration(duration);

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.card,
        leading: GroupBackButton(tourId: _attempt.tourId),
        title: Text(
          l10n.translate('study_exam_review_title'),
          style: TextStyle(
            color: palette.text,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Score Summary Hero Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: palette.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isPassed
                      ? AppColors.mintGreen.withValues(alpha: 0.5)
                      : Colors.amber.withValues(alpha: 0.5),
                  width: 1.2,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _attempt.paperTitle,
                            style: TextStyle(
                              color: palette.text,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.translate('study_exam_time_spent',
                                args: {'time': _digitsOf(formattedTime)}),
                            style: TextStyle(
                              color: palette.text54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isPassed
                              ? AppColors.mintGreen.withValues(alpha: 0.15)
                              : Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color:
                                isPassed ? AppColors.mintGreen : Colors.amber,
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          isPassed
                              ? l10n.translate('study_exam_pass', args: {
                                  'percent':
                                      l10n.number(ExamAttempt.passPercent)
                                })
                              : l10n.translate('study_exam_fail', args: {
                                  'percent':
                                      l10n.number(ExamAttempt.passPercent)
                                }),
                          style: TextStyle(
                            color:
                                isPassed ? AppColors.mintGreen : Colors.amber,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Divider(height: 1, color: palette.divider10),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _MetricItem(
                        label: l10n.translate('study_exam_metric_total'),
                        value:
                            '${l10n.number(totalScore)} / ${l10n.number(totalMarks)}',
                        color: palette.accentText,
                      ),
                      _MetricItem(
                        label: l10n.translate('study_exam_metric_percent'),
                        value: '${l10n.number(percentage.toStringAsFixed(1))}%',
                        color: isPassed ? AppColors.mintGreen : Colors.amber,
                      ),
                      _MetricItem(
                        label: l10n.translate('study_exam_metric_answered'),
                        value:
                            '${l10n.number(_attempt.draftAnswers.values.where((v) => v.trim().isNotEmpty).length)} / ${l10n.number(widget.questions.length)}',
                        color: palette.text70,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Question Reviews List
            for (int i = 0; i < widget.questions.length; i++)
              _buildQuestionReviewTile(
                context,
                index: i,
                question: widget.questions[i],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionReviewTile(
    BuildContext context, {
    required int index,
    required ExamQuestion question,
  }) {
    final l10n = context.l10n;
    final palette = context.forest;
    final draft = _attempt.draftAnswers[question.id]?.trim() ?? '';
    final score = _scores[question.id] ?? 0;
    final hasDraft = draft.isNotEmpty;

    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.divider12, width: 0.8),
      ),
      child: ExpansionTile(
        initiallyExpanded: index == 0,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 14,
          backgroundColor: hasDraft
              ? palette.accentText.withValues(alpha: 0.2)
              : palette.divider12,
          child: Text(
            '${index + 1}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: hasDraft ? palette.accentText : palette.text54,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                l10n.translate('study_exam_review_question', args: {
                  'n': l10n.number(index + 1),
                  'marks': l10n.number(question.marks),
                }),
                style: TextStyle(
                  color: palette.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: palette.accentText.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                l10n.translate('study_exam_score', args: {
                  'score': l10n.number(score),
                  'marks': l10n.number(question.marks),
                }),
                style: TextStyle(
                  color: palette.accentText,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        subtitle: question.moduleCode != null
            ? Text(
                l10n.translate('study_exam_module',
                    args: {'code': question.moduleCode!}),
                style: TextStyle(color: palette.text54, fontSize: 12),
              )
            : null,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Question Prompt
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: palette.background,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ChatRichText(
                    text: question.prompt,
                    baseStyle: TextStyle(
                      color: palette.text,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Candidate's Draft
                Text(
                  l10n.translate('study_exam_candidate_draft'),
                  style: TextStyle(
                    color: palette.accentText,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: palette.isDark
                        ? const Color(0xFF16241C)
                        : const Color(0xFFF1F8F4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: palette.accentText.withValues(alpha: 0.3),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    hasDraft ? draft : l10n.translate('study_exam_no_draft'),
                    style: TextStyle(
                      color: hasDraft ? palette.text : palette.text54,
                      fontSize: 13,
                      height: 1.45,
                      fontStyle: hasDraft ? FontStyle.normal : FontStyle.italic,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Model Answer
                if (question.modelAnswer.trim().isNotEmpty) ...[
                  Text(
                    l10n.translate('study_exam_model_answer'),
                    style: TextStyle(
                      color: palette.text70,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: palette.background,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ChatRichText(
                      text: question.modelAnswer,
                      baseStyle: TextStyle(
                        color: palette.text,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Marks Stepper
                Row(
                  children: [
                    Text(
                      l10n.translate('study_exam_self_score'),
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                      color: score > 0 ? palette.accentText : palette.text54,
                      onPressed: score > 0
                          ? () => _updateScore(question.id, score - 1)
                          : null,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: palette.accentText.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${l10n.number(score)} / ${l10n.number(question.marks)}',
                        style: TextStyle(
                          color: palette.accentText,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      color: score < question.marks
                          ? palette.accentText
                          : palette.text54,
                      onPressed: score < question.marks
                          ? () => _updateScore(question.id, score + 1)
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricItem({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: context.forest.text54,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
