import '../widgets/group_back_button.dart';
import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../../core/utils/app_logger.dart';
import '../../data/study_reading_position.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/study_models.dart';
import '../../domain/models/study_subject_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/study_subject_rules.dart';
import '../widgets/study/study_labels.dart';
import '../widgets/study/study_module_sheet.dart';
import '../widgets/study/study_today_card.dart';
import 'study_assignments_screen.dart';
import 'study_book_chapters_screen.dart';
import 'study_challenge_screen.dart';
import 'study_discussion_screen.dart';
import 'study_findings_screen.dart';
import 'study_flashcards_screen.dart';
import 'study_glossary_screen.dart';
import 'study_problems_screen.dart';
import 'study_module_posts_screen.dart';
import 'study_quizzes_screen.dart';
import 'study_reading_screen.dart';

import '../widgets/study/study_rich_text.dart';

/// One subject: its modules. Members see the modules an admin has turned on. An admin sees
/// every module, and customises them.
class StudySubjectScreen extends StatefulWidget {
  const StudySubjectScreen({
    super.key,
    required this.tourId,
    required this.subject,
    this.repository,
  });

  final String tourId;
  final StudySubject subject;

  /// The data source. Null in the app, where the screen makes its own; tests pass one.
  final TourGroupRepository? repository;

  @override
  State<StudySubjectScreen> createState() => _StudySubjectScreenState();
}

