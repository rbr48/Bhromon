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
import 'study_exam_review_screen.dart';

/// Fullscreen 3-hour timed exam simulator for candidate mock tests.
/// Provides a countdown HUD, question status tray, candidate scratchpad,
/// and auto-submission on expiration.
class StudyExamSimulatorScreen extends StatefulWidget {
  final String tourId;
  final String bookId;
  final String? chapterId;
  final String paperTitle;
  final String? rawContent;
  final int initialDurationMinutes;
  final List<ExamQuestion>? initialQuestions;

  const StudyExamSimulatorScreen({
    super.key,
    required this.tourId,
    required this.bookId,
    this.chapterId,
    required this.paperTitle,
    this.rawContent,
    this.initialDurationMinutes = 180,
    this.initialQuestions,
  });

  /// Helper to push simulator onto navigation stack.
  static Future<void> open(
    BuildContext context, {
    required String tourId,
    required String bookId,
    String? chapterId,
    required String paperTitle,
    String? rawContent,
    int initialDurationMinutes = 180,
    List<ExamQuestion>? initialQuestions,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StudyExamSimulatorScreen(
          tourId: tourId,
          bookId: bookId,
          chapterId: chapterId,
          paperTitle: paperTitle,
          rawContent: rawContent,
          initialDurationMinutes: initialDurationMinutes,
          initialQuestions: initialQuestions,
        ),
      ),
    );
  }

  @override
  State<StudyExamSimulatorScreen> createState() =>
      _StudyExamSimulatorScreenState();
}

class _StudyExamSimulatorScreenState extends State<StudyExamSimulatorScreen> {
  late final List<ExamQuestion> _questions;
  late final String _attemptId;
  late int _remainingSeconds;
  late final int _totalDurationSeconds;
  int _currentIndex = 0;
  final Map<String, String> _drafts = {};
  late final TextEditingController _scratchpadController;
  Timer? _timer;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _attemptId =
        'att_${DateTime.now().millisecondsSinceEpoch}_${widget.bookId.hashCode.abs()}';
    _totalDurationSeconds = widget.initialDurationMinutes * 60;
    _remainingSeconds = _totalDurationSeconds;

    if (widget.initialQuestions != null &&
        widget.initialQuestions!.isNotEmpty) {
      _questions = widget.initialQuestions!;
    } else if (widget.rawContent != null &&
        widget.rawContent!.trim().isNotEmpty) {
      _questions = StudyExamSimulatorExtractor.extractQuestions(
        widget.rawContent!,
        widget.paperTitle,
      );
    } else {
      _questions = StudyExamSimulatorExtractor.fallbackQuestions(
        widget.paperTitle,
        count: 8,
      );
    }

    _scratchpadController = TextEditingController();
    _scratchpadController.addListener(_onDraftChanged);

    if (_questions.isNotEmpty) {
      _scratchpadController.text = _drafts[_questions[0].id] ?? '';
    }

