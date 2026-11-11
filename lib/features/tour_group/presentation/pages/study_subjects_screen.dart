import 'package:bhromon/core/widgets/skeleton.dart';
import '../widgets/group_back_button.dart';
import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../../core/utils/app_logger.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/study_models.dart';
import '../../domain/models/study_subject_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/study_rules.dart';
import '../../domain/services/study_subject_rules.dart';
import '../widgets/study/study_decline_dialog.dart';
import '../widgets/study/study_subject_editor.dart';
import 'study_subject_screen.dart';
import 'package:bhromon/core/theme/colors.dart';

/// A study group's subjects: what the group studies. An admin adds a subject, and a member
/// proposes one for an admin to decide. Each subject holds its own modules.
class StudySubjectsScreen extends StatefulWidget {
  const StudySubjectsScreen({super.key, required this.tourId, this.repository});

  final String tourId;

  /// The data source. Null in the app, where the screen makes its own; tests pass one.
  final TourGroupRepository? repository;

  @override
  State<StudySubjectsScreen> createState() => _StudySubjectsScreenState();
}

class _StudySubjectsScreenState extends State<StudySubjectsScreen> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();
  late final Stream<List<StudySubject>> _subjects =
      _repository.watchStudySubjects(widget.tourId);
  TourRole? _myRole;

  String get _me => _repository.currentEmail;
  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;

  bool _canEdit(StudySubject subject) => canEditStudyItem(
        createdByEmail: subject.createdByEmail,
        currentEmail: _me,
        isAdmin: _isAdmin,
      );

  @override
  void initState() {
    super.initState();
    _repository.myRole(widget.tourId).then((role) {
      if (mounted) setState(() => _myRole = role);
    }, onError: (Object _) {});
  }

  /// The group's books, for the subject's book choice. Null, with a message, when they cannot be
  /// read: the editor must not open without them, or saving would clear a subject's book.
  Future<List<StudyBook>?> _booksForEditor() async {
    try {
      return await _repository.watchStudyBooks(widget.tourId).first;
    } catch (error, stackTrace) {
      logWarning('The study books did not load', error, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.l10n.translate('study_failed')),
          backgroundColor: AppColors.amber,
        ));
      }
      return null;
    }
  }

  /// An admin adds a subject straight to the list, or a member proposes one.
  Future<void> _create({required bool proposal}) async {
    final books = await _booksForEditor();
    if (books == null || !mounted) return;
    final draft = await showStudySubjectEditor(
      context,
      proposal: proposal,
      books: books,
    );
    if (draft == null || !mounted) return;
    await _run(
      () => _repository.addStudySubject(
        widget.tourId,
        title: draft.title,
        code: draft.code,
        description: draft.description,
        examDate: draft.examDate,
        bookId: draft.bookId,
        approval:
            proposal ? StudyBookApproval.proposed : StudyBookApproval.listed,
      ),
      proposal ? 'study_subject_proposal_sent' : 'study_subject_listed',
    );
  }

  Future<void> _edit(StudySubject subject) async {
    final books = await _booksForEditor();
    if (books == null || !mounted) return;
    final draft = await showStudySubjectEditor(
      context,
      existing: subject,
      books: books,
    );
    if (draft == null || !mounted) return;
    await _run(
      () => _repository.editStudySubject(
        widget.tourId,
        subject,
        title: draft.title,
        code: draft.code,
        description: draft.description,
        examDate: draft.examDate,
        bookId: draft.bookId,
      ),
      'study_subject_saved',
    );
  }

  Future<void> _approve(StudySubject subject) async {
    await _run(
      () => _repository.approveStudySubject(widget.tourId, subject.id),
      'study_subject_listed',
    );
  }

  Future<void> _decline(StudySubject subject) async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => const StudyDeclineDialog(),
    );
    if (note == null || !mounted) return;
    await _run(
      () => _repository.declineStudySubject(widget.tourId, subject.id,
          note: note),
      'study_subject_declined_done',
    );
  }

  /// Hides a listed subject from members. Its content stays, and an admin restores it from the
  /// archive section.
  Future<void> _archive(StudySubject subject) async {
    await _run(
      () => _repository.setStudySubjectArchived(widget.tourId, subject.id,
          archived: true),
      'study_subject_archived_done',
    );
  }

  Future<void> _restore(StudySubject subject) async {
    await _run(
      () => _repository.setStudySubjectArchived(widget.tourId, subject.id,
          archived: false),
      'study_subject_restored_done',
    );
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
      logWarning('A study subject change failed', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: AppColors.amber,
      ));
    }
  }

  /// The line under a subject's name: its course code and, when it is near, the exam.
  String? _subtitleFor(StudySubject subject) {
    final l10n = context.l10n;
    final parts = <String>[
      if (subject.code.isNotEmpty) subject.code,
      if (subject.examDate != null) ..._examParts(subject.examDate!, l10n),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  List<String> _examParts(DateTime exam, AppLocalizations l10n) {
    final days = daysUntilExam(exam, DateTime.now());
    if (days < 0) return const [];
    if (days == 0) return [l10n.translate('study_subject_exam_today')];
    return [
      l10n.translate('study_subject_exam_in',
          args: {'days': l10n.number(days)}),
    ];
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
          title: Text(l10n.translate('study_subjects_title'),
              style: TextStyle(
                  color: palette.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
          backgroundColor: palette.card,
          foregroundColor: palette.text,
          iconTheme: IconThemeData(color: palette.text),
          elevation: 0,
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _create(proposal: !_isAdmin),
          icon: const Icon(Icons.add_rounded),
          label: Text(l10n.translate(
              _isAdmin ? 'study_subjects_add' : 'study_subjects_propose')),
        ),
        body: StreamBuilder<List<StudySubject>>(
          stream: _subjects,
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
            final subjects = snap.data!;
            // A member sees only the subjects the group studies. An admin also sees the archive.
            final listed = studySubjectsByTitle(activeStudySubjects(subjects));
            final proposed =
                studySubjectsByTitle(subjects.where((s) => s.isProposed));
            final declined =
                studySubjectsByTitle(subjects.where((s) => s.isDeclined));
            final archived = _isAdmin
                ? archivedStudySubjects(subjects)
                : const <StudySubject>[];
            if (listed.isEmpty &&
                proposed.isEmpty &&
                declined.isEmpty &&
                archived.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l10n.translate(_isAdmin
                        ? 'study_subjects_empty'
                        : 'study_subjects_empty_member'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: palette.text70),
                  ),
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                for (final subject in listed) _subjectTile(subject),
                if (proposed.isNotEmpty) ...[
                  _header(l10n.translate('study_book_proposed_section')),
                  for (final subject in proposed)
                    _pendingTile(
                        subject,
                        [
                          if (subject.code.isNotEmpty) subject.code,
                          l10n.translate('study_book_waiting'),
                        ].join(' · ')),
                ],
                if (declined.isNotEmpty) ...[
                  _header(l10n.translate('study_book_declined_section')),
                  for (final subject in declined)
                    _pendingTile(
                      subject,
                      subject.declineNote.isEmpty
                          ? l10n.translate('study_book_declined_plain')
                          : l10n.translate('study_book_declined_with_note',
                              args: {'note': subject.declineNote}),
                    ),
                ],
                if (archived.isNotEmpty) ...[
                  _header(l10n.translate('study_subjects_archived_section')),
                  for (final subject in archived) _archivedTile(subject),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(String text) {
    final palette = context.forest;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(
        text,
        style:
            TextStyle(color: palette.accentText, fontWeight: FontWeight.bold),
      ),
    );
  }

  /// A listed subject. Tapping it opens the subject, with its modules.
  Widget _subjectTile(StudySubject subject) {
    final palette = context.forest;
    final l10n = context.l10n;
    final subtitle = _subtitleFor(subject);
    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => StudySubjectScreen(
            tourId: widget.tourId,
            subject: subject,
            repository: _repository,
          ),
        )),
        title: Text(subject.title,
            style: TextStyle(color: palette.text, fontWeight: FontWeight.w600)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle, style: TextStyle(color: palette.text54)),
        trailing: _canEdit(subject) || _isAdmin
            ? PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, color: palette.text54),
                tooltip: l10n.translate('study_subject_menu'),
                onSelected: (choice) =>
                    choice == 'archive' ? _archive(subject) : _edit(subject),
                itemBuilder: (_) => [
                  if (_canEdit(subject))
                    PopupMenuItem<String>(
                      value: 'edit',
                      child: Text(l10n.translate('study_edit')),
                    ),
                  if (_isAdmin)
                    PopupMenuItem<String>(
                      value: 'archive',
                      child: Text(l10n.translate('study_subject_archive')),
                    ),
                ],
              )
            : Icon(Icons.chevron_right_rounded, color: palette.text54),
      ),
    );
  }

  /// A subject an admin archived. Members do not see it; an admin restores it from here.
  Widget _archivedTile(StudySubject subject) {
    final l10n = context.l10n;
    final palette = context.forest;
    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(subject.title,
            style: TextStyle(color: palette.text, fontWeight: FontWeight.w600)),
        subtitle: Text(
          [
            if (subject.code.isNotEmpty) subject.code,
            l10n.translate('study_subject_archived_note'),
          ].join(' · '),
          style: TextStyle(color: palette.text54),
        ),
        trailing: TextButton(
          onPressed: () => _restore(subject),
          child: Text(l10n.translate('study_subject_restore')),
        ),
      ),
    );
  }

  /// A subject a member proposed or an admin declined. An admin lists it, and declines a
  /// proposal.
  Widget _pendingTile(StudySubject subject, String subtitle) {
    final l10n = context.l10n;
    final palette = context.forest;
    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            onTap: _canEdit(subject) ? () => _edit(subject) : null,
            title: Text(subject.title,
                style: TextStyle(
                    color: palette.text, fontWeight: FontWeight.w600)),
            subtitle: Text(subtitle, style: TextStyle(color: palette.text54)),
          ),
          if (_isAdmin)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: () => _approve(subject),
                    child: Text(l10n.translate('study_subject_approve')),
                  ),
                  if (subject.isProposed)
                    TextButton(
                      onPressed: () => _decline(subject),
                      child: Text(l10n.translate('study_book_decline')),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