class _StudySubjectScreenState extends State<StudySubjectScreen> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();
  late final Stream<Map<StudyModuleKey, StudyModuleSettings>> _modules =
      _repository.watchStudyModules(widget.tourId, widget.subject.id);
  late final Stream<List<StudyBook>> _books =
      _repository.watchStudyBooks(widget.tourId);
  TourRole? _myRole;

  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;

  @override
  void initState() {
    super.initState();
    _repository.myRole(widget.tourId).then((role) {
      if (mounted) setState(() => _myRole = role);
    }, onError: (Object _) {});
  }

  /// The subject's book, when the group still lists it. Null when the subject names none, or
  /// when the book has been removed or declined since.
  StudyBook? _bookIn(List<StudyBook> books) {
    final id = widget.subject.bookId;
    if (id == null) return null;
    for (final book in books) {
      if (book.id == id && book.isListed) return book;
    }
    return null;
  }

  /// An admin turns modules on and off, renames them, and chooses who may post in each.
  Future<void> _customise() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final current = await _repository
        .watchStudyModules(widget.tourId, widget.subject.id)
        .first;
    if (!mounted) return;
    final saved = await showStudyModuleSheet(context, current: current);
    if (saved == null || !mounted) return;
    final changes = [
      for (final settings in saved)
        if (_changed(current[settings.key], settings)) settings,
    ];
    // A book module is on only in a subject that names a book, as the rules check.
    if (widget.subject.bookId == null &&
        changes
            .any((settings) => settings.key.isBookModule && settings.enabled)) {
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.translate('study_subject_book_needed'))));
      return;
    }
    try {
      for (final settings in changes) {
        await _repository.setStudyModule(
            widget.tourId, widget.subject.id, settings);
      }
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.translate('study_module_saved'))));
    } catch (error, stackTrace) {
      logWarning('A study module change failed', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  /// Whether a module's settings differ from the saved ones, or the module is new.
  bool _changed(StudyModuleSettings? before, StudyModuleSettings after) =>
      before == null ||
      before.enabled != after.enabled ||
      before.name != after.name ||
      before.postPolicy != after.postPolicy;

  /// Opens a module's page. A book module opens the subject's [book], and does nothing without
  /// one. The other modules open their own screens.
  void _open(StudyModuleSettings settings, [StudyBook? book]) {
    if (settings.key == StudyModuleKey.papers && book != null) {
      _push(StudyBookChaptersScreen(
        tourId: widget.tourId,
        book: book,
        repository: _repository,
      ));
      return;
    }
    if (settings.key.isBookModule) {
      if (book == null) return;
      _push(_bookPage(settings.key, book));
      return;
    }
    _push(switch (settings.key) {
      StudyModuleKey.findings => StudyFindingsScreen(
          tourId: widget.tourId,
          subject: widget.subject,
          settings: settings,
          repository: _repository,
        ),
      StudyModuleKey.problems => StudyProblemsScreen(
          tourId: widget.tourId,
          subject: widget.subject,
          settings: settings,
          repository: _repository,
        ),
      StudyModuleKey.assignments => StudyAssignmentsScreen(
          tourId: widget.tourId,
          subject: widget.subject,
          settings: settings,
          repository: _repository,
        ),
      StudyModuleKey.challenges => StudyChallengeScreen(
          tourId: widget.tourId,
          subject: widget.subject,
          settings: settings,
          repository: _repository,
        ),
      _ => StudyModulePostsScreen(
          tourId: widget.tourId,
          subject: widget.subject,
          moduleKey: settings.key,
          settings: settings,
          repository: _repository,
        ),
    });
  }

  void _push(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => page,
    ));
  }

  /// The page of a book module: the book's own screen, reached from this subject.
  Widget _bookPage(StudyModuleKey key, StudyBook book) => switch (key) {
        StudyModuleKey.discussion => StudyDiscussionScreen(
            tourId: widget.tourId,
            book: book,
            repository: _repository,
            position: StudyReadingPosition(),
          ),
        StudyModuleKey.glossary => StudyGlossaryScreen(
            tourId: widget.tourId,
            book: book,
            repository: _repository,
          ),
        StudyModuleKey.flashcards => StudyFlashcardsScreen(
            book: book,
            tourId: widget.tourId,
          ),
        StudyModuleKey.quizzes => StudyQuizzesScreen(
            tourId: widget.tourId,
            book: book,
            repository: _repository,
          ),
        _ => StudyReadingScreen(
            tourId: widget.tourId,
            book: book,
            repository: _repository,
          ),
      };

  /// The exam, when it is still to come: how many days away, or today.
  String? _examLine() {
    final exam = widget.subject.examDate;
    if (exam == null) return null;
    final l10n = context.l10n;
    final days = daysUntilExam(exam, DateTime.now());
    if (days < 0) return null;
    if (days == 0) return l10n.translate('study_subject_exam_today');
    return l10n
        .translate('study_subject_exam_in', args: {'days': l10n.number(days)});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final subject = widget.subject;
    return GroupPopScope(
      tourId: widget.tourId,
      child: Scaffold(
        backgroundColor: palette.background,
        appBar: AppBar(
          leading: GroupBackButton(tourId: widget.tourId),
          title: Text(subject.title,
              style: TextStyle(
                  color: palette.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
          backgroundColor: palette.card,
          foregroundColor: palette.text,
          iconTheme: IconThemeData(color: palette.text),
          elevation: 0,
          actions: [
            if (_isAdmin)
              IconButton(
                tooltip: l10n.translate('study_subject_customise'),
                icon: const Icon(Icons.tune_rounded),
                onPressed: _customise,
              ),
          ],
        ),
        body: StreamBuilder<Map<StudyModuleKey, StudyModuleSettings>>(
          stream: _modules,
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
            final settings = snap.data!;
            return StreamBuilder<List<StudyBook>>(
              stream: _books,
              builder: (context, bookSnap) {
                final booksKnown = bookSnap.hasData;
                final book = booksKnown ? _bookIn(bookSnap.data!) : null;
                // A member does not see a book module the subject has no book for.
                final keys = [
                  for (final key in visibleStudyModules(
                      settings: settings, isAdmin: _isAdmin))
                    if (_isAdmin || !key.isBookModule || book != null) key,
                ];
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    _overview(),
                    StudyTodayCard(
                      tourId: widget.tourId,
                      subject: widget.subject,
                      repository: _repository,
                      findingsModule:
                          _liveModule(settings, StudyModuleKey.findings),
                      challengeModule:
                          _liveModule(settings, StudyModuleKey.challenges),
                      problemsModule:
                          _liveModule(settings, StudyModuleKey.problems),
                      assignmentsModule:
                          _liveModule(settings, StudyModuleKey.assignments),
                      isAdmin: _isAdmin,
                      onOpenModule: _open,
                    ),
                    if (keys.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          l10n.translate(_isAdmin
                              ? 'study_subject_no_modules_admin'
                              : 'study_subject_no_modules'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: palette.text70),
                        ),
                      ),
                    for (final key in keys)
                      _moduleTile(
                        key,
                        settings[key],
                        book: book,
                        booksKnown: booksKnown,
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// The subject's code, what it covers, and the exam, when there is one.
  Widget _overview() {
    final palette = context.forest;
    final subject = widget.subject;
    final exam = _examLine();
    final lines = <String>[
      if (subject.code.isNotEmpty) subject.code,
      if (subject.description.isNotEmpty) subject.description,
      if (exam != null) exam,
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
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
                child:
                    StudyRichText(line, style: TextStyle(color: palette.text)),
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(StudyModuleKey key) => switch (key) {
        StudyModuleKey.tips => Icons.lightbulb_rounded,
        StudyModuleKey.suggestions => Icons.thumb_up_rounded,
        StudyModuleKey.findings => Icons.fact_check_rounded,
        StudyModuleKey.problems => Icons.assignment_rounded,
        StudyModuleKey.challenges => Icons.flag_rounded,
        StudyModuleKey.papers => Icons.description_rounded,
        StudyModuleKey.assignments => Icons.assignment_turned_in_rounded,
        StudyModuleKey.discussion => Icons.forum_rounded,
        StudyModuleKey.glossary => Icons.menu_book_rounded,
        StudyModuleKey.flashcards => Icons.style_rounded,
        StudyModuleKey.quizzes => Icons.quiz_rounded,
        StudyModuleKey.plan => Icons.event_note_rounded,
      };

  /// A module's settings when an admin has turned it on, or null when it is off or not set up.
  StudyModuleSettings? _liveModule(
    Map<StudyModuleKey, StudyModuleSettings> settings,
    StudyModuleKey key,
  ) {
    final module = settings[key];
    return module != null && module.enabled ? module : null;
  }

  /// One module. A live module that is on opens its posts, and a book module opens the subject's
  /// book. An admin also sees the modules that are off.
  Widget _moduleTile(
    StudyModuleKey key,
    StudyModuleSettings? settings, {
    required StudyBook? book,
    required bool booksKnown,
  }) {
    final l10n = context.l10n;
    final palette = context.forest;
    final on = settings?.enabled ?? false;
    final openable =
        settings != null && on && (!key.isBookModule || book != null);
    final name = settings?.name ?? l10n.translate(studyModuleLabelKey(key));
    String? note;
    if (key.isBookModule && on) {
      // The book the module opens, or what is missing for it to open.
      if (book != null) {
        note = book.title;
      } else if (booksKnown) {
        note = l10n.translate('study_subject_book_needed');
      }
    } else if (!on && _isAdmin) {
      note = l10n.translate('study_module_off');
    }
    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: openable ? () => _open(settings, book) : null,
        leading: Icon(_iconFor(key), color: palette.accentText),
        title: Text(name,
            style: TextStyle(color: palette.text, fontWeight: FontWeight.w600)),
        subtitle: note == null
            ? null
            : Text(note, style: TextStyle(color: palette.text54)),
        trailing: openable
            ? Icon(Icons.chevron_right_rounded, color: palette.text54)
            : null,
      ),
    );
  }
}
