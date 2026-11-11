import '../widgets/group_back_button.dart';
import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../../core/utils/app_logger.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/study_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/study_rules.dart';
import '../widgets/study/study_book_editor.dart';
import '../widgets/study/study_decline_dialog.dart';
import '../widgets/study/study_labels.dart';
import '../widgets/study/study_vote_row.dart';
import 'study_book_chapters_screen.dart';
import 'package:bhromon/core/theme/colors.dart';

/// A study or book club's shared book list. A member proposes a book, and an admin lists it
/// or declines it. Anyone moves a listed book along its statuses. A book's creator or an
/// admin changes its details or removes it.
class StudyBooksScreen extends StatefulWidget {
  const StudyBooksScreen({super.key, required this.tourId, this.repository});

  final String tourId;

  /// The data source. Null in the app, where the screen makes its own; tests pass one.
  final TourGroupRepository? repository;

  @override
  State<StudyBooksScreen> createState() => _StudyBooksScreenState();
}

class _StudyBooksScreenState extends State<StudyBooksScreen> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();
  late final Stream<List<StudyBook>> _books =
      _repository.watchStudyBooks(widget.tourId);
  TourRole? _myRole;

  String get _me => _repository.currentEmail;
  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;

  bool _canEdit(StudyBook book) => canEditStudyItem(
        createdByEmail: book.createdByEmail,
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

  /// An admin adds a book straight to the list.
  Future<void> _add() async {
    final draft = await showStudyBookEditor(context);
    if (draft == null || !mounted) return;
    await _run(
      () => _repository.addStudyBook(
        widget.tourId,
        title: draft.title,
        author: draft.author,
        notes: draft.notes,
        status: draft.status,
        approval: StudyBookApproval.listed,
      ),
      'study_book_saved',
    );
  }

  /// A member proposes a book, which waits for an admin to list it or decline it.
  Future<void> _propose() async {
    final draft = await showStudyBookEditor(context, proposal: true);
    if (draft == null || !mounted) return;
    await _run(
      () => _repository.addStudyBook(
        widget.tourId,
        title: draft.title,
        author: draft.author,
        notes: draft.notes,
        status: draft.status,
        approval: StudyBookApproval.proposed,
      ),
      'study_book_proposal_sent',
    );
  }

  Future<void> _edit(StudyBook book) async {
    final draft = await showStudyBookEditor(context, existing: book);
    if (draft == null || !mounted) return;
    await _run(
      () => _repository.editStudyBook(
        widget.tourId,
        book,
        title: draft.title,
        author: draft.author,
        notes: draft.notes,
        status: draft.status,
      ),
      'study_book_saved',
    );
  }

  Future<void> _setStatus(StudyBook book, StudyBookStatus status) async {
    if (status == book.status) return;
    await _run(
      () => _repository.setStudyBookStatus(widget.tourId, book.id, status),
      'study_book_status_changed',
    );
  }

  /// An admin lists a proposed or declined book.
  Future<void> _approve(StudyBook book) async {
    await _run(
      () => _repository.approveStudyBook(widget.tourId, book.id),
      'study_book_listed',
    );
  }

  /// An admin declines a proposal, with an optional note for the person who proposed it.
  Future<void> _decline(StudyBook book) async {
    final note = await _askDeclineNote();
    if (note == null || !mounted) return;
    await _run(
      () => _repository.declineStudyBook(widget.tourId, book.id, note: note),
      'study_book_declined_done',
    );
  }

  /// Opens a listed book's chapters, with the reading progress of the signed-in member.
  void _openChapters(StudyBook book) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StudyBookChaptersScreen(
        tourId: widget.tourId,
        book: book,
        repository: _repository,
      ),
    ));
  }

  /// Asks an admin for the optional note. Null when the admin cancels.
  Future<String?> _askDeclineNote() => showDialog<String>(
        context: context,
        builder: (_) => const StudyDeclineDialog(),
      );

  Future<void> _remove(StudyBook book) async {
    final l10n = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('study_book_delete_title')),
        content: Text(l10n.translate('study_book_delete_body')),
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
      () => _repository.deleteStudyBook(widget.tourId, book.id),
      'study_book_deleted',
    );
  }

  /// Runs one change and says how it went. A failure is logged and shown, and the list
  /// keeps what it had.
  Future<void> _run(Future<void> Function() change, String doneKey) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await change();
      messenger.showSnackBar(SnackBar(content: Text(l10n.translate(doneKey))));
    } catch (error, stackTrace) {
      logWarning('A study book change failed', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: AppColors.amber,
      ));
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
          title: Text(l10n.translate('study_books_title'),
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
          onPressed: _isAdmin ? _add : _propose,
          icon: const Icon(Icons.add_rounded),
          label: Text(l10n
              .translate(_isAdmin ? 'study_books_add' : 'study_books_propose')),
        ),
        body: StreamBuilder<List<StudyBook>>(
          stream: _books,
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
            final books = snap.data!;
            if (books.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l10n.translate(_isAdmin
                        ? 'study_books_empty'
                        : 'study_books_empty_member'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: palette.text70),
                  ),
                ),
              );
            }
            final proposals = studyBookProposals(books);
            final groups = groupStudyBooks(books);
            final declined = studyBookDeclined(books);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                if (proposals.isNotEmpty) ...[
                  _header(l10n.translate('study_book_proposed_section')),
                  for (final book in proposals)
                    _pendingTile(book, _proposalSubtitle(book)),
                ],
                for (final status in kStudyBookSectionOrder)
                  if (groups[status]!.isNotEmpty) ...[
                    _header(l10n.translate(studyBookStatusKey(status))),
                    for (final book in groups[status]!) _tile(book),
                  ],
                if (declined.isNotEmpty) ...[
                  _header(l10n.translate('study_book_declined_section')),
                  for (final book in declined)
                    _pendingTile(book, _declinedSubtitle(book)),
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

  String _proposalSubtitle(StudyBook book) {
    final l10n = context.l10n;
    return [
      if (book.author.isNotEmpty) book.author,
      l10n.translate('study_book_waiting'),
    ].join(' · ');
  }

  String _declinedSubtitle(StudyBook book) {
    final l10n = context.l10n;
    return book.declineNote.isEmpty
        ? l10n.translate('study_book_declined_plain')
        : l10n.translate('study_book_declined_with_note',
            args: {'note': book.declineNote});
  }

  /// A book that is not on the list: a proposal, or one an admin declined. An admin lists
  /// it, and declines a proposal.
  Widget _pendingTile(StudyBook book, String subtitle) {
    final l10n = context.l10n;
    final palette = context.forest;
    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            onTap: _canEdit(book) ? () => _edit(book) : null,
            title: Text(book.title,
                style: TextStyle(
                    color: palette.text, fontWeight: FontWeight.w600)),
            subtitle: Text(subtitle, style: TextStyle(color: palette.text54)),
            trailing: _creatorMenu(book),
          ),
          if (book.isProposed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
              child: StudyVoteRow(
                tourId: widget.tourId,
                bookId: book.id,
                repository: _repository,
              ),
            ),
          if (_isAdmin)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: () => _approve(book),
                    child: Text(l10n.translate('study_book_approve')),
                  ),
                  if (book.isProposed)
                    TextButton(
                      onPressed: () => _decline(book),
                      child: Text(l10n.translate('study_book_decline')),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// The edit and remove options of a book its viewer may change. Null when they may not.
  Widget? _creatorMenu(StudyBook book) {
    if (!_canEdit(book)) return null;
    final l10n = context.l10n;
    final palette = context.forest;
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, color: palette.text54),
      tooltip: l10n.translate('study_book_menu'),
      onSelected: (value) {
        if (value == 'edit') {
          _edit(book);
        } else {
          _remove(book);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: 'edit',
          child: Text(l10n.translate('study_edit')),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Text(l10n.translate('study_remove')),
        ),
      ],
    );
  }

  Widget _tile(StudyBook book) {
    final l10n = context.l10n;
    final palette = context.forest;
    final canEdit = _canEdit(book);
    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => _openChapters(book),
        title: Text(book.title,
            style: TextStyle(color: palette.text, fontWeight: FontWeight.w600)),
        subtitle: book.author.isEmpty
            ? null
            : Text(book.author, style: TextStyle(color: palette.text54)),
        trailing: PopupMenuButton<String>(
          icon: Icon(Icons.more_vert_rounded, color: palette.text54),
          tooltip: l10n.translate('study_book_menu'),
          onSelected: (value) {
            switch (value) {
              case 'edit':
                _edit(book);
              case 'delete':
                _remove(book);
              default:
                _setStatus(book, StudyBookStatus.values.byName(value));
            }
          },
          itemBuilder: (_) => [
            for (final status in StudyBookStatus.values)
              PopupMenuItem<String>(
                value: status.name,
                enabled: status != book.status,
                child: Text(l10n.translate(studyBookStatusKey(status))),
              ),
            if (canEdit) const PopupMenuDivider(),
            if (canEdit)
              PopupMenuItem<String>(
                value: 'edit',
                child: Text(l10n.translate('study_edit')),
              ),
            if (canEdit)
              PopupMenuItem<String>(
                value: 'delete',
                child: Text(l10n.translate('study_remove')),
              ),
          ],
        ),
      ),
    );
  }
}
