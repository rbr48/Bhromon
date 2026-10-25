import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/tour_activity_models.dart';
import '../../domain/models/tour_group.dart';

class NoticeBoardScreen extends StatefulWidget {
  final String tourId;

  const NoticeBoardScreen({super.key, required this.tourId});

  @override
  State<NoticeBoardScreen> createState() => _NoticeBoardScreenState();
}

class _NoticeBoardScreenState extends State<NoticeBoardScreen> {
  final TourGroupRepository _repository = TourGroupRepository();
  late final Stream<List<TourNotice>> _notices =
      _repository.watchNotices(widget.tourId);

  TourGroup? _group;
  TourRole? _myRole;

  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final group = await _repository.getGroup(widget.tourId);
    final role = await _repository.myRole(widget.tourId);
    if (mounted) {
      setState(() {
        _group = group;
        _myRole = role;
      });
    }
  }

  void _showError(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: Colors.redAccent),
    );
  }

  String _meetingTitle(BuildContext context) =>
      _group?.meetingPointTitle ??
      context.l10n.translate('tour_meeting_point_default', args: {
        'destination': _group?.destination ??
            context.l10n.translate('tour_default_destination'),
      });

  String get _meetingMapUrl =>
      _group?.meetingPointMapUrl ??
      'https://maps.google.com/?q=${Uri.encodeComponent(_group?.destination ?? 'Hotel Lobby')}';

  Future<void> _openMap() async {
    final uri = Uri.parse(_meetingMapUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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
        backgroundColor: const Color(0xFF142428),
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
      _showError(l10n.translate('tour_map_link_needs_https'));
      return;
    }
    try {
      await _repository.updateMeetingPoint(widget.tourId,
          title: title, note: note, mapUrl: url);
      await _load();
    } catch (e) {
      _showError(
          l10n.translate('tour_meeting_point_save_failed', args: {'error': e}));
    }
  }

  /// Posts a new notice, or edits [existing] when it is given.
  void _showNoticeDialog({TourNotice? existing}) {
    final l10n = context.l10n;
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final contentCtrl = TextEditingController(text: existing?.content ?? '');
    bool isUrgent = existing?.urgent ?? false;

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF142428),
          title: Text(
              existing == null
                  ? l10n.translate('tour_notice_new_title')
                  : l10n.translate('tour_notice_edit_title'),
              style: const TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  maxLength: 100,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                      labelText: l10n.translate('tour_notice_heading')),
                ),
                TextField(
                  controller: contentCtrl,
                  maxLines: 4,
                  maxLength: 1000,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                      labelText: l10n.translate('tour_details')),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.translate('tour_notice_urgent'),
                      style: const TextStyle(color: Colors.white)),
                  value: isUrgent,
                  onChanged: (v) => setDialogState(() => isUrgent = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.translate('tour_cancel'),
                  style: const TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.tealAccent.shade700,
                  foregroundColor: Colors.white),
              onPressed: () async {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;
                final content = contentCtrl.text.trim();
                Navigator.pop(ctx);
                try {
                  if (existing == null) {
                    await _repository.postNotice(
                      tourId: widget.tourId,
                      title: title,
                      content: content,
                      urgent: isUrgent,
                    );
                  } else {
                    await _repository.updateNotice(
                      tourId: widget.tourId,
                      noticeId: existing.id,
                      title: title,
                      content: content,
                      urgent: isUrgent,
                    );
                  }
                } catch (e) {
                  _showError(existing == null
                      ? l10n.translate('tour_notice_post_admin_only')
                      : l10n.translate('tour_notice_update_admin_only'));
                }
              },
              child: Text(l10n.translate('tour_post'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      titleCtrl.dispose();
      contentCtrl.dispose();
    });
  }

  Future<void> _deleteNotice(TourNotice notice) async {
    final l10n = context.l10n;
    try {
      await _repository.deleteNotice(widget.tourId, notice.id);
    } catch (_) {
      _showError(l10n.translate('tour_notice_delete_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = _repository.currentEmail;
    return Scaffold(
      backgroundColor: const Color(0xFF0F1A1C),
      appBar: AppBar(
        title: Text(context.l10n.translate('tour_notice_board_title'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF142428),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.add_alert),
              tooltip: context.l10n.translate('tour_notice_new'),
              onPressed: () => _showNoticeDialog(),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildMeetingPointCard(),
            const SizedBox(height: 20),
            Text(context.l10n.translate('tour_notice_board'),
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
            const SizedBox(height: 10),
            StreamBuilder<List<TourNotice>>(
              stream: _notices,
              builder: (context, snapshot) {
                if (snapshot.hasError && !snapshot.hasData) {
                  return Text(
                      context.l10n.translate('tour_notices_load_failed'),
                      style: const TextStyle(color: Colors.white54));
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child:
                          CircularProgressIndicator(color: Colors.tealAccent),
                    ),
                  );
                }
                final notices = snapshot.data!;
                if (notices.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(context.l10n.translate('tour_no_notices'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white38)),
                  );
                }
                return Column(
                  children: [
                    for (final notice in notices)
                      _buildNoticeCard(
                        notice,
                        canDelete: _isAdmin || notice.authorEmail == me,
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMeetingPointCard() {
    final note = _group?.meetingPointNote ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF142428),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.place, color: Colors.amber, size: 14),
              const SizedBox(width: 4),
              Text(context.l10n.translate('tour_live_meeting_point'),
                  style: const TextStyle(color: Colors.amber, fontSize: 11)),
              const Spacer(),
              if (_isAdmin)
                IconButton(
                  tooltip: context.l10n.translate('tour_edit_meeting_point'),
                  icon: const Icon(Icons.edit, size: 18, color: Colors.white70),
                  onPressed: _editMeetingPoint,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(_meetingTitle(context),
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15)),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(note,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.navigation, size: 16),
            label: Text(context.l10n.translate('tour_view_on_map')),
            onPressed: _openMap,
          ),
        ],
      ),
    );
  }

  Widget _buildNoticeCard(TourNotice notice, {required bool canDelete}) {
    final dateText = DateFormat('dd MMM, hh:mm a').format(notice.createdAt);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: notice.urgent
            ? Colors.redAccent.withValues(alpha: 0.08)
            : const Color(0xFF142428),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: notice.urgent
                ? Colors.redAccent.withValues(alpha: 0.5)
                : Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (notice.urgent)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.warning_amber_rounded,
                      color: Colors.redAccent, size: 16),
                ),
              Expanded(
                child: Text(notice.title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
              ),
              if (canDelete)
                IconButton(
                  tooltip: context.l10n.translate('tour_notice_edit_title'),
                  icon: const Icon(Icons.edit_outlined,
                      color: Colors.white38, size: 18),
                  onPressed: () => _showNoticeDialog(existing: notice),
                ),
              if (canDelete)
                IconButton(
                  tooltip: context.l10n.translate('tour_delete_notice'),
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.white38, size: 18),
                  onPressed: () => _deleteNotice(notice),
                ),
            ],
          ),
          if (notice.content.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(notice.content,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
          const SizedBox(height: 8),
          Text(
              context.l10n.translate('tour_notice_sender',
                  args: {'author': notice.author, 'date': dateText}),
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }
}
