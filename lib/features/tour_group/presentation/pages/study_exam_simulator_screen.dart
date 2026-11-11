import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../chat/presentation/widgets/chat_rich_text.dart';
import '../../data/study_exam_attempt_store.dart';
import '../../domain/models/study_exam_simulator_models.dart';
import '../../domain/services/study_exam_simulator_rules.dart';
import '../widgets/group_back_button.dart';
import 'study_exam_review_screen.dart';

/// Fullscreen timed exam simulator for a past paper.
///
/// The clock is the wall clock: the attempt ends at its start plus its duration, whether or
/// not the screen was open in between. Drafts are saved on this phone as the candidate
/// writes, so leaving the screen, switching apps or a restart keeps the answers, and coming
/// back resumes the same attempt. Leaving asks first, and the time keeps running meanwhile.
class StudyExamSimulatorScreen extends StatefulWidget {
  const StudyExamSimulatorScreen({
    super.key,
    required this.tourId,
    required this.bookId,
    this.chapterId,
    required this.paperTitle,
    this.rawContent,
    this.initialDurationMinutes = 180,
    this.initialQuestions,
    this.store,
    this.clock,
  });

  final String tourId;
  final String bookId;
  final String? chapterId;
  final String paperTitle;

  /// The paper's solution markdown. Its questions are read from it.
  final String? rawContent;
  final int initialDurationMinutes;
  final List<ExamQuestion>? initialQuestions;

  /// Where attempts are kept. Tests pass their own; the app uses the encrypted box.
  final StudyExamAttemptStore? store;

  /// The time now. Tests pass a fixed clock.
  final DateTime Function()? clock;

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

class _StudyExamSimulatorScreenState extends State<StudyExamSimulatorScreen>
    with WidgetsBindingObserver {
  static const Duration _saveDelay = Duration(milliseconds: 1200);
  static const Uuid _uuid = Uuid();

  late final List<ExamQuestion> _questions = _questionsFor(widget);
  late final int _paperMarks =
      _questions.fold<int>(0, (sum, question) => sum + question.marks);
  late final TextEditingController _scratchpadController =
      TextEditingController();

  /// The attempt being taken: resumed from this phone, or started now. Null until loaded.
  ExamAttempt? _attempt;
  final Map<String, String> _drafts = {};
  int _currentIndex = 0;
  Duration _remaining = Duration.zero;
  bool _loaded = false;
  bool _resumed = false;
  bool _isSubmitting = false;
  bool _didSubmit = false;
  bool _saveFailed = false;
  Timer? _ticker;
  Timer? _saveTimer;

  static List<ExamQuestion> _questionsFor(StudyExamSimulatorScreen widget) {
    final given = widget.initialQuestions;
    if (given != null && given.isNotEmpty) return given;
    final raw = widget.rawContent;
    if (raw == null || raw.trim().isEmpty) return const [];
    return StudyExamSimulatorExtractor.extractQuestions(
      subjectTitle: widget.paperTitle,
      markdownContent: raw,
    );
  }

  DateTime _now() => (widget.clock ?? DateTime.now)();

  StudyExamAttemptStore get _store =>
      widget.store ?? StudyExamAttemptStore.instance;

  /// Whether leaving now loses nothing: there is no paper, or the attempt is already handed in.
  bool get _mayLeaveAtOnce =>
      _attempt == null || !_attempt!.isOpen || _didSubmit || _questions.isEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scratchpadController.addListener(_onDraftChanged);
    unawaited(_load());
  }

