import 'package:flutter/material.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/localization/localized_date.dart';
import '../../../../../core/theme/forest_palette.dart';
import '../../../../../core/utils/app_logger.dart';
import '../../../data/tour_group_repository.dart';
import '../../../domain/models/study_problem_models.dart';
import '../../../domain/models/tour_group.dart';
import 'study_modal.dart';

/// Opens an admin's list of a problem set's members, with the date each one has for the set: a date of their own when an
/// admin set one, or the set's date. An admin sets a member's own date here, or takes it away.
Future<void> showStudyMemberDeadlinesSheet(
  BuildContext context, {
  required TourGroupRepository repository,
  required String tourId,
  required String subjectId,
  required StudyProblemSet set,
}) {
  return showStudyModal<void>(
    context: context,
    builder: (_) => _StudyMemberDeadlinesSheet(
      repository: repository,
      tourId: tourId,
      subjectId: subjectId,
      set: set,
    ),
  );
}

class _StudyMemberDeadlinesSheet extends StatefulWidget {
  const _StudyMemberDeadlinesSheet({
    required this.repository,
    required this.tourId,
    required this.subjectId,
    required this.set,
  });

  final TourGroupRepository repository;
  final String tourId;
  final String subjectId;
  final StudyProblemSet set;

  @override
  State<_StudyMemberDeadlinesSheet> createState() =>
      _StudyMemberDeadlinesSheetState();
}

class _StudyMemberDeadlinesSheetState
    extends State<_StudyMemberDeadlinesSheet> {
  // The streams are made once, here and not in build, so that each rebuild reads the same ones.
  late final Stream<List<StudyMemberDeadline>> _deadlines =
      widget.repository.watchMemberDeadlines(
    widget.tourId,
    widget.subjectId,
    widget.set.id,
  );
  late final Stream<List<TourMember>> _members =
      widget.repository.watchMembers(widget.tourId);

  String _nameOf(TourMember member) {
    final name = member.displayName.trim();
    return name.isEmpty ? member.email : name;
  }

  Future<void> _pick(StudyMemberDeadline? current, TourMember member) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current?.dueAt ?? widget.set.dueAt ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null || !mounted) return;
    await _run(
      () => widget.repository.setStudyMemberDeadline(
        widget.tourId,
        widget.subjectId,
        widget.set.id,
        member.email,
        dueAt: DateTime(picked.year, picked.month, picked.day),
      ),
      'study_member_deadline_saved',
    );
  }

  Future<void> _clear(TourMember member) => _run(
        () => widget.repository.clearStudyMemberDeadline(
          widget.tourId,
          widget.subjectId,
          widget.set.id,
          member.email,
        ),
        'study_member_deadline_cleared',
      );

  Future<void> _run(Future<void> Function() change, String doneKey) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await change();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.translate(doneKey))));
    } catch (error, stackTrace) {
      logWarning('A member due date change failed', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  Widget _memberRow(TourMember member, StudyMemberDeadline? own) {
    final l10n = context.l10n;
    final palette = context.forest;
    final format = localizedDateFormat('d MMM yyyy');
    final setDue = widget.set.dueAt;
    final line = own != null
        ? l10n.translate('study_member_deadline_own',
            args: {'date': format.format(own.dueAt)})
        : setDue != null
            ? l10n.translate('study_member_deadline_set_date',
                args: {'date': format.format(setDue)})
            : l10n.translate('study_set_no_due');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(_nameOf(member),
          style: TextStyle(color: palette.text, fontWeight: FontWeight.w600)),
      subtitle: Text(line,
          style: TextStyle(
              color: own != null ? palette.accentText : palette.text70)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.event_outlined, color: palette.text70),
            tooltip: l10n.translate('study_member_deadline_pick'),
            onPressed: () => _pick(own, member),
          ),
          if (own != null)
            IconButton(
              icon: Icon(Icons.undo_rounded, color: palette.text70),
              tooltip: l10n.translate('study_member_deadline_clear'),
              onPressed: () => _clear(member),
            ),
        ],
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
        Text(l10n.translate('study_member_deadlines_title'),
            style: TextStyle(
                color: palette.text,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
        const SizedBox(height: 4),
        Text(widget.set.title, style: TextStyle(color: palette.text70)),
        const SizedBox(height: 8),
        Text(l10n.translate('study_member_deadlines_hint'),
            style: TextStyle(color: palette.text54)),
        const SizedBox(height: 8),
        Flexible(
          child: StreamBuilder<List<StudyMemberDeadline>>(
            stream: _deadlines,
            builder: (context, dueSnap) => StreamBuilder<List<TourMember>>(
              stream: _members,
              builder: (context, memberSnap) {
                if (dueSnap.hasError || memberSnap.hasError) {
                  return Center(
                    child: Text(l10n.translate('study_failed'),
                        style: TextStyle(color: palette.text70)),
                  );
                }
                if (!dueSnap.hasData || !memberSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final dues = {for (final d in dueSnap.data!) d.email: d};
                final members = [
                  for (final member in memberSnap.data!)
                    if (member.status == TourMemberStatus.active) member,
                ]..sort((a, b) => _nameOf(a)
                    .toLowerCase()
                    .compareTo(_nameOf(b).toLowerCase()));
                return ListView(
                  children: [
                    for (final member in members)
                      _memberRow(member, dues[member.email]),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
