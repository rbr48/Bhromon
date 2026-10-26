import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/colors.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/tour_activity_models.dart';
import '../../domain/models/tour_group.dart';

class TourChecklistScreen extends StatefulWidget {
  final String tourId;

  const TourChecklistScreen({super.key, required this.tourId});

  @override
  State<TourChecklistScreen> createState() => _TourChecklistScreenState();
}

class _TourChecklistScreenState extends State<TourChecklistScreen> {
  static const String _beachCategory = 'সৈকত অনুষঙ্গ (Beach Gear)';
  static const String _customCategory = 'আমার আইটেম (Custom)';

  final TourGroupRepository _repository = TourGroupRepository();
  late final Stream<List<ChecklistItem>> _items =
      _repository.watchChecklist(widget.tourId);
  TourGroup? _group;
  StreamSubscription<TourGroup?>? _groupSub;

  // Default items keep stable ids so each person's ticks survive re-ordering.
  static String _defaultId(int index) => 'default_$index';

  @override
  void initState() {
    super.initState();
    _watchGroup();
  }

  void _watchGroup() {
    _groupSub?.cancel();
    _groupSub = _repository.watchGroup(widget.tourId).listen((g) {
      if (mounted) setState(() => _group = g);
    });
  }

  @override
  void dispose() {
    _groupSub?.cancel();
    super.dispose();
  }

  /// Default items for this tour. Beach items are left out of hill and city tours.
  List<({String id, String title, String category})> get _visibleDefaults {
    final isBeach = _group == null || _group!.tourType == TourType.beach;
    final items = <({String id, String title, String category})>[];
    for (var i = 0; i < _defaultItems.length; i++) {
      final item = _defaultItems[i];
      if (!isBeach && item.category == _beachCategory) continue;
      items
          .add((id: _defaultId(i), title: item.title, category: item.category));
    }
    return items;
  }

  Future<void> _setPacked(String itemId, bool packed) async {
    try {
      await _repository.setChecklistItemPacked(widget.tourId, itemId, packed);
    } catch (e) {
      _showError('সংরক্ষণ করা যায়নি: $e');
    }
  }

