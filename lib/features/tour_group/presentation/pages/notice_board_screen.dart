import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/itinerary_models.dart';
import '../../domain/models/tour_activity_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/notice_engine.dart';
import '../widgets/notice/notice_composer.dart';
import '../../../../core/localization/localized_date.dart';

const _bg = Color(0xFF0F1A1C);
const _card = Color(0xFF142428);

/// "in 1h 20m", "in 3 days", "now", "25m ago".
String noticeCountdown(AppLocalizations l10n, DateTime at, DateTime now) {
  final d = at.difference(now);
  if (d.abs() <= NoticeEngine.nowWindow) return l10n.translate('notice_now');
  final past = d.isNegative;
  final a = d.abs();
  if (a.inDays >= 2) {
    return l10n.translate(past ? 'notice_ago_days' : 'notice_in_days',
        args: {'n': l10n.number(a.inDays)});
  }
  final h = a.inHours;
  final m = a.inMinutes % 60;
  if (h == 0) {
    return l10n.translate(past ? 'notice_ago_m' : 'notice_in_m',
        args: {'m': l10n.number(m)});
  }
  return l10n.translate(past ? 'notice_ago_hm' : 'notice_in_hm',
      args: {'h': l10n.number(h), 'm': l10n.number(m)});
}

/// The tour's notice board: the meeting point, what happens next and when,
/// today's schedule, and notices members answer or check in to.
class NoticeBoardScreen extends StatefulWidget {
  final String tourId;

  const NoticeBoardScreen({super.key, required this.tourId});

  @override
  State<NoticeBoardScreen> createState() => _NoticeBoardScreenState();
}

class _NoticeBoardScreenState extends State<NoticeBoardScreen> {
  final TourGroupRepository _repository = TourGroupRepository();
  final List<StreamSubscription<Object?>> _subs = [];
  Timer? _clock;

  TourGroup? _group;
  TourRole? _myRole;
  List<TourMember> _members = const [];
  List<TourNotice>? _notices;
  bool _loadFailed = false;
  NoticeFilter _filter = NoticeFilter.all;
  DateTime _now = DateTime.now();

  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;
  // In a family circle every member posts a notice; its author may delete it.
  bool get _isFamily => _group?.isFamily ?? false;
  String get _me => _repository.currentEmail;

  @override
  void initState() {
    super.initState();
    _repository.myRole(widget.tourId).then((r) {
      if (mounted) setState(() => _myRole = r);
    });
    _subs.add(_repository.watchGroup(widget.tourId).listen((g) {
      if (mounted) setState(() => _group = g);
    }, onError: (Object _) {}));
    _subs.add(_repository.watchMembers(widget.tourId).listen((m) {
      if (mounted) setState(() => _members = m);
    }, onError: (Object _) {}));
    _subs.add(_repository.watchNotices(widget.tourId).listen((n) {
      if (mounted) setState(() => _notices = n);
    }, onError: (Object _) {
      if (mounted) setState(() => _loadFailed = true);
    }));
    // Countdowns tick, and notices move to the archive as they expire.
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _clock?.cancel();
    super.dispose();
  }

