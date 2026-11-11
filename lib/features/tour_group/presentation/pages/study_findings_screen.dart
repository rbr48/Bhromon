import 'package:bhromon/core/widgets/empty_state.dart';
import 'package:bhromon/core/widgets/skeleton.dart';
import '../widgets/group_back_button.dart';
import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../../core/utils/app_logger.dart';
import '../../data/study_activity_log.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/study_finding_models.dart';
import '../../domain/models/study_subject_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/models/study_thread_models.dart';
import '../../domain/services/study_finding_rules.dart';
import '../../domain/services/study_subject_rules.dart';
import '../widgets/study/study_finding_checks_sheet.dart';
import '../widgets/study/study_finding_composer.dart';

import '../widgets/study/study_rich_text.dart';
import 'package:bhromon/core/theme/colors.dart';

/// The shared findings of one subject: a result a member reached, and how it was checked.
/// Members post findings where the module lets them, and confirm or challenge the findings of
/// others, once each. An admin shows findings that wait for approval, and pins the ones to read
/// first.
class StudyFindingsScreen extends StatefulWidget {
  const StudyFindingsScreen({
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
  State<StudyFindingsScreen> createState() => _StudyFindingsScreenState();
}

class _StudyFindingsScreenState extends State<StudyFindingsScreen> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();
  late final Stream<List<StudyFinding>> _findings =
      _repository.watchStudyFindings(widget.tourId, widget.subject.id);
  TourRole? _myRole;

  /// The signed-in member's checks, by finding id, and the findings whose checks were asked for.
  final Map<String, StudyFindingCheck> _myChecks = {};
  final Set<String> _checksAsked = {};

  String get _me => _repository.currentEmail;
  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;

  @override
  void initState() {
    super.initState();
    _repository.myRole(widget.tourId).then((role) {
      if (mounted) setState(() => _myRole = role);
    }, onError: (Object _) {});
  }

  /// Asks for the member's checks of the findings that have not been asked for yet. Each
  /// finding is asked once, so building the list again does not ask again.
  void _askChecks(List<String> ids) {
    final missing = [
      for (final id in ids)
        if (_checksAsked.add(id)) id
    ];
    if (missing.isEmpty) return;
    _repository
        .loadMyFindingChecks(widget.tourId, widget.subject.id, missing)
        .then((checks) {
      if (mounted) setState(() => _myChecks.addAll(checks));
    }, onError: (Object error, StackTrace stackTrace) {
      logWarning('Loading the study finding checks failed', error, stackTrace);
    });
  }

  Future<void> _add() async {
    final draft = await showStudyFindingEditor(context);
    if (draft == null || !mounted) return;
    final shown = postShownAtOnce(settings: widget.settings, isAdmin: _isAdmin);
    await _run(
      () => _repository.addStudyFinding(
        widget.tourId,
        widget.subject.id,
        text: draft.text,
        method: draft.method,
        shown: shown,
      ),
      shown ? 'study_post_saved' : 'study_post_waiting',
    );
  }

  Future<void> _edit(StudyFinding finding) async {
    final draft = await showStudyFindingEditor(context, existing: finding);
    if (draft == null || !mounted) return;
    await _run(
      () => _repository.editStudyFinding(
        widget.tourId,
        widget.subject.id,
        finding,
        text: draft.text,
        method: draft.method,
      ),
      'study_post_saved',
    );
  }

  Future<void> _remove(StudyFinding finding) async {
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
      () => _repository.deleteStudyFinding(
          widget.tourId, widget.subject.id, finding.id),
      'study_post_deleted',
    );
  }

