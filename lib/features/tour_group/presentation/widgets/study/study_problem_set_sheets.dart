import 'package:flutter/material.dart';
import 'study_member_deadlines_sheet.dart';
import 'study_modal.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/localization/localized_date.dart';
import '../../../../../core/theme/forest_palette.dart';
import '../../../../../core/utils/app_logger.dart';
import '../../../data/tour_group_repository.dart';
import '../../../domain/models/study_problem_models.dart';
import '../../../domain/services/study_problem_rules.dart';

/// What an admin entered for a problem set: its name, and the day it is due, or none.
class StudyProblemSetDraft {
  const StudyProblemSetDraft({required this.title, required this.dueAt});

  final String title;
  final DateTime? dueAt;
}

/// The set a problem goes into, or null for no set. The box exists so that "no set" and a cancelled picker are
/// told apart: a cancelled picker returns no choice at all.
class StudyProblemSetChoice {
  const StudyProblemSetChoice(this.setId);

  final String? setId;
}

/// The due line of a set for the viewer, such as "Due 20 Nov 2026 · Due soon". [ownDue] is the viewer's own date when an
/// admin set one for them, which is shown in place of the set's. The state words are shown only when they apply.
String problemSetDueLabel(
  BuildContext context,
  StudyProblemSet set, {
  DateTime? now,
  DateTime? ownDue,
}) {
  final l10n = context.l10n;
  final at = ownDue ?? set.dueAt;
  if (at == null) return l10n.translate('study_set_no_due');
  final date = localizedDateFormat('d MMM yyyy').format(at);
  final line = ownDue != null
      ? l10n.translate('study_set_due_for_you', args: {'date': date})
      : l10n.translate('study_set_due_line', args: {'date': date});
  final word =
      switch (problemSetDueState(dueAt: at, now: now ?? DateTime.now())) {
    ProblemSetDue.overdue => l10n.translate('study_set_overdue'),
    ProblemSetDue.dueSoon => l10n.translate('study_set_due_soon'),
    _ => null,
  };
  return word == null ? line : '$line · $word';
}

/// Asks for a problem set's name and due date. Returns null when the admin cancels.
Future<StudyProblemSetDraft?> showStudyProblemSetEditor(
  BuildContext context, {
  StudyProblemSet? existing,
}) {
  return showStudyModal<StudyProblemSetDraft>(
    context: context,
    builder: (_) => _StudyProblemSetEditor(existing: existing),
  );
}

