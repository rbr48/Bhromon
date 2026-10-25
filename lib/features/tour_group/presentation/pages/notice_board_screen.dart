import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../domain/models/tour_group.dart';
import '../../data/tour_group_repository.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class NoticeBoardScreen extends StatefulWidget {
  final String tourId;

  const NoticeBoardScreen({super.key, required this.tourId});

  @override
  State<NoticeBoardScreen> createState() => _NoticeBoardScreenState();
}

class _NoticeBoardScreenState extends State<NoticeBoardScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TourGroupRepository _repository = TourGroupRepository();
  TourGroup? _tourGroup;

  String _meetingTitle = 'প্রধান মিটিং পয়েন্ট ও হোটেল লবি';
  String _meetingNote =
      'সকল ভ্রমণের আগে ও পরে সবাই নির্ধারিত সময়ে এখানে সমবেত হব।';
  String _meetingMapUrl = 'https://maps.google.com/?q=Hotel+Lobby';

  @override
  void initState() {
    super.initState();
    _loadMeetingPoint();
  }

  Future<void> _loadMeetingPoint() async {
    try {
      final group = await _repository.getGroup(widget.tourId);
      if (mounted && group != null) {
        setState(() {
          _tourGroup = group;
          _meetingTitle = group.meetingPointTitle ??
              '${group.destination} প্রধান মিটিং পয়েন্ট (হোটেল লবি)';
          _meetingMapUrl = group.meetingPointMapUrl ??
              'https://maps.google.com/?q=${Uri.encodeComponent(group.destination)}';
        });
      }

      final doc = await _firestore.collection('tours').doc(widget.tourId).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final mp = data['meetingPoint'] as Map<String, dynamic>?;
        if (mp != null) {
          setState(() {
            _meetingTitle = mp['title'] as String? ?? _meetingTitle;
            _meetingNote = mp['note'] as String? ?? _meetingNote;
            _meetingMapUrl = mp['mapUrl'] as String? ?? _meetingMapUrl;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _updateMeetingPoint(
      String title, String note, String mapUrl) async {
    try {
      await _firestore.collection('tours').doc(widget.tourId).set({
        'meetingPoint': {
          'title': title,
          'note': note,
          'mapUrl': mapUrl,
        }
      }, SetOptions(merge: true));

      setState(() {
        _meetingTitle = title;
        _meetingNote = note;
        _meetingMapUrl = mapUrl;
      });
    } catch (_) {}
  }

  Future<void> _openMapUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _deleteNotice(String noticeId) async {
    try {
      await _firestore
          .collection('tours')
          .doc(widget.tourId)
          .collection('notices')
          .doc(noticeId)
          .delete();
    } catch (_) {}
  }

  void _showAddNoticeDialog() {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    final authorCtrl = TextEditingController(text: 'ট্যুর লিডার');
    bool isUrgent = false;

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF142428),
          title: const Text('নতুন নোটিশ জারি করুন',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'শিরোনাম',
                    labelStyle: TextStyle(color: Colors.white70),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contentCtrl,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'বিস্তারিত নির্দেশনা',
                    labelStyle: TextStyle(color: Colors.white70),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: authorCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'প্রেরক / দায়িত্বপ্রাপ্ত ব্যক্তি',
                    labelStyle: TextStyle(color: Colors.white70),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('জরুরি ঘোষণা (Urgent)',
                      style: TextStyle(color: Colors.white, fontSize: 13)),
                  value: isUrgent,
                  activeThumbColor: Colors.amber,
                  onChanged: (val) => setDialogState(() => isUrgent = val),
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
                if (titleCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);

                await _firestore
                    .collection('tours')
                    .doc(widget.tourId)
                    .collection('notices')
                    .add({
                  'title': titleCtrl.text.trim(),
                  'content': contentCtrl.text.trim(),
                  'author': authorCtrl.text.trim(),
                  'urgent': isUrgent,
                  'createdAt': FieldValue.serverTimestamp(),
                });
              },
              child: const Text('পোস্ট করুন',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditMeetingDialog() {
    final titleCtrl = TextEditingController(text: _meetingTitle);
    final noteCtrl = TextEditingController(text: _meetingNote);
    final urlCtrl = TextEditingController(text: _meetingMapUrl);

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF142428),
        title: const Text('লাইভ মিটিং পয়েন্ট আপডেট',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'মিটিং স্পটের নাম',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLines: 2,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'বিশেষ নির্দেশনা / জমায়েতের সময়',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'গুগল ম্যাপস লিংক',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('বাতিল', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.tealAccent.shade700,
                foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              _updateMeetingPoint(
                titleCtrl.text.trim(),
                noteCtrl.text.trim(),
                urlCtrl.text.trim(),
              );
            },
            child: const Text('সংরক্ষণ করুন',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1A1C),
      appBar: AppBar(
        title: Text(
          _tourGroup != null
              ? '${_tourGroup!.name} নোটিশ বোর্ড'
              : 'Notice Board & Meeting Point',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: const Color(0xFF142428),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_alert),
            tooltip: 'নতুন নোটিশ',
            onPressed: _showAddNoticeDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Pinned Meeting Point Banner
            _buildMeetingPointCard(),

            const SizedBox(height: 20),

            // Notice Board Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'জরুরি ঘোষণা ও নোটিশ তালিকা',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label:
                      const Text('নোটিশ দিন', style: TextStyle(fontSize: 12)),
                  style:
                      TextButton.styleFrom(foregroundColor: Colors.tealAccent),
                  onPressed: _showAddNoticeDialog,
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Notices Stream
            StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('tours')
                  .doc(widget.tourId)
                  .collection('notices')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: Colors.tealAccent),
                  ));
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: const Color(0xFF142428),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: Column(
                        children: [
                          Icon(Icons.campaign_outlined,
                              color: Colors.white24, size: 48),
                          SizedBox(height: 10),
                          Text(
                            'বর্তমানে কোনো নোটিশ নেই।',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'ট্যুর লিডারের জরুরি বার্তা এখানে প্রদর্শিত হবে।',
                            style:
                                TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Column(
                  children: docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final isUrgent = data['urgent'] as bool? ?? false;
                    final title = data['title'] as String? ?? 'নোটিশ';
                    final content = data['content'] as String? ?? '';
                    final author = data['author'] as String? ?? 'ট্যুর লিডার';
                    final ts = data['createdAt'] as Timestamp?;
                    final dateStr = ts != null
                        ? DateFormat('dd MMM, hh:mm a').format(ts.toDate())
                        : 'এখনই';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF142428),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isUrgent ? Colors.redAccent : Colors.white12,
                          width: isUrgent ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (isUrgent) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color:
                                        Colors.redAccent.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text('🚨 জরুরি',
                                      style: TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Expanded(
                                child: Text(
                                  title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 18, color: Colors.white38),
                                onPressed: () => _deleteNotice(doc.id),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            content,
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                height: 1.4),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('প্রেরক: $author',
                                  style: const TextStyle(
                                      color: Colors.tealAccent, fontSize: 11)),
                              Text(dateStr,
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 11)),
                            ],
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMeetingPointCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F3A3B), Color(0xFF071F22)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.3)),
        boxShadow: const [
          BoxShadow(
              color: Colors.black38, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.place, color: Colors.amber, size: 12),
                    SizedBox(width: 4),
                    Text('লাইভ মিটিং পয়েন্ট',
                        style: TextStyle(
                            color: Colors.amber,
                            fontWeight: FontWeight.bold,
                            fontSize: 10)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit, size: 18, color: Colors.white70),
                tooltip: 'মিটিং পয়েন্ট পরিবর্তন',
                onPressed: _showEditMeetingDialog,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _meetingTitle,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
          ),
          const SizedBox(height: 4),
          Text(
            _meetingNote,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.navigation, size: 16),
              label: const Text('গুগল ম্যাপসে ডিরেকশন দেখুন',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.tealAccent.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _openMapUrl(_meetingMapUrl),
            ),
          ),
        ],
      ),
    );
  }
}
