import 'package:bhromon/core/widgets/skeleton.dart';
import '../widgets/group_back_button.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/localized_date.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../../core/utils/app_logger.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/study_models.dart';
import '../../domain/models/study_summary_models.dart';
import '../../domain/models/study_thread_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/study_progress_rules.dart';

import '../widgets/study/study_text_field.dart';
import '../widgets/study/study_rich_text.dart';
import 'package:bhromon/core/theme/colors.dart';

/// The shared summary of one chapter. The group reads the revision an admin pinned, or the newest when none is
/// pinned. A member adds a revision, or restores an earlier one as a new revision: nothing is overwritten, so every
/// earlier version stays on the page. An admin pins the revision the group should read.
class StudySummaryScreen extends StatefulWidget {
  const StudySummaryScreen({
    super.key,
    required this.tourId,
    required this.book,
    required this.chapter,
    this.repository,
  });

  final String tourId;
  final StudyBook book;
  final StudyChapter chapter;

  /// The data source. Null in the app, where the screen makes its own; tests pass one.
  final TourGroupRepository? repository;

  @override
  State<StudySummaryScreen> createState() => _StudySummaryScreenState();
}

/// What a member does with one revision from its sheet.
enum _RevisionAction { restore, pin, unpin, report, hide, show }

class _StudySummaryScreenState extends State<StudySummaryScreen> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();
  StreamSubscription<List<StudySummaryRevision>>? _revisionSub;
  StreamSubscription<List<StudyChapter>>? _chapterSub;

  TourRole? _myRole;
  List<StudySummaryRevision> _revisions = const [];
  String? _pinnedId;
  bool _loaded = false;
  bool _failed = false;

  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;
  String get _me => _repository.currentEmail;

  @override
  void initState() {
    super.initState();
    _pinnedId = widget.chapter.pinnedSummaryId;
    _repository.myRole(widget.tourId).then((role) {
      if (mounted) setState(() => _myRole = role);
    }, onError: (Object _) {});
    _revisionSub = _repository
        .watchSummaries(widget.tourId, widget.book.id, widget.chapter.id)
        .listen(
      (revisions) {
        if (!mounted) return;
        setState(() {
          _revisions = revisions;
          _loaded = true;
          _failed = false;
        });
      },
      onError: (Object _) {
        if (mounted) setState(() => _failed = true);
      },
    );
    _chapterSub =
        _repository.watchStudyChapters(widget.tourId, widget.book.id).listen(
      (chapters) {
        if (!mounted) return;
        for (final chapter in chapters) {
          if (chapter.id == widget.chapter.id) {
            setState(() => _pinnedId = chapter.pinnedSummaryId);
            return;
          }
        }
      },
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    _revisionSub?.cancel();
    _chapterSub?.cancel();
    super.dispose();
  }

  /// Runs one change and says how it went. A failure is logged and shown.
  Future<void> _run(Future<void> Function() change, String doneKey) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await change();
      messenger.showSnackBar(SnackBar(content: Text(l10n.translate(doneKey))));
    } catch (error, stackTrace) {
      logWarning('A chapter summary change failed', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: AppColors.amber,
      ));
    }
  }

  Future<void> _addRevision() async {
    final text = await showStudySummaryComposer(context);
    if (text == null || !mounted) return;
    await _run(
      () => _repository.addSummaryRevision(
        widget.tourId,
        widget.book.id,
        widget.chapter.id,
        text: text,
      ),
      'study_summary_added',
    );
  }

  /// Restores an earlier revision: its text is written again as a new revision that names the one it restores.
  Future<void> _restore(StudySummaryRevision revision) {
    return _run(
      () => _repository.addSummaryRevision(
        widget.tourId,
        widget.book.id,
        widget.chapter.id,
        text: revision.text,
        restoredFromId: revision.id,
      ),
      'study_summary_restored',
    );
  }

  Future<void> _pin(StudySummaryRevision revision) {
    return _run(
      () => _repository.setChapterPin(
        widget.tourId,
        widget.book.id,
        widget.chapter.id,
        revisionId: revision.id,
      ),
      'study_summary_pinned_done',
    );
  }

  Future<void> _unpin() {
    return _run(
      () => _repository.setChapterPin(
        widget.tourId,
        widget.book.id,
        widget.chapter.id,
        revisionId: null,
      ),
      'study_summary_unpinned_done',
    );
  }

  /// Asks why a revision is reported. Returns null when the member cancels.
  Future<StudyReportReason?> _askReportReason() {
    final l10n = context.l10n;
    return showDialog<StudyReportReason>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.translate('study_summary_report_title')),
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

  /// Reports a revision to the admins. The count rises, and an admin decides whether to hide it.
  Future<void> _report(StudySummaryRevision revision) async {
    final reason = await _askReportReason();
    if (reason == null || !mounted) return;
    await _run(
      () => _repository.reportStudySummary(
        widget.tourId,
        widget.book.id,
        widget.chapter.id,
        revision.id,
        reason: reason,
      ),
      'study_report_thanks',
    );
  }

  /// An admin hides a revision from the group, or shows it again.
  Future<void> _setHidden(StudySummaryRevision revision,
      {required bool hidden}) {
    return _run(
      () => _repository.setSummaryHidden(
        widget.tourId,
        widget.book.id,
        widget.chapter.id,
        revision.id,
        hidden: hidden,
      ),
      hidden ? 'study_summary_hidden_done' : 'study_summary_shown_done',
    );
  }

  /// Who wrote a revision, and when, as one line.
  String _byline(StudySummaryRevision revision) {
    final l10n = context.l10n;
    final name = revision.editorName.isEmpty
        ? l10n.translate('study_summary_unnamed')
        : revision.editorName;
    final created = revision.createdAt;
    final date = created == null
        ? ''
        : localizedDateFormat('d MMM yyyy, HH:mm').format(created);
    return l10n.translate('study_summary_by', args: {
      'name': name,
      'date': date,
    });
  }

  /// A revision's full text, with what the member may do with it.
  Future<void> _openRevision(
    StudySummaryRevision revision, {
    required bool isNewest,
    required bool isPinned,
  }) async {
    final l10n = context.l10n;
    final action = await showDialog<_RevisionAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_byline(revision)),
        content: SingleChildScrollView(child: StudyRichText(revision.text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.translate('study_done')),
          ),
          if (!isNewest)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(_RevisionAction.restore),
              child: Text(l10n.translate('study_summary_restore')),
            ),
          if (!_isAdmin && revision.editorEmail != _me && !revision.isReported)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(_RevisionAction.report),
              child: Text(l10n.translate('study_summary_report')),
            ),
          if (_isAdmin && !revision.hidden)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(_RevisionAction.hide),
              child: Text(l10n.translate('study_summary_hide')),
            ),
          if (_isAdmin && revision.hidden)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(_RevisionAction.show),
              child: Text(l10n.translate('study_summary_show')),
            ),
          if (_isAdmin && !isPinned && !revision.hidden)
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(_RevisionAction.pin),
              child: Text(l10n.translate('study_summary_pin')),
            ),
          if (_isAdmin && isPinned)
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(_RevisionAction.unpin),
              child: Text(l10n.translate('study_summary_unpin')),
            ),
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case _RevisionAction.restore:
        await _restore(revision);
      case _RevisionAction.pin:
        await _pin(revision);
      case _RevisionAction.unpin:
        await _unpin();
      case _RevisionAction.report:
        await _report(revision);
      case _RevisionAction.hide:
        await _setHidden(revision, hidden: true);
      case _RevisionAction.show:
        await _setHidden(revision, hidden: false);
      case null:
        return;
    }
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
          title: Text(
            l10n.translate('study_summary_title'),
            style: TextStyle(
                color: palette.text, fontWeight: FontWeight.bold, fontSize: 18),
          ),
          backgroundColor: palette.card,
          foregroundColor: palette.text,
          iconTheme: IconThemeData(color: palette.text),
          elevation: 0,
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addRevision,
          icon: const Icon(Icons.edit_note_rounded),
          label: Text(l10n.translate('study_summary_add')),
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    final l10n = context.l10n;
    final palette = context.forest;
    if (_failed) {
      return Center(
        child: Text(l10n.translate('study_failed'),
            style: TextStyle(color: palette.text70)),
      );
    }
    if (!_loaded) return const ListRowsSkeleton();
    final shown = summaryShownToGroup(_revisions, pinnedId: _pinnedId);
    // A member does not see a hidden revision. An admin sees every revision, with the hidden ones marked.
    final ordered = newestFirst(_revisions);
    final listed = _isAdmin
        ? ordered
        : [
            for (final revision in ordered)
              if (!revision.hidden) revision
          ];
    final newestId = listed.isEmpty ? null : listed.first.id;
    final pinnedRevisionId = shown.pinned ? shown.revision?.id : null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        _shownCard(shown),
        if (ordered.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
            child: Text(
              l10n.translate('study_summary_revisions'),
              style: TextStyle(
                  color: palette.accentText, fontWeight: FontWeight.w600),
            ),
          ),
        for (final revision in listed)
          _revisionTile(
            revision,
            isNewest: revision.id == newestId,
            isPinned: revision.id == pinnedRevisionId,
          ),
      ],
    );
  }

  /// The revision the group reads, and why it is the one shown.
  Widget _shownCard(({StudySummaryRevision? revision, bool pinned}) shown) {
    final l10n = context.l10n;
    final palette = context.forest;
    final revision = shown.revision;
    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: revision == null
            ? Text(
                l10n.translate('study_summary_empty'),
                style: TextStyle(color: palette.text70),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.translate(shown.pinned
                        ? 'study_summary_pinned'
                        : 'study_summary_newest'),
                    style: TextStyle(
                        color: palette.accentText,
                        fontWeight: FontWeight.w600,
                        fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  StudyRichText(revision.text,
                      style: TextStyle(color: palette.text)),
                  const SizedBox(height: 8),
                  Text(
                    _byline(revision),
                    style: TextStyle(color: palette.text54, fontSize: 12),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _revisionTile(
    StudySummaryRevision revision, {
    required bool isNewest,
    required bool isPinned,
  }) {
    final palette = context.forest;
    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          _byline(revision),
          style: TextStyle(color: palette.text54, fontSize: 12),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              revision.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.text),
            ),
            if (_isAdmin && revision.hidden)
              Text(
                context.l10n.translate('study_summary_hidden_notice'),
                style: TextStyle(
                    color: palette.text54, fontStyle: FontStyle.italic),
              )
            else if (_isAdmin && revision.isReported)
              Text(
                context.l10n.translate('study_summary_reported_notice',
                    args: {'n': context.l10n.number(revision.reportCount)}),
                style: TextStyle(
                    color: palette.text54, fontStyle: FontStyle.italic),
              ),
          ],
        ),
        trailing: isPinned
            ? Icon(Icons.push_pin_rounded, color: palette.accentText)
            : Icon(Icons.chevron_right_rounded, color: palette.text54),
        onTap: () => _openRevision(
          revision,
          isNewest: isNewest,
          isPinned: isPinned,
        ),
      ),
    );
  }
}

/// Asks for the text of a summary revision. Returns the text once it is filled in and within the limit, or null
/// when the member cancels.
Future<String?> showStudySummaryComposer(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _SummaryComposer(),
  );
}

class _SummaryComposer extends StatefulWidget {
  const _SummaryComposer();

  @override
  State<_SummaryComposer> createState() => _SummaryComposerState();
}

class _SummaryComposerState extends State<_SummaryComposer> {
  final _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final l10n = context.l10n;
    final text = _text.text.trim();
    if (text.isEmpty) {
      setState(() => _error = l10n.translate('study_summary_text_required'));
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.translate('study_summary_add')),
      content: SingleChildScrollView(
        child: StudyTextField(
          controller: _text,
          maxLines: 8,
          decoration: InputDecoration(
            labelText: l10n.translate('study_summary_text_label'),
            errorText: _error,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.translate('study_cancel')),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(l10n.translate('study_save')),
        ),
      ],
    );
  }
}
