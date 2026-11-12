import 'package:bhromon/core/widgets/empty_state.dart';
import 'package:bhromon/core/widgets/skeleton.dart';
import '../widgets/group_back_button.dart';
import 'dart:async';
import '../widgets/study/study_modal.dart';

import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/localized_date.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../../core/utils/app_logger.dart';
import '../../data/study_activity_log.dart';
import '../../data/study_reading_position.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/study_material_models.dart';
import '../../domain/models/study_models.dart';
import '../../domain/models/study_streak_models.dart';
import '../../domain/models/study_syllabus_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/study_banking_master_catalog.dart';
import '../../domain/services/study_booklet_pdf_generator.dart';
import '../../domain/services/study_chapter_rules.dart';
import '../../domain/services/study_daily_streak_rules.dart';
import '../../domain/services/study_exam_simulator_rules.dart';
import '../../domain/services/study_solution_rules.dart';
import 'package:bhromon/core/media/media_access.dart';
import '../../data/study_offline_vault.dart';
import '../../domain/models/study_offline_vault_models.dart';
import '../widgets/study/branch_study_hall_sheet.dart';
import '../widgets/study/study_chapter_editor.dart';
import '../widgets/study/study_daily_streak_card.dart';
import '../widgets/study/study_offline_vault_card.dart';
import '../widgets/study/study_pace_sheet.dart';
import 'package:dio/dio.dart';
import '../widgets/study/study_thread_composer.dart';
import 'markdown_viewer_screen.dart';
import 'pdf_viewer_screen.dart';
import 'study_discussion_screen.dart';
import 'study_exam_simulator_screen.dart';
import 'study_flashcards_screen.dart';
import 'study_glossary_screen.dart';
import 'study_graph_atlas_screen.dart';
import 'study_materials_screen.dart';
import 'study_pack_share.dart';
import 'study_progress_screen.dart';
import 'study_quizzes_screen.dart';
import 'study_summary_screen.dart';

import '../widgets/study/study_rich_text.dart';

/// The learning tools a book offers, from the sheet on its chapters.
/// A chapter's past paper the exam simulator can run: its solution text, and how many
/// questions it holds. A paper with no text on this phone has no questions and no raw text.
class _ExamPaper {
  const _ExamPaper({
    required this.chapter,
    required this.raw,
    required this.questionCount,
  });

  final StudyChapter chapter;
  final String? raw;
  final int questionCount;
}

