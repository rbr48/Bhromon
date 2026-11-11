import '../widgets/group_back_button.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../../core/utils/app_logger.dart';
import '../../data/study_reading_position.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/study_models.dart';
import '../../domain/models/study_thread_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/study_chapter_rules.dart';
import '../../domain/services/study_thread_rules.dart';
import '../widgets/study/study_chat_composer.dart';
import '../widgets/study/study_thread_composer.dart';
import 'study_thread_screen.dart';
import 'package:bhromon/core/theme/colors.dart';

/// The discussions of a study book, opened as a conversation: the threads members have started, in
/// chat order (pinned ones first, the newest at the foot), with the chat box under them. A member
/// posts from the box, and anyone opens a thread. A thread about a later chapter than the member's
/// place shows only a "later chapter" label until it is opened, when the fence is on. An admin pins
/// and locks threads.
class StudyDiscussionScreen extends StatefulWidget {
  const StudyDiscussionScreen({
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

  /// Where the member is in the book and whether the fence is on, kept on this device. Null in
  /// the app; tests pass one.
  final StudyReadingPosition? position;

  @override
  State<StudyDiscussionScreen> createState() => _StudyDiscussionScreenState();
}

class _StudyDiscussionScreenState extends State<StudyDiscussionScreen> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();
  late final StudyReadingPosition _position =
      widget.position ?? StudyReadingPosition();
  StreamSubscription<List<StudyThread>>? _threadSub;
  StreamSubscription<List<StudyChapter>>? _chapterSub;

  TourRole? _myRole;
  List<StudyThread> _threads = const [];
  bool _threadsLoaded = false;
  bool _failed = false;
  List<StudyChapter> _chapters = const [];
  Map<String, int> _chapterNumberById = const {};
  Map<String, String> _chapterTitleById = const {};
  int? _place;
  bool _fenceOn = true;
  bool _searching = false;
  String _query = '';
  final TextEditingController _draft = TextEditingController();
  bool _posting = false;

  String get _me => _repository.currentEmail;
  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;

  @override
  void initState() {
    super.initState();
    _repository.myRole(widget.tourId).then((role) {
      if (mounted) setState(() => _myRole = role);
    }, onError: (Object _) {});
    _threadSub =
        _repository.watchStudyThreads(widget.tourId, widget.book.id).listen(
      (threads) {
        if (!mounted) return;
        setState(() {
          _threads = sortStudyThreads(threads);
          _threadsLoaded = true;
          _failed = false;
        });
      },
      onError: (Object _) {
        if (mounted) setState(() => _failed = true);
      },
    );
    _chapterSub =
        _repository.watchStudyChapters(widget.tourId, widget.book.id).listen(
      (chapters) {
        if (!mounted) return;
        final sorted = sortStudyChapters(chapters);
        setState(() {
          _chapters = sorted;
          _chapterNumberById = {for (final c in sorted) c.id: c.number};
          _chapterTitleById = {for (final c in sorted) c.id: c.title};
        });
      },
      onError: (Object _) {},
    );
    _position
        .load(tourId: widget.tourId, bookId: widget.book.id)
        .then((number) {
      if (mounted) setState(() => _place = number);
    });
    _position.loadFence().then((on) {
      if (mounted) setState(() => _fenceOn = on);
    });
  }

  @override
  void dispose() {
    _threadSub?.cancel();
    _chapterSub?.cancel();
    _draft.dispose();
    super.dispose();
  }

  /// Whether a thread waits behind the fence: the fence is on, and the thread is about a later
  /// chapter than the member's place.
  bool _behindFence(StudyThread thread) =>
      _fenceOn &&
      isBehindFence(
        thread,
        chapterNumberById: _chapterNumberById,
        place: _place,
      );

  Future<void> _run(Future<void> Function() change, String doneKey) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await change();
      messenger.showSnackBar(SnackBar(content: Text(l10n.translate(doneKey))));
    } catch (error, stackTrace) {
      logWarning('A study discussion change failed', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: AppColors.amber,
      ));
    }
  }

  /// Whether a member may start another thread today. Says so when they may not.
  bool _withinDailyLimit() {
    if (canStartThreadToday(_threads, email: _me, now: DateTime.now())) {
      return true;
    }
    final l10n = context.l10n;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(l10n.translate('study_thread_daily_limit',
          args: {'count': l10n.number(kThreadsPerDayMax)})),
    ));
    return false;
  }

  /// Saves a new thread. Returns whether it was saved; a failure is logged and shown.
  Future<bool> _post({
    required String title,
    required String body,
    required String pageRef,
    required String? chapterId,
  }) async {
    setState(() => _posting = true);
    try {
      await _repository.addStudyThread(
        widget.tourId,
        widget.book.id,
        title: title,
        body: body,
        pageRef: pageRef,
        chapterId: chapterId,
      );
      return true;
    } catch (error, stackTrace) {
      logWarning('A study thread failed to post', error, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.l10n.translate('study_failed')),
          backgroundColor: AppColors.amber,
        ));
      }
      return false;
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  /// A member posts what is in the chat box as a new thread. Its first line is the title.
  Future<void> _sendDraft() async {
    final text = _draft.text.trim();
    if (text.isEmpty || _posting || !_withinDailyLimit()) return;
    final parts = threadTitleAndBody(text);
    final saved = await _post(
      title: parts.title,
      body: parts.body,
      pageRef: '',
      chapterId: null,
    );
    if (saved && mounted) _draft.clear();
  }

  /// The chapter and page choices. The form opens with what is in the chat box, and the thread is
  /// saved only when the member posts it there.
  Future<void> _openDetails() async {
    if (_posting || !_withinDailyLimit()) return;
    final typed = _draft.text.trim();
    final parts = typed.isEmpty ? null : threadTitleAndBody(typed);
    final draft = await showStudyThreadComposer(
      context,
      chapters: _chapters,
      initialTitle: parts?.title ?? '',
      initialBody: parts?.body ?? '',
    );
    if (draft == null || !mounted) return;
    final saved = await _post(
      title: draft.title,
      body: draft.body,
      pageRef: draft.pageRef,
      chapterId: draft.chapterId,
    );
    if (saved && mounted) _draft.clear();
  }

  Future<void> _setPinned(StudyThread thread, bool pinned) async {
    if (pinned && !canPinMoreThreads(_threads)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.l10n.translate('study_thread_pin_limit')),
      ));
      return;
    }
    await _run(
      () => _repository.setStudyThreadPinned(
        widget.tourId,
        widget.book.id,
        thread.id,
        pinned: pinned,
      ),
      pinned ? 'study_thread_pinned' : 'study_thread_unpinned',
    );
  }

  Future<void> _setLocked(StudyThread thread, bool locked) async {
    await _run(
      () => _repository.setStudyThreadLocked(
        widget.tourId,
        widget.book.id,
        thread.id,
        locked: locked,
      ),
      locked ? 'study_thread_locked_done' : 'study_thread_unlocked_done',
    );
  }

  Future<void> _deleteThread(StudyThread thread) async {
    final l10n = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('study_thread_delete_title')),
        content: Text(l10n.translate('study_thread_delete_body')),
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
      () => _repository.deleteStudyThread(
          widget.tourId, widget.book.id, thread.id),
      'study_thread_deleted',
    );
  }

  void _open(StudyThread thread) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StudyThreadScreen(
        tourId: widget.tourId,
        bookId: widget.book.id,
        bookTitle: widget.book.title,
        threadId: thread.id,
        chapterNumberById: _chapterNumberById,
        chapterTitleById: _chapterTitleById,
        place: _place,
        // Opening a thread from the list is the member's choice to read it.
        showBehindFence: true,
        repository: _repository,
      ),
    ));
  }

  Future<void> _toggleFence() async {
    final next = !_fenceOn;
    setState(() => _fenceOn = next);
    await _position.saveFence(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final shown = searchStudyThreads(_threads, _query);
    return GroupPopScope(
      tourId: widget.tourId,
      child: Scaffold(
        backgroundColor: palette.background,
        appBar: AppBar(
          leading: GroupBackButton(tourId: widget.tourId),
          title: Text(l10n.translate('study_discussion_title'),
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
              tooltip: l10n.translate('study_discussion_search'),
              icon: const Icon(Icons.search_rounded),
              onPressed: () => setState(() {
                _searching = !_searching;
                if (!_searching) _query = '';
              }),
            ),
            if (_place != null)
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, color: palette.text54),
                tooltip: l10n.translate('study_discussion_menu'),
                onSelected: (_) => _toggleFence(),
                itemBuilder: (_) => [
                  PopupMenuItem<String>(
                    value: 'fence',
                    child: Text(l10n.translate(_fenceOn
                        ? 'study_fence_show_all'
                        : 'study_fence_hide_later')),
                  ),
                ],
              ),
          ],
        ),
        body: Column(
          children: [
            if (_searching)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextField(
                  autofocus: true,
                  style: TextStyle(color: palette.text),
                  decoration: InputDecoration(
                    hintText: l10n.translate('study_discussion_search_hint'),
                    prefixIcon: const Icon(Icons.search_rounded),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
            Expanded(child: _list(shown)),
            StudyChatComposer(
              controller: _draft,
              hint: l10n.translate('study_discussion_hint'),
              sending: _posting,
              onSend: _sendDraft,
              onDetails: _openDetails,
              detailsTooltip: l10n.translate('study_thread_details'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(List<StudyThread> shown) {
    final l10n = context.l10n;
    final palette = context.forest;
    if (_failed) {
      return Center(
        child: Text(l10n.translate('study_failed'),
            style: TextStyle(color: palette.text70)),
      );
    }
    if (!_threadsLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_threads.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.translate('study_discussion_empty'),
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.text70),
          ),
        ),
      );
    }
    if (shown.isEmpty) {
      return Center(
        child: Text(l10n.translate('study_discussion_no_match'),
            style: TextStyle(color: palette.text70)),
      );
    }
    // The newest thread is at the foot, and the list starts there, as a chat does.
    return ListView(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      children: [
        for (final thread in chatOrderStudyThreads(shown).reversed)
          _tile(thread),
      ],
    );
  }

  Widget _tile(StudyThread thread) {
    final l10n = context.l10n;
    final palette = context.forest;
    final behind = _behindFence(thread);
    final chapterTitle =
        thread.chapterId == null ? null : _chapterTitleById[thread.chapterId];
    final chapterNumber =
        thread.chapterId == null ? null : _chapterNumberById[thread.chapterId];
    final subtitle = behind
        ? l10n.translate('study_thread_later_chapter')
        : [
            if (chapterNumber != null)
              l10n.translate('study_chapter_chip', args: {
                'number': l10n.number(chapterNumber),
                'title': chapterTitle ?? '',
              }),
            if (thread.isAnswered) l10n.translate('study_thread_answered_chip'),
            if (thread.locked) l10n.translate('study_thread_locked_chip'),
          ].join(' · ');
    final canDelete = _isAdmin || thread.createdByEmail == _me;
    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => _open(thread),
        leading: thread.pinned
            ? Icon(Icons.push_pin_rounded, color: palette.accentText)
            : null,
        title: Text(
          behind ? l10n.translate('study_thread_later_title') : thread.title,
          style: TextStyle(color: palette.text, fontWeight: FontWeight.w600),
        ),
        subtitle: subtitle.isEmpty
            ? null
            : Text(subtitle, style: TextStyle(color: palette.text54)),
        trailing: _isAdmin || canDelete
            ? PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, color: palette.text54),
                tooltip: l10n.translate('study_thread_menu'),
                onSelected: (value) {
                  switch (value) {
                    case 'pin':
                      _setPinned(thread, !thread.pinned);
                    case 'lock':
                      _setLocked(thread, !thread.locked);
                    case 'delete':
                      _deleteThread(thread);
                  }
                },
                itemBuilder: (_) => [
                  if (_isAdmin)
                    PopupMenuItem<String>(
                      value: 'pin',
                      child: Text(l10n.translate(thread.pinned
                          ? 'study_thread_unpin'
                          : 'study_thread_pin')),
                    ),
                  if (_isAdmin)
                    PopupMenuItem<String>(
                      value: 'lock',
                      child: Text(l10n.translate(thread.locked
                          ? 'study_thread_unlock'
                          : 'study_thread_lock')),
                    ),
                  if (canDelete)
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
