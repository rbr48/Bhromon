import '../widgets/group_back_button.dart';
import 'dart:async';
import '../widgets/study/study_modal.dart';

import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/localized_date.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../../core/utils/app_logger.dart';
import '../../data/study_reading_position.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/study_material_models.dart';
import '../../domain/models/study_models.dart';
import '../../domain/models/study_syllabus_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/study_chapter_rules.dart';
import '../../domain/services/study_solution_rules.dart';
import '../widgets/study/study_chapter_editor.dart';
import '../widgets/study/study_pace_sheet.dart';
import '../widgets/study/study_thread_composer.dart';
import 'markdown_viewer_screen.dart';
import 'pdf_viewer_screen.dart';
import 'study_discussion_screen.dart';
import 'study_flashcards_screen.dart';
import 'study_glossary_screen.dart';
import 'study_materials_screen.dart';
import 'study_pack_share.dart';
import 'study_progress_screen.dart';
import 'study_quizzes_screen.dart';
import 'study_summary_screen.dart';

import '../widgets/study/study_rich_text.dart';

/// The learning tools a book offers, from the sheet on its chapters.
enum _LearningTool { quizzes, glossary, flashcards, progress, studyPack }

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
  StreamSubscription<List<StudyMaterial>>? _materialsSub;

  TourRole? _myRole;
  List<StudyChapter> _chapters = const [];
  Map<String, StudyReadMark> _marks = const {};
  List<StudyMaterial> _materials = const [];
  bool _loaded = false;
  bool _failed = false;

  /// The chapter number the member is on, kept on this device.
  int? _here;
  String? _selectedModuleCode;
  late final List<SyllabusModule> _syllabusModules =
      StudySyllabusCatalog.modulesFor(widget.book.title);

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
    _materialsSub =
        _repository.watchStudyMaterials(widget.tourId, widget.book.id).listen(
      (materials) {
        if (mounted) setState(() => _materials = materials);
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
    _materialsSub?.cancel();
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

  /// Opens the materials of this book: the notes, files, links and recordings members filed.
  void _openMaterials() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StudyMaterialsScreen(
        tourId: widget.tourId,
        book: widget.book,
        repository: _repository,
      ),
    ));
  }

  /// Opens the discussion of this book: its threads, with the fence and the member's place.
  void _openDiscussion() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StudyDiscussionScreen(
        tourId: widget.tourId,
        book: widget.book,
        repository: _repository,
        position: _position,
      ),
    ));
  }

  /// The learning tools of this book, chosen from a sheet: quizzes, the glossary and flashcards.
  Future<void> _openLearning() async {
    final l10n = context.l10n;
    final palette = context.forest;
    final tool = await showStudyModal<_LearningTool>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                l10n.translate('study_learning_title'),
                style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
            ),
            ListTile(
              leading: Icon(Icons.quiz_rounded, color: palette.accentText),
              title: Text(l10n.translate('study_quizzes_title'),
                  style: TextStyle(color: palette.text)),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_LearningTool.quizzes),
            ),
            ListTile(
              leading: Icon(Icons.menu_book_rounded, color: palette.accentText),
              title: Text(l10n.translate('study_glossary_title'),
                  style: TextStyle(color: palette.text)),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_LearningTool.glossary),
            ),
            ListTile(
              leading: Icon(Icons.style_rounded, color: palette.accentText),
              title: Text(l10n.translate('study_flashcards_title'),
                  style: TextStyle(color: palette.text)),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_LearningTool.flashcards),
            ),
            ListTile(
              leading: Icon(Icons.insights_rounded, color: palette.accentText),
              title: Text(l10n.translate('study_progress_title'),
                  style: TextStyle(color: palette.text)),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_LearningTool.progress),
            ),
            ListTile(
              leading:
                  Icon(Icons.picture_as_pdf_rounded, color: palette.accentText),
              title: Text(l10n.translate('study_pack_action'),
                  style: TextStyle(color: palette.text)),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_LearningTool.studyPack),
            ),
          ],
        ),
      ),
    );
    if (tool == null || !mounted) return;
    if (tool == _LearningTool.studyPack) {
      await shareStudyPack(
        context: context,
        repository: _repository,
        tourId: widget.tourId,
        book: widget.book,
      );
      return;
    }
    final Widget page = switch (tool) {
      _LearningTool.quizzes => StudyQuizzesScreen(
          tourId: widget.tourId,
          book: widget.book,
          repository: _repository,
        ),
      _LearningTool.glossary => StudyGlossaryScreen(
          tourId: widget.tourId,
          book: widget.book,
          repository: _repository,
        ),
      _LearningTool.flashcards => StudyFlashcardsScreen(
          book: widget.book,
          tourId: widget.tourId,
          repository: _repository,
        ),
      _LearningTool.progress => StudyProgressScreen(
          tourId: widget.tourId,
          book: widget.book,
          repository: _repository,
        ),
      // The study pack opens a share sheet, not a page, so it returned above.
      _LearningTool.studyPack => const SizedBox.shrink(),
    };
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  /// The shared summary of a chapter: the revision the group reads, and the older ones.
  void _openSummary(StudyChapter chapter) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StudySummaryScreen(
        tourId: widget.tourId,
        book: widget.book,
        chapter: chapter,
        repository: _repository,
      ),
    ));
  }

  /// A guide question starts a thread on its chapter, with the question as its title. The
  /// member writes the body and may change the title first.
  Future<void> _startThreadFromGuide(
      StudyChapter chapter, String question) async {
    final draft = await showStudyThreadComposer(
      context,
      chapters: _chapters,
      initialTitle: question,
      initialChapterId: chapter.id,
    );
    if (draft == null || !mounted) return;
    await _run(
      () => _repository.addStudyThread(
        widget.tourId,
        widget.book.id,
        title: draft.title,
        body: draft.body,
        pageRef: draft.pageRef,
        chapterId: draft.chapterId,
      ),
      'study_thread_posted',
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
    return GroupPopScope(
      tourId: widget.tourId,
      child: Scaffold(
        backgroundColor: palette.background,
        appBar: AppBar(
          leading: GroupBackButton(tourId: widget.tourId),
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
            IconButton(
              tooltip: l10n.translate('study_material_title'),
              icon: const Icon(Icons.folder_open_rounded),
              onPressed: _openMaterials,
            ),
            IconButton(
              tooltip: l10n.translate('study_discussion_title'),
              icon: const Icon(Icons.forum_rounded),
              onPressed: _openDiscussion,
            ),
            IconButton(
              tooltip: l10n.translate('study_learning_title'),
              icon: const Icon(Icons.school_rounded),
              onPressed: _openLearning,
            ),
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
        _syllabusBlueprintCard(),
        for (final chapter in _chapters) _chapterCard(chapter, today),
      ],
    );
  }

  Widget _syllabusBlueprintCard() {
    if (_syllabusModules.isEmpty) return const SizedBox.shrink();
    final l10n = context.l10n;
    final palette = context.forest;
    final isBn = l10n.locale.languageCode == 'bn';
    final activeModule = _selectedModuleCode == null
        ? null
        : _syllabusModules.firstWhere(
            (m) => m.code == _selectedModuleCode,
            orElse: () => _syllabusModules.first,
          );

    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _selectedModuleCode != null
              ? palette.accentText.withValues(alpha: 0.5)
              : palette.divider12,
          width: 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_tree_rounded,
                    color: palette.accentText, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.translate('study_syllabus_blueprint'),
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_selectedModuleCode != null)
                  TextButton(
                    onPressed: () => setState(() => _selectedModuleCode = null),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 24),
                    ),
                    child: Text(
                      l10n.translate('viewer_filter_all_modules'),
                      style: TextStyle(
                        color: palette.accentText,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(
                        l10n.translate('viewer_filter_all_modules'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: _selectedModuleCode == null
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: _selectedModuleCode == null
                              ? palette.accentText
                              : palette.text70,
                        ),
                      ),
                      selected: _selectedModuleCode == null,
                      selectedColor: palette.accentText.withValues(alpha: 0.2),
                      backgroundColor: palette.divider10,
                      side: BorderSide(
                        color: _selectedModuleCode == null
                            ? palette.accentText.withValues(alpha: 0.6)
                            : palette.divider12,
                        width: 0.8,
                      ),
                      onSelected: (_) =>
                          setState(() => _selectedModuleCode = null),
                    ),
                  ),
                  for (final mod in _syllabusModules)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(
                          'Module ${mod.code}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: _selectedModuleCode == mod.code
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: _selectedModuleCode == mod.code
                                ? palette.accentText
                                : palette.text70,
                          ),
                        ),
                        selected: _selectedModuleCode == mod.code,
                        selectedColor:
                            palette.accentText.withValues(alpha: 0.2),
                        backgroundColor: palette.divider10,
                        side: BorderSide(
                          color: _selectedModuleCode == mod.code
                              ? palette.accentText.withValues(alpha: 0.6)
                              : palette.divider12,
                          width: 0.8,
                        ),
                        onSelected: (selected) => setState(() {
                          _selectedModuleCode = selected ? mod.code : null;
                        }),
                      ),
                    ),
                ],
              ),
            ),
            if (activeModule != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: palette.accentText.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: palette.accentText.withValues(alpha: 0.25),
                    width: 0.8,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Module ${activeModule.code}: ${isBn && activeModule.titleBn.isNotEmpty ? activeModule.titleBn : activeModule.title}',
                      style: TextStyle(
                        color: palette.accentText,
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (activeModule.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        activeModule.description,
                        style: TextStyle(
                          color: palette.text70,
                          fontSize: 11.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
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

  String _formatFileSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Opens a solution in its reader: a PDF in the PDF viewer, and a note or a Markdown file in the Markdown reader.
  /// A note opens from its text, and a Markdown file from its address, which the reader fetches. The other
  /// language pairs only when its text is a note.
  void _openSolution(
    StudyMaterial material,
    StudyMaterial? other, {
    StudyChapter? chapter,
  }) {
    final titleWithChapter = chapter != null && chapter.title.isNotEmpty
        ? '${chapter.title} · ${material.title}'
        : material.title;
    if (isPdfSolution(material)) {
      PdfViewerScreen.open(
        context,
        title: titleWithChapter,
        fileUrl: material.url,
        tourId: widget.tourId,
      );
      return;
    }
    final source = solutionSource(material, other);
    MarkdownViewerScreen.open(
      context,
      title: material.title,
      rawContent: source.rawContent,
      fileUrl: source.fileUrl,
      tourId: widget.tourId,
      alternateRawContent: source.paired?.body,
      alternateTitle: source.paired?.title,
      alternateLanguageLabel: isBanglaSolution(material) ? 'English' : 'বাংলা',
      subjectTitle: widget.book.title,
      chapterTitle: chapter?.title,
    );
  }

  Widget _chapterCard(StudyChapter chapter, DateTime today) {
    final l10n = context.l10n;
    final palette = context.forest;
    final mark = _marks[chapter.id];
    final read = mark != null;
    final overdue = isChapterOverdue(chapter, read: read, today: today);
    final here = _here == chapter.number;

    // Only a solution the reader can open gets a one-tap button: a note with text, or a Markdown file.
    final chapterMaterials = _materials
        .where((m) =>
            m.chapterId == chapter.id && m.isPublished && isReadableSolution(m))
        .toList();

    StudyMaterial? englishNote;
    StudyMaterial? banglaNote;

    for (final m in chapterMaterials) {
      if (isBanglaSolution(m)) {
        banglaNote ??= m;
      } else {
        englishNote ??= m;
      }
    }

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
          if (englishNote != null || banglaNote != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  if (englishNote != null)
                    ElevatedButton.icon(
                      onPressed: () => _openSolution(englishNote!, banglaNote,
                          chapter: chapter),
                      icon: const Text('🇬🇧', style: TextStyle(fontSize: 16)),
                      label: Text(
                        englishNote.sizeBytes != null &&
                                englishNote.sizeBytes! > 0
                            ? '${l10n.translate('study_solution_english')} (${_formatFileSize(englishNote.sizeBytes)})'
                            : l10n.translate('study_solution_english'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: palette.isDark
                            ? const Color(0xFF1E3A2B)
                            : const Color(0xFFE8F5E9),
                        foregroundColor: palette.isDark
                            ? AppColors.mintGreen
                            : const Color(0xFF1B5E20),
                        elevation: 0,
                        side: BorderSide(
                          color: (palette.isDark
                                  ? AppColors.mintGreen
                                  : const Color(0xFF2E7D32))
                              .withValues(alpha: 0.4),
                        ),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                      ),
                    ),
                  if (banglaNote != null)
                    ElevatedButton.icon(
                      onPressed: () => _openSolution(banglaNote!, englishNote,
                          chapter: chapter),
                      icon: const Text('🇧🇩', style: TextStyle(fontSize: 16)),
                      label: Text(
                        banglaNote.sizeBytes != null &&
                                banglaNote.sizeBytes! > 0
                            ? '${l10n.translate('study_solution_bangla')} (${_formatFileSize(banglaNote.sizeBytes)})'
                            : l10n.translate('study_solution_bangla'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: palette.isDark
                            ? const Color(0xFF193B28)
                            : const Color(0xFFE8F5E9),
                        foregroundColor: palette.isDark
                            ? const Color(0xFF81C784)
                            : const Color(0xFF2E7D32),
                        elevation: 0,
                        side: BorderSide(
                          color: (palette.isDark
                                  ? const Color(0xFF81C784)
                                  : const Color(0xFF388E3C))
                              .withValues(alpha: 0.4),
                        ),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                      ),
                    ),
                ],
              ),
            ),
          if (chapter.guide.isNotEmpty)
            ExpansionTile(
              title: Text(l10n.translate('study_chapter_guide_section'),
                  style: TextStyle(color: palette.accentText)),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final question in chapter.guide)
                  Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: StudyRichText(question,
                              style: TextStyle(color: palette.text)),
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.translate('study_guide_start_thread'),
                        icon: Icon(Icons.add_comment_outlined,
                            color: palette.accentText),
                        onPressed: () =>
                            _startThreadFromGuide(chapter, question),
                      ),
                    ],
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
          case 'summary':
            _openSummary(chapter);
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
        PopupMenuItem<String>(
          value: 'summary',
          child: Text(l10n.translate('study_summary_title')),
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
