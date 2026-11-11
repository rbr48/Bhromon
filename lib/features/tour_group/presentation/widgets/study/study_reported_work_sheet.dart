import 'package:flutter/material.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/theme/forest_palette.dart';
import '../../../../../core/utils/app_logger.dart';
import '../../../data/tour_group_repository.dart';
import '../../../domain/models/study_problem_models.dart';
import '../../../domain/services/study_problem_rules.dart';
import 'study_modal.dart';
import 'package:bhromon/core/theme/colors.dart';

/// Opens an admin's list of the reported workings across a subject's problems, oldest report first. An admin restores a
/// working to the group, or removes it for good.
Future<void> showStudyReportedWorkSheet(
  BuildContext context, {
  required TourGroupRepository repository,
  required String tourId,
  required String subjectId,
}) {
  return showStudyModal<void>(
    context: context,
    builder: (_) => _StudyReportedWorkSheet(
      repository: repository,
      tourId: tourId,
      subjectId: subjectId,
    ),
  );
}

class _StudyReportedWorkSheet extends StatefulWidget {
  const _StudyReportedWorkSheet({
    required this.repository,
    required this.tourId,
    required this.subjectId,
  });

  final TourGroupRepository repository;
  final String tourId;
  final String subjectId;

  @override
  State<_StudyReportedWorkSheet> createState() =>
      _StudyReportedWorkSheetState();
}

class _StudyReportedWorkSheetState extends State<_StudyReportedWorkSheet> {
  // Read once when the sheet opens, and again after each change, never in build.
  late Future<List<ReportedWork>> _items;

  @override
  void initState() {
    super.initState();
    _items = _load();
  }

  /// The reported workings of the subject, each with its problem, oldest report first.
  Future<List<ReportedWork>> _load() async {
    final problems = await widget.repository
        .watchStudyProblems(widget.tourId, widget.subjectId)
        .first;
    final reported = await widget.repository.loadReportedWork(
      widget.tourId,
      widget.subjectId,
      [for (final problem in problems) problem.id],
    );
    final problemById = {for (final problem in problems) problem.id: problem};
    return reportedWorkForReview([
      for (final entry in reported.entries)
        for (final work in entry.value)
          if (problemById[entry.key] case final problem?)
            ReportedWork(problem: problem, work: work),
    ]);
  }

  /// Reloads the list, so a restored or removed working leaves it. The future is made outside setState, which takes a
  /// callback that returns nothing.
  void _reload() {
    final next = _load();
    setState(() {
      _items = next;
    });
  }

  Future<void> _run(Future<void> Function() change, String doneKey) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await change();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.translate(doneKey))));
      _reload();
    } catch (error, stackTrace) {
      logWarning('A reported working change failed', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: AppColors.amber,
      ));
    }
  }

  Future<void> _restore(ReportedWork item) => _run(
        () => widget.repository.restoreStudyWork(
          widget.tourId,
          widget.subjectId,
          item.problem.id,
          item.work.solverEmail,
        ),
        'study_problem_restored',
      );

  /// An admin removes a reported working for good, once they have confirmed it.
  Future<void> _remove(ReportedWork item) async {
    final l10n = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('study_post_delete_title')),
        content: Text(l10n.translate('study_post_delete_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.translate('study_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.translate('study_remove')),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    await _run(
      () => widget.repository.deleteStudyWork(
        widget.tourId,
        widget.subjectId,
        item.problem.id,
        item.work.solverEmail,
      ),
      'study_post_deleted',
    );
  }

  String _titleOf(StudyProblem problem) =>
      problem.title.trim().isEmpty ? problem.text.trim() : problem.title.trim();

  Widget _itemCard(ReportedWork item) {
    final l10n = context.l10n;
    final palette = context.forest;
    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_titleOf(item.problem),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: palette.text, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              l10n.translate('study_work_queue_by',
                  args: {'email': item.work.solverEmail}),
              style: TextStyle(color: palette.text70),
            ),
            const SizedBox(height: 4),
            Text(
              item.work.text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.text70),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _restore(item),
                  child: Text(l10n.translate('study_problem_restore')),
                ),
                TextButton(
                  onPressed: () => _remove(item),
                  child: Text(l10n.translate('study_remove')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.translate('study_work_queue_title'),
            style: TextStyle(
                color: palette.text,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
        const SizedBox(height: 8),
        Flexible(
          child: FutureBuilder<List<ReportedWork>>(
            future: _items,
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
              final items = snap.data!;
              if (items.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(l10n.translate('study_work_queue_empty'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: palette.text70)),
                  ),
                );
              }
              return ListView(
                children: [for (final item in items) _itemCard(item)],
              );
            },
          ),
        ),
      ],
    );
  }
}