  /// Resumes the open attempt for this paper, or starts one, then starts the clock.
  Future<void> _load() async {
    if (_questions.isEmpty) {
      if (mounted) setState(() => _loaded = true);
      return;
    }
    final open = await _store.loadOpenFor(
      bookId: widget.bookId,
      chapterId: widget.chapterId ?? '',
    );
    if (!mounted) return;
    if (open != null) {
      _attempt = open;
      _resumed = true;
      _drafts
        ..clear()
        ..addAll(open.draftAnswers);
    } else {
      final started = ExamAttempt(
        id: _uuid.v4(),
        tourId: widget.tourId,
        bookId: widget.bookId,
        chapterId: widget.chapterId ?? '',
        paperTitle: widget.paperTitle,
        durationMinutes: widget.initialDurationMinutes,
        startedAt: _now(),
        paperMarks: _paperMarks,
      );
      _attempt = started;
      final saved = await _store.put(started);
      if (!mounted) return;
      _saveFailed = !saved;
    }
    final attempt = _attempt!;
    final now = _now();
    if (attempt.isOverAt(now)) {
      // The time ran out while the candidate was away: hand the attempt in as it stands.
      setState(() => _loaded = true);
      await _submitExam(forced: true);
      return;
    }
    _scratchpadController.text = _drafts[_questions[_currentIndex].id] ?? '';
    setState(() {
      _remaining = attempt.remainingAt(now);
      _loaded = true;
    });
    if (_resumed) {
      _showMessage(context.l10n
          .translate('study_exam_resumed', args: {'time': _clock(_remaining)}));
    }
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final attempt = _attempt;
    if (!mounted || attempt == null || _didSubmit || _isSubmitting) return;
    final now = _now();
    final before = _remaining;
    final after = attempt.remainingAt(now);
    setState(() => _remaining = after);
    final warning = StudyExamTimerRules.crossedWarning(before, after);
    if (warning != null) {
      _showMessage(context.l10n.translate(
        warning == ExamTimerWarning.tenMinutes
            ? 'study_exam_warning_10m'
            : 'study_exam_warning_30m',
      ));
    }
    if (attempt.isOverAt(now)) {
      _ticker?.cancel();
      unawaited(_submitExam(forced: true));
    }
  }

  /// The wall clock is read again on resume, so the time left is right after the app was away.
  void _refreshClock() {
    final attempt = _attempt;
    if (!mounted || attempt == null || _didSubmit || _isSubmitting) return;
    final now = _now();
    if (attempt.isOverAt(now)) {
      _ticker?.cancel();
      unawaited(_submitExam(forced: true));
      return;
    }
    setState(() => _remaining = attempt.remainingAt(now));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshClock();
    } else {
      // Leaving the foreground keeps the draft at once.
      unawaited(_saveNow());
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// The time left, with the digits of the current language.
  String _clock(Duration duration) {
    final l10n = context.l10n;
    return StudyExamTimerRules.formatDuration(duration).replaceAllMapped(
      RegExp('[0-9]'),
      (match) => l10n.number(int.parse(match.group(0)!)),
    );
  }

  void _onDraftChanged() {
    final attempt = _attempt;
    if (attempt == null || _didSubmit || _questions.isEmpty) return;
    final id = _questions[_currentIndex].id;
    final text = _scratchpadController.text;
    if ((_drafts[id] ?? '') == text) return;
    _drafts[id] = text;
    setState(() {});
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, () => unawaited(_saveNow()));
  }

  Future<void> _saveNow() async {
    _saveTimer?.cancel();
    if (_attempt == null || _didSubmit) return;
    final saved = await _store.put(_snapshot(isCompleted: false));
    if (!mounted) return;
    final failed = !saved;
    if (failed != _saveFailed) setState(() => _saveFailed = failed);
  }

  ExamAttempt _snapshot({required bool isCompleted, DateTime? submittedAt}) {
    final attempt = _attempt!;
    final used = _now().difference(attempt.startedAt).inSeconds;
    return attempt.copyWith(
      draftAnswers: Map.unmodifiable(_drafts),
      isCompleted: isCompleted,
      submittedAt: submittedAt,
      elapsedSeconds: used.clamp(0, attempt.durationMinutes * 60).toInt(),
    );
  }

  void _selectQuestion(int index) {
    if (index < 0 || index >= _questions.length || index == _currentIndex) {
      return;
    }
    setState(() => _currentIndex = index);
    _scratchpadController.text = _drafts[_questions[index].id] ?? '';
    unawaited(_saveNow());
  }

