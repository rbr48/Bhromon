import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/localization/localized_date.dart';
import '../../../../../core/theme/forest_palette.dart';
import '../../../../../core/utils/app_logger.dart';
import '../../../data/study_activity_log.dart';
import '../../../data/study_flashcard_store.dart';
import '../../../data/tour_group_repository.dart';
import '../../../domain/models/study_challenge_models.dart';
import '../../../domain/models/study_problem_models.dart';
import '../../../domain/models/study_subject_models.dart';
import '../../../domain/models/study_today_models.dart';
import '../../../domain/services/study_challenge_rules.dart';
import '../../../domain/services/study_flashcard_rules.dart';
import '../../../domain/services/study_subject_rules.dart';
import '../../../domain/services/study_today_rules.dart';

/// One line of a Today card: an icon, its words, and what a tap opens, when there is one.
class _TodayLine {
  const _TodayLine({required this.icon, required this.text, this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback? onTap;
}

/// The Today card of a subject: what needs the member today. A line appears only when there is something to say,
/// and a line that has a tap opens the place it is about.
class StudyTodayCard extends StatefulWidget {
  const StudyTodayCard({
    super.key,
    required this.tourId,
    required this.subject,
    required this.onOpenModule,
    this.findingsModule,
    this.challengeModule,
    this.problemsModule,
    this.assignmentsModule,
    this.isAdmin = false,
    this.repository,
    this.cardsDue,
    this.cardsReviewed,
    this.today,
  });

  final String tourId;
  final StudySubject subject;

  /// The findings module, when it is on. Its line is shown only then.
  final StudyModuleSettings? findingsModule;

  /// The challenge module, when it is on. Its line is shown only then.
  final StudyModuleSettings? challengeModule;

  /// The problems module, when it is on. The problem-set line is shown only then, and opens it.
  final StudyModuleSettings? problemsModule;

  /// The assignments module, when it is on. The assignment line is shown only then, and opens it.
  final StudyModuleSettings? assignmentsModule;

  /// Whether the viewer is an admin, who sees the problems a member does not (see visibleStudyProblems).
  final bool isAdmin;

  /// Opens a module that a line is about.
  final void Function(StudyModuleSettings module) onOpenModule;

  /// The data source. Null in the app, where the card makes its own; tests pass one.
  final TourGroupRepository? repository;

  /// The flashcards due today in this group's decks. Null in the app, which reads the device; tests pass one.
  final Future<int> Function()? cardsDue;

  /// Counts the flashcards reviewed from one day up to, but not including, another. Null in the app; tests pass one.
  final Future<int> Function(DateTime from, DateTime to)? cardsReviewed;

  /// The day to treat as today. Null in the app; tests pass one.
  final DateTime? today;

  @override
  State<StudyTodayCard> createState() => _StudyTodayCardState();
}

class _StudyTodayCardState extends State<StudyTodayCard> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();
  final List<StreamSubscription<dynamic>> _subs = [];

  StudyDeadline? _deadline;
  DueAssignment? _assignment;
  DueProblemSet? _problemSet;
  int _findingsWaiting = 0;
  int _cardsDue = 0;
  StudyChallenge? _challenge;
  Set<String> _joins = const {};
  int? _challengeDone;

  DateTime get _today => widget.today ?? DateTime.now();
  DateTime get _week => challengeWeekStart(_today);
  String get _weekKey => challengeWeekKey(_week);
  String get _me => _repository.currentEmail;

  @override
  void initState() {
    super.initState();
    _subs.addAll([
      _repository
          .watchStudyChallenge(widget.tourId, widget.subject.id, _weekKey)
          .listen(_onChallenge, onError: (Object _) {}),
      _repository
          .watchChallengeJoins(widget.tourId, widget.subject.id, _weekKey)
          .listen((joins) {
        if (mounted) setState(() => _joins = joins);
      }, onError: (Object _) {}),
    ]);
    _loadCounts();
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  void _onChallenge(StudyChallenge? challenge) {
    if (!mounted) return;
    setState(() {
      _challenge = challenge;
      _challengeDone = null;
    });
    if (challenge != null) _loadChallengeDone(challenge);
  }

  /// Counts the member's tasks done this week toward the challenge, for the line that shows it.
  Future<void> _loadChallengeDone(StudyChallenge challenge) async {
    try {
      final done = await _repository.countMyChallengeTasks(
        widget.tourId,
        widget.subject.id,
        challenge.kind,
        _week,
        cardsReviewed: _cardsReviewedThisWeek,
      );
      if (mounted && _challenge?.kind == challenge.kind) {
        setState(() => _challengeDone = done);
      }
    } catch (error, stackTrace) {
      logWarning(
          'The challenge progress could not be counted', error, stackTrace);
    }
  }

  Future<int> _cardsReviewedThisWeek() {
    final end = challengeWeekEnd(_week);
    final loader = widget.cardsReviewed;
    if (loader != null) return loader(_week, end);
    return StudyActivityLog().cardsReviewedBetween(_week, end);
  }

  /// Reads the deadline, the findings waiting for the member's check, and the flashcards due.
  Future<void> _loadCounts() async {
    final tourId = widget.tourId;
    final subjectId = widget.subject.id;
    try {
      final deadlines = await _repository.loadStudyDeadlines(tourId);
      final findings =
          await _repository.watchStudyFindings(tourId, subjectId).first;
      final checks = await _repository.loadMyFindingChecks(
        tourId,
        subjectId,
        [for (final finding in findings) finding.id],
      );
      final assignments =
          await _repository.watchStudyAssignments(tourId, subjectId).first;
      final finishedAssignments =
          await _repository.watchMyFinishedAssignments(tourId, subjectId).first;
      final problemSets =
          await _repository.watchStudyProblemSets(tourId, subjectId).first;
      final problems =
          await _repository.watchStudyProblems(tourId, subjectId).first;
      final myWork = problems.isEmpty
          ? const <String, StudyProblemSolution>{}
          : await _repository.loadMyWork(
              tourId,
              subjectId,
              [for (final problem in problems) problem.id],
            );
      // The viewer's own due dates for the sets: an admin may have given them a date of their own for one.
      final ownDue = problemSets.isEmpty
          ? const <String, DateTime>{}
          : await _repository.loadMyProblemSetDeadlines(
              tourId,
              subjectId,
              [for (final set in problemSets) set.id],
            );
      final due = await _cardsDueNow();
      if (!mounted) return;
      setState(() {
        _deadline = nextStudyDeadline(deadlines, _today);
        _assignment = nextDueAssignment(
          assignments: assignments,
          finishedIds: finishedAssignments,
          viewerEmail: _me,
          isAdmin: widget.isAdmin,
          now: _today,
        );
        _problemSet = nextDueProblemSet(
          sets: problemSets,
          problems: problems,
          workedIds: myWork.keys.toSet(),
          viewerEmail: _me,
          isAdmin: widget.isAdmin,
          now: _today,
          ownDueBySetId: ownDue,
        );
        _findingsWaiting = findingsWaitingForCheck(
          findings: findings,
          viewerEmail: _me,
          checkedIds: checks.keys.toSet(),
        );
        _cardsDue = due;
      });
    } catch (error, stackTrace) {
      logWarning('The study Today card could not be read', error, stackTrace);
    }
  }

  Future<int> _cardsDueNow() {
    final loader = widget.cardsDue;
    if (loader != null) return loader();
    return _deviceCardsDue(widget.tourId, _repository, _today);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final lines = <_TodayLine>[];

    // Each line is built here, then placed in the order the rules give for the day (todayCardLineOrder).
    final exam = widget.subject.examDate;
    final daysLeft = exam == null ? null : daysUntilExam(exam, _today);
    _TodayLine? examLine;
    if (daysLeft != null && daysLeft == 0) {
      examLine = _TodayLine(
        icon: Icons.event_rounded,
        text: l10n.translate('study_subject_exam_today'),
      );
    } else if (daysLeft != null && daysLeft > 0) {
      examLine = _TodayLine(
        icon: examModeOn(daysLeft) ? Icons.school_rounded : Icons.event_rounded,
        text: examModeOn(daysLeft)
            ? l10n.translate('study_today_exam_mode',
                args: {'days': l10n.number(daysLeft)})
            : l10n.translate('study_subject_exam_in',
                args: {'days': l10n.number(daysLeft)}),
      );
    }

    final deadline = _deadline;
    _TodayLine? deadlineLine;
    if (deadline != null) {
      deadlineLine = _TodayLine(
        icon: Icons.event_note_rounded,
        text: l10n.translate('study_today_next_deadline', args: {
          'chapter': deadline.chapterTitle,
          'book': deadline.bookTitle,
          'date': localizedDateFormat('d MMM').format(deadline.dueOn),
        }),
      );
    }

    final findingsModule = widget.findingsModule;
    _TodayLine? findingsLine;
    if (findingsModule != null && _findingsWaiting > 0) {
      findingsLine = _TodayLine(
        icon: Icons.fact_check_rounded,
        text: l10n.translate('study_today_findings_waiting',
            args: {'count': l10n.number(_findingsWaiting)}),
        onTap: () => widget.onOpenModule(findingsModule),
      );
    }

    _TodayLine? cardsLine;
    if (_cardsDue > 0) {
      cardsLine = _TodayLine(
        icon: Icons.style_rounded,
        text: l10n.translate('study_today_cards_due',
            args: {'count': l10n.number(_cardsDue)}),
      );
    }

    final challenge = _challenge;
    final challengeModule = widget.challengeModule;
    _TodayLine? challengeLine;
    if (challenge != null && challengeModule != null) {
      final joined = _joins.contains(_me);
      final done = _challengeDone;
      if (joined && done != null) {
        challengeLine = _TodayLine(
          icon: Icons.flag_rounded,
          text: l10n.translate('study_today_challenge_progress', args: {
            'done': l10n.number(challengeDone(done, challenge.target)),
            'target': l10n.number(challenge.target),
          }),
          onTap: () => widget.onOpenModule(challengeModule),
        );
      } else if (!joined && challengeIsOpen(weekStart: _week, now: _today)) {
        challengeLine = _TodayLine(
          icon: Icons.flag_outlined,
          text: l10n.translate('study_today_challenge_join'),
          onTap: () => widget.onOpenModule(challengeModule),
        );
      }
    }

    final assignment = _assignment;
    final assignmentsModule = widget.assignmentsModule;
    _TodayLine? assignmentLine;
    if (assignment != null && assignmentsModule != null) {
      assignmentLine = _TodayLine(
        icon: Icons.assignment_rounded,
        text: l10n.translate('study_today_assignment_due', args: {
          'title': assignment.assignment.title,
          'date': localizedDateFormat('d MMM').format(assignment.due),
        }),
        onTap: () => widget.onOpenModule(assignmentsModule),
      );
    }

    final problemSet = _problemSet;
    final problemsModule = widget.problemsModule;
    _TodayLine? problemSetLine;
    if (problemSet != null && problemsModule != null) {
      problemSetLine = _TodayLine(
        icon: Icons.edit_note_rounded,
        text: l10n.translate('study_today_problem_set', args: {
          'title': problemSet.set.title,
          'date': localizedDateFormat('d MMM').format(problemSet.due),
          'worked': l10n.number(problemSet.worked),
          'total': l10n.number(problemSet.total),
        }),
        onTap: () => widget.onOpenModule(problemsModule),
      );
    }

    final byLine = <TodayCardLine, _TodayLine?>{
      TodayCardLine.exam: examLine,
      TodayCardLine.deadline: deadlineLine,
      TodayCardLine.assignment: assignmentLine,
      TodayCardLine.problemSet: problemSetLine,
      TodayCardLine.findings: findingsLine,
      TodayCardLine.cards: cardsLine,
      TodayCardLine.challenge: challengeLine,
    };
    for (final line in todayCardLineOrder(examMode: examModeOn(daysLeft))) {
      final entry = byLine[line];
      if (entry != null) lines.add(entry);
    }

    if (lines.isEmpty) {
      lines.add(_TodayLine(
        icon: Icons.check_circle_outline_rounded,
        text: l10n.translate('study_today_nothing'),
      ));
    }

    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.translate('study_today_title'),
              style: TextStyle(
                color: palette.text,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            for (final line in lines) _TodayLineTile(line: line),
          ],
        ),
      ),
    );
  }
}

