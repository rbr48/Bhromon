import '../widgets/group_back_button.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/localized_date.dart';
import '../../../../core/utils/app_logger.dart';
import '../../data/tour_group_repository.dart';
import '../../data/voice_room_service.dart';
import '../../domain/models/study_models.dart';
import '../../domain/models/study_session_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/study_room_rules.dart';
import '../../domain/services/study_session_rules.dart';

import '../widgets/study/study_text_field.dart';
import '../widgets/study/study_rich_text.dart';
import 'package:bhromon/core/theme/colors.dart';

/// One reading session: when and where it is, the agenda and the link, each member's answer and check-in,
/// the shared focus timer, and the recap. Its creator or an admin writes the agenda, runs the timer and
/// writes the recap.
class StudySessionScreen extends StatefulWidget {
  const StudySessionScreen({
    super.key,
    required this.tourId,
    required this.session,
    this.repository,
  });

  final String tourId;
  final ReadingSession session;
  final TourGroupRepository? repository;

  @override
  State<StudySessionScreen> createState() => _StudySessionScreenState();
}

/// What the recap dialog returns: the text as typed, one open question a line.
class _RecapDraft {
  const _RecapDraft({
    required this.covered,
    required this.hard,
    required this.questions,
  });

  final String covered;
  final String hard;
  final String questions;
}

