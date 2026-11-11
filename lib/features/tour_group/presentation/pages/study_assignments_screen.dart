import 'package:bhromon/core/widgets/skeleton.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/group_back_button.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/localized_date.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../../core/utils/app_logger.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/study_assignment_models.dart';
import '../../domain/models/study_subject_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/study_assignment_rules.dart';
import '../../domain/services/study_subject_rules.dart';
import '../widgets/study/study_assignment_editor.dart';
import '../widgets/study/study_rich_text.dart';
import 'package:bhromon/core/theme/colors.dart';

/// The assignments of one subject. Any member the module's post policy allows adds one, and a
/// member marks the ones they have finished. An admin shows an assignment that waited for them,
/// and the one who added it or an admin changes or removes it.
class StudyAssignmentsScreen extends StatefulWidget {
  const StudyAssignmentsScreen({
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
  State<StudyAssignmentsScreen> createState() => _StudyAssignmentsScreenState();
}

class _StudyAssignmentsScreenState extends State<StudyAssignmentsScreen> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();
  late final Stream<List<StudyAssignment>> _assignments =
      _repository.watchStudyAssignments(widget.tourId, widget.subject.id);
  late final Stream<Set<String>> _finished =
      _repository.watchMyFinishedAssignments(widget.tourId, widget.subject.id);
  TourRole? _myRole;

  String get _me => _repository.currentEmail;
  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;
  bool get _canPost =>
      canPostInStudyModule(settings: widget.settings, isAdmin: _isAdmin);

  @override
  void initState() {
    super.initState();
    _repository.myRole(widget.tourId).then((role) {
      if (mounted) setState(() => _myRole = role);
    }, onError: (Object _) {});
  }

  Future<void> _add() async {
    final draft = await showStudyAssignmentEditor(context);
    if (draft == null || !mounted) return;
    final shown = postShownAtOnce(settings: widget.settings, isAdmin: _isAdmin);
    await _run(
      () => _repository.addStudyAssignment(
        widget.tourId,
        widget.subject.id,
        title: draft.title,
        details: draft.details,
        url: draft.url,
        dueAt: draft.dueAt,
        shown: shown,
      ),
      'study_assignment_added',
    );
  }

  Future<void> _edit(StudyAssignment assignment) async {
    final draft =
        await showStudyAssignmentEditor(context, existing: assignment);
    if (draft == null || !mounted) return;
    await _run(
      () => _repository.editStudyAssignment(
        widget.tourId,
        widget.subject.id,
        assignment.id,
        title: draft.title,
        details: draft.details,
        url: draft.url,
        dueAt: draft.dueAt,
      ),
      'study_assignment_saved',
    );
  }

  Future<void> _remove(StudyAssignment assignment) async {
    final l10n = context.l10n;
    final remove = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('study_assignment_delete_title')),
        content: Text(l10n.translate('study_assignment_delete_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.translate('study_cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.translate('study_remove')),
          ),
        ],
      ),
    );
    if (remove != true || !mounted) return;
    await _run(
      () => _repository.deleteStudyAssignment(
          widget.tourId, widget.subject.id, assignment.id),
      'study_assignment_removed',
    );
  }

  /// An admin shows an assignment that waited, or takes it back.
  Future<void> _setShown(StudyAssignment assignment, bool shown) => _run(
        () => _repository.setStudyAssignmentShown(
          widget.tourId,
          widget.subject.id,
          assignment.id,
          shown: shown,
        ),
        'study_assignment_saved',
      );

  /// Marks an assignment finished for the member, or takes the mark back. A mark is quiet when it
  /// saves; a failure says so.
  Future<void> _setFinished(StudyAssignment assignment, bool finished) async {
    try {
      await _repository.setMyAssignmentFinished(
        widget.tourId,
        widget.subject.id,
        assignment.id,
        finished: finished,
      );
    } catch (error, stackTrace) {
      logWarning('An assignment mark did not save', error, stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.l10n.translate('study_failed')),
        backgroundColor: AppColors.amber,
      ));
    }
  }

  Future<void> _openLink(String url) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text(l10n.translate('study_assignment_open_failed')),
          backgroundColor: AppColors.amber,
        ));
      }
    } catch (error, stackTrace) {
      logWarning('An assignment link did not open', error, stackTrace);
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text(l10n.translate('study_assignment_open_failed')),
          backgroundColor: AppColors.amber,
        ));
      }
    }
  }

  /// Runs a change and says whether it saved.
  Future<void> _run(Future<void> Function() change, String doneKey) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await change();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.translate(doneKey))));
    } catch (error, stackTrace) {
      logWarning('A study assignment change failed', error, stackTrace);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: AppColors.amber,
      ));
    }
  }

  /// The due line of an assignment, which says how near the day is.
  String _dueLine(DateTime due, AssignmentDue state) {
    final l10n = context.l10n;
    final date = localizedDateFormat('d MMM yyyy').format(due);
    return switch (state) {
      AssignmentDue.overdue =>
        l10n.translate('study_assignment_overdue', args: {'date': date}),
      AssignmentDue.dueToday => l10n.translate('study_assignment_due_today'),
      AssignmentDue.dueSoon =>
        l10n.translate('study_assignment_due_soon', args: {'date': date}),
      _ => l10n.translate('study_assignment_due_on', args: {'date': date}),
    };
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
          title: Text(widget.settings.name,
              style: TextStyle(
                  color: palette.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
          backgroundColor: palette.card,
          foregroundColor: palette.text,
          iconTheme: IconThemeData(color: palette.text),
          elevation: 0,
        ),
        floatingActionButton: _canPost
            ? FloatingActionButton.extended(
                onPressed: _add,
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.translate('study_assignment_add')),
              )
            : null,
        body: StreamBuilder<List<StudyAssignment>>(
          stream: _assignments,
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                child: Text(l10n.translate('study_failed'),
                    style: TextStyle(color: palette.text70)),
              );
            }
            if (!snap.hasData) {
              return const ListRowsSkeleton();
            }
            return StreamBuilder<Set<String>>(
              stream: _finished,
              builder: (context, doneSnap) {
                final finished = doneSnap.data ?? const <String>{};
                final visible = visibleStudyAssignments(
                  assignments: snap.data!,
                  viewerEmail: _me,
                  isAdmin: _isAdmin,
                );
                if (visible.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        l10n.translate('study_assignment_empty'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: palette.text70),
                      ),
                    ),
                  );
                }
                final ordered =
                    sortStudyAssignments(visible, finished: finished);
                final doneCount = finishedAssignmentCount(
                  assignments: visible,
                  finished: finished,
                );
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        l10n.translate('study_assignment_progress', args: {
                          'done': l10n.number(doneCount),
                          'total': l10n.number(visible.length),
                        }),
                        style: TextStyle(color: palette.text70),
                      ),
                    ),
                    for (final assignment in ordered)
                      _card(assignment, finished.contains(assignment.id)),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _card(StudyAssignment assignment, bool finished) {
    final l10n = context.l10n;
    final palette = context.forest;
    final due = assignment.dueAt;
    final state = assignmentDueState(dueAt: due, now: DateTime.now());
    final canEdit = canEditAssignment(
      createdByEmail: assignment.createdByEmail,
      viewerEmail: _me,
      isAdmin: _isAdmin,
    );
    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Semantics(
          label: l10n.translate('study_assignment_mark_done'),
          child: Checkbox(
            value: finished,
            onChanged: (value) => _setFinished(assignment, value ?? false),
          ),
        ),
        title: Text(
          assignment.title,
          style: TextStyle(
            color: finished ? palette.text54 : palette.text,
            fontWeight: FontWeight.w600,
            decoration: finished ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (due != null)
              Text(
                _dueLine(due, state),
                style: TextStyle(
                  color: state == AssignmentDue.overdue
                      ? Colors.redAccent
                      : palette.text70,
                ),
              ),
            if (assignment.details.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: StudyRichText(
                  assignment.details,
                  style: TextStyle(color: palette.text70),
                ),
              ),
            if (!assignment.shown)
              Text(
                l10n.translate('study_post_waiting_label'),
                style: TextStyle(color: palette.accentText),
              ),
            if (assignment.url.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _openLink(assignment.url),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(l10n.translate('study_assignment_open_link')),
                ),
              ),
          ],
        ),
        trailing: canEdit
            ? PopupMenuButton<String>(
                tooltip: l10n.translate('study_post_menu'),
                onSelected: (choice) => switch (choice) {
                  'edit' => _edit(assignment),
                  'show' => _setShown(assignment, true),
                  _ => _remove(assignment),
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(l10n.translate('study_edit')),
                  ),
                  if (_isAdmin && !assignment.shown)
                    PopupMenuItem(
                      value: 'show',
                      child: Text(l10n.translate('study_post_show')),
                    ),
                  PopupMenuItem(
                    value: 'remove',
                    child: Text(l10n.translate('study_remove')),
                  ),
                ],
              )
            : null,
      ),
    );
  }
}
