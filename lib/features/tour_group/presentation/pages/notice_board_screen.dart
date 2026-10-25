import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

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

  String get _meetingTitle =>
      _group?.meetingPointTitle ??
      '${_group?.destination ?? 'ট্যুর'} প্রধান মিটিং পয়েন্ট (হোটেল লবি)';

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
        title: const Text('মিটিং পয়েন্ট বদলান',
            style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'স্থানের নাম'),
              ),
              TextField(
                controller: noteCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'বিস্তারিত'),
              ),
              TextField(
                controller: urlCtrl,
                style: const TextStyle(color: Colors.white),
                decoration:
                    const InputDecoration(labelText: 'ম্যাপের লিংক (https://)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('বাতিল')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('সংরক্ষণ')),
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
      _showError('ম্যাপের লিংক https:// দিয়ে শুরু হতে হবে।');
      return;
    }
    try {
      await _repository.updateMeetingPoint(widget.tourId,
          title: title, note: note, mapUrl: url);
      await _load();
    } catch (e) {
      _showError('মিটিং পয়েন্ট সংরক্ষণ করা যায়নি: $e');
    }
  }

  /// Posts a new notice, or edits [existing] when it is given.
  void _showNoticeDialog({TourNotice? existing}) {
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
              existing == null ? 'নতুন নোটিশ জারি করুন' : 'নোটিশ সম্পাদনা',
              style: const TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  maxLength: 100,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'শিরোনাম'),
                ),
                TextField(
                  controller: contentCtrl,
                  maxLines: 4,
                  maxLength: 1000,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'বিস্তারিত'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('জরুরি নোটিশ',
                      style: TextStyle(color: Colors.white)),
                  value: isUrgent,
                  onChanged: (v) => setDialogState(() => isUrgent = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('বাতিল', style: TextStyle(color: Colors.white54)),
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
                      ? 'নোটিশ পাঠানো যায়নি: শুধু অ্যাডমিন নোটিশ দিতে পারেন।'
                      : 'নোটিশ বদলানো যায়নি: শুধু অ্যাডমিন বদলাতে পারেন।');
                }
              },
              child: const Text('পোস্ট করুন',
                  style: TextStyle(fontWeight: FontWeight.bold)),
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
    try {
      await _repository.deleteNotice(widget.tourId, notice.id);
    } catch (_) {
      _showError('নোটিশ মোছা যায়নি।');
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = _repository.currentEmail;
    return Scaffold(
      backgroundColor: const Color(0xFF0F1A1C),
      appBar: AppBar(
        title: const Text('Notice Board & Meeting Point',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF142428),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.add_alert),
              tooltip: 'নতুন নোটিশ',
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
            const Text('নোটিশ বোর্ড',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
            const SizedBox(height: 10),
            StreamBuilder<List<TourNotice>>(
              stream: _notices,
              builder: (context, snapshot) {
                if (snapshot.hasError && !snapshot.hasData) {
                  return const Text('নোটিশ লোড করা যায়নি।',
                      style: TextStyle(color: Colors.white54));
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
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('এখনও কোনো নোটিশ নেই।',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white38)),
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
              const Text('লাইভ মিটিং পয়েন্ট',
                  style: TextStyle(color: Colors.amber, fontSize: 11)),
              const Spacer(),
              if (_isAdmin)
                IconButton(
                  tooltip: 'মিটিং পয়েন্ট বদলান',
                  icon: const Icon(Icons.edit, size: 18, color: Colors.white70),
                  onPressed: _editMeetingPoint,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(_meetingTitle,
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
            label: const Text('ম্যাপে দেখুন'),
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
                  tooltip: 'নোটিশ সম্পাদনা',
                  icon: const Icon(Icons.edit_outlined,
                      color: Colors.white38, size: 18),
                  onPressed: () => _showNoticeDialog(existing: notice),
                ),
              if (canDelete)
                IconButton(
                  tooltip: 'নোটিশ মুছুন',
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
          Text('প্রেরক: ${notice.author} • $dateText',
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }
}
