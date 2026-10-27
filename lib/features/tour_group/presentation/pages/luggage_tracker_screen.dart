import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/logistics_models.dart';
import '../../domain/models/tour_group.dart';

const List<Color> kLuggageTagColors = [
  Color(0xFF00BFA5), // Mint Green
  Color(0xFFEF5350), // Red
  Color(0xFF42A5F5), // Blue
  Color(0xFFFFB300), // Amber / Gold
  Color(0xFFAB47BC), // Purple
  Color(0xFF26A69A), // Teal
  Color(0xFF8D6E63), // Brown
  Color(0xFF78909C), // Slate
];

class LuggageTrackerScreen extends StatefulWidget {
  final String tourId;
  final bool embedded;

  const LuggageTrackerScreen({
    super.key,
    required this.tourId,
    this.embedded = false,
  });

  @override
  State<LuggageTrackerScreen> createState() => _LuggageTrackerScreenState();
}

class _LuggageTrackerScreenState extends State<LuggageTrackerScreen> {
  final TourGroupRepository _repository = TourGroupRepository();
  final List<StreamSubscription<Object?>> _subs = [];

  List<LuggageItem> _items = const [];
  List<TourMember> _members = const [];
  TourRole? _myRole;
  bool _loaded = false;

  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;
  String get _me => _repository.currentEmail;

  @override
  void initState() {
    super.initState();
    _repository.myRole(widget.tourId).then((r) {
      if (mounted) setState(() => _myRole = r);
    });

    _subs.add(_repository.watchMembers(widget.tourId).listen((m) {
      if (mounted) setState(() => _members = m);
    }));

    _subs.add(_repository.watchLuggage(widget.tourId).listen((items) {
      if (mounted) {
        setState(() {
          _items = items;
          _loaded = true;
        });
      }
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  bool _canManage(LuggageItem item) =>
      _isAdmin ||
      item.ownerEmail.toLowerCase() == _me ||
      (item.custodianEmail != null &&
          item.custodianEmail!.toLowerCase() == _me);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final loadedCount = _items.where((i) => i.isLoaded).length;
    final pendingCount = _items.length - loadedCount;

    final content = ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 96),
      children: [
        // Summary Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF142428),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.translate('luggage_title'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${l10n.translate('luggage_loaded_badge')}: ${l10n.number(loadedCount)} · '
                      '${l10n.translate('luggage_unloaded_badge')}: ${l10n.number(pendingCount)}',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.mintGreen,
                  foregroundColor: AppColors.darkGreen,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(l10n.translate('luggage_add')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (!_loaded)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: AppColors.mintGreen),
            ),
          )
        else if (_items.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
            alignment: Alignment.center,
            child: Column(
              children: [
                const Icon(Icons.luggage_rounded,
                    size: 48, color: Colors.white24),
                const SizedBox(height: 12),
                Text(
                  l10n.translate('luggage_empty_title'),
                  style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.translate('luggage_empty_sub'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          )
        else
          for (final item in _items) _buildLuggageCard(l10n, item),
      ],
    );

    if (widget.embedded) return content;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1A1C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF142428),
        foregroundColor: Colors.white,
        title: Text(l10n.translate('luggage_title')),
      ),
      body: content,
    );
  }

