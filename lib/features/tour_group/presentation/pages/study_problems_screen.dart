import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/localized_date.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../../core/utils/app_logger.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/study_problem_models.dart';
import '../../domain/models/study_subject_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/study_problem_rules.dart';
import '../../domain/services/study_subject_rules.dart';
import '../widgets/study/study_problem_composer.dart';
import '../widgets/study/study_problem_set_sheets.dart';
import 'study_problem_screen.dart';

/// The problems of one subject. Members open a problem to submit their own working; an admin posts
/// problems, shows the ones that wait for approval, and pins the ones to read first.
class StudyProblemsScreen extends StatefulWidget {
  const StudyProblemsScreen({
    super.key,
    required this.tourId,
    required this.subject,
    required this.settings,
    this.repository,
  });

  final String tourId;
  final StudySubject subject;
  final StudyModuleSettings settings;

  /// The data source. Null in the app, where the screen makes its own; tests pass one.
  final TourGroupRepository? repository;

  @override
  State<StudyProblemsScreen> createState() => _StudyProblemsScreenState();
}

class _StudyProblemsScreenState extends State<StudyProblemsScreen> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();
  late final Stream<List<StudyProblem>> _problems =
      _repository.watchStudyProblems(widget.tourId, widget.subject.id);
  late final Stream<List<StudyProblemSet>> _sets =
      _repository.watchStudyProblemSets(widget.tourId, widget.subject.id);
  TourRole? _myRole;

  /// The signed-in member's working, by problem id, and the problems whose working was asked for.
  Map<String, StudyProblemSolution> _myWork = {};
  final Set<String> _workAsked = {};

  String get _me => _repository.currentEmail;
  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;

  @override
  void initState() {
    super.initState();
    _repository.myRole(widget.tourId).then((role) {
      if (mounted) setState(() => _myRole = role);
    }, onError: (Object _) {});
  }

  /// Asks for the member's working on the problems not asked for yet. Each problem is asked once.
  void _askWork(List<String> ids) {
    final missing = [
      for (final id in ids)
        if (_workAsked.add(id)) id
    ];
    if (missing.isEmpty) return;
    _loadWork(missing);
  }

  void _loadWork(List<String> ids) {
    _repository.loadMyWork(widget.tourId, widget.subject.id, ids).then((work) {
      if (mounted) setState(() => _myWork = {..._myWork, ...work});
    }, onError: (Object error, StackTrace stackTrace) {
      logWarning('Loading the study problem work failed', error, stackTrace);
    });
  }

  /// Opens a problem. When the member comes back, their working is read again, since they may have
  /// submitted it on the problem's page.
  Future<void> _open(StudyProblem problem, {String? setTitle}) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StudyProblemScreen(
        tourId: widget.tourId,
        subject: widget.subject,
        settings: widget.settings,
        problem: problem,
        repository: _repository,
        setTitle: setTitle,
      ),
    ));
    if (!mounted) return;
    _loadWork([problem.id]);
  }

  Future<void> _add() async {
    final draft = await showStudyProblemEditor(context, withRelease: _isAdmin);
    if (draft == null || !mounted) return;
    final shown = postShownAtOnce(settings: widget.settings, isAdmin: _isAdmin);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await _repository.addStudyProblem(
        widget.tourId,
        widget.subject.id,
        text: draft.text,
        title: draft.title,
        releaseAt: draft.releaseAt,
        shown: shown,
      );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(
            l10n.translate(shown ? 'study_post_saved' : 'study_post_waiting')),
      ));
    } catch (error, stackTrace) {
      logWarning('A study problem could not be added', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final canPost =
        canPostInStudyModule(settings: widget.settings, isAdmin: _isAdmin);
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: Text(widget.settings.name,
            style: TextStyle(
                color: palette.text,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
        backgroundColor: palette.card,
        foregroundColor: palette.text,
        iconTheme: IconThemeData(color: palette.text),
        elevation: 0,
        actions: [
          if (_isAdmin)
            IconButton(
              icon: Icon(Icons.library_books_outlined, color: palette.text),
              tooltip: l10n.translate('study_set_manage'),
              onPressed: () => showStudyProblemSetsManager(
                context,
                repository: _repository,
                tourId: widget.tourId,
                subjectId: widget.subject.id,
              ),
            ),
        ],
      ),
      floatingActionButton: canPost
          ? FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.translate('study_problem_add')),
            )
          : null,
      body: StreamBuilder<List<StudyProblem>>(
        stream: _problems,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text(l10n.translate('study_failed'),
                  style: TextStyle(color: palette.text70)),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final shown = sortStudyProblems(visibleStudyProblems(
            problems: snap.data!,
            viewerEmail: _me,
            isAdmin: _isAdmin,
          ));
          _askWork([for (final problem in shown) problem.id]);
          // An admin decides the reported problems first, the oldest report first. Each is listed once.
          final queue = _isAdmin
              ? reportedProblemsForReview(shown)
              : const <StudyProblem>[];
          final rest = [
            for (final problem in shown)
              if (!queue.contains(problem)) problem,
          ];
          return StreamBuilder<List<StudyProblemSet>>(
            stream: _sets,
            builder: (context, setSnap) {
              // Until the sets arrive, the problems are listed flat, as they were before sets existed.
              final sets = setSnap.data ?? const <StudyProblemSet>[];
              // Nothing to list at all: say so, unless a set is there to show.
              if (shown.isEmpty && sets.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      l10n.translate('study_problem_empty'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: palette.text70),
                    ),
                  ),
                );
              }
              final titles = {for (final set in sets) set.id: set.title};
              String? titleOf(StudyProblem problem) =>
                  problem.setId == null ? null : titles[problem.setId];
              final grouping = groupProblemsBySet(problems: rest, sets: sets);
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  if (queue.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        l10n.translate('study_problem_queue_title'),
                        style: TextStyle(
                            color: palette.text,
                            fontWeight: FontWeight.bold,
                            fontSize: 15),
                      ),
                    ),
                    for (final problem in queue)
                      _problemCard(problem, setTitle: titleOf(problem)),
                    const SizedBox(height: 8),
                  ],
                  if (sets.isEmpty)
                    for (final problem in rest) _problemCard(problem)
                  else ...[
                    for (final section in grouping.sections) ...[
                      _setHeader(section),
                      for (final problem in section.problems)
                        _problemCard(problem, setTitle: section.set.title),
                      const SizedBox(height: 8),
                    ],
                    if (grouping.unset.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 8),
                        child: Text(
                          l10n.translate('study_set_other_heading'),
                          style: TextStyle(
                              color: palette.text,
                              fontWeight: FontWeight.bold,
                              fontSize: 15),
                        ),
                      ),
                      for (final problem in grouping.unset)
                        _problemCard(problem, setTitle: titleOf(problem)),
                    ],
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// The header of a set's section: its name, its due line, and how many of its problems the viewer has worked.
  Widget _setHeader(ProblemSetSection section) {
    final l10n = context.l10n;
    final palette = context.forest;
    final total = section.problems.length;
    final worked = workedCount(
      problems: section.problems,
      workedIds: _myWork.keys.toSet(),
    );
    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(section.set.title,
                style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            const SizedBox(height: 4),
            Text(problemSetDueLabel(context, section.set),
                style: TextStyle(color: palette.text70)),
            const SizedBox(height: 4),
            Text(
              total == 0
                  ? l10n.translate('study_set_empty')
                  : l10n.translate('study_set_progress', args: {
                      'done': l10n.number(worked),
                      'total': l10n.number(total),
                    }),
              style: TextStyle(
                  color: palette.accentText, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _problemCard(StudyProblem problem, {String? setTitle}) {
    final l10n = context.l10n;
    final palette = context.forest;
    final now = DateTime.now();
    final status = referenceStatus(problem: problem, now: now);
    final submitted = _myWork.containsKey(problem.id);
    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(problem, setTitle: setTitle),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (problem.pinned)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(l10n.translate('study_post_pinned_label'),
                      style: TextStyle(
                          color: palette.accentText,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              if (problem.title.isNotEmpty) ...[
                Text(problem.title,
                    style: TextStyle(
                        color: palette.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 16)),
                const SizedBox(height: 4),
              ],
              Text(problem.text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.text)),
              const SizedBox(height: 8),
              Text(_releaseLine(problem, status),
                  style: TextStyle(color: palette.text70)),
              Text(
                l10n.translate(submitted
                    ? 'study_problem_work_submitted'
                    : 'study_problem_work_none'),
                style: TextStyle(
                    color: palette.accentText, fontWeight: FontWeight.w600),
              ),
              if (problem.isReported) ...[
                const SizedBox(height: 6),
                Text(l10n.translate('study_problem_reported_label'),
                    style: TextStyle(
                        color: palette.accentText,
                        fontWeight: FontWeight.w600)),
              ] else if (!problem.shown) ...[
                const SizedBox(height: 6),
                Text(l10n.translate('study_post_waiting_label'),
                    style: TextStyle(
                        color: palette.text54, fontStyle: FontStyle.italic)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The release line of a problem: when its reference solution opens, or that none is set.
  String _releaseLine(StudyProblem problem, ReferenceStatus status) {
    final l10n = context.l10n;
    return switch (status) {
      ReferenceStatus.noRelease =>
        l10n.translate('study_problem_release_none_line'),
      ReferenceStatus.scheduled =>
        l10n.translate('study_problem_reference_opens', args: {
          'date': localizedDateFormat('d MMM yyyy').format(problem.releaseAt!),
        }),
      ReferenceStatus.open =>
        l10n.translate('study_problem_reference_open_line'),
    };
  }
}