/// The Today card of a study group, on its home: the group's next deadline, the nearest exam across its subjects, and
/// the flashcards due. Lines appear only when there is something to say.
class StudyGroupTodayCard extends StatefulWidget {
  const StudyGroupTodayCard({
    super.key,
    required this.tourId,
    this.repository,
    this.cardsDue,
    this.today,
  });

  final String tourId;

  /// The data source. Null in the app, where the card makes its own; tests pass one.
  final TourGroupRepository? repository;

  /// The flashcards due today in this group's decks. Null in the app, which reads the device; tests pass one.
  final Future<int> Function()? cardsDue;

  /// The day to treat as today. Null in the app; tests pass one.
  final DateTime? today;

  @override
  State<StudyGroupTodayCard> createState() => _StudyGroupTodayCardState();
}

class _StudyGroupTodayCardState extends State<StudyGroupTodayCard> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();
  StreamSubscription<List<StudySubject>>? _subjects;

  List<StudySubject> _allSubjects = const [];
  StudyDeadline? _deadline;
  int _cardsDue = 0;

  DateTime get _today => widget.today ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _subjects = _repository.watchStudySubjects(widget.tourId).listen(
      (subjects) {
        if (mounted) setState(() => _allSubjects = subjects);
      },
      onError: (Object _) {},
    );
    _loadCounts();
  }

  @override
  void dispose() {
    _subjects?.cancel();
    super.dispose();
  }

  Future<void> _loadCounts() async {
    try {
      final deadlines = await _repository.loadStudyDeadlines(widget.tourId);
      final loader = widget.cardsDue;
      final due = loader != null
          ? await loader()
          : await _deviceCardsDue(widget.tourId, _repository, _today);
      if (!mounted) return;
      setState(() {
        _deadline = nextStudyDeadline(deadlines, _today);
        _cardsDue = due;
      });
    } catch (error, stackTrace) {
      logWarning(
          'The study group Today card could not be read', error, stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final lines = <_TodayLine>[];

    // Only the subjects the group studies count: a proposal or an archived subject has no countdown.
    final exam = nearestExam(activeStudySubjects(_allSubjects), _today);
    if (exam != null) {
      final days = daysUntilExam(exam.examDate!, _today);
      lines.add(_TodayLine(
        icon: examModeOn(days) ? Icons.school_rounded : Icons.event_rounded,
        text: days == 0
            ? l10n.translate('study_today_exam_for_today',
                args: {'subject': exam.title})
            : l10n.translate('study_today_exam_for', args: {
                'subject': exam.title,
                'days': l10n.number(days),
              }),
      ));
    }

    final deadline = _deadline;
    if (deadline != null) {
      lines.add(_TodayLine(
        icon: Icons.event_note_rounded,
        text: l10n.translate('study_today_next_deadline', args: {
          'chapter': deadline.chapterTitle,
          'book': deadline.bookTitle,
          'date': localizedDateFormat('d MMM').format(deadline.dueOn),
        }),
      ));
    }

    if (_cardsDue > 0) {
      lines.add(_TodayLine(
        icon: Icons.style_rounded,
        text: l10n.translate('study_today_cards_due',
            args: {'count': l10n.number(_cardsDue)}),
      ));
    }

    if (lines.isEmpty) {
      lines.add(_TodayLine(
        icon: Icons.check_circle_outline_rounded,
        text: l10n.translate('study_today_nothing'),
      ));
    }

    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.translate('study_today_title'),
              style: TextStyle(
                color: palette.text,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            for (final line in lines) _TodayLineTile(line: line),
          ],
        ),
      ),
    );
  }
}

