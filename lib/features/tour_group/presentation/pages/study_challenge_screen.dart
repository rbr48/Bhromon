import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/localized_date.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../../core/utils/app_logger.dart';
import '../../data/study_activity_log.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/study_challenge_models.dart';
import '../../domain/models/study_subject_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/study_challenge_rules.dart';
import '../widgets/group_back_button.dart';
import '../widgets/study/study_challenge_editor.dart';
import '../widgets/study/study_labels.dart';
import 'package:bhromon/core/theme/colors.dart';

/// One subject's weekly challenge: this week's task, how many members have joined it, and the member's own
/// progress. Members join and leave while the week runs. An admin sets the week's challenge. Only counts are shown,
/// and nobody is ranked.
class StudyChallengeScreen extends StatefulWidget {
  const StudyChallengeScreen({
    super.key,
    required this.tourId,
    required this.subject,
    required this.settings,
    this.repository,
    this.cardsReviewed,
    this.today,
  });

  final String tourId;
  final StudySubject subject;
  final StudyModuleSettings settings;

  /// The data source. Null in the app, where the screen makes its own; tests pass one.
  final TourGroupRepository? repository;

  /// Counts the flashcards reviewed from one day up to, but not including, another. Null in the app, where the device
  /// counts them; tests pass one.
  final Future<int> Function(DateTime from, DateTime to)? cardsReviewed;

  /// The day to treat as today. Null in the app; tests pass one.
  final DateTime? today;

  @override
  State<StudyChallengeScreen> createState() => _StudyChallengeScreenState();
}

class _StudyChallengeScreenState extends State<StudyChallengeScreen> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();
  final List<StreamSubscription<dynamic>> _subs = [];
  TourRole? _myRole;

  /// This week's challenge, or null when an admin has not set one.
  StudyChallenge? _challenge;

  /// The emails of the members who joined this week's challenge. The screen shows only how many.
  Set<String> _joins = const {};

  /// The member's own tasks done this week toward the challenge, or null while they are counted.
  int? _done;
  bool _busy = false;

  DateTime get _today => widget.today ?? DateTime.now();
  DateTime get _week => challengeWeekStart(_today);
  String get _weekKey => challengeWeekKey(_week);
  String get _me => _repository.currentEmail;
  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;
  bool get _open => challengeIsOpen(weekStart: _week, now: _today);
  bool get _joined => _joins.contains(_me);

  @override
  void initState() {
    super.initState();
    _repository.myRole(widget.tourId).then((role) {
      if (mounted) setState(() => _myRole = role);
    }, onError: (Object _) {});
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
      _done = null;
    });
    if (challenge != null) _loadProgress(challenge);
  }

  /// Counts the member's tasks done this week toward the challenge.
  Future<void> _loadProgress(StudyChallenge challenge) async {
    try {
      final done = await _repository.countMyChallengeTasks(
        widget.tourId,
        widget.subject.id,
        challenge.kind,
        _week,
        cardsReviewed: _cardsReviewedThisWeek,
      );
      if (mounted && _challenge?.kind == challenge.kind) {
        setState(() => _done = done);
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

  /// Joins the challenge, or leaves it, for the signed-in member.
  Future<void> _toggleJoin() async {
    if (_busy) return;
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final me = _me;
    final leaving = _joined;
    setState(() => _busy = true);
    try {
      if (leaving) {
        await _repository.leaveStudyChallenge(
            widget.tourId, widget.subject.id, _weekKey);
      } else {
        await _repository.joinStudyChallenge(
            widget.tourId, widget.subject.id, _weekKey);
      }
      if (!mounted) return;
      setState(() {
        _joins = leaving ? ({..._joins}..remove(me)) : {..._joins, me};
      });
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate(leaving
            ? 'study_challenge_left_done'
            : 'study_challenge_joined_done')),
      ));
    } catch (error, stackTrace) {
      logWarning('A challenge join could not be saved', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: AppColors.amber,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// An admin sets the week's challenge, or changes it.
  Future<void> _setChallenge() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final saved = await showStudyChallengeEditor(
      context,
      weekKey: _weekKey,
      current: _challenge,
    );
    if (saved == null || !mounted) return;
    try {
      await _repository.setStudyChallenge(
          widget.tourId, widget.subject.id, saved);
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.translate('study_challenge_saved'))));
    } catch (error, stackTrace) {
      logWarning('A challenge could not be saved', error, stackTrace);
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
    final challenge = _challenge;
    return GroupPopScope(
      tourId: widget.tourId,
      child: Scaffold(
        backgroundColor: palette.background,
        appBar: AppBar(
          leading: GroupBackButton(tourId: widget.tourId),
          title: Text(widget.settings.name,
              style: TextStyle(
                  color: palette.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
          backgroundColor: palette.card,
          foregroundColor: palette.text,
          iconTheme: IconThemeData(color: palette.text),
          elevation: 0,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(
              l10n.translate('study_challenge_week', args: {
                'date': localizedDateFormat('d MMM').format(_week),
              }),
              style: TextStyle(color: palette.text70),
            ),
            const SizedBox(height: 12),
            if (challenge == null)
              Text(
                l10n.translate('study_challenge_none'),
                style: TextStyle(color: palette.text),
              )
            else
              _challengeCard(challenge),
            if (_isAdmin && _open) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _setChallenge,
                child: Text(l10n.translate(challenge == null
                    ? 'study_challenge_set_btn'
                    : 'study_challenge_change_btn')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The week's task, the member's progress and the join action, and how many have joined.
  Widget _challengeCard(StudyChallenge challenge) {
    final l10n = context.l10n;
    final palette = context.forest;
    final done = _done;
    final target = challenge.target;
    final task = l10n.translate(challengeTaskKey(challenge.kind),
        args: {'target': l10n.number(target)});
    final progressText = done == null
        ? null
        : l10n.translate('study_challenge_progress', args: {
            'done': l10n.number(challengeDone(done, target)),
            'target': l10n.number(target),
          });
    return Card(
      color: palette.card,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(task,
                style: TextStyle(
                  color: palette.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                )),
            const SizedBox(height: 12),
            if (!_joined)
              Text(
                l10n.translate('study_challenge_join_hint'),
                style: TextStyle(color: palette.text70),
              )
            else if (progressText == null)
              Text(
                l10n.translate('study_challenge_counting'),
                style: TextStyle(color: palette.text70),
              )
            else ...[
              Semantics(
                label: progressText,
                child: LinearProgressIndicator(
                  value: challengeDone(done!, target) / target,
                ),
              ),
              const SizedBox(height: 6),
              Text(progressText, style: TextStyle(color: palette.text)),
              if (challengeMet(done, target)) ...[
                const SizedBox(height: 4),
                Text(
                  l10n.translate('study_challenge_done'),
                  style: TextStyle(color: palette.accentText),
                ),
              ],
            ],
            const SizedBox(height: 12),
            Text(
              l10n.translate('study_challenge_joined_count', args: {
                'count': l10n.number(_joins.length),
              }),
              style: TextStyle(color: palette.text70),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.translate('study_challenge_streak_note'),
              style: TextStyle(color: palette.text54, fontSize: 12),
            ),
            if (_open) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy ? null : _toggleJoin,
                child: Text(l10n.translate(_joined
                    ? 'study_challenge_leave_btn'
                    : 'study_challenge_join_btn')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
