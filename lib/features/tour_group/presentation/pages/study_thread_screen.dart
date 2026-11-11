import '../widgets/group_back_button.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../chat/presentation/widgets/chat_rich_text.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/study_thread_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/study_thread_rules.dart';

import '../widgets/study/study_chat_composer.dart';
import 'package:bhromon/core/theme/colors.dart';

/// One thread on a book: its question, the replies in time order, and the actions each viewer
/// may take. The asker or an admin accepts an answer. A member marks a reply helpful once and
/// reports it once. A locked thread takes no replies.
class StudyThreadScreen extends StatefulWidget {
  const StudyThreadScreen({
    super.key,
    required this.tourId,
    required this.bookId,
    required this.bookTitle,
    required this.threadId,
    this.chapterNumberById = const {},
    this.chapterTitleById = const {},
    this.place,
    this.showBehindFence = false,
    this.repository,
  });

  final String tourId;
  final String bookId;
  final String bookTitle;
  final String threadId;

  /// The chapter numbers and titles, so the thread can name its chapter.
  final Map<String, int> chapterNumberById;
  final Map<String, String> chapterTitleById;

  /// The chapter the member is on, from this device. Null when they have not said.
  final int? place;

  /// Whether a thread past the member's place shows its body at once. The discussion list sets
  /// it, since a thread opened by a tap on its later-chapter label has been asked for.
  final bool showBehindFence;

  /// The data source. Null in the app, where the screen makes its own; tests pass one.
  final TourGroupRepository? repository;

  @override
  State<StudyThreadScreen> createState() => _StudyThreadScreenState();
}

class _StudyThreadScreenState extends State<StudyThreadScreen> {
  static const _uuid = Uuid();

  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();
  StreamSubscription<List<StudyThread>>? _threadSub;
  StreamSubscription<List<StudyReply>>? _replySub;
  TourRole? _myRole;
  StudyThread? _thread;
  bool _threadLoaded = false;
  List<StudyReply> _replies = const [];
  bool _repliesLoaded = false;
  bool _failed = false;
  bool _sending = false;
  final TextEditingController _reply = TextEditingController();

  /// Spoiler spans the viewer has revealed, by the text they belong to.
  final Map<String, Set<int>> _revealed = {};

  /// Whether the member has chosen to show a thread's body behind the fence.
  late bool _showBehindFence = widget.showBehindFence;

  String get _me => _repository.currentEmail;
  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;

  @override
  void initState() {
    super.initState();
    _repository.myRole(widget.tourId).then((role) {
      if (mounted) setState(() => _myRole = role);
    }, onError: (Object _) {});
    _threadSub =
        _repository.watchStudyThreads(widget.tourId, widget.bookId).listen(
      (threads) {
        if (!mounted) return;
        final match = threads.where((t) => t.id == widget.threadId);
        setState(() {
          _thread = match.isEmpty ? null : match.first;
          _threadLoaded = true;
        });
      },
      onError: (Object _) {
        if (mounted) setState(() => _failed = true);
      },
    );
    _replySub = _repository
        .watchStudyReplies(widget.tourId, widget.bookId, widget.threadId)
        .listen(
      (replies) {
        if (!mounted) return;
        setState(() {
          _replies = sortStudyReplies(replies);
          _repliesLoaded = true;
        });
      },
      onError: (Object _) {
        if (mounted) setState(() => _failed = true);
      },
    );
  }

  @override
  void dispose() {
    _threadSub?.cancel();
    _replySub?.cancel();
    _reply.dispose();
    super.dispose();
  }

