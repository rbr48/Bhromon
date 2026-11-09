import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/localized_date.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../../core/utils/app_logger.dart';
import '../../data/study_reading_position.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/study_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/study_chapter_rules.dart';
import '../widgets/study/study_chapter_editor.dart';
import '../widgets/study/study_pace_sheet.dart';

/// One book's chapters in reading order. Each has its due date and guide questions. A member
/// marks a chapter read in their own name, and can keep a place in the book on this device.
/// An admin adds chapters, changes them, and sets the reading pace.
class StudyBookChaptersScreen extends StatefulWidget {
  const StudyBookChaptersScreen({
    super.key,
    required this.tourId,
    required this.book,
    this.repository,
    this.position,
  });

  final String tourId;
  final StudyBook book;

  /// The data source. Null in the app, where the screen makes its own; tests pass one.
  final TourGroupRepository? repository;

  /// Where the member is in the book, kept on this device. Null in the app; tests pass one.
  final StudyReadingPosition? position;

  @override
  State<StudyBookChaptersScreen> createState() =>
      _StudyBookChaptersScreenState();
}

class _StudyBookChaptersScreenState extends State<StudyBookChaptersScreen> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();
  late final StudyReadingPosition _position =
      widget.position ?? StudyReadingPosition();
  StreamSubscription<List<StudyChapter>>? _chapterSub;
  StreamSubscription<Map<String, StudyReadMark>>? _markSub;

  TourRole? _myRole;
  List<StudyChapter> _chapters = const [];
  Map<String, StudyReadMark> _marks = const {};
  bool _loaded = false;
  bool _failed = false;

  /// The chapter number the member is on, kept on this device.
  int? _here;

  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;

  @override
  void initState() {
    super.initState();
    _repository.myRole(widget.tourId).then((role) {
      if (mounted) setState(() => _myRole = role);
    }, onError: (Object _) {});
    _chapterSub =
        _repository.watchStudyChapters(widget.tourId, widget.book.id).listen(
      (chapters) {
        if (!mounted) return;
        setState(() {
          _chapters = sortStudyChapters(chapters);
          _loaded = true;
          _failed = false;
        });
      },
      onError: (Object _) {
        if (mounted) setState(() => _failed = true);
      },
    );
    _markSub =
        _repository.watchMyReadMarks(widget.tourId, widget.book.id).listen(
      (marks) {
        if (mounted) setState(() => _marks = marks);
      },
      onError: (Object _) {},
    );
    _position
        .load(tourId: widget.tourId, bookId: widget.book.id)
        .then((number) {
      if (mounted) setState(() => _here = number);
    });
  }

  @override
  void dispose() {
    _chapterSub?.cancel();
    _markSub?.cancel();
    super.dispose();
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
      logWarning('A study chapter change failed', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  Future<void> _addChapter() async {
    final suggested = _chapters.isEmpty ? 1 : _chapters.last.number + 1;
    final draft = await showStudyChapterEditor(
      context,
      suggestedNumber: suggested.clamp(1, StudyChapter.numberMax),
    );
    if (draft == null || !mounted) return;
    await _run(
      () => _repository.addStudyChapter(
        widget.tourId,
        widget.book.id,
        StudyChapter(
          id: '',
          number: draft.number,
          title: draft.title,
          pageFrom: draft.pageFrom,
          pageTo: draft.pageTo,
          dueOn: draft.dueOn,
          guide: draft.guide,
        ),
      ),
      'study_chapter_saved',
    );
  }

  Future<void> _editChapter(StudyChapter chapter) async {
    final draft = await showStudyChapterEditor(
      context,
      existing: chapter,
    );
    if (draft == null || !mounted) return;
    await _run(
      () => _repository.editStudyChapter(
        widget.tourId,
        widget.book.id,
        StudyChapter(
          id: chapter.id,
          number: draft.number,
          title: draft.title,
          pageFrom: draft.pageFrom,
          pageTo: draft.pageTo,
          dueOn: draft.dueOn,
          guide: draft.guide,
        ),
      ),
      'study_chapter_saved',
    );
  }

  Future<void> _removeChapter(StudyChapter chapter) async {
    final l10n = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('study_chapter_delete_title')),
        content: Text(l10n.translate('study_chapter_delete_body')),
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
      () => _repository.deleteStudyChapter(
          widget.tourId, widget.book.id, chapter.id),
      'study_chapter_deleted',
    );
  }

  Future<void> _setPace() async {
    final pace = await showStudyPaceSheet(
      context,
      chapterCount: _chapters.length,
    );
    if (pace == null || !mounted) return;
    await _run(
      () => _repository.setStudyReadingPace(
        widget.tourId,
        widget.book.id,
        chapters: _chapters,
        start: pace.start,
        perWeek: pace.perWeek,
      ),
      'study_pace_done',
    );
  }

  Future<void> _toggleRead(StudyChapter chapter) async {
    final wasRead = _marks.containsKey(chapter.id);
    await _run(
      () => wasRead
          ? _repository.unmarkStudyChapterRead(
              widget.tourId, widget.book.id, chapter.id)
          : _repository.markStudyChapterRead(
              widget.tourId, widget.book.id, chapter.id,
              counted: false),
      wasRead ? 'study_chapter_unread_done' : 'study_chapter_read_done',
    );
  }

  Future<void> _toggleCounted(StudyChapter chapter, StudyReadMark mark) async {
    await _run(
      () => _repository.setStudyChapterReadCounted(
        widget.tourId,
        widget.book.id,
        chapter.id,
        counted: !mark.counted,
      ),
      'study_chapter_saved',
    );
  }

  /// Keeps the member's place in the book on this device. Choosing the chapter they are on
  /// again clears it.
  Future<void> _setHere(StudyChapter chapter) async {
    final next = _here == chapter.number ? null : chapter.number;
    setState(() => _here = next);
    await _position.save(
      tourId: widget.tourId,
      bookId: widget.book.id,
      chapterNumber: next,
    );
    if (!mounted) return;
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(
      content: Text(l10n.translate(next == null
          ? 'study_chapter_position_cleared'
          : 'study_chapter_position_done')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: Text(widget.book.title,
            style: TextStyle(
                color: palette.text,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
        backgroundColor: palette.card,
        foregroundColor: palette.text,
        iconTheme: IconThemeData(color: palette.text),
        elevation: 0,
        actions: [
          if (_isAdmin && _chapters.isNotEmpty)
            IconButton(
              tooltip: l10n.translate('study_pace_action'),
              icon: const Icon(Icons.timeline_rounded),
              onPressed: _setPace,
            ),
        ],
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: _addChapter,
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.translate('study_chapter_add')),
            )
          : null,
      body: _body(),
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
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (_chapters.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.translate(_isAdmin
                ? 'study_chapters_empty'
                : 'study_chapters_empty_member'),
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.text70),
          ),
        ),
      );
    }
    final next = nextUnreadChapter(_chapters, _marks.keys.toSet());
    final today = DateTime.now();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        _summary(next),
        for (final chapter in _chapters) _chapterCard(chapter, today),
      ],
    );
  }

  /// Where the member is, and the next chapter to read.
  Widget _summary(StudyChapter? next) {
    final l10n = context.l10n;
    final palette = context.forest;
    final here = _here;
    final lines = <String>[
      if (here != null)
        l10n.translate('study_chapter_here_line',
            args: {'number': l10n.number(here)}),
      next == null
          ? l10n.translate('study_chapter_all_read')
          : l10n.translate('study_chapter_next',
              args: {'number': l10n.number(next.number)}),
    ];
    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(line, style: TextStyle(color: palette.text)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chapterCard(StudyChapter chapter, DateTime today) {
    final l10n = context.l10n;
    final palette = context.forest;
    final mark = _marks[chapter.id];
    final read = mark != null;
    final overdue = isChapterOverdue(chapter, read: read, today: today);
    final here = _here == chapter.number;
    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: Icon(
              read
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: read ? palette.accentText : palette.text54,
            ),
            title: Text(
              l10n.translate('study_chapter_title_line', args: {
                'number': l10n.number(chapter.number),
                'title': chapter.title,
              }),
              style:
                  TextStyle(color: palette.text, fontWeight: FontWeight.w600),
            ),
            subtitle: _chapterSubtitle(chapter, overdue: overdue, here: here),
            trailing: _chapterMenu(chapter, mark, here: here),
          ),
          if (chapter.guide.isNotEmpty)
            ExpansionTile(
              title: Text(l10n.translate('study_chapter_guide_section'),
                  style: TextStyle(color: palette.accentText)),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final question in chapter.guide)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child:
                        Text(question, style: TextStyle(color: palette.text)),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// The pages, the due date, and whether the chapter is overdue or where the member is.
  Widget? _chapterSubtitle(StudyChapter chapter,
      {required bool overdue, required bool here}) {
    final l10n = context.l10n;
    final palette = context.forest;
    final from = chapter.pageFrom;
    final to = chapter.pageTo;
    final parts = <String>[
      if (from != null && to != null && from != to)
        l10n.translate('study_chapter_pages_range', args: {
          'from': l10n.number(from),
          'to': l10n.number(to),
        })
      else if (from != null)
        l10n.translate('study_chapter_page_single',
            args: {'page': l10n.number(from)}),
      if (chapter.dueOn != null)
        l10n.translate('study_chapter_due_on', args: {
          'date': localizedDateFormat('d MMM yyyy').format(chapter.dueOn!),
        }),
      if (overdue) l10n.translate('study_chapter_overdue'),
      if (here) l10n.translate('study_chapter_here'),
    ];
    if (parts.isEmpty) return null;
    return Text(
      parts.join(' · '),
      style: TextStyle(color: overdue ? Colors.redAccent : palette.text54),
    );
  }

  Widget _chapterMenu(StudyChapter chapter, StudyReadMark? mark,
      {required bool here}) {
    final l10n = context.l10n;
    final palette = context.forest;
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, color: palette.text54),
      tooltip: l10n.translate('study_chapter_menu'),
      onSelected: (value) {
        switch (value) {
          case 'read':
            _toggleRead(chapter);
          case 'counted':
            if (mark != null) _toggleCounted(chapter, mark);
          case 'here':
            _setHere(chapter);
          case 'edit':
            _editChapter(chapter);
          case 'delete':
            _removeChapter(chapter);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: 'read',
          child: Text(l10n.translate(
              mark == null ? 'study_chapter_read' : 'study_chapter_unread')),
        ),
        if (mark != null)
          PopupMenuItem<String>(
            value: 'counted',
            child: Text(l10n.translate(mark.counted
                ? 'study_chapter_counted_off'
                : 'study_chapter_counted_on')),
          ),
        PopupMenuItem<String>(
          value: 'here',
          child: Text(l10n.translate(
              here ? 'study_chapter_clear_here' : 'study_chapter_set_here')),
        ),
        if (_isAdmin) ...[
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: 'edit',
            child: Text(l10n.translate('study_edit')),
          ),
          PopupMenuItem<String>(
            value: 'delete',
            child: Text(l10n.translate('study_remove')),
          ),
        ],
      ],
    );
  }
}
