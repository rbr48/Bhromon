import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../data/active_group.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/desktop_nav.dart';

/// Desktop quick group switcher dialog triggered from the sidebar header.
/// Allows fast 1-click group switching from anywhere on desktop web.
class DesktopGroupSwitcherDialog extends StatefulWidget {
  final String activeTourId;
  final String currentLocation;
  final TourGroupRepository repository;

  const DesktopGroupSwitcherDialog({
    super.key,
    required this.activeTourId,
    required this.currentLocation,
    required this.repository,
  });

  static Future<void> show(
    BuildContext context, {
    required String activeTourId,
    required String currentLocation,
    required TourGroupRepository repository,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => DesktopGroupSwitcherDialog(
        activeTourId: activeTourId,
        currentLocation: currentLocation,
        repository: repository,
      ),
    );
  }

  @override
  State<DesktopGroupSwitcherDialog> createState() =>
      _DesktopGroupSwitcherDialogState();
}

class _DesktopGroupSwitcherDialogState
    extends State<DesktopGroupSwitcherDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  late final Stream<List<TourGroup>> _groupsStream;

  @override
  void initState() {
    super.initState();
    _groupsStream = widget.repository.watchMyGroups();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _groupEmoji(TourGroup g) {
    if (g.isFriends) return '🤝';
    if (g.isStudy) return '📚';
    if (g.isOffice) return '💼';
    if (g.isMess) return '🍛';
    if (g.isSociety) return '🏘️';
    if (g.isCampus) return '🎓';
    if (g.kind == GroupKind.family) return '👨‍👩‍👧';
    return '🌴';
  }

  void _onSelect(TourGroup group) async {
    await ActiveGroup.instance.select(group.id);
    if (!mounted) return;
    final router = GoRouter.of(context);
    final targetRoute = pathForGroupSwitch(group, widget.currentLocation);
    Navigator.of(context).pop();
    router.go(targetRoute);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isBn = l10n.locale.languageCode == 'bn';
    final palette = context.forest;

    return Dialog(
      backgroundColor: palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.divider10),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 420,
          maxHeight: 520,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    Icons.swap_horiz_rounded,
                    color: palette.accentText,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isBn ? 'গ্রুপ পরিবর্তন করুন' : 'Switch Group',
                      style: TextStyle(
                        color: palette.text,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded,
                        color: palette.text54, size: 20),
                    splashRadius: 18,
                    tooltip: isBn ? 'বন্ধ করুন' : 'Close',
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Search Input
              TextField(
                controller: _searchController,
                style: TextStyle(color: palette.text, fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: isBn
                      ? 'নাম বা ধরন দিয়ে খুঁজুন...'
                      : 'Search groups by name or type...',
                  hintStyle: TextStyle(color: palette.text54, fontSize: 13),
                  prefixIcon: Icon(Icons.search_rounded,
                      color: palette.text54, size: 18),
                  filled: true,
                  fillColor: palette.surfaceFor(const Color(0xFF132219)),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: palette.divider10),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: palette.divider10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                        color: AppColors.mintGreen, width: 1.5),
                  ),
                ),
                onChanged: (val) => setState(() => _query = val.trim()),
              ),
              const SizedBox(height: 12),

              // Group List
              Expanded(
                child: StreamBuilder<List<TourGroup>>(
                  stream: _groupsStream,
                  builder: (context, snapshot) {
                    final allGroups = snapshot.data ?? [];
                    final filtered = allGroups.where((g) {
                      if (_query.isEmpty) return true;
                      final q = _query.toLowerCase();
                      return g.name.toLowerCase().contains(q) ||
                          g.destination.toLowerCase().contains(q) ||
                          (g.preset ?? '').toLowerCase().contains(q);
                    }).toList();

                    if (filtered.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            isBn
                                ? 'কোনো গ্রুপ পাওয়া যায়নি'
                                : 'No groups found',
                            style: TextStyle(
                              color: palette.text54,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final g = filtered[index];
                        final isSelected = g.id == widget.activeTourId;
                        final typeKey = groupTypeLabelKey(g);
                        final subtitle = typeKey != null
                            ? l10n.translate(typeKey)
                            : (g.destination.isNotEmpty
                                ? g.destination
                                : (isBn ? 'ভ্রমণ' : 'Trip'));

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: InkWell(
                            onTap: () => _onSelect(g),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.mintGreen
                                        .withValues(alpha: 0.12)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.mintGreen
                                          .withValues(alpha: 0.6)
                                      : Colors.transparent,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: palette
                                          .surfaceFor(const Color(0xFF132219)),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: Text(
                                        _groupEmoji(g),
                                        style: const TextStyle(fontSize: 18),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          g.name,
                                          style: TextStyle(
                                            color: palette.text,
                                            fontWeight: isSelected
                                                ? FontWeight.bold
                                                : FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          subtitle,
                                          style: TextStyle(
                                            color: palette.text54,
                                            fontSize: 11.5,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: AppColors.mintGreen,
                                      size: 18,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              const SizedBox(height: 8),
              Divider(color: palette.divider10, height: 1),
              const SizedBox(height: 8),

              // Bottom Hub Link
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    final router = GoRouter.of(context);
                    Navigator.of(context).pop();
                    router.go('/group-hub');
                  },
                  icon: const Icon(Icons.hub_outlined, size: 16),
                  label: Text(
                    isBn ? 'সকল গ্রুপ হাব দেখুন' : 'View all groups hub',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
