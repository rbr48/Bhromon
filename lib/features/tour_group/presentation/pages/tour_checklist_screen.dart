import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/theme/colors.dart';

class TourChecklistScreen extends StatefulWidget {
  final String tourId;

  const TourChecklistScreen({super.key, required this.tourId});

  @override
  State<TourChecklistScreen> createState() => _TourChecklistScreenState();
}

class _TourChecklistScreenState extends State<TourChecklistScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static final List<({String title, String category})> _defaultItems = [
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

  @override
  Widget build(BuildContext context) {
    final checklistRef = _firestore
        .collection('tours')
        .doc(widget.tourId)
        .collection('checklist');

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
            tooltip: 'Add item',
            onPressed: () => _showAddItemDialog(context),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: checklistRef.snapshots(),
        builder: (context, snapshot) {
          final itemsMap = <String, bool>{};
          final customTitles = <String, String>{};

          if (snapshot.hasData) {
            for (final doc in snapshot.data!.docs) {
              final data = doc.data();
              itemsMap[doc.id] = data['completed'] as bool? ?? false;
              if (data['title'] != null) {
                customTitles[doc.id] = data['title'] as String;
              }
            }
          }

          final categories = [
            'ডকুমেন্টস (Documents)',
            'ওষুধ ও ফার্স্ট এইড (Medicines)',
            'ইলেকট্রনিক্স (Electronics)',
            'পোশাক (Clothing)',
            'সৈকত অনুষঙ্গ (Beach Gear)',
          ];

          int completedCount = itemsMap.values.where((c) => c).length;
          int totalCount = _defaultItems.length;

          return Column(
            children: [
              // Progress Bar Header
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
                        const Text('Packing Readiness (প্যাকিং প্রস্তুতি)',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                        Text('$completedCount / $totalCount Done',
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
                            ? (completedCount / totalCount).clamp(0.0, 1.0)
                            : 0,
                        backgroundColor: Colors.white12,
                        valueColor:
                            const AlwaysStoppedAnimation(AppColors.mintGreen),
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),
              ),

              // Checklist Sections
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  children: categories.map((cat) {
                    final catItems =
                        _defaultItems.where((i) => i.category == cat).toList();

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
                              cat,
                              style: const TextStyle(
                                color: AppColors.gold,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const Divider(color: Colors.white10, height: 1),
                          ...catItems.map((item) {
                            final itemId = 'item_${item.title.hashCode}';
                            final isDone = itemsMap[itemId] ?? false;

                            return CheckboxListTile(
                              title: Text(
                                item.title,
                                style: TextStyle(
                                  color: isDone ? Colors.white38 : Colors.white,
                                  fontSize: 13,
                                  decoration: isDone
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                              value: isDone,
                              activeColor: AppColors.midGreen,
                              checkColor: Colors.white,
                              controlAffinity: ListTileControlAffinity.leading,
                              onChanged: (val) async {
                                await checklistRef.doc(itemId).set({
                                  'id': itemId,
                                  'title': item.title,
                                  'category': item.category,
                                  'completed': val ?? false,
                                }, SetOptions(merge: true));
                              },
                            );
                          }),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
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
          title: const Text('Add Custom Item',
              style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: titleCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Item name',
              labelStyle: TextStyle(color: Colors.white70),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.midGreen),
              onPressed: () async {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;
                Navigator.pop(ctx);

                final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
                await _firestore
                    .collection('tours')
                    .doc(widget.tourId)
                    .collection('checklist')
                    .doc(id)
                    .set({
                  'id': id,
                  'title': title,
                  'category': 'Others',
                  'completed': false,
                });
              },
              child: const Text('Add', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
}