/// Asks which set a problem goes into. Returns null when the admin cancels, and a choice otherwise, whose id is null
/// for no set.
Future<StudyProblemSetChoice?> showStudyProblemSetPicker(
  BuildContext context, {
  required List<StudyProblemSet> sets,
  required String? currentSetId,
}) {
  final l10n = context.l10n;
  return showDialog<StudyProblemSetChoice>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(l10n.translate('study_set_pick_title')),
      children: [
        SimpleDialogOption(
          onPressed: () =>
              Navigator.of(ctx).pop(const StudyProblemSetChoice(null)),
          child: Text(
            l10n.translate('study_set_none'),
            style: TextStyle(
              fontWeight:
                  currentSetId == null ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        for (final set in sets)
          SimpleDialogOption(
            onPressed: () =>
                Navigator.of(ctx).pop(StudyProblemSetChoice(set.id)),
            child: Text(
              set.title,
              style: TextStyle(
                fontWeight: set.id == currentSetId
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ),
      ],
    ),
  );
}

/// Opens an admin's list of a subject's problem sets, where a set is added, renamed, given a due date, or deleted.
Future<void> showStudyProblemSetsManager(
  BuildContext context, {
  required TourGroupRepository repository,
  required String tourId,
  required String subjectId,
}) {
  return showStudyModal<void>(
    context: context,
    builder: (_) => _StudyProblemSetsManager(
      repository: repository,
      tourId: tourId,
      subjectId: subjectId,
    ),
  );
}

class _StudyProblemSetEditor extends StatefulWidget {
  const _StudyProblemSetEditor({this.existing});

  final StudyProblemSet? existing;

  @override
  State<_StudyProblemSetEditor> createState() => _StudyProblemSetEditorState();
}

class _StudyProblemSetEditorState extends State<_StudyProblemSetEditor> {
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late DateTime? _dueAt = widget.existing?.dueAt;
  bool _tried = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null || !mounted) return;
    setState(() => _dueAt = DateTime(picked.year, picked.month, picked.day));
  }

  void _save() {
    setState(() => _tried = true);
    final title = _title.text.trim();
    if (title.isEmpty) return;
    Navigator.of(context)
        .pop(StudyProblemSetDraft(title: title, dueAt: _dueAt));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final titleError = _tried && _title.text.trim().isEmpty
        ? l10n.translate('study_set_title_required')
        : null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.translate(widget.existing == null
                    ? 'study_set_add'
                    : 'study_set_edit'),
                style: TextStyle(
                    color: palette.text,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _title,
                autofocus: widget.existing == null,
                style: TextStyle(color: palette.text),
                decoration: InputDecoration(
                  labelText: l10n.translate('study_set_title_label'),
                  errorText: titleError,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: _pickDue,
                    icon: Icon(Icons.event_rounded,
                        size: 18, color: palette.accentText),
                    label: Text(_dueAt == null
                        ? l10n.translate('study_set_no_due')
                        : l10n.translate('study_set_due_line', args: {
                            'date': localizedDateFormat('d MMM yyyy')
                                .format(_dueAt!),
                          })),
                  ),
                  if (_dueAt != null)
                    TextButton(
                      onPressed: () => setState(() => _dueAt = null),
                      child: Text(l10n.translate('study_set_clear_due')),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _save,
                  child: Text(l10n.translate('study_save')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudyProblemSetsManager extends StatefulWidget {
  const _StudyProblemSetsManager({
    required this.repository,
    required this.tourId,
    required this.subjectId,
  });

  final TourGroupRepository repository;
  final String tourId;
  final String subjectId;

  @override
  State<_StudyProblemSetsManager> createState() =>
      _StudyProblemSetsManagerState();
}

class _StudyProblemSetsManagerState extends State<_StudyProblemSetsManager> {
  late final Stream<List<StudyProblemSet>> _sets =
      widget.repository.watchStudyProblemSets(widget.tourId, widget.subjectId);

  Future<void> _add() async {
    final draft = await showStudyProblemSetEditor(context);
    if (draft == null || !mounted) return;
    await _run(
      () => widget.repository.addStudyProblemSet(
        widget.tourId,
        widget.subjectId,
        title: draft.title,
        dueAt: draft.dueAt,
      ),
      'study_set_saved',
    );
  }

  Future<void> _edit(StudyProblemSet set) async {
    final draft = await showStudyProblemSetEditor(context, existing: set);
    if (draft == null || !mounted) return;
    await _run(
      () => widget.repository.editStudyProblemSet(
        widget.tourId,
        widget.subjectId,
        set.id,
        title: draft.title,
        dueAt: draft.dueAt,
        dueChanged: problemSetDueMoved(set.dueAt, draft.dueAt),
      ),
      'study_set_saved',
    );
  }

  Future<void> _delete(StudyProblemSet set) async {
    final l10n = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('study_set_delete')),
        content: Text(l10n.translate('study_set_delete_body')),
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
      () => widget.repository.deleteStudyProblemSet(
        widget.tourId,
        widget.subjectId,
        set.id,
      ),
      'study_set_deleted',
    );
  }

  /// Runs one change to a set and reports the outcome. The list above updates itself, since it is a live stream.
  Future<void> _run(Future<void> Function() change, String doneKey) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await change();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.translate(doneKey))));
    } catch (error, stackTrace) {
      logWarning('A study problem set change failed', error, stackTrace);
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.translate('study_set_manage'),
              style: TextStyle(
                  color: palette.text,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: StreamBuilder<List<StudyProblemSet>>(
                stream: _sets,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Text(l10n.translate('study_failed'),
                        style: TextStyle(color: palette.text70));
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final sets = snap.data!;
                  if (sets.isEmpty) {
                    return Text(l10n.translate('study_set_none_yet'),
                        style: TextStyle(color: palette.text70));
                  }
                  return ListView(
                    shrinkWrap: true,
                    children: [for (final set in sets) _setRow(set)],
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.translate('study_set_add')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _setRow(StudyProblemSet set) {
    final l10n = context.l10n;
    final palette = context.forest;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(set.title,
          style: TextStyle(color: palette.text, fontWeight: FontWeight.w600)),
      subtitle: Text(problemSetDueLabel(context, set),
          style: TextStyle(color: palette.text70)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.group_outlined, color: palette.text70),
            tooltip: l10n.translate('study_member_deadlines_action'),
            onPressed: () => showStudyMemberDeadlinesSheet(
              context,
              repository: widget.repository,
              tourId: widget.tourId,
              subjectId: widget.subjectId,
              set: set,
            ),
          ),
          IconButton(
            icon: Icon(Icons.edit_outlined, color: palette.text70),
            tooltip: l10n.translate('study_set_edit'),
            onPressed: () => _edit(set),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline_rounded, color: palette.text70),
            tooltip: l10n.translate('study_set_delete'),
            onPressed: () => _delete(set),
          ),
        ],
      ),
    );
  }
}