  void _showError(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = _repository.currentEmail;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1A12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1A12),
        elevation: 0,
        title: const Text(
          'Packing Checklist (ট্যুর চেকলিস্ট)',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon:
                const Icon(Icons.add_task_rounded, color: AppColors.mintGreen),
            tooltip: 'নতুন আইটেম যোগ করুন',
            onPressed: () => _showAddItemDialog(context),
          ),
        ],
      ),
      body: StreamBuilder<List<ChecklistItem>>(
        stream: _items,
        builder: (context, snapshot) {
          if (snapshot.hasError && !snapshot.hasData) {
            return const Center(
              child: Text('চেকলিস্ট লোড করা যায়নি।',
                  style: TextStyle(color: Colors.white54)),
            );
          }
          final saved = snapshot.data ?? const <ChecklistItem>[];
          final byId = {for (final item in saved) item.id: item};
          final defaults = _visibleDefaults;
          final custom =
              saved.where((i) => i.id.startsWith('custom_')).toList();

          final packedCount = defaults
                  .where((d) => byId[d.id]?.isCheckedBy(me) ?? false)
                  .length +
              custom.where((c) => c.isCheckedBy(me)).length;
          final totalCount = defaults.length + custom.length;

          final categories = <String>[];
          for (final d in defaults) {
            if (!categories.contains(d.category)) categories.add(d.category);
          }
          if (custom.isNotEmpty) categories.add(_customCategory);

          return Column(
            children: [
              // Progress for the signed-in person only
              Container(
                margin: const EdgeInsets.all(14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF14241B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('আমার প্যাকিং প্রস্তুতি',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                        Text('$packedCount / $totalCount',
                            style: const TextStyle(
                                color: AppColors.mintGreen,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: totalCount > 0
                            ? (packedCount / totalCount).clamp(0.0, 1.0)
                            : 0,
                        backgroundColor: Colors.white12,
                        valueColor:
                            const AlwaysStoppedAnimation(AppColors.mintGreen),
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'প্রতিটি সদস্য নিজের আইটেম নিজে টিক দেবেন।',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  children: [
                    for (final category in categories)
                      _buildSection(
                        category: category,
                        defaults: defaults
                            .where((d) => d.category == category)
                            .toList(),
                        custom: category == _customCategory ? custom : const [],
                        byId: byId,
                        me: me,
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSection({
    required String category,
    required List<({String id, String title, String category})> defaults,
    required List<ChecklistItem> custom,
    required Map<String, ChecklistItem> byId,
    required String me,
  }) {
    final rows = <Widget>[
      for (final d in defaults)
        _buildRow(
          id: d.id,
          title: d.title,
          checked: byId[d.id]?.isCheckedBy(me) ?? false,
          deletable: false,
        ),
      for (final c in custom)
        _buildRow(
          id: c.id,
          title: c.title,
          checked: c.isCheckedBy(me),
          deletable: true,
        ),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF14241B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              category,
              style: const TextStyle(
                color: AppColors.gold,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          ...rows,
        ],
      ),
    );
  }

  Widget _buildRow({
    required String id,
    required String title,
    required bool checked,
    required bool deletable,
  }) {
    return CheckboxListTile(
      title: Text(
        title,
        style: TextStyle(
          color: checked ? Colors.white38 : Colors.white,
          fontSize: 13,
          decoration: checked ? TextDecoration.lineThrough : null,
        ),
      ),
      value: checked,
      activeColor: AppColors.midGreen,
      checkColor: Colors.white,
      controlAffinity: ListTileControlAffinity.leading,
      secondary: deletable
          ? IconButton(
              tooltip: 'আইটেম মুছুন',
              icon: const Icon(Icons.delete_outline, color: Colors.white54),
              onPressed: () => _confirmDelete(id, title),
            )
          : null,
      onChanged: (val) => _setPacked(id, val ?? false),
    );
  }

  Future<void> _confirmDelete(String id, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF14241B),
        title: Text('"$title" মুছবেন?',
            style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('না')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('মুছুন',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.deleteChecklistItem(widget.tourId, id);
    } catch (_) {
      _showError('শুধু অ্যাডমিন আইটেম মুছতে পারবেন।');
    }
  }

  void _showAddItemDialog(BuildContext context) {
    final titleCtrl = TextEditingController();

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF14241B),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('নতুন আইটেম যোগ করুন',
              style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: titleCtrl,
            autofocus: true,
            maxLength: 80,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'আইটেমের নাম',
              labelStyle: TextStyle(color: Colors.white70),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('বাতিল', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.midGreen),
              onPressed: () async {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;
                Navigator.pop(ctx);
                try {
                  await _repository.addChecklistItem(
                      widget.tourId, title, _customCategory);
                } catch (e) {
                  _showError('আইটেম যোগ করা যায়নি: $e');
                }
              },
              child:
                  const Text('যোগ করুন', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    ).whenComplete(titleCtrl.dispose);
  }

  static const List<({String title, String category})> _defaultItems = [
    (
      title: 'জাতীয় পরিচয়পত্র / NID বা জন্ম নিবন্ধন ফটোকপি',
      category: 'ডকুমেন্টস (Documents)'
    ),
    (
      title: 'হোটেল ও বাসের টিকিট কপি / কনফার্মেশন',
      category: 'ডকুমেন্টস (Documents)'
    ),
    (
      title: 'প্যারাসিটামল, ওরস্যালাইন ও গ্যাস্ট্রিকের ওষুধ',
      category: 'ওষুধ ও ফার্স্ট এইড (Medicines)'
    ),
    (
      title: 'ব্যান্ড-এইড, স্যাভলন ও মোশন সিকনেস ওষুধ',
      category: 'ওষুধ ও ফার্স্ট এইড (Medicines)'
    ),
    (
      title: 'মোবাইল চার্জার ও পাওয়ার ব্যাংক (১০,০০০+ mAh)',
      category: 'ইলেকট্রনিক্স (Electronics)'
    ),
    (
      title: 'মাল্টিপ্লাগ ও ওয়াটারপ্রুফ মোবাইল পাউচ',
      category: 'ইলেকট্রনিক্স (Electronics)'
    ),
    (
      title: 'হালকা সুতি পোশাক ও রোদচশমা (Sunglasses)',
      category: 'পোশাক (Clothing)'
    ),
    (
      title: 'সুইমিং কস্টিউম বা অতিরিক্ত হাফপ্যান্ট ও টি-শার্ট',
      category: 'পোশাক (Clothing)'
    ),
    (
      title: 'সানস্ক্রিন লোশন (SPF 50+) ও বড় হ্যাট',
      category: 'সৈকত অনুষঙ্গ (Beach Gear)'
    ),
    (
      title: 'স্যান্ডেল / ওয়াটার শু ও হালকা ছাতা',
      category: 'সৈকত অনুষঙ্গ (Beach Gear)'
    ),
  ];
}