class _StudySessionScreenState extends State<StudySessionScreen> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();

  late ReadingSession _session = widget.session;
  List<StudySessionRsvp> _answers = const [];
  TourRole? _myRole;
  DateTime _now = DateTime.now();
  Timer? _ticker;

  StreamSubscription<List<ReadingSession>>? _sessionsSub;
  StreamSubscription<List<StudySessionRsvp>>? _answersSub;
  StreamSubscription<void>? _voiceSub;

  // The study room's voice connection. The page shows the room, and leaves it when the page closes.
  final VoiceRoomService _voice = VoiceRoomService();
  late final Stream<List<VoiceParticipant>> _roomSeats =
      _voice.watchParticipants(
    widget.tourId,
    studyRoomChannelId(widget.session.id),
  );

  String get _me => _repository.currentEmail;
  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;

  @override
  void initState() {
    super.initState();
    _repository.myRole(widget.tourId).then((role) {
      if (mounted) setState(() => _myRole = role);
    });
    _sessionsSub =
        _repository.watchReadingSessions(widget.tourId).listen((sessions) {
      final match = [
        for (final session in sessions)
          if (session.id == widget.session.id) session,
      ];
      if (!mounted || match.isEmpty) return;
      setState(() {
        _session = match.first;
        _syncTicker();
      });
    }, onError: (Object error, StackTrace stackTrace) {
      logWarning('The session could not be read', error, stackTrace);
    });
    _answersSub = _repository
        .watchSessionRsvps(widget.tourId, widget.session.id)
        .listen((answers) {
      if (mounted) setState(() => _answers = answers);
    }, onError: (Object error, StackTrace stackTrace) {
      logWarning('The answers could not be read', error, stackTrace);
    });
    _voiceSub = _voice.changes.listen((_) {
      if (mounted) setState(() {});
    });
    _syncTicker();
  }

  @override
  void dispose() {
    _sessionsSub?.cancel();
    _answersSub?.cancel();
    _voiceSub?.cancel();
    _ticker?.cancel();
    // Leaving the page leaves this session's room, so no microphone stays on where nobody can see it.
    if (_inRoom) unawaited(_voice.leaveVoiceRoom());
    super.dispose();
  }

  /// Ticks once a second while the focus timer runs, so every phone shows the same time.
  void _syncTicker() {
    final left = focusTimeLeft(_session, now: DateTime.now());
    final running = left != null && left > Duration.zero;
    if (running && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
    } else if (!running && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  StudySessionRsvp? _myAnswer() {
    for (final answer in _answers) {
      if (answer.email == _me) return answer;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final now = DateTime.now();
    final started = sessionHasStarted(_session, now: now);
    final tally = tallySessionAnswers(_answers);
    final mine = _myAnswer();
    final canManage = canRunTimer(
      _session,
      viewerEmail: _me,
      isAdmin: _isAdmin,
    );
    final recap = _session.recap;
    final canRecap = canWriteRecap(
      _session,
      viewerEmail: _me,
      isAdmin: _isAdmin,
      now: now,
    );

    return GroupPopScope(
      tourId: widget.tourId,
      child: Scaffold(
        appBar: AppBar(
          leading: GroupBackButton(tourId: widget.tourId),
          title: Text(_session.title),
          actions: [
            if (canManage)
              IconButton(
                tooltip: l10n.translate('study_session_edit_details'),
                icon: const Icon(Icons.edit_note_rounded),
                onPressed: _editDetails,
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              localizedDateFormat('d MMM y, h:mm a').format(_session.startsAt),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_session.place.isNotEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.place_rounded),
                title: Text(_session.place),
              ),
            if (_session.link.isNotEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.link_rounded),
                title: Text(_session.link),
              ),
            if (_session.agenda.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                l10n.translate('study_session_agenda_heading'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              StudyRichText(_session.agenda),
            ],
            const SizedBox(height: 16),
            Text(
              l10n.translate('study_session_answer_heading'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final response in StudySessionResponse.values)
                  ChoiceChip(
                    label: Text(
                      '${l10n.translate('study_session_${response.name}')} '
                      '(${l10n.number(_countFor(tally, response))})',
                    ),
                    selected: mine?.response == response,
                    onSelected: (_) => _answer(response),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (!started)
              Text(l10n.translate('study_session_not_started'))
            else if (mine?.isCheckedIn ?? false)
              Text(l10n.translate('study_session_checked_in_done'))
            else
              FilledButton.icon(
                onPressed: canCheckIn(_session, answer: mine, now: now)
                    ? _checkIn
                    : null,
                icon: const Icon(Icons.how_to_reg_rounded),
                label: Text(l10n.translate('study_session_checkin')),
              ),
            if (started)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.translate(
                    'study_session_checked_in_count',
                    args: {'count': l10n.number(tally.checkedIn)},
                  ),
                ),
              ),
            ..._roomSection(context),
            ..._timerSection(context, canManage),
            if (recap != null && !recap.isEmpty || canRecap)
              _recapSection(context, recap, canRecap),
          ],
        ),
      ),
    );
  }

  int _countFor(StudySessionTally tally, StudySessionResponse response) =>
      switch (response) {
        StudySessionResponse.going => tally.going,
        StudySessionResponse.maybe => tally.maybe,
        StudySessionResponse.cannot => tally.cannot,
      };

  List<Widget> _timerSection(BuildContext context, bool canManage) {
    final l10n = context.l10n;
    final left = focusTimeLeft(_session, now: _now);
    final running = left != null && left > Duration.zero;
    if (!running && !canManage) return const [];
    return [
      const SizedBox(height: 16),
      Text(
        l10n.translate('study_session_timer_title'),
        style: Theme.of(context).textTheme.titleSmall,
      ),
      if (running)
        Text(
          l10n.translate(
            'study_session_timer_left',
            args: {'time': _clock(context, left)},
          ),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      if (canManage)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: OutlinedButton(
            onPressed: running ? _stopTimer : _startTimer,
            child: Text(l10n.translate(running
                ? 'study_session_timer_stop'
                : 'study_session_timer_start')),
          ),
        ),
    ];
  }

  /// The time left as m:ss, in the language's digits.
  String _clock(BuildContext context, Duration left) {
    final l10n = context.l10n;
    final minutes = left.inMinutes;
    final seconds = left.inSeconds % 60;
    final secondsText = l10n.number(seconds);
    final padded = seconds < 10 ? '${l10n.number(0)}$secondsText' : secondsText;
    return '${l10n.number(minutes)}:$padded';
  }

  Widget _recapSection(
    BuildContext context,
    StudySessionRecap? recap,
    bool canRecap,
  ) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.translate('study_session_recap_heading'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (recap != null && recap.covered.isNotEmpty) ...[
            Text(l10n.translate('study_session_recap_covered')),
            StudyRichText(recap.covered),
          ],
          if (recap != null && recap.hard.isNotEmpty) ...[
            Text(l10n.translate('study_session_recap_hard')),
            StudyRichText(recap.hard),
          ],
          if (recap != null && recap.openQuestions.isNotEmpty) ...[
            Text(l10n.translate('study_session_recap_questions')),
            for (final question in recap.openQuestions)
              StudyRichText('• $question'),
          ],
          if (canRecap)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: OutlinedButton(
                onPressed: _writeRecap,
                child: Text(l10n.translate('study_session_recap_write')),
              ),
            ),
        ],
      ),
    );
  }

  /// Runs a change and says so, or says it failed.
  Future<void> _run(Future<void> Function() change, String doneKey) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await change();
      messenger.showSnackBar(SnackBar(content: Text(l10n.translate(doneKey))));
    } catch (error, stackTrace) {
      logWarning('A study session change failed', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: AppColors.amber,
      ));
    }
  }

  void _say(String key, {Map<String, Object> args = const {}}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.l10n.translate(key, args: args)),
      backgroundColor: AppColors.amber,
    ));
  }

  /// Whether the voice service is connected to this session's study room, in this tour.
  bool get _inRoom =>
      _voice.isConnected &&
      _voice.currentTourId == widget.tourId &&
      _voice.currentChannelId == studyRoomChannelId(_session.id);

  /// The study room: a voice room for this session's meeting, six people at most. It opens when the session
  /// starts and closes 24 hours after the session is taken to end.
  List<Widget> _roomSection(BuildContext context) {
    final l10n = context.l10n;
    final now = DateTime.now();
    return [
      const SizedBox(height: 16),
      Text(
        l10n.translate('study_room_title'),
        style: Theme.of(context).textTheme.titleSmall,
      ),
      if (_inRoom)
        ..._roomControls(context)
      else if (studyRoomClosed(_session, now: now))
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(l10n.translate('study_room_closed')),
        )
      else if (!studyRoomOpen(_session, now: now))
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(l10n.translate('study_room_opens')),
        )
      else
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: FilledButton.icon(
            onPressed: _joinRoom,
            icon: const Icon(Icons.headset_mic_rounded),
            label: Text(l10n.translate('study_room_join')),
          ),
        ),
    ];
  }

  /// Who is in the room, with their microphones, and the mute and leave controls. The other people's audio
  /// plays through the renderers at the end, so they stay mounted while the room is open.
  List<Widget> _roomControls(BuildContext context) {
    final l10n = context.l10n;
    return [
      StreamBuilder<List<VoiceParticipant>>(
        stream: _roomSeats,
        builder: (context, snapshot) {
          final people = snapshot.data ?? const <VoiceParticipant>[];
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(l10n.translate('study_room_people', args: {
                  'count': l10n.number(people.length),
                  'max': l10n.number(StudySessionLimits.roomMax),
                })),
                for (final person in people)
                  Chip(
                    avatar: Icon(
                      person.isAudioMuted
                          ? Icons.mic_off_rounded
                          : Icons.mic_rounded,
                      size: 16,
                    ),
                    label: Text(person.displayName),
                  ),
              ],
            ),
          );
        },
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _toggleMute,
            icon: Icon(
              _voice.isAudioMuted ? Icons.mic_rounded : Icons.mic_off_rounded,
            ),
            label: Text(l10n.translate(
              _voice.isAudioMuted ? 'study_room_unmute' : 'study_room_mute',
            )),
          ),
          TextButton.icon(
            onPressed: () => _voice.leaveVoiceRoom(),
            icon: const Icon(Icons.call_end_rounded),
            label: Text(l10n.translate('study_room_leave')),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          l10n.translate('study_room_stay'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      for (final renderer in _voice.remoteRenderers.values)
        SizedBox(
          width: 1,
          height: 1,
          child: RTCVideoView(renderer),
        ),
    ];
  }

  /// Joins this session's study room. A full room says how many it holds. The voice service leaves any other
  /// room first.
  Future<void> _joinRoom() async {
    try {
      await _voice.joinVoiceRoom(
        tourId: widget.tourId,
        channelId: studyRoomChannelId(_session.id),
        myEmail: _me,
        myName: _repository.currentDisplayName,
        myUid: _repository.currentUid,
        capacity: StudySessionLimits.roomMax,
      );
    } on VoiceRoomFullException catch (error) {
      if (mounted) {
        _say('study_room_full',
            args: {'count': context.l10n.number(error.capacity)});
      }
    } catch (error, stackTrace) {
      logWarning('The study room could not be joined', error, stackTrace);
      if (mounted) _say('study_room_failed');
    }
  }

  Future<void> _toggleMute() async {
    try {
      await _voice.toggleAudio();
    } catch (error, stackTrace) {
      logWarning('The microphone could not be switched', error, stackTrace);
    }
  }

  Future<void> _answer(StudySessionResponse response) => _run(
        () =>
            _repository.setSessionAnswer(widget.tourId, _session.id, response),
        'study_session_saved',
      );

  Future<void> _checkIn() => _run(
        () => _repository.checkInToSession(widget.tourId, _session.id),
        'study_session_checked_in',
      );

  Future<void> _startTimer() => _run(
        () => _repository.startSessionTimer(
          widget.tourId,
          _session.id,
          seconds: StudySessionLimits.focusSeconds,
        ),
        'study_session_timer_started',
      );

  Future<void> _stopTimer() => _run(
        () => _repository.stopSessionTimer(widget.tourId, _session.id),
        'study_session_saved',
      );

  /// The agenda and the meeting link. The link must be https.
  Future<void> _editDetails() async {
    final l10n = context.l10n;
    final agenda = TextEditingController(text: _session.agenda);
    final link = TextEditingController(text: _session.link);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.translate('study_session_edit_details')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StudyTextField(
                controller: agenda,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: l10n.translate('study_session_agenda_label'),
                  alignLabelWithHint: true,
                ),
              ),
              TextField(
                controller: link,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: l10n.translate('study_session_link_label'),
                  hintText: 'https://',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.translate('study_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.translate('study_save')),
          ),
        ],
      ),
    );
    final agendaText = agenda.text;
    final linkText = link.text;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      agenda.dispose();
      link.dispose();
    });
    if (saved != true || !mounted) return;
    if (!isSessionLinkValid(linkText)) {
      _say('study_session_link_invalid');
      return;
    }
    await _run(
      () => _repository.setSessionDetails(
        widget.tourId,
        _session.id,
        agenda: agendaText,
        link: linkText,
      ),
      'study_session_saved',
    );
  }

  /// The recap: what was covered, what was hard, and the open questions, one a line. Each new question
  /// becomes a thread on the book.
  Future<void> _writeRecap() async {
    final l10n = context.l10n;
    final previous = _session.recap ?? const StudySessionRecap();
    final covered = TextEditingController(text: previous.covered);
    final hard = TextEditingController(text: previous.hard);
    final questions =
        TextEditingController(text: previous.openQuestions.join('\n'));
    final draft = await showDialog<_RecapDraft>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.translate('study_session_recap_heading')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StudyTextField(
                controller: covered,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: l10n.translate('study_session_recap_covered'),
                ),
              ),
              StudyTextField(
                controller: hard,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: l10n.translate('study_session_recap_hard'),
                ),
              ),
              TextField(
                controller: questions,
                maxLines: 6,
                decoration: InputDecoration(
                  labelText: l10n.translate('study_session_recap_questions'),
                  helperText:
                      l10n.translate('study_session_recap_questions_hint'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.translate('study_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(_RecapDraft(
              covered: covered.text,
              hard: hard.text,
              questions: questions.text,
            )),
            child: Text(l10n.translate('study_save')),
          ),
        ],
      ),
    );
    SchedulerBinding.instance.addPostFrameCallback((_) {
      covered.dispose();
      hard.dispose();
      questions.dispose();
    });
    if (draft == null || !mounted) return;

    final openQuestions = cleanOpenQuestions(draft.questions.split('\n'));
    switch (openQuestionsProblem(openQuestions)) {
      case StudyRecapProblem.tooMany:
        _say('study_session_recap_too_many');
        return;
      case StudyRecapProblem.tooLong:
        _say('study_session_recap_too_long');
        return;
      case null:
        break;
    }
    final recap = StudySessionRecap(
      covered: draft.covered.trim(),
      hard: draft.hard.trim(),
      openQuestions: openQuestions,
    );
    final alreadyAsked = previous.openQuestions.toSet();
    final newQuestions = [
      for (final question in openQuestions)
        if (!alreadyAsked.contains(question)) question,
    ];
    final hasBook = _session.bookId != null;
    await _run(
      () => _repository.saveSessionRecap(
        widget.tourId,
        _session,
        recap,
        newQuestions: newQuestions,
      ),
      hasBook || newQuestions.isEmpty
          ? 'study_session_recap_saved'
          : 'study_session_recap_no_book',
    );
  }
}
