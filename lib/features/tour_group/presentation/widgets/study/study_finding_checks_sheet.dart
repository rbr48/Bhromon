import 'package:flutter/material.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/theme/forest_palette.dart';
import '../../../../../core/utils/app_logger.dart';
import '../../../data/tour_group_repository.dart';
import '../../../domain/models/study_finding_models.dart';
import 'study_modal.dart';

/// Opens the checks on a finding for an admin, who sees who checked and what they said, and may
/// withdraw any one of them.
Future<void> showStudyFindingChecksSheet(
  BuildContext context, {
  required TourGroupRepository repository,
  required String tourId,
  required String subjectId,
  required String findingId,
}) {
  return showStudyModal<void>(
    context: context,
    builder: (_) => StudyFindingChecksSheet(
      repository: repository,
      tourId: tourId,
      subjectId: subjectId,
      findingId: findingId,
    ),
  );
}

class StudyFindingChecksSheet extends StatefulWidget {
  const StudyFindingChecksSheet({
    super.key,
    required this.repository,
    required this.tourId,
    required this.subjectId,
    required this.findingId,
  });

  final TourGroupRepository repository;
  final String tourId;
  final String subjectId;
  final String findingId;

  @override
  State<StudyFindingChecksSheet> createState() =>
      _StudyFindingChecksSheetState();
}

class _StudyFindingChecksSheetState extends State<StudyFindingChecksSheet> {
  late Future<List<StudyFindingCheck>> _checks;

  @override
  void initState() {
    super.initState();
    _checks = _load();
  }

  Future<List<StudyFindingCheck>> _load() => widget.repository
      .loadFindingChecks(widget.tourId, widget.subjectId, widget.findingId);

  void _reload() {
    setState(() {
      _checks = _load();
    });
  }

  /// Asks first, then withdraws the check and shows the list again.
  Future<void> _withdraw(StudyFindingCheck check) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('study_finding_check_withdraw_title')),
        content: Text(l10n.translate('study_finding_check_withdraw_body')),
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
    if (ok != true || !mounted) return;
    try {
      await widget.repository.withdrawOtherFindingCheck(
        widget.tourId,
        widget.subjectId,
        widget.findingId,
        check,
      );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_finding_check_withdrawn')),
      ));
      _reload();
    } catch (error, stackTrace) {
      logWarning(
          'A study finding check could not be withdrawn', error, stackTrace);
      if (!mounted) return;
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
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.translate('study_finding_checks_title'),
                style: TextStyle(
                    color: palette.text,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<StudyFindingCheck>>(
                future: _checks,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Text(l10n.translate('study_failed'),
                        style: TextStyle(color: palette.text70));
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final checks = snap.data!;
                  if (checks.isEmpty) {
                    return Text(l10n.translate('study_finding_checks_none'),
                        style: TextStyle(color: palette.text70));
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final check in checks)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            l10n.translate(
                              check.verdict == FindingVerdict.confirm
                                  ? 'study_finding_check_confirmed_by'
                                  : 'study_finding_check_challenged_by',
                              args: {'email': check.email},
                            ),
                            style: TextStyle(color: palette.text),
                          ),
                          subtitle: check.note.isEmpty
                              ? null
                              : Text(check.note,
                                  style: TextStyle(color: palette.text70)),
                          trailing: IconButton(
                            tooltip:
                                l10n.translate('study_finding_check_withdraw'),
                            icon: const Icon(Icons.undo_rounded),
                            onPressed: () => _withdraw(check),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