  Widget _buildLuggageCard(AppLocalizations l10n, LuggageItem item) {
    Color tagColor;
    try {
      tagColor = Color(int.parse(item.tagColor));
    } catch (_) {
      tagColor = AppColors.mintGreen;
    }

    final canManage = _canManage(item);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF142428),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: item.isLoaded
              ? AppColors.mintGreen.withValues(alpha: 0.3)
              : Colors.white12,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Tag Color Indicator
              Container(width: 6, color: tagColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.luggage_rounded,
                              size: 18, color: tagColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          // Loaded / Unloaded Quick Switch
                          InkWell(
                            onTap: canManage
                                ? () => _toggleLoaded(item)
                                : null,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: item.isLoaded
                                    ? AppColors.mintGreen
                                        .withValues(alpha: 0.15)
                                    : Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: item.isLoaded
                                      ? AppColors.mintGreen
                                      : Colors.white24,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    item.isLoaded
                                        ? Icons.check_circle_rounded
                                        : Icons.radio_button_unchecked_rounded,
                                    size: 14,
                                    color: item.isLoaded
                                        ? AppColors.mintGreen
                                        : Colors.white60,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    l10n.translate(item.isLoaded
                                        ? 'luggage_loaded_badge'
                                        : 'luggage_unloaded_badge'),
                                    style: TextStyle(
                                      color: item.isLoaded
                                          ? AppColors.mintGreen
                                          : Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (canManage) ...[
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded,
                                  size: 18, color: Colors.white54),
                              padding: EdgeInsets.zero,
                              color: const Color(0xFF1E3238),
                              onSelected: (action) {
                                if (action == 'edit') {
                                  _openEditor(item: item);
                                } else if (action == 'delete') {
                                  _confirmDelete(item);
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      const Icon(Icons.edit_rounded,
                                          size: 16, color: Colors.white70),
                                      const SizedBox(width: 8),
                                      Text(l10n.translate('luggage_edit'),
                                          style: const TextStyle(
                                              color: Colors.white)),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      const Icon(Icons.delete_outline_rounded,
                                          size: 16, color: Colors.redAccent),
                                      const SizedBox(width: 8),
                                      Text(l10n.translate('luggage_delete'),
                                          style: const TextStyle(
                                              color: Colors.redAccent)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _chip(
                            Icons.person_rounded,
                            '${l10n.translate('luggage_owner_label')}: ${item.ownerName}',
                            Colors.white70,
                          ),
                          if ((item.custodianName ?? '').isNotEmpty)
                            _chip(
                              Icons.handshake_rounded,
                              '${l10n.translate('luggage_custodian_label')}: ${item.custodianName}',
                              AppColors.mintGreen,
                            ),
                          if ((item.locationNotes ?? '').isNotEmpty)
                            _chip(
                              Icons.place_rounded,
                              item.locationNotes!,
                              AppColors.gold,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: color, fontSize: 11)),
        ],
      ),
    );
  }

  Future<void> _toggleLoaded(LuggageItem item) async {
    final updated = item.copyWith(isLoaded: !item.isLoaded);
    await _repository.saveLuggage(widget.tourId, updated);
  }

  Future<void> _confirmDelete(LuggageItem item) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF142428),
        title: Text(l10n.translate('luggage_delete'),
            style: const TextStyle(color: Colors.white)),
        content: Text(
          l10n.translate('luggage_delete_confirm'),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.translate('hub_no')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.translate('hub_yes')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _repository.deleteLuggage(widget.tourId, item.id);
    }
  }

  Future<void> _openEditor({LuggageItem? item}) async {
    final l10n = context.l10n;
    final titleCtrl = TextEditingController(text: item?.title ?? '');
    final locationCtrl = TextEditingController(text: item?.locationNotes ?? '');
    Color selectedColor = item != null
        ? Color(int.tryParse(item.tagColor) ?? 0xFF00BFA5)
        : kLuggageTagColors.first;

    String selectedOwnerEmail = item?.ownerEmail ?? _me;
    String selectedOwnerName =
        item?.ownerName ?? _repository.currentDisplayName;
    String? selectedCustodianEmail = item?.custodianEmail;
    String? selectedCustodianName = item?.custodianName;

    bool isLoaded = item?.isLoaded ?? false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF142428),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.translate(item == null ? 'luggage_add' : 'luggage_edit'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),

                // Title
                TextField(
                  controller: titleCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: l10n.translate('luggage_name_label'),
                    hintText: l10n.translate('luggage_name_hint'),
                    hintStyle: const TextStyle(color: Colors.white30),
                  ),
                ),
                const SizedBox(height: 10),

                // Color picker strip
                Wrap(
                  spacing: 8,
                  children: [
                    for (final color in kLuggageTagColors)
                      InkWell(
                        onTap: () =>
                            setModalState(() => selectedColor = color),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selectedColor == color
                                  ? Colors.white
                                  : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          child: selectedColor == color
                              ? const Icon(Icons.check,
                                  size: 16, color: Colors.white)
                              : null,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // Owner dropdown
                DropdownButtonFormField<String>(
                  initialValue: _members.any((m) =>
                          m.email.toLowerCase() ==
                          selectedOwnerEmail.toLowerCase())
                      ? selectedOwnerEmail.toLowerCase()
                      : (_members.isNotEmpty
                          ? _members.first.email.toLowerCase()
                          : _me.toLowerCase()),
                  dropdownColor: const Color(0xFF1E3238),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: l10n.translate('luggage_owner_label'),
                  ),
                  items: [
                    if (_members.isEmpty)
                      DropdownMenuItem(
                        value: _me.toLowerCase(),
                        child: Text(_repository.currentDisplayName),
                      )
                    else
                      for (final m in _members)
                        DropdownMenuItem(
                          value: m.email.toLowerCase(),
                          child: Text(m.displayName),
                        ),
                  ],
                  onChanged: (email) {
                    if (email != null) {
                      setModalState(() {
                        selectedOwnerEmail = email;
                        final match = _members
                            .where((m) => m.email.toLowerCase() == email)
                            .firstOrNull;
                        selectedOwnerName =
                            match?.displayName ?? _repository.currentDisplayName;
                      });
                    }
                  },
                ),
                const SizedBox(height: 10),

                // Custodian dropdown
                DropdownButtonFormField<String?>(
                  initialValue: selectedCustodianEmail?.toLowerCase(),
                  dropdownColor: const Color(0xFF1E3238),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: l10n.translate('luggage_custodian_label'),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('—', style: TextStyle(color: Colors.white54)),
                    ),
                    for (final m in _members)
                      DropdownMenuItem<String?>(
                        value: m.email.toLowerCase(),
                        child: Text(m.displayName),
                      ),
                  ],
                  onChanged: (email) {
                    setModalState(() {
                      selectedCustodianEmail = email;
                      final match = email == null
                          ? null
                          : _members
                              .where((m) => m.email.toLowerCase() == email)
                              .firstOrNull;
                      selectedCustodianName = match?.displayName;
                    });
                  },
                ),
                const SizedBox(height: 10),

                // Location notes
                TextField(
                  controller: locationCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: l10n.translate('luggage_location_label'),
                    hintText: l10n.translate('luggage_location_hint'),
                    hintStyle: const TextStyle(color: Colors.white30),
                  ),
                ),
                const SizedBox(height: 10),

                // Loaded toggle
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    l10n.translate(isLoaded
                        ? 'luggage_loaded_status'
                        : 'luggage_unloaded_status'),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  value: isLoaded,
                  activeThumbColor: AppColors.mintGreen,
                  onChanged: (val) => setModalState(() => isLoaded = val),
                ),
                const SizedBox(height: 14),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.mintGreen,
                      foregroundColor: AppColors.darkGreen,
                    ),
                    onPressed: () async {
                      final title = titleCtrl.text.trim();
                      if (title.isEmpty) return;

                      final id = item?.id ??
                          DateTime.now().millisecondsSinceEpoch.toString();
                      final hex =
                          '0x${selectedColor.toARGB32().toRadixString(16).padLeft(8, '0')}';

                      final newItem = LuggageItem(
                        id: id,
                        tourId: widget.tourId,
                        title: title,
                        tagColor: hex,
                        ownerEmail: selectedOwnerEmail,
                        ownerName: selectedOwnerName,
                        custodianEmail: selectedCustodianEmail,
                        custodianName: selectedCustodianName,
                        locationNotes: locationCtrl.text.trim().isEmpty
                            ? null
                            : locationCtrl.text.trim(),
                        isLoaded: isLoaded,
                        updatedAt: DateTime.now(),
                      );

                      await _repository.saveLuggage(widget.tourId, newItem);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: Text(l10n.translate(
                        item == null ? 'luggage_add' : 'mag_close')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
