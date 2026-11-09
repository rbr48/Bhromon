import 'dart:async';

import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:flutter/material.dart';
import '../widgets/group_back_button.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../data/notice_read_aloud.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/itinerary_models.dart';
import '../../domain/models/tour_activity_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/destination_catalog.dart';
import '../../domain/services/notice_engine.dart';
import '../../domain/services/notice_speech.dart';
import '../widgets/notice/notice_composer.dart';
import '../../../../core/localization/localized_date.dart';
import '../../../../core/widgets/swipe_step.dart';

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
  bool get _hasManagedNotices => _group?.hasManagedNotices ?? false;

  /// Members of a family circle post notices. An office, a campus or a mess reserves
  /// them for its owner and admins.
  bool get _membersPost => _isFamily && !_hasManagedNotices;
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
    if (NoticeReadAloud.instance.playingId.value != null) {
      unawaited(NoticeReadAloud.instance.stop());
    }
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

  String _effectiveDestination(AppLocalizations l10n) {
    final raw = _group?.currentDestination(_now) ??
        _group?.destination ??
        l10n.translate('tour_default_destination');
    final preset = presetForName(raw);
    if (preset != null) {
      return preset.nameFor(l10n.locale.languageCode);
    }
    return raw;
  }

  String _meetingTitle(AppLocalizations l10n) {
    if (_group?.meetingPointTitle != null &&
        _group!.meetingPointTitle!.trim().isNotEmpty) {
      return _group!.meetingPointTitle!;
    }
    final g = _group;
    if (g != null) {
      if (g.isOffice) return l10n.translate('tour_meeting_point_office');
      if (g.isCampus) return l10n.translate('tour_meeting_point_campus');
      if (g.isMess) return l10n.translate('tour_meeting_point_mess');
      if (g.isSociety) return l10n.translate('tour_meeting_point_society');
      if (g.isSamity) return l10n.translate('tour_meeting_point_samity');
      if (g.isStudy) return l10n.translate('tour_meeting_point_study');
      if (g.isFriends) return l10n.translate('tour_meeting_point_friends');
      if (g.isSchool) return l10n.translate('tour_meeting_point_school');
      if (g.isSports) return l10n.translate('tour_meeting_point_sports');
      if (g.isCommittee) return l10n.translate('tour_meeting_point_committee');
      if (g.isHousehold) return l10n.translate('tour_meeting_point_family');
    }
    return l10n.translate('tour_meeting_point_default', args: {
      'destination': _effectiveDestination(l10n),
    });
  }

  Uri get _meetingMapUri {
    final g = _group;
    String fallback;
    if (g != null) {
      if (g.isOffice) {
        fallback = '${g.name} Office';
      } else if (g.isCampus) {
        fallback = '${g.name} Campus';
      } else if (g.isMess) {
        fallback = '${g.name} Mess';
      } else if (g.isSociety) {
        fallback = '${g.name} Community Hall';
      } else if (g.isSamity) {
        fallback = '${g.name} Meeting Venue';
      } else if (g.isStudy) {
        fallback = '${g.name} Library';
      } else if (g.isFriends) {
        fallback = '${g.name} Hangout Spot';
      } else if (g.isSchool) {
        fallback = '${g.name} School';
      } else if (g.isSports) {
        fallback = '${g.name} Sports Ground';
      } else if (g.isCommittee) {
        fallback = '${g.name} Community Center';
      } else if (g.isHousehold) {
        fallback = '${g.name} Residence';
      } else {
        final cur = g.currentDestination(_now);
        fallback = cur.isNotEmpty
            ? cur
            : (g.destination.isNotEmpty ? g.destination : 'Meeting Point');
      }
    } else {
      fallback = 'Meeting Point';
    }
    final dest = _group?.meetingPointTitle ?? fallback;
    return Uri.parse(_group?.meetingPointMapUrl ??
        'https://maps.google.com/?q=${Uri.encodeComponent(dest)}');
  }

  List<String> _meetingSuggestions(AppLocalizations l10n) {
    final g = _group;
    final isBn = l10n.locale.languageCode == 'bn';
    if (g == null) return const [];
    if (g.isOffice) {
      return isBn
          ? const [
              'কনফারেন্স রুম ১',
              'অফিস রিসেপশন',
              'ক্যাফেটেরিয়া',
              'মিটিং রুম'
            ]
          : const [
              'Conference Room 1',
              'Office Reception',
              'Main Cafeteria',
              'Meeting Room A'
            ];
    }
    if (g.isCampus) {
      return isBn
          ? const [
              'ক্যাম্পাস মূল ফটক',
              'ডিপার্টমেন্ট করিডোর',
              'ক্যাম্পাস ক্যান্টিন',
              'সেন্ট্রাল লাইব্রেরি'
            ]
          : const [
              'Main Gate',
              'Department Corridor',
              'Campus Canteen',
              'Central Library'
            ];
    }
    if (g.isMess) {
      return isBn
          ? const ['মেস ডাইনিং রুম', 'ড্রয়িং রুম', 'বারান্দা', 'মেসের ছাদ']
          : const ['Dining Room', 'Drawing Room', 'Balcony', 'Flat Rooftop'];
    }
    if (g.isSociety) {
      return isBn
          ? const ['কমিউনিটি হল', 'বিল্ডিং রিসেপশন', 'সিকিউরিটি গেট', 'ছাদ']
          : const [
              'Community Hall',
              'Building Reception',
              'Security Gate',
              'Rooftop'
            ];
    }
    if (g.isSamity) {
      return isBn
          ? const [
              'সমিতি কার্যালয়',
              'মাসিক বৈঠক স্থান',
              'ক্লাব রুম',
              'অডিটোরিয়াম'
            ]
          : const ['Main Office', 'Monthly Venue', 'Club Room', 'Auditorium'];
    }
    if (g.isStudy) {
      return isBn
          ? const [
              'স্টাডি লাউঞ্জ',
              'রিডিং রুম',
              'ক্যাম্পাস ক্যাফে',
              'সেমিনার হল'
            ]
          : const [
              'Study Lounge',
              'Reading Room',
              'Campus Cafe',
              'Seminar Hall'
            ];
    }
    if (g.isFriends) {
      return isBn
          ? const [
              'প্রিয় ক্যাফে ও আড্ডার স্থান',
              'টিএসসি বা আড্ডার মোড়',
              'রেস্তোরাঁ ও ফুড কোর্ট',
              'দোস্তের বাসা বা ছাদ'
            ]
          : const [
              'Favorite Cafe & Hangout',
              'Campus Hangout Corner',
              'Food Court & Restaurant',
              "Friend's Place / Rooftop"
            ];
    }
    if (g.isSchool) {
      return isBn
          ? const [
              'স্কুল অডিটোরিয়াম',
              'প্রধান ফটক',
              'স্টাফ রুম',
              'মাঠের প্যাভিলিয়ন'
            ]
          : const [
              'School Auditorium',
              'Main Gate',
              'Staff Room',
              'School Field & Pavilion'
            ];
    }
    if (g.isSports) {
      return isBn
          ? const [
              'ড্রেসিং রুম',
              'ক্লাব হাউজ',
              'স্টেডিয়াম গ্যালারি',
              'জিমনেসিয়াম'
            ]
          : const [
              'Dressing Room',
              'Club House',
              'Stadium Gallery',
              'Gymnasium'
            ];
    }
    if (g.isCommittee) {
      return isBn
          ? const [
              'কমিটি কনফারেন্স রুম',
              'কমিউনিটি হল',
              'অ্যাসোসিয়েশন অফিস',
              'পার্ক প্রাঙ্গণ'
            ]
          : const [
              'Committee Conference Room',
              'Community Hall',
              'Association Office',
              'Park / Plaza'
            ];
    }
    if (g.isHousehold) {
      return isBn
          ? const ['ড্রয়িং রুম', 'পারিবারিক বাসভবন', 'ডাইনিং স্পেস', 'বাগান']
          : const ['Living Room', 'Family Residence', 'Dining Area', 'Garden'];
    }
    return isBn
        ? const ['হোটেল লবি', 'বাস টার্মিনাল', 'এয়ারপোর্ট লাউঞ্জ', 'বিচ পয়েন্ট']
        : const [
            'Hotel Lobby',
            'Bus Terminal',
            'Airport Lounge',
            'Beach Point'
          ];
  }

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
        backgroundColor: context.forest.surfaceFor(_card),
        title: Text(l10n.translate('tour_edit_meeting_point'),
            style: TextStyle(color: context.forest.text)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                style: TextStyle(color: context.forest.text),
                decoration: InputDecoration(
                    labelText: l10n.translate('tour_place_name')),
              ),
              const SizedBox(height: 6),
              Builder(builder: (ctx) {
                final suggestions = _meetingSuggestions(l10n);
                if (suggestions.isEmpty) return const SizedBox.shrink();
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final s in suggestions)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ActionChip(
                            label:
                                Text(s, style: const TextStyle(fontSize: 11)),
                            onPressed: () {
                              titleCtrl.text = s;
                            },
                          ),
                        ),
                    ],
                  ),
                );
              }),
              TextField(
                controller: noteCtrl,
                style: TextStyle(color: context.forest.text),
                decoration:
                    InputDecoration(labelText: l10n.translate('tour_details')),
              ),
              TextField(
                controller: urlCtrl,
                style: TextStyle(color: context.forest.text),
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
          ? (_membersPost
              ? 'notice_post_failed'
              : 'tour_notice_post_admin_only')
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
        backgroundColor: context.forest.surfaceFor(_card),
        title: Text(l10n.translate('tour_delete_notice'),
            style: TextStyle(color: context.forest.text)),
        content: Text(n.title, style: TextStyle(color: context.forest.text70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l10n.translate('tour_cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(l10n.translate('fund_delete'),
                  style: TextStyle(
                      color: context.forest.readable(Colors.redAccent)))),
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
            {Color? color}) =>
        ListTile(
          leading: Icon(icon, color: color ?? context.forest.text70),
          title: Text(label, style: TextStyle(color: context.forest.text)),
          onTap: () {
            Navigator.pop(context);
            onTap();
          },
        );
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.forest.surfaceFor(_card),
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
            if (_isAdmin || (_membersPost && n.authorEmail == _me))
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
      backgroundColor: context.forest.surfaceFor(_card),
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
                    style: TextStyle(
                        color: context.forest.text,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _progressRing(l10n, a, rollcall),
                const SizedBox(height: 12),
                if (a.waiting.isNotEmpty) ...[
                  Row(children: [
                    Expanded(
                      child: Text(
                          l10n.translate(
                              rollcall ? 'notice_missing' : 'notice_waiting',
                              args: {'n': l10n.number(a.waiting.length)}),
                          style: TextStyle(
                              color: context.forest.readable(AppColors.gold),
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
                      icon: Icon(Icons.share_rounded,
                          size: 16,
                          color: context.forest.readable(AppColors.gold)),
                      label: Text(l10n.translate('notice_share'),
                          style: TextStyle(
                              color: context.forest.readable(AppColors.gold))),
                    ),
                  ]),
                  for (final m in a.waiting)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.hourglass_top_rounded,
                          color: context.forest.readable(AppColors.gold),
                          size: 20),
                      title: Text(m.displayName,
                          style: TextStyle(color: context.forest.text)),
                      subtitle: m.familyCount > 1
                          ? Text(
                              l10n.translate('fund_family_of',
                                  args: {'n': l10n.number(m.familyCount)}),
                              style: TextStyle(
                                  color: context.forest.text38, fontSize: 11))
                          : null,
                      trailing: _isAdmin
                          ? TextButton(
                              onPressed: () => _answer(n, true, email: m.email),
                              child: Text(
                                  l10n.translate(rollcall
                                      ? 'notice_mark_present'
                                      : 'notice_mark_answered'),
                                  style: TextStyle(
                                      color: context.forest.accentText)),
                            )
                          : null,
                    ),
                  Divider(color: context.forest.divider12),
                ],
                Text(
                    l10n.translate(
                        rollcall ? 'notice_present' : 'notice_answered',
                        args: {'n': l10n.number(a.answered.length)}),
                    style: TextStyle(
                        color: context.forest.accentText,
                        fontWeight: FontWeight.bold)),
                for (final m in a.answered)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.check_circle_rounded,
                        color: context.forest.accentText, size: 20),
                    title: Text(m.displayName,
                        style: TextStyle(color: context.forest.text)),
                    trailing: _isAdmin && m.email != _me
                        ? IconButton(
                            tooltip: l10n.translate('notice_undo'),
                            icon: Icon(Icons.undo_rounded,
                                color: context.forest.text38, size: 18),
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

    return GroupPopScope(
      tourId: widget.tourId,
      child: Scaffold(
        backgroundColor: context.forest.surfaceFor(_bg),
        appBar: AppBar(
          leading: GroupBackButton(tourId: widget.tourId),
          title: Text(l10n.translate('tour_notice_board_title'),
              style: TextStyle(
                  color: context.forest.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          backgroundColor: context.forest.surfaceFor(_card),
          foregroundColor: context.forest.text,
          iconTheme: IconThemeData(color: context.forest.text),
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
        floatingActionButton: _isAdmin || _membersPost
            ? FloatingActionButton.extended(
                backgroundColor: AppColors.mintGreen,
                foregroundColor: AppColors.darkGreen,
                icon: const Icon(Icons.add_alert_rounded),
                label: Text(l10n.translate('tour_notice_new')),
                onPressed: () => _compose(),
              )
            : null,
        body: SafeArea(
          // A swipe moves to the next or previous filter. It only changes which
          // notices of the stream already on screen are shown.
          child: SwipeStep(
            onStep: _stepFilter,
            nextLabel: l10n.translate('notice_next_filter'),
            previousLabel: l10n.translate('notice_previous_filter'),
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
          context.forest.surfaceFor(_card),
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
        color: context.forest.surfaceFor(_card),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.place_rounded,
              color: context.forest.readable(Colors.amber)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.translate('tour_live_meeting_point'),
                    style: TextStyle(
                        color: context.forest.readable(Colors.amber),
                        fontSize: 11)),
                Text(_meetingTitle(l10n),
                    style: TextStyle(
                        color: context.forest.text,
                        fontWeight: FontWeight.bold)),
                if (note.isNotEmpty)
                  Text(note,
                      style: TextStyle(
                          color: context.forest.text70, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            tooltip: l10n.translate('tour_view_on_map'),
            icon: Icon(Icons.navigation_rounded,
                color: context.forest.accentText),
            onPressed: () => _open(_meetingMapUri),
          ),
          if (_isAdmin)
            IconButton(
              tooltip: l10n.translate('tour_edit_meeting_point'),
              icon: Icon(Icons.edit_rounded,
                  size: 18, color: context.forest.text54),
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
        color: context.forest.surfaceFor(_card),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.forest.divider10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.translate('notice_today'),
              style: TextStyle(
                  color: context.forest.text, fontWeight: FontWeight.bold)),
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
                                ? context.forest.text38
                                : context.forest.accentText,
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
                                ? context.forest.text38
                                : context.forest.text,
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

  /// Moves the filter by [by]. The first and last filters stop the swipe.
  void _stepFilter(int by) {
    final next = NoticeEngine.stepFilter(_filter, by);
    if (next == _filter) return;
    setState(() => _filter = next);
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
                backgroundColor: context.forest.surfaceFor(_card),
                labelStyle: TextStyle(
                    color: _filter == f
                        ? AppColors.darkGreen
                        : (f == NoticeFilter.needsMe && needsMe > 0
                            ? AppColors.gold
                            : context.forest.text)),
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
                style: TextStyle(color: context.forest.text54))
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
              style: TextStyle(color: context.forest.text54)),
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

  Widget _progressRing(AppLocalizations l10n, NoticeAnswers a, bool rollcall) {
    final pct = (a.ratio * 100).round();
    final isDone = a.waiting.isEmpty && a.total > 0;
    final ringColor = isDone ? AppColors.mintGreen : AppColors.gold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: context.forest.surfaceFor(const Color(0xFF142428)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.forest.divider10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 38,
            height: 38,
            child: Stack(
              fit: StackFit.expand,
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: a.ratio,
                  strokeWidth: 3.5,
                  color: ringColor,
                  backgroundColor: context.forest.divider10,
                ),
                Center(
                  child: Text(
                    '$pct%',
                    style: TextStyle(
                      color: ringColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.translate(
                      rollcall ? 'notice_present_of' : 'notice_answered_of',
                      args: {
                        'n': l10n.number(a.answered.length),
                        'total': l10n.number(a.total),
                      }),
                  style: TextStyle(
                    color: context.forest.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  a.waiting.isEmpty
                      ? l10n.translate(rollcall
                          ? 'notice_progress_all_present'
                          : 'notice_progress_all_done')
                      : l10n.translate('notice_pending_count',
                          args: {'n': l10n.number(a.waiting.length)}),
                  style: TextStyle(
                    color: isDone ? AppColors.mintGreen : context.forest.text54,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded,
              size: 16, color: context.forest.text38),
        ],
      ),
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
          style: TextStyle(color: context.forest.text70, fontSize: 12),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: a.ratio,
            minHeight: 6,
            color: a.waiting.isEmpty ? AppColors.mintGreen : AppColors.gold,
            backgroundColor: context.forest.divider10,
          ),
        ),
      ],
    );
  }

  /// Reads the notice aloud, or stops it when it is the one being read.
  Widget _readAloudButton(AppLocalizations l10n, TourNotice n) {
    return ValueListenableBuilder<String?>(
      valueListenable: NoticeReadAloud.instance.playingId,
      builder: (context, playing, _) {
        final reading = playing == n.id;
        return IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: l10n.translate(
              reading ? 'notice_read_aloud_stop' : 'notice_read_aloud'),
          icon: Icon(
            reading ? Icons.stop_circle_rounded : Icons.volume_up_rounded,
            color: reading ? context.forest.accentText : context.forest.text54,
            size: 20,
          ),
          onPressed: () => _readAloud(l10n, n),
        );
      },
    );
  }

  void _readAloud(AppLocalizations l10n, TourNotice n) {
    final bengali = l10n.locale.languageCode == 'bn';
    final at = n.eventAt;
    final place = n.place?.trim() ?? '';
    final text = noticeSpeechText(
      title: n.title,
      content: n.content,
      timeSentence: at == null
          ? null
          : l10n.translate('notice_speech_at', args: {
              'time': localizedDateFormat('EEE, d MMM, h:mm a').format(at),
            }),
      placeSentence: place.isEmpty
          ? null
          : l10n.translate('notice_speech_place', args: {'place': place}),
      bengali: bengali,
    );
    unawaited(
        NoticeReadAloud.instance.speak(id: n.id, text: text, bengali: bengali));
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
          color: hot
              ? Colors.redAccent.withValues(alpha: 0.08)
              : context.forest.surfaceFor(_card),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: hot
                  ? Colors.redAccent.withValues(alpha: 0.6)
                  : (n.pinned
                      ? AppColors.mintGreen.withValues(alpha: 0.5)
                      : context.forest.divider12)),
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
                          style: TextStyle(
                              color: context.forest.text54, fontSize: 11)),
                    ),
                  ],
                  const Spacer(),
                  if (n.pinned)
                    Icon(Icons.push_pin_rounded,
                        size: 16, color: context.forest.accentText),
                  if (hot)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(Icons.warning_amber_rounded,
                          color: context.forest.readable(Colors.redAccent),
                          size: 18),
                    ),
                  Icon(Icons.more_vert_rounded,
                      size: 18, color: context.forest.text38),
                ]),
                const SizedBox(height: 8),
                Text(n.title,
                    style: TextStyle(
                        color: context.forest.text,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                if (n.content.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(n.content,
                      style: TextStyle(
                          color: context.forest.text70, fontSize: 13)),
                ],
                if (n.eventAt != null || n.place != null) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 10, runSpacing: 4, children: [
                    if (n.eventAt != null)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.schedule_rounded,
                            size: 15,
                            color: context.forest.readable(AppColors.gold)),
                        const SizedBox(width: 4),
                        Text(
                            localizedDateFormat('EEE d MMM, h:mm a')
                                .format(n.eventAt!),
                            style: TextStyle(
                                color: context.forest.text, fontSize: 12)),
                        if (!archived) ...[
                          const SizedBox(width: 6),
                          Text(noticeCountdown(l10n, n.eventAt!, _now),
                              style: TextStyle(
                                  color: timing == NoticeTiming.past
                                      ? context.forest.text38
                                      : context.forest.readable(AppColors.gold),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ]),
                    if (n.place != null)
                      InkWell(
                        onTap: mapUri == null ? null : () => _open(mapUri),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.place_rounded,
                              size: 15,
                              color: context.forest.readable(Colors.amber)),
                          const SizedBox(width: 4),
                          Text(n.place!,
                              style: TextStyle(
                                  color: context.forest.text,
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
                        child: (_group?.isManaged ?? false)
                            ? _progressRing(
                                l10n,
                                NoticeEngine.answers(n, _members),
                                n.kind == NoticeKind.rollcall)
                            : _progress(l10n, NoticeEngine.answers(n, _members),
                                n.kind == NoticeKind.rollcall),
                      ),
                    ),
                  ]),
                ],
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: Text(
                        l10n.translate('tour_notice_sender', args: {
                          'author': n.author,
                          'date': localizedDateFormat('dd MMM, hh:mm a')
                              .format(n.createdAt),
                        }),
                        style: TextStyle(
                            color: context.forest.text38, fontSize: 11)),
                  ),
                  _readAloudButton(l10n, n),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
