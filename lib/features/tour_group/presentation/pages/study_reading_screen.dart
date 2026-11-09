import '../widgets/group_back_button.dart';
import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/localized_date.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../../core/utils/app_logger.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/study_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/study_rules.dart';
import '../widgets/study/reading_session_editor.dart';
import 'study_session_screen.dart';

/// A study or book club's reading plan: the sessions the group has planned, upcoming ones
/// first. Any member plans a session. Its creator or an admin changes or removes it.
class StudyReadingScreen extends StatefulWidget {
  const StudyReadingScreen({super.key, required this.tourId, this.repository});

  final String tourId;

  /// The data source. Null in the app, where the screen makes its own; tests pass one.
  final TourGroupRepository? repository;

  @override
  State<StudyReadingScreen> createState() => _StudyReadingScreenState();
}

class _StudyReadingScreenState extends State<StudyReadingScreen> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();
  late final Stream<List<StudyBook>> _books =
      _repository.watchStudyBooks(widget.tourId);
  late final Stream<List<ReadingSession>> _sessions =
      _repository.watchReadingSessions(widget.tourId);
  TourRole? _myRole;

  String get _me => _repository.currentEmail;
  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;

  bool _canEdit(ReadingSession session) => canEditStudyItem(
        createdByEmail: session.createdByEmail,
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
    // A fresh read of the books, so the choice is current when the sheet opens.
    final books = await _repository.watchStudyBooks(widget.tourId).first;
    if (!mounted) return;
    final draft = await showReadingSessionEditor(
      context,
      books: books,
      chaptersOf: _chaptersOf,
    );
    if (draft == null || !mounted) return;
    await _run(
      () => _repository.addReadingSession(
        widget.tourId,
        title: draft.title,
        startsAt: draft.startsAt,
        bookId: draft.bookId,
        chapterIds: draft.chapterIds,
        place: draft.place,
        notes: draft.notes,
      ),
      'study_session_saved',
    );
  }

  /// The chapters of a book, for the session editor's chapter choice.
  Stream<List<StudyChapter>> _chaptersOf(String bookId) =>
      _repository.watchStudyChapters(widget.tourId, bookId);

  Future<void> _edit(ReadingSession session, List<StudyBook> books) async {
    final draft = await showReadingSessionEditor(
      context,
      books: books,
      chaptersOf: _chaptersOf,
      existing: session,
    );
    if (draft == null || !mounted) return;
    await _run(
      () => _repository.editReadingSession(
        widget.tourId,
        ReadingSession(
          id: session.id,
          title: draft.title,
          startsAt: draft.startsAt,
          bookId: draft.bookId,
          chapterIds: draft.chapterIds,
          place: draft.place,
          notes: draft.notes,
          createdByEmail: session.createdByEmail,
        ),
        startChanged: draft.startsAt != session.startsAt,
      ),
      'study_session_saved',
    );
  }

  Future<void> _remove(ReadingSession session) async {
    final l10n = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('study_session_delete_title')),
        content: Text(l10n.translate('study_session_delete_body')),
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
      () => _repository.deleteReadingSession(widget.tourId, session.id),
      'study_session_deleted',
    );
  }

  /// Runs one change and says how it went. A failure is logged and shown, and the plan
  /// keeps what it had.
  Future<void> _run(Future<void> Function() change, String doneKey) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await change();
      messenger.showSnackBar(SnackBar(content: Text(l10n.translate(doneKey))));
    } catch (error, stackTrace) {
      logWarning('A reading session change failed', error, stackTrace);
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
    return GroupPopScope(
      tourId: widget.tourId,
      child: Scaffold(
        backgroundColor: palette.background,
        appBar: AppBar(
          leading: GroupBackButton(tourId: widget.tourId),
          title: Text(l10n.translate('study_reading_title'),
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
          label: Text(l10n.translate('study_reading_add')),
        ),
        body: StreamBuilder<List<StudyBook>>(
          stream: _books,
          builder: (context, bookSnap) {
            final books = bookSnap.data ?? const <StudyBook>[];
            final titles = {for (final b in books) b.id: b.title};
            return StreamBuilder<List<ReadingSession>>(
              stream: _sessions,
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
                final split = splitSessions(snap.data!, DateTime.now());
                if (split.upcoming.isEmpty && split.past.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        l10n.translate('study_reading_empty'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: palette.text70),
                      ),
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: [
                    if (split.upcoming.isNotEmpty) ...[
                      _header(l10n.translate('study_reading_upcoming')),
                      for (final s in split.upcoming) _tile(s, books, titles),
                    ],
                    if (split.past.isNotEmpty) ...[
                      _header(l10n.translate('study_reading_past')),
                      for (final s in split.past) _tile(s, books, titles),
                    ],
                  ],
                );
              },
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

  Widget _tile(
    ReadingSession session,
    List<StudyBook> books,
    Map<String, String> titles,
  ) {
    final l10n = context.l10n;
    final palette = context.forest;
    final canEdit = _canEdit(session);
    final bookTitle = session.bookId == null ? null : titles[session.bookId];
    final details = [
      localizedDateFormat('d MMM, h:mm a').format(session.startsAt),
      if (bookTitle != null) bookTitle,
      if (session.place.isNotEmpty) session.place,
    ].join(' · ');
    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => StudySessionScreen(
            tourId: widget.tourId,
            session: session,
            repository: _repository,
          ),
        )),
        title: Text(session.title,
            style: TextStyle(color: palette.text, fontWeight: FontWeight.w600)),
        subtitle: Text(details, style: TextStyle(color: palette.text54)),
        trailing: canEdit
            ? PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, color: palette.text54),
                tooltip: l10n.translate('study_session_menu'),
                onSelected: (value) {
                  if (value == 'edit') {
                    _edit(session, books);
                  } else {
                    _remove(session);
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
              )
            : null,
      ),
    );
  }
}