  /// Asks why a finding is reported. Returns null when the member cancels.
  Future<StudyReportReason?> _askReportReason() {
    final l10n = context.l10n;
    return showDialog<StudyReportReason>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.translate('study_finding_report_title')),
        children: [
          for (final reason in StudyReportReason.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(reason),
              child: Text(l10n.translate('study_thread_reason_${reason.name}')),
            ),
        ],
      ),
    );
  }

  /// Reports a finding to the admins. Its members stop seeing it at once.
  Future<void> _report(StudyFinding finding) async {
    final reason = await _askReportReason();
    if (reason == null || !mounted) return;
    await _run(
      () => _repository.reportStudyFinding(
        widget.tourId,
        widget.subject.id,
        finding.id,
        reason: reason,
      ),
      'study_report_thanks',
    );
  }

  /// An admin shows a reported finding again, which clears its report time.
  /// Opens the checks on a finding, where an admin sees them and may withdraw any.
  Future<void> _openChecks(StudyFinding finding) => showStudyFindingChecksSheet(
        context,
        repository: _repository,
        tourId: widget.tourId,
        subjectId: widget.subject.id,
        findingId: finding.id,
      );

  Future<void> _restore(StudyFinding finding) => _run(
        () => _repository.restoreStudyFinding(
          widget.tourId,
          widget.subject.id,
          finding.id,
        ),
        'study_finding_restored',
      );

  Future<void> _setFlags(StudyFinding finding,
      {bool? shown, bool? pinned}) async {
    await _run(
      () => _repository.setStudyFindingFlags(
        widget.tourId,
        widget.subject.id,
        finding.id,
        shown: shown,
        pinned: pinned,
      ),
      shown == true ? 'study_post_shown_done' : 'study_post_saved',
    );
  }

  /// Confirms a finding, or challenges it with an optional note. The check and its count are
  /// saved together, and the card then shows the member's own check.
  Future<void> _check(StudyFinding finding, FindingVerdict verdict) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    var note = '';
    if (verdict == FindingVerdict.challenge) {
      final asked = await showStudyChallengeDialog(context);
      if (asked == null || !mounted) return;
      note = asked;
    }
    try {
      await _repository.checkStudyFinding(
        widget.tourId,
        widget.subject.id,
        finding.id,
        verdict: verdict,
        note: note,
      );
      // A check counts as a study action on this device, so it keeps the member's streak.
      await countStudyActionToday();
      if (!mounted) return;
      setState(() {
        _myChecks[finding.id] =
            StudyFindingCheck(email: _me, verdict: verdict, note: note);
      });
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_finding_checked_done')),
      ));
    } catch (error, stackTrace) {
      logWarning('A study finding check failed', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: AppColors.amber,
      ));
    }
  }

  /// Takes the member's own check back. The check and its count are removed together.
  Future<void> _withdraw(StudyFinding finding, FindingVerdict verdict) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repository.withdrawStudyFindingCheck(
        widget.tourId,
        widget.subject.id,
        finding.id,
        verdict,
      );
      if (!mounted) return;
      setState(() {
        _myChecks.remove(finding.id);
      });
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_finding_withdrawn_done')),
      ));
    } catch (error, stackTrace) {
      logWarning(
          'A study finding check could not be withdrawn', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: AppColors.amber,
      ));
    }
  }

  /// Runs one change and says how it went. A failure is logged and shown, and the list keeps
  /// what it had.
  Future<void> _run(Future<void> Function() change, String doneKey) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await change();
      messenger.showSnackBar(SnackBar(content: Text(l10n.translate(doneKey))));
    } catch (error, stackTrace) {
      logWarning('A study finding change failed', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: AppColors.amber,
      ));
    }
  }

  String _standingKey(FindingStanding standing) => switch (standing) {
        FindingStanding.unchecked => 'study_finding_standing_unchecked',
        FindingStanding.confirmed => 'study_finding_standing_confirmed',
        FindingStanding.challenged => 'study_finding_standing_challenged',
        FindingStanding.contested => 'study_finding_standing_contested',
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final canPost =
        canPostInStudyModule(settings: widget.settings, isAdmin: _isAdmin);
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
        floatingActionButton: canPost
            ? FloatingActionButton.extended(
                onPressed: _add,
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.translate('study_finding_add')),
              )
            : null,
        body: StreamBuilder<List<StudyFinding>>(
          stream: _findings,
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
            final shown = sortStudyFindings(visibleStudyFindings(
              findings: snap.data!,
              viewerEmail: _me,
              isAdmin: _isAdmin,
            ));
            _askChecks([for (final finding in shown) finding.id]);
            if (shown.isEmpty) {
              return EmptyState(
                icon: Icons.lightbulb_outline_rounded,
                message: l10n.translate('study_finding_empty'),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [for (final finding in shown) _findingCard(finding)],
            );
          },
        ),
      ),
    );
  }

  Widget _findingCard(StudyFinding finding) {
    final l10n = context.l10n;
    final palette = context.forest;
    final mine = finding.createdByEmail == _me;
    final myCheck = _myChecks[finding.id];
    final standing = findingStanding(finding);
    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (finding.pinned)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(l10n.translate('study_post_pinned_label'),
                    style: TextStyle(
                        color: palette.accentText,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ),
            StudyRichText(finding.text,
                style: TextStyle(color: palette.text, fontSize: 16)),
            const SizedBox(height: 6),
            Text(
              l10n.translate('study_finding_method_line',
                  args: {'method': finding.method}),
              style: TextStyle(color: palette.text70),
            ),
            const SizedBox(height: 8),
            Text(l10n.translate(_standingKey(standing)),
                style: TextStyle(
                    color: palette.accentText, fontWeight: FontWeight.w600)),
            Text(
              l10n.translate('study_finding_counts', args: {
                'confirmed': l10n.number(finding.confirmCount),
                'challenged': l10n.number(finding.challengeCount),
              }),
              style: TextStyle(color: palette.text54),
            ),
            if (finding.isReported) ...[
              const SizedBox(height: 6),
              Text(l10n.translate('study_finding_reported_notice'),
                  style: TextStyle(
                      color: palette.text54, fontStyle: FontStyle.italic)),
            ] else if (!finding.shown) ...[
              const SizedBox(height: 6),
              Text(l10n.translate('study_post_waiting_label'),
                  style: TextStyle(
                      color: palette.text54, fontStyle: FontStyle.italic)),
            ],
            const SizedBox(height: 4),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (myCheck != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      l10n.translate(myCheck.verdict == FindingVerdict.confirm
                          ? 'study_finding_you_confirmed'
                          : 'study_finding_you_challenged'),
                      style: TextStyle(color: palette.text),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _withdraw(finding, myCheck.verdict),
                    child: Text(l10n.translate('study_finding_withdraw')),
                  ),
                ] else if (canCheckFinding(
                  finding: finding,
                  viewerEmail: _me,
                  hasOwnCheck: false,
                )) ...[
                  TextButton.icon(
                    onPressed: () => _check(finding, FindingVerdict.confirm),
                    icon: Icon(Icons.check_circle_outline_rounded,
                        size: 18, color: palette.accentText),
                    label: Text(l10n.translate('study_finding_confirm')),
                  ),
                  TextButton.icon(
                    onPressed: () => _check(finding, FindingVerdict.challenge),
                    icon: Icon(Icons.help_outline_rounded,
                        size: 18, color: palette.accentText),
                    label: Text(l10n.translate('study_finding_challenge')),
                  ),
                ],
              ],
            ),
            if (mine ||
                _isAdmin ||
                canReportFinding(finding: finding, viewerEmail: _me))
              Align(
                alignment: Alignment.centerRight,
                child: PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded, color: palette.text54),
                  tooltip: l10n.translate('study_post_menu'),
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        _edit(finding);
                      case 'show':
                        _setFlags(finding, shown: true);
                      case 'pin':
                        _setFlags(finding, pinned: !finding.pinned);
                      case 'report':
                        _report(finding);
                      case 'checks':
                        _openChecks(finding);
                      case 'restore':
                        _restore(finding);
                      default:
                        _remove(finding);
                    }
                  },
                  itemBuilder: (_) => [
                    if (mine)
                      PopupMenuItem<String>(
                        value: 'edit',
                        child: Text(l10n.translate('study_edit')),
                      ),
                    if (canReportFinding(finding: finding, viewerEmail: _me))
                      PopupMenuItem<String>(
                        value: 'report',
                        child: Text(l10n.translate('study_finding_report')),
                      ),
                    if (_isAdmin && finding.isReported)
                      PopupMenuItem<String>(
                        value: 'restore',
                        child: Text(l10n.translate('study_problem_restore')),
                      ),
                    if (_isAdmin && !finding.shown && !finding.isReported)
                      PopupMenuItem<String>(
                        value: 'show',
                        child: Text(l10n.translate('study_post_show')),
                      ),
                    if (_isAdmin)
                      PopupMenuItem<String>(
                        value: 'pin',
                        child: Text(l10n.translate(finding.pinned
                            ? 'study_post_unpin'
                            : 'study_post_pin')),
                      ),
                    if (_isAdmin)
                      PopupMenuItem<String>(
                        value: 'checks',
                        child:
                            Text(l10n.translate('study_finding_checks_action')),
                      ),
                    if (mine || _isAdmin)
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Text(l10n.translate('study_remove')),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
