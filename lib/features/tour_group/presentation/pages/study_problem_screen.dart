import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/localized_date.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../../core/utils/app_logger.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/study_problem_models.dart';
import '../../domain/models/study_subject_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/study_problem_rules.dart';
import '../widgets/study/study_problem_composer.dart';

/// One problem: its statement, its reference solution once it has opened, the member's own working,
/// and the working of the other members. A member sees and reviews the others' working only after
/// they have submitted their own. An admin writes the reference solution and sets when it opens.
class StudyProblemScreen extends StatefulWidget {
  const StudyProblemScreen({
    super.key,
    required this.tourId,
    required this.subject,
    required this.settings,
    required this.problem,
    this.repository,
  });

  final String tourId;
  final StudySubject subject;
  final StudyModuleSettings settings;
  final StudyProblem problem;

  /// The data source. Null in the app, where the screen makes its own; tests pass one.
  final TourGroupRepository? repository;

  @override
  State<StudyProblemScreen> createState() => _StudyProblemScreenState();
}

class _StudyProblemScreenState extends State<StudyProblemScreen> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();
  late StudyProblem _problem = widget.problem;
  TourRole? _myRole;

  /// The reference solution, once it has been read, and whether the read has been tried.
  StudyReferenceSolution? _reference;
  bool _referenceChecked = false;

  /// The member's own working, whether it has been read, and the stream of everyone's working, which
  /// the rules open to a member only after their own working is submitted (and to an admin always).
  StudyProblemSolution? _myWork;
  bool _workChecked = false;
  Stream<List<StudyProblemSolution>>? _workStream;

  /// The member's own review of each working, by the solver's email, and the solvers asked for.
  final Map<String, StudyWorkReview> _myReviews = {};
  final Set<String> _reviewsAsked = {};

  String get _me => _repository.currentEmail;
  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;
  bool get _isAuthor => _problem.createdByEmail == _me;
  bool get _canManage => _isAdmin || _isAuthor;

  @override
  void initState() {
    super.initState();
    // The reference waits for the viewer's role: an admin may read it before its release day, and
    // reading it once here and again after the role is known would read it twice for a member.
    _repository.myRole(widget.tourId).then((role) {
      if (!mounted) return;
      setState(() {
        _myRole = role;
        _ensureWorkStream();
      });
      _loadReference();
    }, onError: (Object _) {
      _loadReference();
    });
    _loadMine();
  }

  /// Reads the reference solution when the member may read it. An admin may always read it.
  Future<void> _loadReference() async {
    final now = DateTime.now();
    if (!canSeeReference(problem: _problem, isAdmin: _isAdmin, now: now)) {
      if (mounted) setState(() => _referenceChecked = true);
      return;
    }
    try {
      final reference = await _repository.loadStudyReference(
          widget.tourId, widget.subject.id, _problem.id);
      if (mounted) {
        setState(() {
          _reference = reference;
          _referenceChecked = true;
        });
      }
    } catch (error, stackTrace) {
      logWarning(
          'Loading the study reference solution failed', error, stackTrace);
      if (mounted) setState(() => _referenceChecked = true);
    }
  }

  /// Reads the member's own working. A working that exists opens the stream of everyone's working.
  Future<void> _loadMine() async {
    try {
      final work = await _repository
          .loadMyWork(widget.tourId, widget.subject.id, [_problem.id]);
      if (!mounted) return;
      setState(() {
        _myWork = work[_problem.id];
        _workChecked = true;
        _ensureWorkStream();
      });
    } catch (error, stackTrace) {
      logWarning('Loading the study working failed', error, stackTrace);
      if (mounted) setState(() => _workChecked = true);
    }
  }

  /// Starts the stream of everyone's working, once it may be read: when the member has submitted
  /// their own, or when the viewer is an admin. Called from a callback, never from build.
  void _ensureWorkStream() {
    if (_workStream != null) return;
    if (_myWork == null && !_isAdmin) return;
    _workStream = _repository.watchStudyWork(
        widget.tourId, widget.subject.id, _problem.id);
  }

  /// Asks for the member's review of the working not asked for yet. Each working is asked once.
  void _askReviews(List<String> solvers) {
    final missing = [
      for (final s in solvers)
        if (_reviewsAsked.add(s)) s
    ];
    if (missing.isEmpty) return;
    _repository
        .loadMyWorkReviews(
            widget.tourId, widget.subject.id, _problem.id, missing)
        .then((reviews) {
      if (mounted) setState(() => _myReviews.addAll(reviews));
    }, onError: (Object error, StackTrace stackTrace) {
      logWarning('Loading the study work reviews failed', error, stackTrace);
    });
  }

  /// Runs one change to the member's working, then reads the working again.
  Future<void> _saveWork(Future<void> Function() change) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await change();
      if (!mounted) return;
      await _loadMine();
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.translate('study_work_saved'))));
    } catch (error, stackTrace) {
      logWarning('A study working change failed', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  Future<void> _submitWork() async {
    final text = await showStudyTextEditor(
      context,
      titleKey: 'study_work_submit_title',
      labelKey: 'study_work_text_label',
      maxLength: StudyProblemLimits.workMax,
    );
    if (text == null || !mounted) return;
    await _saveWork(() => _repository.submitStudyWork(
          widget.tourId,
          widget.subject.id,
          _problem.id,
          text: text,
        ));
  }

  Future<void> _editWork() async {
    final current = _myWork;
    if (current == null) return;
    final text = await showStudyTextEditor(
      context,
      titleKey: 'study_work_edit_title',
      labelKey: 'study_work_text_label',
      maxLength: StudyProblemLimits.workMax,
      initial: current.text,
    );
    if (text == null || !mounted) return;
    await _saveWork(() => _repository.editStudyWork(
          widget.tourId,
          widget.subject.id,
          _problem.id,
          text: text,
        ));
  }

  /// Gives a verdict on a peer's working. A gap takes an optional note first.
  Future<void> _review(StudyProblemSolution work, WorkVerdict verdict) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    var note = '';
    if (verdict == WorkVerdict.gap) {
      final asked = await showStudyGapDialog(context);
      if (asked == null || !mounted) return;
      note = asked;
    }
    try {
      await _repository.reviewStudyWork(
        widget.tourId,
        widget.subject.id,
        _problem.id,
        work.solverEmail,
        verdict: verdict,
        note: note,
      );
      if (!mounted) return;
      setState(() {
        _myReviews[work.solverEmail] = StudyWorkReview(
          reviewerEmail: _me,
          verdict: verdict,
          note: note,
        );
      });
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.translate('study_work_review_done'))));
    } catch (error, stackTrace) {
      logWarning('A study work review failed', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  Future<void> _withdrawReview(
      StudyProblemSolution work, WorkVerdict verdict) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repository.withdrawStudyWorkReview(
        widget.tourId,
        widget.subject.id,
        _problem.id,
        work.solverEmail,
        verdict,
      );
      if (!mounted) return;
      setState(() {
        _myReviews.remove(work.solverEmail);
      });
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_work_review_withdrawn')),
      ));
    } catch (error, stackTrace) {
      logWarning(
          'A study work review could not be withdrawn', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  /// Writes or changes the reference solution. The admin who saves it is its reviewer.
  Future<void> _editReference() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final text = await showStudyTextEditor(
      context,
      titleKey: 'study_problem_reference_title',
      labelKey: 'study_problem_reference_text_label',
      maxLength: StudyProblemLimits.referenceMax,
      initial: _reference?.text ?? '',
    );
    if (text == null || !mounted) return;
    try {
      await _repository.saveStudyReference(
          widget.tourId, widget.subject.id, _problem.id,
          text: text);
      if (!mounted) return;
      await _loadReference();
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.translate('study_post_saved'))));
    } catch (error, stackTrace) {
      logWarning(
          'Saving the study reference solution failed', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  Future<void> _removeReference() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repository.deleteStudyReference(
          widget.tourId, widget.subject.id, _problem.id);
      if (!mounted) return;
      setState(() => _reference = null);
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.translate('study_post_deleted'))));
    } catch (error, stackTrace) {
      logWarning(
          'Removing the study reference solution failed', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  /// Runs one change to the problem itself, and keeps the page's copy of it up to date.
  Future<void> _runProblem(
    Future<void> Function() change,
    StudyProblem updated,
    String doneKey,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await change();
      if (!mounted) return;
      setState(() => _problem = updated);
      messenger.showSnackBar(SnackBar(content: Text(l10n.translate(doneKey))));
    } catch (error, stackTrace) {
      logWarning('A study problem change failed', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  Future<void> _editProblem() async {
    final draft = await showStudyProblemEditor(context, existing: _problem);
    if (draft == null || !mounted) return;
    await _runProblem(
      () => _repository.editStudyProblem(
        widget.tourId,
        widget.subject.id,
        _problem,
        text: draft.text,
        title: draft.title,
      ),
      _copy(text: draft.text, title: draft.title),
      'study_post_saved',
    );
  }

  Future<void> _setShown() async {
    await _runProblem(
      () => _repository.setStudyProblemFlags(
          widget.tourId, widget.subject.id, _problem.id,
          shown: true),
      _copy(shown: true),
      'study_post_shown_done',
    );
  }

  Future<void> _togglePinned() async {
    final pinned = !_problem.pinned;
    await _runProblem(
      () => _repository.setStudyProblemFlags(
          widget.tourId, widget.subject.id, _problem.id,
          pinned: pinned),
      _copy(pinned: pinned),
      'study_post_saved',
    );
  }

  /// An admin sets the day the reference solution opens. The date picker gives a day, which opens at
  /// its start.
  Future<void> _pickRelease() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _problem.releaseAt ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null || !mounted) return;
    final release = DateTime(picked.year, picked.month, picked.day);
    await _runProblem(
      () => _repository.setStudyProblemRelease(
          widget.tourId, widget.subject.id, _problem.id, release),
      _copy(releaseAt: release),
      'study_post_saved',
    );
  }

  Future<void> _clearRelease() async {
    await _runProblem(
      () => _repository.setStudyProblemRelease(
          widget.tourId, widget.subject.id, _problem.id, null),
      _copy(clearRelease: true),
      'study_post_saved',
    );
  }

  Future<void> _remove() async {
    final l10n = context.l10n;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('study_post_delete_title')),
        content: Text(l10n.translate('study_post_delete_body')),
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
    try {
      await _repository.deleteStudyProblem(
          widget.tourId, widget.subject.id, _problem.id);
      if (!mounted) return;
      navigator.pop();
    } catch (error, stackTrace) {
      logWarning('Removing a study problem failed', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  /// A copy of the problem with some fields changed, for the page after a change is saved.
  StudyProblem _copy({
    String? text,
    String? title,
    bool? shown,
    bool? pinned,
    DateTime? releaseAt,
    bool clearRelease = false,
  }) =>
      StudyProblem(
        id: _problem.id,
        text: text ?? _problem.text,
        title: title ?? _problem.title,
        createdByEmail: _problem.createdByEmail,
        createdAt: _problem.createdAt,
        releaseAt: clearRelease ? null : (releaseAt ?? _problem.releaseAt),
        shown: shown ?? _problem.shown,
        pinned: pinned ?? _problem.pinned,
      );

  String _standingKey(WorkStanding standing) => switch (standing) {
        WorkStanding.unreviewed => 'study_work_standing_unreviewed',
        WorkStanding.rightSoFar => 'study_work_standing_right',
        WorkStanding.gapsFound => 'study_work_standing_gaps',
        WorkStanding.mixed => 'study_work_standing_mixed',
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final now = DateTime.now();
    final heading = _problem.title.isEmpty
        ? l10n.translate('study_problem_screen_title')
        : _problem.title;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: Text(heading,
            style: TextStyle(
                color: palette.text,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
        backgroundColor: palette.card,
        foregroundColor: palette.text,
        iconTheme: IconThemeData(color: palette.text),
        elevation: 0,
        actions: [
          if (_canManage)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, color: palette.text),
              tooltip: l10n.translate('study_post_menu'),
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    _editProblem();
                  case 'show':
                    _setShown();
                  case 'pin':
                    _togglePinned();
                  case 'release':
                    _pickRelease();
                  case 'clear_release':
                    _clearRelease();
                  default:
                    _remove();
                }
              },
              itemBuilder: (_) => [
                if (_isAuthor)
                  PopupMenuItem<String>(
                    value: 'edit',
                    child: Text(l10n.translate('study_edit')),
                  ),
                if (_isAdmin && !_problem.shown)
                  PopupMenuItem<String>(
                    value: 'show',
                    child: Text(l10n.translate('study_post_show')),
                  ),
                if (_isAdmin)
                  PopupMenuItem<String>(
                    value: 'pin',
                    child: Text(l10n.translate(_problem.pinned
                        ? 'study_post_unpin'
                        : 'study_post_pin')),
                  ),
                if (_isAdmin)
                  PopupMenuItem<String>(
                    value: 'release',
                    child: Text(l10n.translate('study_problem_release_set')),
                  ),
                if (_isAdmin && _problem.releaseAt != null)
                  PopupMenuItem<String>(
                    value: 'clear_release',
                    child: Text(l10n.translate('study_problem_release_clear')),
                  ),
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Text(l10n.translate('study_remove')),
                ),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _statementCard(),
          const SizedBox(height: 8),
          _referenceCard(now),
          const SizedBox(height: 8),
          _ownWorkCard(),
          const SizedBox(height: 8),
          _othersWorkSection(),
        ],
      ),
    );
  }

  Widget _card({required List<Widget> children}) {
    final palette = context.forest;
    return Card(
      color: palette.card,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _statementCard() {
    final l10n = context.l10n;
    final palette = context.forest;
    return _card(children: [
      if (_problem.title.isNotEmpty) ...[
        Text(_problem.title,
            style: TextStyle(
                color: palette.text,
                fontWeight: FontWeight.w600,
                fontSize: 16)),
        const SizedBox(height: 4),
      ],
      Text(_problem.text, style: TextStyle(color: palette.text)),
      if (!_problem.shown) ...[
        const SizedBox(height: 6),
        Text(l10n.translate('study_post_waiting_label'),
            style:
                TextStyle(color: palette.text54, fontStyle: FontStyle.italic)),
      ],
    ]);
  }

  Widget _referenceCard(DateTime now) {
    final l10n = context.l10n;
    final palette = context.forest;
    final status = referenceStatus(problem: _problem, now: now);
    final reference = _reference;
    final String releaseLine = switch (status) {
      ReferenceStatus.noRelease =>
        l10n.translate('study_problem_release_none_line'),
      ReferenceStatus.scheduled =>
        l10n.translate('study_problem_reference_opens', args: {
          'date': localizedDateFormat('d MMM yyyy').format(_problem.releaseAt!),
        }),
      ReferenceStatus.open =>
        l10n.translate('study_problem_reference_open_line'),
    };
    final children = <Widget>[
      Text(l10n.translate('study_problem_reference_heading'),
          style: TextStyle(
              color: palette.text, fontWeight: FontWeight.w600, fontSize: 15)),
      const SizedBox(height: 6),
    ];
    if (!_referenceChecked) {
      children.add(const Center(child: CircularProgressIndicator()));
    } else if (reference != null) {
      children.add(Text(reference.text, style: TextStyle(color: palette.text)));
      children.add(Text(l10n.translate('study_problem_reviewed_by_admin'),
          style: TextStyle(
              color: palette.accentText, fontWeight: FontWeight.w600)));
    } else if (status == ReferenceStatus.scheduled && !_isAdmin) {
      children.add(Text(releaseLine, style: TextStyle(color: palette.text70)));
    } else {
      children.add(Text(
        l10n.translate(_isAdmin
            ? 'study_problem_reference_none_admin'
            : status == ReferenceStatus.open
                ? 'study_problem_reference_missing'
                : 'study_problem_reference_none'),
        style: TextStyle(color: palette.text70),
      ));
    }
    if (_isAdmin) {
      children.add(const SizedBox(height: 6));
      children.add(Text(releaseLine, style: TextStyle(color: palette.text70)));
      children.add(Wrap(
        children: [
          TextButton(
            onPressed: _editReference,
            child: Text(l10n.translate(reference == null
                ? 'study_problem_reference_write'
                : 'study_problem_reference_edit')),
          ),
          if (reference != null)
            TextButton(
              onPressed: _removeReference,
              child: Text(l10n.translate('study_problem_reference_remove')),
            ),
        ],
      ));
    }
    return _card(children: children);
  }

  Widget _ownWorkCard() {
    final l10n = context.l10n;
    final palette = context.forest;
    final heading = Text(l10n.translate('study_work_heading'),
        style: TextStyle(
            color: palette.text, fontWeight: FontWeight.w600, fontSize: 15));
    if (!_workChecked) {
      return _card(children: [
        heading,
        const SizedBox(height: 6),
        const Center(child: CircularProgressIndicator()),
      ]);
    }
    final mine = _myWork;
    if (mine == null) {
      return _card(children: [
        heading,
        const SizedBox(height: 6),
        Text(l10n.translate('study_work_none'),
            style: TextStyle(color: palette.text70)),
        if (!_problem.shown)
          Text(l10n.translate('study_work_waiting_problem'),
              style:
                  TextStyle(color: palette.text54, fontStyle: FontStyle.italic))
        else
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _submitWork,
              child: Text(l10n.translate('study_work_submit')),
            ),
          ),
      ]);
    }
    return _card(children: [
      heading,
      const SizedBox(height: 6),
      Text(mine.text, style: TextStyle(color: palette.text)),
      const SizedBox(height: 6),
      Text(
        l10n.translate('study_work_counts', args: {
          'right': l10n.number(mine.rightCount),
          'gap': l10n.number(mine.gapCount),
        }),
        style: TextStyle(color: palette.text54),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: _editWork,
          child: Text(l10n.translate('study_edit')),
        ),
      ),
    ]);
  }

  Widget _othersWorkSection() {
    final l10n = context.l10n;
    final palette = context.forest;
    if (!_workChecked) return const SizedBox.shrink();
    if (_myWork == null && !_isAdmin) {
      return _card(children: [
        Text(l10n.translate('study_work_others_heading'),
            style: TextStyle(
                color: palette.text,
                fontWeight: FontWeight.w600,
                fontSize: 15)),
        const SizedBox(height: 6),
        Text(l10n.translate('study_work_others_locked'),
            style: TextStyle(color: palette.text70)),
      ]);
    }
    final stream = _workStream;
    if (stream == null) return const SizedBox.shrink();
    return StreamBuilder<List<StudyProblemSolution>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return _card(children: [
            Text(l10n.translate('study_failed'),
                style: TextStyle(color: palette.text70)),
          ]);
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final work = snap.data!;
        _askReviews([for (final w in work) w.solverEmail]);
        if (work.isEmpty) {
          return _card(children: [
            Text(l10n.translate('study_work_none_yet'),
                style: TextStyle(color: palette.text70)),
          ]);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final w in work) ...[
              _workCard(w),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }

  Widget _workCard(StudyProblemSolution work) {
    final l10n = context.l10n;
    final palette = context.forest;
    final mine = work.solverEmail == _me;
    final myReview = _myReviews[work.solverEmail];
    final canReview = canReviewWork(
      solverEmail: work.solverEmail,
      viewerEmail: _me,
      viewerHasWork: _myWork != null,
      viewerHasReview: myReview != null,
    );
    return _card(children: [
      if (mine)
        Text(l10n.translate('study_work_yours'),
            style: TextStyle(
                color: palette.accentText, fontWeight: FontWeight.bold)),
      Text(work.text, style: TextStyle(color: palette.text)),
      const SizedBox(height: 6),
      Text(
        l10n.translate('study_work_counts', args: {
          'right': l10n.number(work.rightCount),
          'gap': l10n.number(work.gapCount),
        }),
        style: TextStyle(color: palette.text54),
      ),
      Text(l10n.translate(_standingKey(workStanding(work))),
          style: TextStyle(
              color: palette.accentText, fontWeight: FontWeight.w600)),
      if (myReview != null) ...[
        const SizedBox(height: 4),
        Text(
          l10n.translate(myReview.verdict == WorkVerdict.right
              ? 'study_work_you_right'
              : 'study_work_you_gap'),
          style: TextStyle(color: palette.text),
        ),
        if (myReview.note.isNotEmpty)
          Text(myReview.note, style: TextStyle(color: palette.text70)),
      ],
      Wrap(
        children: [
          if (canReview)
            TextButton.icon(
              onPressed: () => _review(work, WorkVerdict.right),
              icon: Icon(Icons.thumb_up_alt_outlined,
                  size: 18, color: palette.accentText),
              label: Text(l10n.translate('study_work_right')),
            ),
          if (canReview)
            TextButton.icon(
              onPressed: () => _review(work, WorkVerdict.gap),
              icon: Icon(Icons.flag_outlined,
                  size: 18, color: palette.accentText),
              label: Text(l10n.translate('study_work_gap')),
            ),
          if (myReview != null)
            TextButton(
              onPressed: () => _withdrawReview(work, myReview.verdict),
              child: Text(l10n.translate('study_work_withdraw')),
            ),
        ],
      ),
    ]);
  }
}