/// One line of a Today card. A line with a tap is a button of at least 48 dp.
class _TodayLineTile extends StatelessWidget {
  const _TodayLineTile({required this.line});

  final _TodayLine line;

  @override
  Widget build(BuildContext context) {
    final palette = context.forest;
    final row = Row(
      children: [
        Icon(line.icon, size: 18, color: palette.accentText),
        const SizedBox(width: 10),
        Expanded(
          child: Text(line.text, style: TextStyle(color: palette.text)),
        ),
        if (line.onTap != null)
          Icon(Icons.chevron_right_rounded, color: palette.text54),
      ],
    );
    final onTap = line.onTap;
    if (onTap == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: row,
      );
    }
    return Semantics(
      button: true,
      label: line.text,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: row,
          ),
        ),
      ),
    );
  }
}

/// The flashcards due today across a study group's decks, read from the device. A deck belongs to a book of the group.
Future<int> _deviceCardsDue(
  String tourId,
  TourGroupRepository repository,
  DateTime today,
) async {
  final books = await repository.watchStudyBooks(tourId).first;
  // A group with no books has no decks, so the device is not read for it.
  if (books.isEmpty) return 0;
  final decks = {for (final book in books) book.id};
  final cards = await StudyFlashcardStore().loadAll();
  return dueCards(
    [
      for (final card in cards)
        if (decks.contains(card.deckId)) card,
    ],
    today,
  ).length;
}