enum _LearningTool {
  quizzes,
  glossary,
  flashcards,
  examSimulator,
  branchHall,
  progress,
  studyPack,
  printableBooklet,
  branchPoster,
}

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
  StreamSubscription<List<TourMember>>? _membersSub;

  TourRole? _myRole;
  List<StudyChapter> _chapters = const [];
  Map<String, StudyReadMark> _marks = const {};
  List<StudyMaterial> _materials = const [];
  List<TourMember> _members = const [];
  bool _loaded = false;
  bool _failed = false;

  /// The chapter number the member is on, kept on this device.
  StudyDailyStreak _dailyStreak = StudyDailyStreak.empty;
  List<BranchStudyStanding> _standings = const [];
  int? _here;
  String? _selectedModuleCode;
  late final List<SyllabusModule> _syllabusModules =
      StudySyllabusCatalog.modulesFor(widget.book.title);

  /// The book's offline package as the index keeps it, or null when the book is not saved here.
  StudyOfflineSummary? _offlineSummary;
  bool _isDownloadingOffline = false;

  /// The readable solutions by chapter, and whether the book has any, worked out once when the
  /// materials arrive rather than for every card built.
  Map<String, List<StudyMaterial>> _readableByChapter = const {};
  bool _hasReadableSolution = false;

  /// Whether the route that shows this screen has finished opening. Until it has, the screen reads
  /// nothing from the device's stores, so a read cannot hold up the transition.
  bool _routeSettled = false;

  final _offlineVault = StudyOfflineVault.instance;

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
        if (mounted) {
          setState(() {
            _marks = marks;
          });
          _refreshStreak();
        }
      },
      onError: (Object _) {},
    );
    _materialsSub =
        _repository.watchStudyMaterials(widget.tourId, widget.book.id).listen(
      (materials) {
        if (!mounted) return;
        setState(() {
          _materials = materials;
          _readableByChapter = _readableSolutionsByChapter(materials);
          _hasReadableSolution =
              materials.any((m) => m.isPublished && isReadableSolution(m));
        });
      },
      onError: (Object _) {
        // Safe fallback if study materials stream errors.
      },
    );
    try {
      _membersSub = _repository.watchMembers(widget.tourId).listen(
        (members) {
          if (mounted) {
            setState(() => _members = members);
            _refreshStreak();
          }
        },
        onError: (Object _) {
          // Safe fallback if tour members stream errors.
        },
      );
    } catch (_) {
      // Safe fallback when running in widget tests or preview mode without Firebase.
    }
    _position
        .load(tourId: widget.tourId, bookId: widget.book.id)
        .then((number) {
      if (mounted) setState(() => _here = number);
    });
    _whenRouteSettles(() {
      _refreshStreak();
      _refreshOfflineSummary();
    });
  }

  /// Runs [action] once the route that shows this screen has finished opening, so a read of the
  /// device's stores does not run in the middle of the transition. A screen that no route animates
  /// runs it straight after its first frame.
  void _whenRouteSettles(VoidCallback action) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final animation = ModalRoute.of(context)?.animation;
      if (animation == null || animation.isCompleted) {
        _settle(action);
        return;
      }
      late final AnimationStatusListener listener;
      listener = (status) {
        if (status != AnimationStatus.completed) return;
        animation.removeStatusListener(listener);
        if (mounted) _settle(action);
      };
      animation.addStatusListener(listener);
    });
  }

  void _settle(VoidCallback action) {
    _routeSettled = true;
    action();
  }

  /// The readable solutions of each chapter, in the order the materials came.
  static Map<String, List<StudyMaterial>> _readableSolutionsByChapter(
      List<StudyMaterial> materials) {
    final byChapter = <String, List<StudyMaterial>>{};
    for (final m in materials) {
      final chapterId = m.chapterId;
      if (chapterId == null || !m.isPublished || !isReadableSolution(m)) {
        continue;
      }
      (byChapter[chapterId] ??= []).add(m);
    }
    return byChapter;
  }

  /// The book's saved package as the index keeps it. Reads the index only.
  Future<void> _refreshOfflineSummary() async {
    try {
      final summary =
          await _offlineVault.getSummary(widget.tourId, widget.book.id);
      if (mounted) setState(() => _offlineSummary = summary);
    } catch (_) {
      // Safe fallback when local offline vault cannot be read.
    }
  }

  Future<void> _downloadBookForOffline() async {
    final l10n = context.l10n;
    setState(() => _isDownloadingOffline = true);

    try {
      final readable = _materials
          .where((m) => m.isPublished && isReadableSolution(m))
          .toList();
      if (readable.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.translate('study_offline_empty_solutions')),
            ),
          );
          setState(() => _isDownloadingOffline = false);
        }
        return;
      }

      final contents = <String, String>{};
      int totalBytes = 0;

      for (final m in readable) {
        String? text = m.body;
        if ((text == null || text.trim().isEmpty) &&
            m.url != null &&
            m.url!.isNotEmpty) {
          try {
            final targetUrl = signedMediaUrl(m.url!);
            final response = await Dio().get<String>(
              targetUrl,
              options: Options(responseType: ResponseType.plain),
            );
            text = response.data;
          } catch (_) {
            // Safe fallback when fetching a remote markdown solution file fails.
          }
        }
        if (text != null && text.isNotEmpty) {
          contents[m.id] = text;
          totalBytes += m.sizeBytes ?? text.length;
        }
      }

      final pkg = StudyOfflinePackage(
        tourId: widget.tourId,
        bookId: widget.book.id,
        bookTitle: widget.book.title,
        cachedAt: DateTime.now(),
        totalSizeBytes: totalBytes,
        chapters: _chapters,
        materials: readable,
        contents: contents,
      );

      await _offlineVault.savePackage(pkg);
      await StudyActivityLog().recordAction(DateTime.now());
      _refreshStreak();

      if (mounted) {
        setState(() {
          _offlineSummary = pkg.summary;
          _isDownloadingOffline = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.translate('study_offline_success', args: {
                'count': '${pkg.materialCount}',
                'size': pkg.formattedSize,
              }),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDownloadingOffline = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save offline vault: $e')),
        );
      }
    }
  }

  Future<void> _removeOfflinePackage() async {
    final l10n = context.l10n;
    try {
      await _offlineVault.removePackage(widget.tourId, widget.book.id);
      if (mounted) {
        setState(() => _offlineSummary = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.translate('study_offline_removed'))),
        );
      }
    } catch (_) {
      // Safe fallback when removing offline vault data fails.
    }
  }

  void _refreshStreak() {
    if (!_routeSettled) return;
    StudyActivityLog().activeDays().then((days) {
      if (!mounted) return;
      final streak = StudyDailyStreakRules.computeDailyStreak(
        days,
        today: DateTime.now(),
      );
      String myEmail = '';
      try {
        myEmail = _repository.requireEmail();
      } catch (error) {
        // Safe to fall back when running in unit tests or preview mode.
        myEmail = '';
      }
      final standings = StudyDailyStreakRules.fromTourMembers(
        members: _members,
        myEmail: myEmail,
        myName: myEmail.isNotEmpty ? myEmail.split('@').first : 'You',
        myStreak: streak.currentStreak > 0 ? streak.currentStreak : 1,
        myChapters: _marks.length,
        groupName: widget.book.title,
      );
      setState(() {
        _dailyStreak = streak;
        _standings = standings;
      });
    }).catchError((Object _) {
      // Safe fallback if active days log fails to load.
    });
  }

  @override
  void dispose() {
    _chapterSub?.cancel();
    _markSub?.cancel();
    _materialsSub?.cancel();
    _membersSub?.cancel();
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
        backgroundColor: AppColors.amber,
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
    if (!wasRead) {
      unawaited(countStudyActionToday());
    }
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
              leading: Icon(Icons.timer_outlined, color: palette.accentText),
              title: Text(l10n.translate('study_exam_simulator_title'),
                  style: TextStyle(color: palette.text)),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_LearningTool.examSimulator),
            ),
            ListTile(
              leading: Icon(Icons.apartment_rounded, color: palette.accentText),
              title: Text(l10n.translate('study_branch_hall'),
                  style: TextStyle(color: palette.text)),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_LearningTool.branchHall),
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
            ListTile(
              leading: Icon(Icons.print_rounded, color: palette.accentText),
              title: Text(l10n.translate('study_printable_booklet_title'),
                  style: TextStyle(color: palette.text)),
              subtitle: Text(l10n.translate('study_printable_booklet_sub'),
                  style: TextStyle(color: palette.text70, fontSize: 12)),
              onTap: () => Navigator.of(sheetContext)
                  .pop(_LearningTool.printableBooklet),
            ),
            ListTile(
              leading: Icon(Icons.campaign_rounded, color: palette.accentText),
              title: Text(l10n.translate('study_branch_poster_title'),
                  style: TextStyle(color: palette.text)),
              subtitle: Text(l10n.translate('study_branch_poster_sub'),
                  style: TextStyle(color: palette.text70, fontSize: 12)),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_LearningTool.branchPoster),
            ),
          ],
        ),
      ),
    );
    if (tool == null || !mounted) return;
    if (tool == _LearningTool.branchHall) {
      await BranchStudyHallSheet.show(context, standings: _standings);
      return;
    }
    if (tool == _LearningTool.studyPack) {
      await shareStudyPack(
        context: context,
        repository: _repository,
        tourId: widget.tourId,
        book: widget.book,
      );
      return;
    }
    if (tool == _LearningTool.printableBooklet) {
      await _generateAndOpenBooklet(isBengali: true);
      return;
    }
    if (tool == _LearningTool.branchPoster) {
      await _generateAndOpenBranchPoster();
      return;
    }
    if (tool == _LearningTool.examSimulator) {
      await _openExamPaperPicker();
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
      // Opened from the paper picker above, never from here.
      _LearningTool.examSimulator => const SizedBox.shrink(),
      _LearningTool.progress => StudyProgressScreen(
          tourId: widget.tourId,
          book: widget.book,
          repository: _repository,
        ),
      // The study pack, branch hall, booklet, and poster open modal sheets, not a page.
      _LearningTool.branchHall => const SizedBox.shrink(),
      _LearningTool.studyPack => const SizedBox.shrink(),
      _LearningTool.printableBooklet => const SizedBox.shrink(),
      _LearningTool.branchPoster => const SizedBox.shrink(),
    };
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  /// Shows the progress card of a booklet or poster being made. [detail] is the line under
  /// the title, and may be empty. Closing the card in any way calls [onCancel].
  void _showPdfProgress({
    required String title,
    required ValueNotifier<String> detail,
    required VoidCallback onCancel,
  }) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => PopScope(
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) onCancel();
        },
        // The card needs a Material above its text, or the text is drawn with the
        // yellow underlines of text that has no theme.
        child: Center(
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: context.forest.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.forest.divider12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: AppColors.mintGreen),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.forest.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  ValueListenableBuilder<String>(
                    valueListenable: detail,
                    builder: (_, text, __) => text.isEmpty
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              text,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: context.forest.text70,
                                fontSize: 13,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: Text(dialogCtx.l10n.translate('study_cancel')),
                    style: TextButton.styleFrom(
                      foregroundColor: context.forest.text54,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Makes the printable booklet of the whole book, or of [chapter] alone when one is given. A
  /// chapter's booklet fetches only that chapter's solutions.
  Future<void> _generateAndOpenBooklet({
    bool isBengali = true,
    StudyChapter? chapter,
  }) async {
    final l10n = context.l10n;
    if (_chapters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('study_chapters_empty_member'))),
      );
      return;
    }

    var isCancelled = false;
    final detail =
        ValueNotifier<String>(l10n.translate('study_booklet_collecting'));
    _showPdfProgress(
      title: l10n.translate('study_generating_booklet'),
      detail: detail,
      onCancel: () => isCancelled = true,
    );

    try {
      final solutionTexts = <String, String>{};
      if (_offlineSummary != null) {
        // The booklet is made from the saved solutions, so they are read here, once, for it.
        final stored =
            await _offlineVault.getPackage(widget.tourId, widget.book.id);
        if (stored != null) solutionTexts.addAll(stored.contents);
      }

      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
          sendTimeout: const Duration(seconds: 4),
        ),
      );

      // The solution files are fetched together, so the wait is one file's, not their sum.
      final scopedMaterials = chapter == null
          ? _materials
          : _materials.where((m) => m.chapterId == chapter.id).toList();
      final scopedChapters = chapter == null ? _chapters : [chapter];
      await Future.wait([
        for (final m in scopedMaterials)
          if (!solutionTexts.containsKey(m.id))
            () async {
              final body = m.body;
              final url = m.url;
              if (body != null && body.isNotEmpty) {
                solutionTexts[m.id] = body;
              } else if (url != null && url.isNotEmpty) {
                try {
                  final response = await dio.get<String>(
                    signedMediaUrl(url),
                    options: Options(responseType: ResponseType.plain),
                  );
                  final data = response.data;
                  if (data != null) solutionTexts[m.id] = data;
                } catch (error, stackTrace) {
                  // The booklet is still made, without this solution.
                  logSkipped(error, stackTrace);
                }
              }
            }(),
      ]);

      if (isCancelled) return;

      String tourName = 'Study Circle';
      String? inviteCode;
      try {
        final group = await _repository
            .watchGroup(widget.tourId)
            .first
            .timeout(const Duration(seconds: 2));
        if (group != null) {
          tourName = group.name;
          inviteCode = group.inviteCode;
        }
      } catch (error, stackTrace) {
        // The booklet is still made, with the standard group name.
        logSkipped(error, stackTrace);
      }

      if (isCancelled) return;

      final combinedContext = '$tourName ${widget.book.title}'.toLowerCase();
      final isBanking =
          RegExp(r'\b(jaibb|aibb|ibb|banking|banker)\b', caseSensitive: false)
                  .hasMatch(combinedContext) ||
              combinedContext.contains('ব্যাংকিং') ||
              combinedContext.contains('ব্যাংকার্স');

      String? subjectCode;
      if (widget.book.author.trim().isNotEmpty) {
        subjectCode = widget.book.author.trim();
      } else {
        final codeMatch =
            RegExp(r'\(([A-Z\d\-\s]{2,10})\)').firstMatch(widget.book.title);
        if (codeMatch != null) {
          subjectCode = codeMatch.group(1);
        } else if (isBanking) {
          subjectCode =
              StudyBankingMasterCatalog.resolveCodeFromText(widget.book.title);
        }
      }

      final content = StudyBookletPdfGenerator.extractContent(
        subjectTitle: widget.book.title,
        subjectCode: subjectCode,
        tourName: tourName,
        inviteCode: inviteCode,
        chapters: scopedChapters,
        materials: scopedMaterials,
        solutionTexts: solutionTexts,
        isBengali: isBengali,
        scopedToChapter: chapter != null,
      );

      // A chapter with no solution text to print is said so, rather than making an empty booklet.
      if (chapter != null && content.chapters.single.questions.isEmpty) {
        if (!isCancelled && mounted) {
          Navigator.of(context, rootNavigator: true).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.translate('study_chapter_booklet_none')),
            ),
          );
        }
        return;
      }

      const generator = StudyBookletPdfGenerator();
      final pdfBytes = await generator.generateBookletPdf(
        content,
        isBengali: isBengali,
        isCancelled: () => isCancelled,
        onProgress: (done, total) {
          detail.value = l10n.translate('study_booklet_progress', args: {
            'done': l10n.number(done < total ? done + 1 : total),
            'total': l10n.number(total),
          });
        },
      );

      if (!isCancelled && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        await PdfViewerScreen.open(
          context,
          title: chapter == null
              ? '${widget.book.title} - ${isBengali ? 'প্রশ্নোত্তর বুকলেট' : 'Exam Booklet'}'
              : '${widget.book.title} - ${chapter.title} - ${isBengali ? 'প্রশ্নোত্তর বুকলেট' : 'Exam Booklet'}',
          bytes: pdfBytes,
          tourId: widget.tourId,
        );
      }
    } on StudyBookletCancelled {
      // The member closed the card: nothing to show.
      return;
    } catch (error, stackTrace) {
      logWarning('The study booklet could not be made', error, stackTrace);
      if (!isCancelled && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.translate('study_booklet_failed'))),
        );
      }
    }
  }

  Future<void> _generateAndOpenBranchPoster() async {
    final l10n = context.l10n;
    var isCancelled = false;
    _showPdfProgress(
      title: l10n.translate('study_generating_poster'),
      detail: ValueNotifier<String>(''),
      onCancel: () => isCancelled = true,
    );

    try {
      String tourName = 'Study Circle';
      String? tourDescription;
      String? inviteCode;
      try {
        final group = await _repository
            .watchGroup(widget.tourId)
            .first
            .timeout(const Duration(seconds: 2));
        if (group != null) {
          tourName = group.name;
          tourDescription = group.description;
          inviteCode = group.inviteCode;
        }
      } catch (error, stackTrace) {
        // The poster is still made, with the standard group name.
        logSkipped(error, stackTrace);
      }

      if (isCancelled) return;

      final combinedContext = '$tourName ${widget.book.title}'.toLowerCase();
      final isBanking =
          RegExp(r'\b(jaibb|aibb|ibb|banking|banker)\b', caseSensitive: false)
                  .hasMatch(combinedContext) ||
              combinedContext.contains('ব্যাংকিং') ||
              combinedContext.contains('ব্যাংকার্স');

      String? subjectCode;
      if (widget.book.author.trim().isNotEmpty) {
        subjectCode = widget.book.author.trim();
      } else {
        final codeMatch =
            RegExp(r'\(([A-Z\d\-\s]{2,10})\)').firstMatch(widget.book.title);
        if (codeMatch != null) {
          subjectCode = codeMatch.group(1);
        } else if (isBanking) {
          subjectCode =
              StudyBankingMasterCatalog.resolveCodeFromText(widget.book.title);
        }
      }

      final content = StudyBookletContent(
        subjectTitle: widget.book.title,
        subjectCode: subjectCode,
        tourName: tourName,
        tourDescription: tourDescription,
        inviteCode: inviteCode,
        chapters: const [],
      );

      // One frame, so the card is drawn before the single page is laid out.
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (isCancelled) return;

      const generator = StudyBookletPdfGenerator();
      final pdfBytes = await generator.generateBranchNoticePoster(content);

      if (!isCancelled && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        await PdfViewerScreen.open(
          context,
          title:
              isBanking ? 'Branch Notice Board Poster' : 'Notice Board Poster',
          bytes: pdfBytes,
          tourId: widget.tourId,
        );
      }
    } catch (error, stackTrace) {
      logWarning('The branch poster could not be made', error, stackTrace);
      if (!isCancelled && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.translate('study_poster_failed'))),
        );
      }
    }
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
            if (_isPoeBook)
              IconButton(
                tooltip: 'Dynamic SVG Graph Atlas (ডাইনামিক গ্রাফ)',
                icon: const Icon(Icons.auto_graph_rounded),
                onPressed: _openGraphAtlas,
              ),
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
    if (!_loaded) return const ListRowsSkeleton();
    if (_chapters.isEmpty) {
      return EmptyState(
        icon: Icons.menu_book_outlined,
        message: l10n.translate(
            _isAdmin ? 'study_chapters_empty' : 'study_chapters_empty_member'),
      );
    }
    final next = nextUnreadChapter(_chapters, _marks.keys.toSet());
    final today = DateTime.now();
    final leadingWidgets = <Widget>[
      _summary(next),
      if (_isPoeBook) _graphAtlasCard(),
      if (_hasBookLevelMaterials) _masterMaterialsCard(),
      StudyDailyStreakCard(
        streak: _dailyStreak,
        standings: _standings,
        onOpenBranchHall: () => BranchStudyHallSheet.show(
          context,
          standings: _standings,
        ),
      ),
      _offlineVaultSection(),
      _syllabusBlueprintCard(),
    ];

    // Built as the list scrolls, so a huge book does not build every chapter card when it opens.
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: leadingWidgets.length + _chapters.length,
      itemBuilder: (context, index) {
        if (index < leadingWidgets.length) {
          return leadingWidgets[index];
        }
        return _chapterCard(_chapters[index - leadingWidgets.length], today);
      },
    );
  }

  bool get _hasBookLevelMaterials {
    return _materials.any((m) => m.chapterId == null && m.isPublished);
  }

  Widget _masterMaterialsCard() {
    final palette = context.forest;
    final count =
        _materials.where((m) => m.chapterId == null && m.isPublished).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            palette.accentText.withValues(alpha: 0.10),
            palette.card,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: palette.accentText.withValues(alpha: 0.30),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _openMaterials,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: palette.accentText.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.auto_stories_rounded,
                    color: palette.accentText,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'মাস্টার এনসাইক্লোপিডিয়া ও শব্দকোষ',
                              style: TextStyle(
                                color: palette.text,
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: palette.accentText,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '$countটি গাইড',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'সকল পরীক্ষার বিষয়ভিত্তিক মাস্টার সংকলন, সূত্রকোষ ও পূর্ণাঙ্গ পরিভাষা',
                        style: TextStyle(
                          color: palette.text70,
                          fontSize: 11.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: palette.accentText,
                  size: 14,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _isPoeBook {
    final title = widget.book.title.toLowerCase();
    return widget.book.id == 'ah9qgOp1e7uA2qcV6a7B' ||
        title.contains('economics') ||
        title.contains('poe') ||
        widget.book.title.contains('অর্থনীতি');
  }

  void _openGraphAtlas() {
    StudyGraphAtlasScreen.open(context, tourId: widget.tourId);
  }

  Widget _graphAtlasCard() {
    final palette = context.forest;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            palette.accentText.withValues(alpha: 0.12),
            palette.card,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: palette.accentText.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _openGraphAtlas,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: palette.accentText.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.auto_graph_rounded,
                    color: palette.accentText,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Dynamic SVG Graph Atlas',
                              style: TextStyle(
                                color: palette.text,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: palette.accentText,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '95 Graphs',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'সকল ৮টি পরীক্ষার ডাইনামিক অর্থনীতি ভেক্টর গ্রাফ (PPC, IC, AC/MC)',
                        style: TextStyle(
                          color: palette.text70,
                          fontSize: 11.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: palette.accentText,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _offlineVaultSection() {
    if (!_hasReadableSolution && _offlineSummary == null) {
      return const SizedBox.shrink();
    }
    return StudyOfflineVaultCard(
      summary: _offlineSummary,
      isDownloading: _isDownloadingOffline,
      onDownload: _downloadBookForOffline,
      onRemove: _removeOfflinePackage,
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
                      fontSize: 14,
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
                        fontSize: 12,
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
                          fontSize: 12,
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
                            fontSize: 12,
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
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (activeModule.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        activeModule.description,
                        style: TextStyle(
                          color: palette.text70,
                          fontSize: 12,
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
  /// The exam simulator runs one chapter's past paper. The picker lists the chapters whose
  /// solution text is on this phone. A chapter whose solution is only a file, not yet saved
  /// here, shows as not available, and nothing is invented to fill the paper.
  Future<void> _openExamPaperPicker() async {
    final l10n = context.l10n;
    final palette = context.forest;
    final papers = <_ExamPaper>[];
    // The saved solutions are read at most once for the picker, and only when a chapter needs them.
    StudyOfflinePackage? stored;
    var storedRead = false;
    for (final chapter in _chapters) {
      final materials = _materials
          .where((m) =>
              m.chapterId == chapter.id &&
              m.isPublished &&
              isReadableSolution(m))
          .toList();
      if (materials.isEmpty) continue;
      StudyMaterial? english;
      StudyMaterial? bangla;
      for (final m in materials) {
        if (isBanglaSolution(m)) {
          bangla ??= m;
        } else {
          english ??= m;
        }
      }
      final primary = english ?? bangla!;
      final other = identical(primary, english) ? bangla : english;
      final source = solutionSource(primary, other);
      if (source.rawContent == null && _offlineSummary != null && !storedRead) {
        stored = await _offlineVault.getPackage(widget.tourId, widget.book.id);
        storedRead = true;
      }
      final raw = source.rawContent ?? stored?.contentFor(primary.id);
      final questions = raw == null || raw.trim().isEmpty
          ? 0
          : StudyExamSimulatorExtractor.extractQuestions(
              subjectTitle: widget.book.title,
              markdownContent: raw,
            ).length;
      papers.add(_ExamPaper(
        chapter: chapter,
        raw: questions > 0 ? raw : null,
        questionCount: questions,
      ));
    }
    if (!mounted) return;

    final chosen = await showModalBottomSheet<_ExamPaper>(
      context: context,
      backgroundColor: palette.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                l10n.translate('study_exam_pick_paper'),
                style: TextStyle(
                  color: palette.text,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Divider(height: 1, color: palette.divider10),
            Flexible(
              child: papers.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        l10n.translate('study_exam_no_paper'),
                        style: TextStyle(color: palette.text70, height: 1.5),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: papers.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: palette.divider10),
                      itemBuilder: (_, idx) {
                        final paper = papers[idx];
                        final ready = paper.questionCount > 0;
                        return ListTile(
                          enabled: ready,
                          title: Text(
                            paper.chapter.title.isNotEmpty
                                ? paper.chapter.title
                                : widget.book.title,
                            style: TextStyle(color: palette.text),
                          ),
                          subtitle: Text(
                            ready
                                ? l10n.translate('study_exam_questions_count',
                                    args: {
                                        'count':
                                            l10n.number(paper.questionCount)
                                      })
                                : l10n
                                    .translate('study_exam_paper_unavailable'),
                            style: TextStyle(
                              color: ready ? palette.text70 : palette.text54,
                              fontSize: 12,
                            ),
                          ),
                          trailing: Icon(Icons.chevron_right_rounded,
                              color: palette.text54),
                          onTap: ready
                              ? () => Navigator.of(sheetCtx).pop(paper)
                              : null,
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    await StudyExamSimulatorScreen.open(
      context,
      tourId: widget.tourId,
      bookId: widget.book.id,
      chapterId: chosen.chapter.id,
      paperTitle: chosen.chapter.title.isNotEmpty
          ? chosen.chapter.title
          : widget.book.title,
      rawContent: chosen.raw,
    );
  }

  /// A note opens from its text, and a Markdown file from its address, which the reader fetches. The other
  /// language pairs only when its text is a note.
  Future<void> _openSolution(
    StudyMaterial material,
    StudyMaterial? other, {
    StudyChapter? chapter,
  }) async {
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
    // A saved solution is read only when the material carries no text of its own.
    final needsStored = source.rawContent == null ||
        (other != null && (source.paired?.body ?? '').isEmpty);
    final stored = needsStored && _offlineSummary != null
        ? await _offlineVault.getPackage(widget.tourId, widget.book.id)
        : null;
    if (!mounted) return;
    final cachedPrimary = stored?.contentFor(material.id);
    final cachedAlternate = other != null ? stored?.contentFor(other.id) : null;
    final primaryContent = source.rawContent ?? cachedPrimary;
    final alternateContent = source.paired?.body ?? cachedAlternate;

    MarkdownViewerScreen.open(
      context,
      title: material.title,
      rawContent: primaryContent,
      fileUrl: primaryContent != null ? null : source.fileUrl,
      tourId: widget.tourId,
      alternateRawContent: alternateContent,
      alternateTitle: source.paired?.title ?? other?.title,
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
    final chapterMaterials =
        _readableByChapter[chapter.id] ?? const <StudyMaterial>[];

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
              child: Row(
                children: [
                  if (englishNote != null)
                    Expanded(
                      child: _solutionButton(
                        language:
                            l10n.translate('study_solution_english_short'),
                        fullLabel: l10n.translate('study_solution_english'),
                        material: englishNote,
                        onTap: () => _openSolution(englishNote!, banglaNote,
                            chapter: chapter),
                      ),
                    ),
                  if (englishNote != null && banglaNote != null)
                    const SizedBox(width: 8),
                  if (banglaNote != null)
                    Expanded(
                      child: _solutionButton(
                        language: l10n.translate('study_solution_bangla_short'),
                        fullLabel: l10n.translate('study_solution_bangla'),
                        material: banglaNote,
                        onTap: () => _openSolution(banglaNote!, englishNote,
                            chapter: chapter),
                      ),
                    ),
                ],
              ),
            ),
          if (chapter.guide.isNotEmpty)
            ExpansionTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              shape: const Border(),
              collapsedShape: const Border(),
              iconColor: palette.accentText,
              collapsedIconColor: palette.text54,
              title: Text(
                l10n.translate('study_chapter_guide_count', args: {
                  'count': l10n.number(chapter.guide.length),
                }),
                style: TextStyle(
                  color: palette.accentText,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
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

  /// One solution of a chapter: the language, and the file's size beside it
  /// when it is known. Two of them share the card's width.
  Widget _solutionButton({
    required String language,
    required String fullLabel,
    required StudyMaterial material,
    required VoidCallback onTap,
  }) {
    final palette = context.forest;
    final size = material.sizeBytes;
    final hasSize = size != null && size > 0;
    return Semantics(
      button: true,
      label: hasSize ? '$fullLabel (${_formatFileSize(size)})' : fullLabel,
      excludeSemantics: true,
      child: Material(
        color: palette.accentText.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.description_outlined,
                      size: 18, color: palette.accentText),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      language,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.accentText,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (hasSize) ...[
                    const SizedBox(width: 6),
                    Text(
                      _formatFileSize(size),
                      style: TextStyle(color: palette.text54, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
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
          case 'booklet':
            _generateAndOpenBooklet(chapter: chapter);
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
        PopupMenuItem<String>(
          value: 'booklet',
          child: Text(l10n.translate('study_chapter_booklet')),
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