  /// Runs one change and says how it went. A failure is logged and shown, and the screen keeps
  /// what it had.
  Future<void> _run(Future<void> Function() change, String doneKey) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await change();
      messenger.showSnackBar(SnackBar(content: Text(l10n.translate(doneKey))));
    } catch (error, stackTrace) {
      logWarning('A study thread change failed', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: AppColors.amber,
      ));
    }
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    // The reply's id is made here, so a reply sent again after a lost connection lands once.
    final replyId = _uuid.v4();
    try {
      await _repository.addStudyReply(
        widget.tourId,
        widget.bookId,
        widget.threadId,
        replyId: replyId,
        text: text,
      );
      if (mounted) _reply.clear();
    } catch (error, stackTrace) {
      logWarning('A study reply failed', error, stackTrace);
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(SnackBar(
          content: Text(context.l10n.translate('study_failed')),
          backgroundColor: AppColors.amber,
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleHelpful(StudyReply reply) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final marked = await _repository.toggleStudyReplyHelpful(
        widget.tourId,
        widget.bookId,
        widget.threadId,
        reply.id,
      );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate(
            marked ? 'study_post_helpful_done' : 'study_post_unhelpful_done')),
      ));
    } catch (error, stackTrace) {
      logWarning('A study reply vote failed', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: AppColors.amber,
      ));
    }
  }

  Future<void> _report(StudyReply reply) async {
    final l10n = context.l10n;
    final reason = await showDialog<StudyReportReason>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.translate('study_thread_report_title')),
        children: [
          for (final r in StudyReportReason.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(r),
              child: Text(l10n.translate('study_thread_reason_${r.name}')),
            ),
        ],
      ),
    );
    if (reason == null || !mounted) return;
    await _run(
      () => _repository.reportStudyReply(
        widget.tourId,
        widget.bookId,
        widget.threadId,
        reply.id,
        reason: reason,
      ),
      'study_thread_reported',
    );
  }

  Future<void> _deleteReply(StudyReply reply) async {
    final accepted = _thread?.acceptedReplyId == reply.id;
    await _run(
      () => _repository.deleteStudyReply(
        widget.tourId,
        widget.bookId,
        widget.threadId,
        reply.id,
        wasAccepted: accepted,
      ),
      'study_thread_reply_removed',
    );
  }

  Future<void> _setAccepted(StudyReply? reply) async {
    await _run(
      () => _repository.setStudyAcceptedAnswer(
        widget.tourId,
        widget.bookId,
        widget.threadId,
        replyId: reply?.id,
      ),
      reply == null ? 'study_thread_unaccepted' : 'study_thread_accepted',
    );
  }

  Future<void> _setPinned(StudyThread thread, bool pinned) async {
    final threads =
        await _repository.watchStudyThreads(widget.tourId, widget.bookId).first;
    if (pinned && !canPinMoreThreads(threads)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.l10n.translate('study_thread_pin_limit')),
      ));
      return;
    }
    await _run(
      () => _repository.setStudyThreadPinned(
        widget.tourId,
        widget.bookId,
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
        widget.bookId,
        thread.id,
        locked: locked,
      ),
      locked ? 'study_thread_locked_done' : 'study_thread_unlocked_done',
    );
  }

  Future<void> _deleteThread() async {
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
          widget.tourId, widget.bookId, widget.threadId),
      'study_thread_deleted',
    );
    if (mounted) Navigator.of(context).maybePop();
  }

  void _reveal(String key, int index) {
    setState(() => _revealed.putIfAbsent(key, () => <int>{}).add(index));
  }

  /// Whether the thread's body is hidden behind the fence: it is about a later chapter than the
  /// member's place, and they have not shown it.
  bool _hiddenBehindFence(StudyThread thread) =>
      !_showBehindFence &&
      isBehindFence(
        thread,
        chapterNumberById: widget.chapterNumberById,
        place: widget.place,
      );

  @override
  Widget build(BuildContext context) {
    final palette = context.forest;
    final thread = _thread;
    return GroupPopScope(
      tourId: widget.tourId,
      child: Scaffold(
        backgroundColor: palette.background,
        appBar: AppBar(
          leading: GroupBackButton(tourId: widget.tourId),
          title: Text(thread?.title ?? widget.bookTitle,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: palette.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
          backgroundColor: palette.card,
          foregroundColor: palette.text,
          iconTheme: IconThemeData(color: palette.text),
          elevation: 0,
          actions: [if (thread != null) _threadMenu(thread)],
        ),
        body: _body(thread),
      ),
    );
  }

  Widget _threadMenu(StudyThread thread) {
    final l10n = context.l10n;
    final palette = context.forest;
    final canDelete = _isAdmin || thread.createdByEmail == _me;
    if (!_isAdmin && !canDelete) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, color: palette.text54),
      tooltip: l10n.translate('study_thread_menu'),
      onSelected: (value) {
        switch (value) {
          case 'pin':
            _setPinned(thread, !thread.pinned);
          case 'lock':
            _setLocked(thread, !thread.locked);
          case 'delete':
            _deleteThread();
        }
      },
      itemBuilder: (_) => [
        if (_isAdmin)
          PopupMenuItem<String>(
            value: 'pin',
            child: Text(l10n.translate(
                thread.pinned ? 'study_thread_unpin' : 'study_thread_pin')),
          ),
        if (_isAdmin)
          PopupMenuItem<String>(
            value: 'lock',
            child: Text(l10n.translate(
                thread.locked ? 'study_thread_unlock' : 'study_thread_lock')),
          ),
        if (canDelete)
          PopupMenuItem<String>(
            value: 'delete',
            child: Text(l10n.translate('study_remove')),
          ),
      ],
    );
  }

  Widget _body(StudyThread? thread) {
    final l10n = context.l10n;
    final palette = context.forest;
    if (_failed) {
      return Center(
        child: Text(l10n.translate('study_failed'),
            style: TextStyle(color: palette.text70)),
      );
    }
    if (!_threadLoaded || !_repliesLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (thread == null) {
      return Center(
        child: Text(l10n.translate('study_thread_gone'),
            style: TextStyle(color: palette.text70)),
      );
    }
    final visible = [
      for (final reply in _replies)
        if (isReplyVisibleTo(reply, viewerEmail: _me, isAdmin: _isAdmin)) reply,
    ];
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              _threadCard(thread),
              const SizedBox(height: 8),
              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    l10n.translate('study_thread_no_replies'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: palette.text70),
                  ),
                ),
              for (final reply in visible) _replyCard(reply, thread),
            ],
          ),
        ),
        _composer(thread),
      ],
    );
  }

  Widget _threadCard(StudyThread thread) {
    final l10n = context.l10n;
    final palette = context.forest;
    final behind = _hiddenBehindFence(thread);
    final chapterTitle = thread.chapterId == null
        ? null
        : widget.chapterTitleById[thread.chapterId];
    final chapterNumber = thread.chapterId == null
        ? null
        : widget.chapterNumberById[thread.chapterId];
    return Card(
      color: palette.card,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (thread.pinned)
                  _chip(l10n.translate('study_thread_pinned_chip')),
                if (thread.isAnswered)
                  _chip(l10n.translate('study_thread_answered_chip')),
                if (thread.locked)
                  _chip(l10n.translate('study_thread_locked_chip')),
              ],
            ),
            if (chapterNumber != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  l10n.translate('study_chapter_chip', args: {
                    'number': l10n.number(chapterNumber),
                    'title': chapterTitle ?? '',
                  }),
                  style: TextStyle(color: palette.text54),
                ),
              ),
            if (thread.pageRef.isNotEmpty)
              Text(thread.pageRef, style: TextStyle(color: palette.text54)),
            const SizedBox(height: 8),
            if (behind)
              Row(
                children: [
                  Expanded(
                    child: Text(l10n.translate('study_thread_later_hidden'),
                        style: TextStyle(color: palette.text70)),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _showBehindFence = true),
                    child: Text(l10n.translate('study_thread_show')),
                  ),
                ],
              )
            else
              ChatRichText(
                text: thread.body,
                baseStyle: TextStyle(color: palette.text),
                revealed: _revealed['thread'],
                onSpoiler: (i) => _reveal('thread', i),
              ),
          ],
        ),
      ),
    );
  }

  Widget _replyCard(StudyReply reply, StudyThread thread) {
    final l10n = context.l10n;
    final palette = context.forest;
    final mine = reply.createdByEmail == _me;
    final accepted = thread.acceptedReplyId == reply.id;
    final canVote = canVoteOnReply(reply, viewerEmail: _me);
    final canAccept =
        canAcceptAnswer(thread, viewerEmail: _me, isAdmin: _isAdmin);
    final canDelete = _isAdmin || mine;
    final author = mine
        ? l10n.translate('study_thread_you')
        : reply.createdByEmail.startsWith('former-')
            ? l10n.translate('study_thread_former_member')
            : l10n.translate('study_thread_member');
    final key = 'reply:${reply.id}';
    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (accepted)
                  _chip(l10n.translate('study_thread_accepted_chip')),
                if (accepted) const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    reply.isReported
                        ? '$author · ${l10n.translate('study_thread_reported_label')}'
                        : author,
                    style: TextStyle(color: palette.text54, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ChatRichText(
              text: reply.text,
              baseStyle: TextStyle(color: palette.text),
              revealed: _revealed[key],
              onSpoiler: (i) => _reveal(key, i),
            ),
            Row(
              children: [
                if (canVote)
                  TextButton.icon(
                    onPressed: () => _toggleHelpful(reply),
                    icon: Icon(Icons.thumb_up_alt_outlined,
                        size: 18, color: palette.accentText),
                    label: Text(l10n.translate('study_post_helpful_label',
                        args: {'count': l10n.number(reply.helpfulCount)})),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      l10n.translate('study_post_helpful_label',
                          args: {'count': l10n.number(reply.helpfulCount)}),
                      style: TextStyle(color: palette.text54),
                    ),
                  ),
                const Spacer(),
                if (canAccept)
                  TextButton(
                    onPressed: () => _setAccepted(accepted ? null : reply),
                    child: Text(l10n.translate(accepted
                        ? 'study_thread_unaccept'
                        : 'study_thread_accept')),
                  ),
                if (canVote || canDelete)
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded, color: palette.text54),
                    tooltip: l10n.translate('study_thread_reply_menu'),
                    onSelected: (value) {
                      if (value == 'report') {
                        _report(reply);
                      } else if (value == 'delete') {
                        _deleteReply(reply);
                      }
                    },
                    itemBuilder: (_) => [
                      if (canVote)
                        PopupMenuItem<String>(
                          value: 'report',
                          child: Text(l10n.translate('study_thread_report')),
                        ),
                      if (canDelete)
                        PopupMenuItem<String>(
                          value: 'delete',
                          child: Text(l10n.translate('study_remove')),
                        ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer(StudyThread thread) {
    final l10n = context.l10n;
    final palette = context.forest;
    if (!canReplyTo(thread)) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(l10n.translate('study_thread_locked_notice'),
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.text70)),
        ),
      );
    }
    return StudyChatComposer(
      controller: _reply,
      hint: l10n.translate('study_thread_reply_hint'),
      sending: _sending,
      onSend: _send,
    );
  }

  Widget _chip(String text) {
    final palette = context.forest;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: palette.accentText.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text,
          style: TextStyle(
              color: palette.accentText,
              fontSize: 12,
              fontWeight: FontWeight.w600)),
    );
  }
}
