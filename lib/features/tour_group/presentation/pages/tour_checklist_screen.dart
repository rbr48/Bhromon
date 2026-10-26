import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
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
  static const String _beachCategory = 'check_cat_beach';
  static const String _customCategory = 'check_cat_custom';

  /// The category saved with each custom item. It is stored data, so it stays
  /// the same in every language.
  static const String _customCategoryStored = 'আমার আইটেম (Custom)';

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

  /// Default items for this tour. Beach items are left out of hill and city
  /// tours. Titles and categories are translation keys.
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
      if (!mounted) return;
      _showError(
          context.l10n.translate('check_save_failed', args: {'error': e}));
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
    final l10n = context.l10n;
    final me = _repository.currentEmail;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1A12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1A12),
        elevation: 0,
        title: Text(
          l10n.translate('check_title'),
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon:
                const Icon(Icons.add_task_rounded, color: AppColors.mintGreen),
            tooltip: l10n.translate('check_add_item'),
            onPressed: () => _showAddItemDialog(context),
          ),
        ],
      ),
      body: StreamBuilder<List<ChecklistItem>>(
        stream: _items,
        builder: (context, snapshot) {
          if (snapshot.hasError && !snapshot.hasData) {
            return Center(
              child: Text(l10n.translate('check_load_failed'),
                  style: const TextStyle(color: Colors.white54)),
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
                        Text(l10n.translate('check_my_progress'),
                            style: const TextStyle(
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
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        l10n.translate('check_tick_own'),
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11),
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
    final l10n = context.l10n;
    final rows = <Widget>[
      for (final d in defaults)
        _buildRow(
          id: d.id,
          title: l10n.translate(d.title),
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
              l10n.translate(category),
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
          color: checked ? Colors.white54 : Colors.white,
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
              tooltip: context.l10n.translate('check_delete_item'),
              icon: const Icon(Icons.delete_outline, color: Colors.white54),
              onPressed: () => _confirmDelete(id, title),
            )
          : null,
      onChanged: (val) => _setPacked(id, val ?? false),
    );
  }

  Future<void> _confirmDelete(String id, String title) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF14241B),
        title: Text(
            l10n.translate('check_delete_confirm', args: {'title': title}),
            style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l10n.translate('check_no'))),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(l10n.translate('check_delete'),
                  style: const TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.deleteChecklistItem(widget.tourId, id);
    } catch (_) {
      _showError(l10n.translate('check_admin_only_delete'));
    }
  }

  void _showAddItemDialog(BuildContext context) {
    final l10n = context.l10n;
    final titleCtrl = TextEditingController();

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF14241B),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(l10n.translate('check_add_item'),
              style: const TextStyle(color: Colors.white)),
          content: TextField(
            controller: titleCtrl,
            autofocus: true,
            maxLength: 80,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: l10n.translate('check_item_name'),
              labelStyle: const TextStyle(color: Colors.white70),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.translate('tour_cancel'),
                  style: const TextStyle(color: Colors.white54)),
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
                      widget.tourId, title, _customCategoryStored);
                } catch (e) {
                  _showError(
                      l10n.translate('check_add_failed', args: {'error': e}));
                }
              },
              child: Text(l10n.translate('check_add'),
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    ).whenComplete(titleCtrl.dispose);
  }

  static const _defaultItems = checklistDefaultItems;
}

/// The default checklist items, in a fixed order: each one's index is its
/// saved id (`default_0`, `default_1`, ...), so new items go at the end.
/// Titles and categories are translation keys.
const List<({String title, String category})> checklistDefaultItems = [
  (title: 'check_item_id_copy', category: 'check_cat_documents'),
  (title: 'check_item_tickets', category: 'check_cat_documents'),
  (title: 'check_item_basic_medicine', category: 'check_cat_medicines'),
  (title: 'check_item_first_aid', category: 'check_cat_medicines'),
  (title: 'check_item_charger', category: 'check_cat_electronics'),
  (title: 'check_item_plug_pouch', category: 'check_cat_electronics'),
  (title: 'check_item_cotton_clothes', category: 'check_cat_clothing'),
  (title: 'check_item_swimwear', category: 'check_cat_clothing'),
  (title: 'check_item_sunscreen', category: 'check_cat_beach'),
  (title: 'check_item_sandals', category: 'check_cat_beach'),
];