    _startTimer();
  }

  void _onDraftChanged() {
    if (_questions.isEmpty || _currentIndex >= _questions.length) return;
    final currentQ = _questions[_currentIndex];
    final text = _scratchpadController.text;
    if (_drafts[currentQ.id] != text) {
      setState(() {
        _drafts[currentQ.id] = text;
      });
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
          if (_remainingSeconds == 1800) {
            _showSnackBar(context.l10n.translate('study_exam_warning_30m'));
          } else if (_remainingSeconds == 600) {
            _showSnackBar(context.l10n.translate('study_exam_warning_10m'));
          }
        } else {
          timer.cancel();
          _onTimeExpired();
        }
      });
    });
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _onTimeExpired() {
    if (_isSubmitting) return;
    _showSnackBar(context.l10n.translate('study_exam_time_expired'));
    _submitExam(forced: true);
  }

  void _selectQuestion(int index) {
    if (index < 0 || index >= _questions.length || index == _currentIndex) {
      return;
    }
    // Save current
    final currentQ = _questions[_currentIndex];
    _drafts[currentQ.id] = _scratchpadController.text;

    setState(() {
      _currentIndex = index;
      _scratchpadController.text = _drafts[_questions[index].id] ?? '';
    });
  }

  ExamAttempt _buildAttempt({required bool isCompleted}) {
    final elapsed = _totalDurationSeconds - _remainingSeconds;
    return ExamAttempt(
      id: _attemptId,
      tourId: widget.tourId,
      bookId: widget.bookId,
      chapterId: widget.chapterId,
      paperTitle: widget.paperTitle,
      durationMinutes: widget.initialDurationMinutes,
      startedAt: DateTime.now().subtract(Duration(seconds: elapsed)),
      submittedAt: DateTime.now(),
      elapsedSeconds: elapsed,
      isCompleted: isCompleted,
      draftAnswers: Map.unmodifiable(_drafts),
      scores: const {},
      notes: const {},
    );
  }

  Future<void> _submitExam({bool forced = false}) async {
    if (_isSubmitting) return;
    _isSubmitting = true;
    _timer?.cancel();

    // Persist latest active question text
    if (_questions.isNotEmpty && _currentIndex < _questions.length) {
      _drafts[_questions[_currentIndex].id] = _scratchpadController.text;
    }

    final attempt = _buildAttempt(isCompleted: true);
    await StudyExamAttemptStore.instance.saveAttempt(attempt);

    if (!mounted) return;

    // Navigate to Review Screen
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => StudyExamReviewScreen(
          attempt: attempt,
          questions: _questions,
        ),
      ),
    );
  }

  void _confirmSubmitDialog() {
    final l10n = context.l10n;
    final answeredCount = _questions
        .where((q) => (_drafts[q.id]?.trim().isNotEmpty ?? false))
        .length;

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: Text(l10n.translate('study_exam_submit')),
          content: Text(
            '${l10n.translate('study_exam_submit_confirm')}\n\n'
            '${l10n.translate('study_exam_total_score', args: {
                  'score': '$answeredCount',
                  'total': '${_questions.length}',
                  'percent': _questions.isEmpty
                      ? '0'
                      : (answeredCount * 100 ~/ _questions.length).toString(),
                })}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text(l10n.translate('dialog_cancel')),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                _submitExam();
              },
              child: Text(l10n.translate('study_exam_submit')),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scratchpadController.removeListener(_onDraftChanged);
    _scratchpadController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final currentQ = _questions.isNotEmpty ? _questions[_currentIndex] : null;

    final duration = Duration(seconds: _remainingSeconds);
    final formattedTime = StudyExamTimerRules.formatDuration(duration);
    final alertState = StudyExamTimerRules.getAlertState(duration);

    final timerColor = switch (alertState) {
      ExamTimerAlertState.critical ||
      ExamTimerAlertState.expired =>
        Colors.redAccent,
      ExamTimerAlertState.warning => Colors.amber,
      ExamTimerAlertState.normal => palette.accentText,
    };

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.card,
        leading: GroupBackButton(tourId: widget.tourId),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.paperTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.text,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              l10n.translate('study_exam_simulator_title'),
              style: TextStyle(
                color: palette.text54,
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          // Question tray shortcut
          IconButton(
            tooltip: l10n.translate('study_exam_question_tray'),
            icon: const Icon(Icons.grid_view_rounded),
            onPressed: () => _openQuestionTraySheet(context),
          ),
          // Submit Exam Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: FilledButton(
              onPressed: _confirmSubmitDialog,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.midGreen,
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: Text(
                l10n.translate('study_exam_submit'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Pinned Top Timer HUD
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: palette.card,
            child: Row(
              children: [
                Icon(Icons.timer_outlined, color: timerColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  '${l10n.translate('study_exam_time_remaining')}: ',
                  style: TextStyle(
                    color: palette.text70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  formattedTime,
                  style: TextStyle(
                    color: timerColor,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const Spacer(),
                if (currentQ != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: palette.accentText.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: palette.accentText.withValues(alpha: 0.4),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      l10n.translate('study_exam_marks',
                          args: {'marks': '${currentQ.marks}'}),
                      style: TextStyle(
                        color: palette.accentText,
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.divider10),

          // Question Selector Strip
          Container(
            height: 48,
            color: palette.background,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _questions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, idx) {
                final q = _questions[idx];
                final isSelected = idx == _currentIndex;
                final text = _drafts[q.id]?.trim() ?? '';
                final isAnswered = text.isNotEmpty;

                return ChoiceChip(
                  label: Text('Q${idx + 1}'),
                  selected: isSelected,
                  avatar: isAnswered
                      ? const Icon(Icons.check_circle_rounded,
                          size: 14, color: AppColors.mintGreen)
                      : null,
                  onSelected: (_) => _selectQuestion(idx),
                  selectedColor: palette.accentText.withValues(alpha: 0.25),
                  backgroundColor: palette.card,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? palette.accentText : palette.text70,
                  ),
                );
              },
            ),
          ),
          Divider(height: 1, color: palette.divider10),

          // Main Scratchpad & Question Content
          Expanded(
            child: currentQ == null
                ? const SizedBox.shrink()
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Question Header & Prompt
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: palette.card,
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: palette.divider12, width: 0.8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Question ${_currentIndex + 1}',
                                    style: TextStyle(
                                      color: palette.accentText,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (currentQ.moduleCode != null) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: palette.accentText
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'Mod ${currentQ.moduleCode}',
                                        style: TextStyle(
                                          color: palette.accentText,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 8),
                              ChatRichText(
                                text: currentQ.prompt,
                                baseStyle: TextStyle(
                                  color: palette.text,
                                  fontSize: 14.5,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Scratchpad Label
                        Row(
                          children: [
                            Icon(Icons.edit_note_rounded,
                                color: palette.accentText, size: 20),
                            const SizedBox(width: 6),
                            Text(
                              l10n.translate('study_exam_candidate_draft'),
                              style: TextStyle(
                                color: palette.text,
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${_scratchpadController.text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length} words',
                              style: TextStyle(
                                color: palette.text54,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Scratchpad Text Field
                        TextField(
                          controller: _scratchpadController,
                          maxLines: null,
                          minLines: 12,
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 14,
                            height: 1.5,
                          ),
                          decoration: InputDecoration(
                            hintText: l10n
                                .translate('study_exam_scratchpad_hint'),
                            hintStyle: TextStyle(color: palette.text54),
                            filled: true,
                            fillColor: palette.card,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: palette.divider12, width: 0.8),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: palette.divider12, width: 0.8),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: palette.accentText, width: 1.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),

          // Bottom Bar (Previous / Next Question)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: palette.card,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton.icon(
                  onPressed: _currentIndex > 0
                      ? () => _selectQuestion(_currentIndex - 1)
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                  label: const Text('Previous'),
                ),
                Text(
                  '${_currentIndex + 1} / ${_questions.length}',
                  style: TextStyle(
                    color: palette.text70,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _currentIndex < _questions.length - 1
                      ? () => _selectQuestion(_currentIndex + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                  label: const Text('Next'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openQuestionTraySheet(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.grid_view_rounded,
                        color: palette.accentText, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      l10n.translate('study_exam_question_tray'),
                      style: TextStyle(
                        color: palette.isDark
                            ? Colors.white
                            : AppColors.darkText,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(sheetCtx).pop(),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: palette.divider10),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(8),
                  itemCount: _questions.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: palette.divider10),
                  itemBuilder: (_, idx) {
                    final q = _questions[idx];
                    final text = _drafts[q.id]?.trim() ?? '';
                    final isAnswered = text.isNotEmpty;
                    final isCurrent = idx == _currentIndex;

                    return ListTile(
                      selected: isCurrent,
                      selectedTileColor:
                          palette.accentText.withValues(alpha: 0.1),
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: isAnswered
                            ? AppColors.midGreen
                            : palette.divider12,
                        child: Text(
                          '${idx + 1}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        'Question ${idx + 1}',
                        style: TextStyle(
                          color: palette.isDark
                              ? Colors.white
                              : AppColors.darkText,
                          fontWeight:
                              isCurrent ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        isAnswered
                            ? l10n.translate('study_exam_status_answered')
                            : l10n.translate('study_exam_status_unattempted'),
                        style: TextStyle(
                          color: isAnswered
                              ? AppColors.mintGreen
                              : palette.text54,
                          fontSize: 11.5,
                        ),
                      ),
                      trailing: Text(
                        l10n.translate('study_exam_marks',
                            args: {'marks': '${q.marks}'}),
                        style: TextStyle(
                          color: palette.text54,
                          fontSize: 12,
                        ),
                      ),
                      onTap: () {
                        Navigator.of(sheetCtx).pop();
                        _selectQuestion(idx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