  void _toast(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.redAccent : AppColors.darkGreen));
  }

  Future<void> _open(Uri? uri) async {
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String? _stopName(String? id) {
    for (final s in _group?.effectiveStops ?? const <TourStop>[]) {
      if (s.id == id) return s.name;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Meeting point
  // ---------------------------------------------------------------------------

  String _meetingTitle(AppLocalizations l10n) =>
      _group?.meetingPointTitle ??
      l10n.translate('tour_meeting_point_default', args: {
        'destination':
            _group?.destination ?? l10n.translate('tour_default_destination'),
      });

  Uri get _meetingMapUri => Uri.parse(_group?.meetingPointMapUrl ??
      'https://maps.google.com/?q=${Uri.encodeComponent(_group?.meetingPointTitle ?? _group?.destination ?? 'Hotel Lobby')}');

  Future<void> _editMeetingPoint() async {
    final l10n = context.l10n;
    final titleCtrl =
        TextEditingController(text: _group?.meetingPointTitle ?? '');
    final noteCtrl =
        TextEditingController(text: _group?.meetingPointNote ?? '');
    final urlCtrl =
        TextEditingController(text: _group?.meetingPointMapUrl ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text(l10n.translate('tour_edit_meeting_point'),
            style: const TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                    labelText: l10n.translate('tour_place_name')),
              ),
              TextField(
                controller: noteCtrl,
                style: const TextStyle(color: Colors.white),
                decoration:
                    InputDecoration(labelText: l10n.translate('tour_details')),
              ),
              TextField(
                controller: urlCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                    labelText: l10n.translate('tour_map_link_label')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.translate('tour_cancel'))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.translate('tour_save'))),
        ],
      ),
    );
    final title = titleCtrl.text;
    final note = noteCtrl.text;
    final url = urlCtrl.text.trim();
    titleCtrl.dispose();
    noteCtrl.dispose();
    urlCtrl.dispose();
    if (saved != true) return;
    if (url.isNotEmpty && !url.startsWith('https://')) {
      _toast(l10n.translate('tour_map_link_needs_https'), error: true);
      return;
    }
    try {
      await _repository.updateMeetingPoint(widget.tourId,
          title: title, note: note, mapUrl: url);
    } catch (e) {
      _toast(
          l10n.translate('tour_meeting_point_save_failed', args: {'error': e}),
          error: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Notice actions
  // ---------------------------------------------------------------------------

  Future<void> _compose({TourNotice? existing, bool duplicate = false}) async {
    final l10n = context.l10n;
    final draft =
        await showNoticeComposer(context, group: _group, existing: existing);
    if (draft == null) return;
    try {
      if (existing == null || duplicate) {
        await _repository.postNotice(widget.tourId, draft);
      } else {
        await _repository.updateNotice(widget.tourId, draft);
      }
    } catch (_) {
      final key = existing == null || duplicate
          ? (_isFamily ? 'notice_post_failed' : 'tour_notice_post_admin_only')
          : 'tour_notice_update_admin_only';
      _toast(l10n.translate(key), error: true);
    }
  }

  Future<void> _answer(TourNotice n, bool answered, {String? email}) async {
    try {
      await _repository.answerNotice(widget.tourId, n.id,
          email: email, answered: answered);
    } catch (_) {
      if (mounted) {
        _toast(context.l10n.translate('notice_answer_failed'), error: true);
      }
    }
  }

  Future<void> _delete(TourNotice n) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: _card,
        title: Text(l10n.translate('tour_delete_notice'),
            style: const TextStyle(color: Colors.white)),
        content: Text(n.title, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l10n.translate('tour_cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(l10n.translate('fund_delete'),
                  style: const TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repository.deleteNotice(widget.tourId, n.id);
    } catch (_) {
      _toast(l10n.translate('tour_notice_delete_failed'), error: true);
    }
  }

  String _shareLine(AppLocalizations l10n, TourNotice n) {
    final lines = [
      '${n.kind.emoji} ${n.title}',
      if (n.eventAt != null)
        '🕒 ${localizedDateFormat('EEE d MMM, h:mm a').format(n.eventAt!)}',
      if (n.place != null) '📍 ${n.place}',
      if (n.content.isNotEmpty) n.content,
      if (NoticeEngine.mapUri(n) != null) NoticeEngine.mapUri(n).toString(),
    ];
    return lines.join('\n');
  }

  void _share(TourNotice n) {
    final l10n = context.l10n;
    // ignore: deprecated_member_use
    Share.share('${_shareLine(l10n, n)}\n\n— ${_group?.name ?? ''}',
        subject: n.title);
  }

  void _shareSchedule(List<TourNotice> today) {
    final l10n = context.l10n;
    final lines = [
      l10n.translate('notice_today_share_title', args: {
        'tour': _group?.name ?? '',
        'date': localizedDateFormat('EEE d MMM').format(_now),
      }),
      '',
      for (final n in today)
        '${localizedDateFormat('h:mm a').format(n.eventAt!)}  ${n.kind.emoji} ${n.title}'
            '${n.place == null ? '' : ' · ${n.place}'}',
    ];
    // ignore: deprecated_member_use
    Share.share(lines.join('\n'), subject: _group?.name);
  }

  void _menu(TourNotice n) {
    final l10n = context.l10n;
    final cal = NoticeEngine.calendarUri(n, tourName: _group?.name);
    Widget item(IconData icon, String label, VoidCallback onTap,
            {Color color = Colors.white70}) =>
        ListTile(
          leading: Icon(icon, color: color),
          title: Text(label, style: const TextStyle(color: Colors.white)),
          onTap: () {
            Navigator.pop(context);
            onTap();
          },
        );
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _card,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            item(Icons.share_rounded, l10n.translate('notice_share'),
                () => _share(n)),
            if (cal != null)
              item(Icons.event_available_rounded,
                  l10n.translate('notice_add_calendar'), () => _open(cal)),
            if (n.asksAnswer)
              item(Icons.groups_rounded, l10n.translate('notice_answers'),
                  () => _answersSheet(n)),
            if (_isAdmin) ...[
              item(Icons.edit_rounded, l10n.translate('fund_edit'),
                  () => _compose(existing: n),
                  color: AppColors.mintGreen),
              item(
                  n.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                  l10n.translate(n.pinned ? 'notice_unpin' : 'notice_pin'),
                  () => _repository
                      .setNoticePinned(widget.tourId, n.id, !n.pinned)
                      .catchError((Object _) {})),
              item(Icons.copy_rounded, l10n.translate('fund_duplicate'),
                  () => _compose(existing: n, duplicate: true)),
            ],
            if (_isAdmin || (_isFamily && n.authorEmail == _me))
              item(Icons.delete_outline_rounded,
                  l10n.translate('tour_delete_notice'), () => _delete(n),
                  color: Colors.redAccent),
          ],
        ),
      ),
    );
  }

  /// Who answered and who has not. Admins can mark someone present (for a
  /// member without a phone) and share the list of who is missing.
  void _answersSheet(TourNotice notice) {
    final l10n = context.l10n;
    // The sheet follows answers as they come in.
    final live = _repository.watchNotices(widget.tourId);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _card,
      isScrollControlled: true,
      builder: (ctx) => StreamBuilder<List<TourNotice>>(
        stream: live,
        builder: (ctx, snap) {
          final n =
              snap.data?.where((x) => x.id == notice.id).firstOrNull ?? notice;
          final a = NoticeEngine.answers(n, _members);
          final rollcall = n.kind == NoticeKind.rollcall;
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            builder: (ctx, scroll) => ListView(
              controller: scroll,
              padding: const EdgeInsets.all(16),
              children: [
                Text(n.title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _progress(l10n, a, rollcall),
                const SizedBox(height: 12),
                if (a.waiting.isNotEmpty) ...[
                  Row(children: [
                    Expanded(
                      child: Text(
                          l10n.translate(
                              rollcall ? 'notice_missing' : 'notice_waiting',
                              args: {'n': l10n.number(a.waiting.length)}),
                          style: const TextStyle(
                              color: AppColors.gold,
                              fontWeight: FontWeight.bold)),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        // ignore: deprecated_member_use
                        Share.share([
                          '${n.kind.emoji} ${n.title}',
                          l10n.translate(
                              rollcall ? 'notice_missing' : 'notice_waiting',
                              args: {'n': l10n.number(a.waiting.length)}),
                          for (final m in a.waiting) '• ${m.displayName}',
                        ].join('\n'));
                      },
                      icon: const Icon(Icons.share_rounded,
                          size: 16, color: AppColors.gold),
                      label: Text(l10n.translate('notice_share'),
                          style: const TextStyle(color: AppColors.gold)),
                    ),
                  ]),
                  for (final m in a.waiting)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.hourglass_top_rounded,
                          color: AppColors.gold, size: 20),
                      title: Text(m.displayName,
                          style: const TextStyle(color: Colors.white)),
                      subtitle: m.familyCount > 1
                          ? Text(
                              l10n.translate('fund_family_of',
                                  args: {'n': l10n.number(m.familyCount)}),
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11))
                          : null,
                      trailing: _isAdmin
                          ? TextButton(
                              onPressed: () => _answer(n, true, email: m.email),
                              child: Text(
                                  l10n.translate(rollcall
                                      ? 'notice_mark_present'
                                      : 'notice_mark_answered'),
                                  style: const TextStyle(
                                      color: AppColors.mintGreen)),
                            )
                          : null,
                    ),
                  const Divider(color: Colors.white12),
                ],
                Text(
                    l10n.translate(
                        rollcall ? 'notice_present' : 'notice_answered',
                        args: {'n': l10n.number(a.answered.length)}),
                    style: const TextStyle(
                        color: AppColors.mintGreen,
                        fontWeight: FontWeight.bold)),
                for (final m in a.answered)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.check_circle_rounded,
                        color: AppColors.mintGreen, size: 20),
                    title: Text(m.displayName,
                        style: const TextStyle(color: Colors.white)),
                    trailing: _isAdmin && m.email != _me
                        ? IconButton(
                            tooltip: l10n.translate('notice_undo'),
                            icon: const Icon(Icons.undo_rounded,
                                color: Colors.white38, size: 18),
                            onPressed: () => _answer(n, false, email: m.email),
                          )
                        : null,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final notices = _notices;
    final today = notices == null
        ? const <TourNotice>[]
        : NoticeEngine.scheduleOn(notices, _now);
    final needsMe = notices == null
        ? 0
        : notices.where((n) => NoticeEngine.needsMe(n, _me, _now)).length;
    final next = notices == null ? null : NoticeEngine.nextUp(notices, _now);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text(l10n.translate('tour_notice_board_title'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: _card,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (today.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.ios_share_rounded),
              tooltip: l10n.translate('notice_share_today'),
              onPressed: () => _shareSchedule(today),
            ),
        ],
      ),
      floatingActionButton: _isAdmin || _isFamily
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.mintGreen,
              foregroundColor: AppColors.darkGreen,
              icon: const Icon(Icons.add_alert_rounded),
              label: Text(l10n.translate('tour_notice_new')),
              onPressed: () => _compose(),
            )
          : null,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            if (next != null) _nextUp(l10n, next),
            _meetingPoint(l10n),
            if (today.isNotEmpty) _todaySchedule(l10n, today),
            const SizedBox(height: 4),
            _filters(l10n, needsMe),
            const SizedBox(height: 8),
            ..._list(l10n),
          ],
        ),
      ),
    );
  }

  Widget _nextUp(AppLocalizations l10n, TourNotice n) {
    final color = noticeKindColor(n.kind);
    final live = NoticeEngine.timing(n, _now) == NoticeTiming.now;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          color.withValues(alpha: 0.28),
          _card,
        ], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.translate(live ? 'notice_happening_now' : 'notice_next_up'),
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(n.kind.emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n.title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold)),
                    Text(
                        '${localizedDateFormat('EEE, h:mm a').format(n.eventAt!)}'
                        '${n.place == null ? '' : ' · ${n.place}'}',
                        style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
              Text(noticeCountdown(l10n, n.eventAt!, _now),
                  style: TextStyle(
                      color: color, fontSize: 18, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            if (n.asksAnswer) _answerButton(l10n, n),
            if (NoticeEngine.mapUri(n) != null)
              OutlinedButton.icon(
                onPressed: () => _open(NoticeEngine.mapUri(n)),
                icon: const Icon(Icons.navigation_rounded, size: 16),
                label: Text(l10n.translate('tour_view_on_map')),
              ),
          ]),
        ],
      ),
    );
  }

  Widget _meetingPoint(AppLocalizations l10n) {
    final note = _group?.meetingPointNote ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.place_rounded, color: Colors.amber),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.translate('tour_live_meeting_point'),
                    style: const TextStyle(color: Colors.amber, fontSize: 11)),
                Text(_meetingTitle(l10n),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                if (note.isNotEmpty)
                  Text(note,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            tooltip: l10n.translate('tour_view_on_map'),
            icon: const Icon(Icons.navigation_rounded,
                color: AppColors.mintGreen),
            onPressed: () => _open(_meetingMapUri),
          ),
          if (_isAdmin)
            IconButton(
              tooltip: l10n.translate('tour_edit_meeting_point'),
              icon: const Icon(Icons.edit_rounded,
                  size: 18, color: Colors.white54),
              onPressed: _editMeetingPoint,
            ),
        ],
      ),
    );
  }

  Widget _todaySchedule(AppLocalizations l10n, List<TourNotice> today) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.translate('notice_today'),
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          for (final (i, n) in today.indexed)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(
                        localizedDateFormat('h:mm a').format(n.eventAt!),
                        style: TextStyle(
                            color: n.eventAt!.isBefore(_now)
                                ? Colors.white38
                                : AppColors.mintGreen,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ),
                  Column(children: [
                    Icon(
                        n.eventAt!
                                .isBefore(_now.subtract(NoticeEngine.nowWindow))
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        size: 14,
                        color: noticeKindColor(n.kind)),
                    if (i < today.length - 1)
                      Expanded(
                          child: Container(width: 2, color: Colors.white12)),
                  ]),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        '${n.kind.emoji} ${n.title}'
                        '${n.place == null ? '' : ' · ${n.place}'}',
                        style: TextStyle(
                            color: n.eventAt!.isBefore(
                                    _now.subtract(NoticeEngine.nowWindow))
                                ? Colors.white38
                                : Colors.white,
                            fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _filters(AppLocalizations l10n, int needsMe) {
    String label(NoticeFilter f) {
      final text = l10n.translate('notice_filter_${f.name}');
      return f == NoticeFilter.needsMe && needsMe > 0
          ? '$text (${l10n.number(needsMe)})'
          : text;
    }

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final f in NoticeFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(label(f), style: const TextStyle(fontSize: 12)),
                selected: _filter == f,
                selectedColor: f == NoticeFilter.needsMe && needsMe > 0
                    ? AppColors.gold
                    : AppColors.mintGreen,
                backgroundColor: _card,
                labelStyle: TextStyle(
                    color: _filter == f
                        ? AppColors.darkGreen
                        : (f == NoticeFilter.needsMe && needsMe > 0
                            ? AppColors.gold
                            : Colors.white)),
                onSelected: (_) => setState(() => _filter = f),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _list(AppLocalizations l10n) {
    final notices = _notices;
    if (notices == null) {
      return [
        _loadFailed
            ? Text(l10n.translate('tour_notices_load_failed'),
                style: const TextStyle(color: Colors.white54))
            : const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: AppColors.mintGreen),
                ),
              ),
      ];
    }
    final shown = NoticeEngine.filter(notices, _filter, me: _me, now: _now);
    if (shown.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Text(
              l10n.translate(
                  notices.isEmpty ? 'tour_no_notices' : 'notice_filter_empty'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54)),
        ),
      ];
    }
    return [for (final n in shown) _noticeCard(l10n, n)];
  }

  Widget _answerButton(AppLocalizations l10n, TourNotice n) {
    final done = n.ackedBy(_me);
    final rollcall = n.kind == NoticeKind.rollcall;
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: done ? Colors.white12 : AppColors.mintGreen,
        foregroundColor: done ? AppColors.mintGreen : AppColors.darkGreen,
        visualDensity: VisualDensity.compact,
      ),
      onPressed:
          NoticeEngine.isArchived(n, _now) ? null : () => _answer(n, !done),
      icon:
          Icon(done ? Icons.check_rounded : Icons.front_hand_rounded, size: 18),
      label: Text(l10n.translate(rollcall
          ? (done ? 'notice_im_here_done' : 'notice_im_here')
          : (done ? 'notice_got_it_done' : 'notice_got_it'))),
    );
  }

  Widget _progress(AppLocalizations l10n, NoticeAnswers a, bool rollcall) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.translate(rollcall ? 'notice_present_of' : 'notice_answered_of',
              args: {
                'n': l10n.number(a.answered.length),
                'total': l10n.number(a.total),
              }),
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: a.ratio,
            minHeight: 6,
            color: a.waiting.isEmpty ? AppColors.mintGreen : AppColors.gold,
            backgroundColor: Colors.white10,
          ),
        ),
      ],
    );
  }

  Widget _noticeCard(AppLocalizations l10n, TourNotice n) {
    final color = noticeKindColor(n.kind);
    final archived = NoticeEngine.isArchived(n, _now);
    final hot = !archived && (n.urgent || n.kind == NoticeKind.emergency);
    final stop = _stopName(n.stopId);
    final mapUri = NoticeEngine.mapUri(n);
    final timing = NoticeEngine.timing(n, _now);

    return Opacity(
      opacity: archived ? 0.6 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: hot ? Colors.redAccent.withValues(alpha: 0.08) : _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: hot
                  ? Colors.redAccent.withValues(alpha: 0.6)
                  : (n.pinned
                      ? AppColors.mintGreen.withValues(alpha: 0.5)
                      : Colors.white12)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _menu(n),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                        '${n.kind.emoji} ${noticeKindLabel(l10n, n.kind)}',
                        style: TextStyle(color: color, fontSize: 11)),
                  ),
                  if (stop != null) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('· $stop',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 11)),
                    ),
                  ],
                  const Spacer(),
                  if (n.pinned)
                    const Icon(Icons.push_pin_rounded,
                        size: 16, color: AppColors.mintGreen),
                  if (hot)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.warning_amber_rounded,
                          color: Colors.redAccent, size: 18),
                    ),
                  const Icon(Icons.more_vert_rounded,
                      size: 18, color: Colors.white38),
                ]),
                const SizedBox(height: 8),
                Text(n.title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                if (n.content.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(n.content,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
                if (n.eventAt != null || n.place != null) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 10, runSpacing: 4, children: [
                    if (n.eventAt != null)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.schedule_rounded,
                            size: 15, color: AppColors.gold),
                        const SizedBox(width: 4),
                        Text(
                            localizedDateFormat('EEE d MMM, h:mm a')
                                .format(n.eventAt!),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12)),
                        if (!archived) ...[
                          const SizedBox(width: 6),
                          Text(noticeCountdown(l10n, n.eventAt!, _now),
                              style: TextStyle(
                                  color: timing == NoticeTiming.past
                                      ? Colors.white38
                                      : AppColors.gold,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ]),
                    if (n.place != null)
                      InkWell(
                        onTap: mapUri == null ? null : () => _open(mapUri),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.place_rounded,
                              size: 15, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(n.place!,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  decoration: mapUri == null
                                      ? null
                                      : TextDecoration.underline)),
                        ]),
                      ),
                  ]),
                ],
                if (n.asksAnswer) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    _answerButton(l10n, n),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () => _answersSheet(n),
                        child: _progress(
                            l10n,
                            NoticeEngine.answers(n, _members),
                            n.kind == NoticeKind.rollcall),
                      ),
                    ),
                  ]),
                ],
                const SizedBox(height: 8),
                Text(
                    l10n.translate('tour_notice_sender', args: {
                      'author': n.author,
                      'date': localizedDateFormat('dd MMM, hh:mm a')
                          .format(n.createdAt),
                    }),
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