  /// Hands the attempt in and opens the review. If it cannot be saved, the candidate is told
  /// and stays on the paper, so nothing is lost by moving on.
  Future<void> _submitExam({bool forced = false}) async {
    if (_isSubmitting || _didSubmit || _attempt == null) return;
    _isSubmitting = true;
    _ticker?.cancel();
    _saveTimer?.cancel();
    final submitted = _snapshot(isCompleted: true, submittedAt: _now());
    final saved = await _store.put(submitted);
    if (!mounted) return;
    if (!saved) {
      _isSubmitting = false;
      setState(() => _saveFailed = true);
      _showMessage(context.l10n.translate('study_exam_save_failed'));
      if (!submitted.isOverAt(_now())) _startTicker();
      return;
    }
    _didSubmit = true;
    if (forced) {
      _showMessage(context.l10n.translate('study_exam_time_up'));
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => StudyExamReviewScreen(
          attempt: submitted,
          questions: _questions,
        ),
      ),
    );
  }

  void _confirmSubmitDialog() {
    final l10n = context.l10n;
    final answered =
        _questions.where((q) => (_drafts[q.id] ?? '').trim().isNotEmpty).length;

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: Text(l10n.translate('study_exam_submit')),
          content: Text(
            '${l10n.translate('study_exam_submit_confirm')}\n\n'
            '${l10n.translate('study_exam_answered_summary', args: {
                  'answered': l10n.number(answered),
                  'total': l10n.number(_questions.length),
                })}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text(l10n.translate('study_cancel')),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                unawaited(_submitExam());
              },
              child: Text(l10n.translate('study_exam_submit')),
            ),
          ],
        );
      },
    );
  }

  /// Leaving mid-exam asks first. The time keeps running while the candidate is away.
  Future<void> _leave() async {
    if (_mayLeaveAtOnce) {
      navigateBackOrToGroup(context, widget.tourId);
      return;
    }
    final l10n = context.l10n;
    final palette = context.forest;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: palette.card,
        title: Text(
          l10n.translate('study_exam_leave_title'),
          style: TextStyle(color: palette.text, fontWeight: FontWeight.bold),
        ),
        content: Text(
          l10n.translate('study_exam_leave_body'),
          style: TextStyle(color: palette.text70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(l10n.translate('study_exam_stay')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(l10n.translate('study_exam_leave')),
          ),
        ],
      ),
    );
    if (leave != true || !mounted) return;
    await _saveNow();
    if (!mounted) return;
    navigateBackOrToGroup(context, widget.tourId);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_saveNow());
    _ticker?.cancel();
    _saveTimer?.cancel();
    _scratchpadController.removeListener(_onDraftChanged);
    _scratchpadController.dispose();
    super.dispose();
  }

  int _wordCount() => _scratchpadController.text
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .length;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final ready = _loaded && _questions.isNotEmpty && _attempt != null;
    final current = ready ? _questions[_currentIndex] : null;

    final timerColor = switch (StudyExamTimerRules.getAlertState(_remaining)) {
      ExamTimerAlertState.critical ||
      ExamTimerAlertState.expired =>
        Colors.redAccent,
      ExamTimerAlertState.warning => Colors.amber,
      ExamTimerAlertState.normal => palette.accentText,
    };

    return PopScope<void>(
      canPop: _mayLeaveAtOnce,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        backgroundColor: palette.background,
        appBar: AppBar(
          backgroundColor: palette.card,
          leading: GroupBackButton(
            tourId: widget.tourId,
            onCustomBack: () => unawaited(_leave()),
          ),
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
                style: TextStyle(color: palette.text54, fontSize: 12),
              ),
            ],
          ),
          actions: [
            if (ready)
              IconButton(
                tooltip: l10n.translate('study_exam_question_tray'),
                icon: const Icon(Icons.grid_view_rounded),
                onPressed: _openQuestionTraySheet,
              ),
            if (ready)
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
        body: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : _questions.isEmpty
                ? _buildEmptyPaper()
                : Column(
                    children: [
                      _buildHud(current, timerColor),
                      if (_saveFailed)
                        Container(
                          width: double.infinity,
                          color: Colors.redAccent.withValues(alpha: 0.12),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                          child: Text(
                            l10n.translate('study_exam_save_failed'),
                            style: const TextStyle(
                                color: Colors.redAccent, fontSize: 12),
                          ),
                        ),
                      Divider(height: 1, color: palette.divider10),
                      _buildQuestionStrip(),
                      Divider(height: 1, color: palette.divider10),
                      Expanded(child: _buildQuestionPanel(current!)),
                      _buildBottomBar(),
                    ],
                  ),
      ),
    );
  }

  Widget _buildEmptyPaper() {
    final l10n = context.l10n;
    final palette = context.forest;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          l10n.translate('study_exam_no_paper'),
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.text70, fontSize: 15, height: 1.5),
        ),
      ),
    );
  }

  Widget _buildHud(ExamQuestion? current, Color timerColor) {
    final l10n = context.l10n;
    final palette = context.forest;
    return Container(
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
            _clock(_remaining),
            style: TextStyle(
              color: timerColor,
              fontSize: 17,
              fontWeight: FontWeight.bold,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const Spacer(),
          if (current != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: palette.accentText.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: palette.accentText.withValues(alpha: 0.4),
                  width: 0.8,
                ),
              ),
              child: Text(
                l10n.translate('study_exam_marks',
                    args: {'marks': l10n.number(current.marks)}),
                style: TextStyle(
                  color: palette.accentText,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuestionStrip() {
    final l10n = context.l10n;
    final palette = context.forest;
    return Container(
      height: 48,
      color: palette.background,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _questions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, idx) {
          final question = _questions[idx];
          final selected = idx == _currentIndex;
          final answered = (_drafts[question.id] ?? '').trim().isNotEmpty;
          return ChoiceChip(
            label: Text(l10n.translate('study_exam_chip',
                args: {'n': l10n.number(idx + 1)})),
            selected: selected,
            // The selected chip shows no checkmark of its own: a tick means answered.
            showCheckmark: false,
            avatar: answered
                ? const Icon(Icons.check_circle_rounded,
                    size: 16, color: AppColors.mintGreen)
                : null,
            onSelected: (_) => _selectQuestion(idx),
            selectedColor: palette.accentText.withValues(alpha: 0.25),
            backgroundColor: palette.card,
            labelStyle: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? palette.accentText : palette.text70,
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuestionPanel(ExamQuestion question) {
    final l10n = context.l10n;
    final palette = context.forest;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.divider12, width: 0.8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      l10n.translate('study_exam_question_n',
                          args: {'n': l10n.number(_currentIndex + 1)}),
                      style: TextStyle(
                        color: palette.accentText,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (question.moduleCode != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: palette.accentText.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          l10n.translate('study_exam_module',
                              args: {'code': question.moduleCode!}),
                          style: TextStyle(
                            color: palette.accentText,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                ChatRichText(
                  text: question.prompt,
                  baseStyle: TextStyle(
                    color: palette.text,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.edit_note_rounded,
                  color: palette.accentText, size: 20),
              const SizedBox(width: 6),
              Text(
                l10n.translate('study_exam_candidate_draft'),
                style: TextStyle(
                  color: palette.text,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                l10n.translate('study_exam_words',
                    args: {'count': l10n.number(_wordCount())}),
                style: TextStyle(color: palette.text54, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _scratchpadController,
            maxLines: null,
            minLines: 12,
            style: TextStyle(color: palette.text, fontSize: 14, height: 1.5),
            decoration: InputDecoration(
              hintText: l10n.translate('study_exam_scratchpad_hint'),
              hintStyle: TextStyle(color: palette.text54),
              filled: true,
              fillColor: palette.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: palette.divider12, width: 0.8),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: palette.divider12, width: 0.8),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: palette.accentText, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final l10n = context.l10n;
    final palette = context.forest;
    return Container(
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
            label: Text(l10n.translate('study_exam_previous')),
          ),
          Text(
            '${l10n.number(_currentIndex + 1)} / ${l10n.number(_questions.length)}',
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
            label: Text(l10n.translate('study_exam_next')),
          ),
        ],
      ),
    );
  }

  void _openQuestionTraySheet() {
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
                        color: palette.text,
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
                    final question = _questions[idx];
                    final answered =
                        (_drafts[question.id] ?? '').trim().isNotEmpty;
                    final isCurrent = idx == _currentIndex;

                    return ListTile(
                      selected: isCurrent,
                      selectedTileColor:
                          palette.accentText.withValues(alpha: 0.1),
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor:
                            answered ? AppColors.midGreen : palette.divider12,
                        child: Text(
                          l10n.number(idx + 1),
                          style: TextStyle(
                            fontSize: 12,
                            color: answered ? Colors.white : palette.text70,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        l10n.translate('study_exam_question_n',
                            args: {'n': l10n.number(idx + 1)}),
                        style: TextStyle(
                          color: palette.text,
                          fontWeight:
                              isCurrent ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        answered
                            ? l10n.translate('study_exam_status_answered')
                            : l10n.translate('study_exam_status_unattempted'),
                        style: TextStyle(
                          color:
                              answered ? AppColors.mintGreen : palette.text54,
                          fontSize: 12,
                        ),
                      ),
                      trailing: Text(
                        l10n.translate('study_exam_marks',
                            args: {'marks': l10n.number(question.marks)}),
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
