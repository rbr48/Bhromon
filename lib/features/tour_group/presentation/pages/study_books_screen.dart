import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../../core/utils/app_logger.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/study_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/study_rules.dart';
import '../widgets/study/study_book_editor.dart';
import '../widgets/study/study_labels.dart';

/// A study or book club's shared book list. Any member adds a book and moves it along
/// its statuses. The book's creator or an admin changes its details or removes it.
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
      ),
      'study_book_saved',
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
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
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
        onPressed: _add,
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.translate('study_books_add')),
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
                  l10n.translate('study_books_empty'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.text70),
                ),
              ),
            );
          }
          final groups = groupStudyBooks(books);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              for (final status in kStudyBookSectionOrder)
                if (groups[status]!.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 6),
                    child: Text(
                      l10n.translate(studyBookStatusKey(status)),
                      style: TextStyle(
                          color: palette.accentText,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  for (final book in groups[status]!) _tile(book),
                ],
            ],
          );
        },
      ),
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
        onTap: canEdit ? () => _edit(book) : null,
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
