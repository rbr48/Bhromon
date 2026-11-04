import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import '../../../domain/services/offline_map_regions.dart';

const double _kMaxModalWidth = 560.0;

/// Bottom sheet modal to explore, download, and manage offline map packs
/// and emergency waypoint contacts for remote Bangladesh travel zones.
class OfflineMapPackSheet extends StatefulWidget {
  const OfflineMapPackSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const OfflineMapPackSheet(),
    );
  }

  @override
  State<OfflineMapPackSheet> createState() => _OfflineMapPackSheetState();
}

class _OfflineMapPackSheetState extends State<OfflineMapPackSheet> {
  String? _selectedDivision;
  final Set<String> _downloadedPacks = {'sajek_valley'};
  String? _downloadingId;
  OfflineMapRegion? _viewingRegion;

  List<OfflineMapRegion> get _filteredRegions {
    if (_selectedDivision == null) return kCuratedOfflineRegions;
    return kCuratedOfflineRegions
        .where((r) => r.division == _selectedDivision)
        .toList();
  }

  Future<void> _callEmergency(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _toggleDownload(OfflineMapRegion region) async {
    if (_downloadedPacks.contains(region.id)) {
      setState(() {
        _downloadedPacks.remove(region.id);
      });
      return;
    }
    setState(() => _downloadingId = region.id);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() {
      _downloadingId = null;
      _downloadedPacks.add(region.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isBn = l10n.locale.languageCode == 'bn';
    final divisions =
        kCuratedOfflineRegions.map((r) => r.division).toSet().toList()..sort();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _kMaxModalWidth),
        child: Container(
          decoration: BoxDecoration(
            color: context.forest.surfaceFor(const Color(0xFF14241F)),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: context.forest.text24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.offline_pin_rounded,
                      color: AppColors.mintGreen, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isBn
                          ? 'অফলাইন ম্যাপ ও ট্রাভেল প্যাক'
                          : 'Offline Map Packs',
                      style: TextStyle(
                        color: context.forest.text,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon:
                        Icon(Icons.close_rounded, color: context.forest.text70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Text(
                isBn
                    ? 'নেটওয়ার্কবিহীন দুর্গম এলাকায় চলাচলের জন্য অফলাইন ম্যাপ এবং হেল্পলাইন সেভ রাখুন।'
                    : 'Download vector map tiles and emergency waypoints for low-connectivity regions.',
                style: TextStyle(color: context.forest.text54, fontSize: 13),
              ),
              const SizedBox(height: 12),
              // Division filter
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      label: Text(isBn ? 'সব অঞ্চল' : 'All Regions',
                          style: const TextStyle(fontSize: 12)),
                      selected: _selectedDivision == null,
                      selectedColor: AppColors.mintGreen,
                      onSelected: (_) =>
                          setState(() => _selectedDivision = null),
                    ),
                    const SizedBox(width: 6),
                    for (final div in divisions) ...[
                      FilterChip(
                        label: Text(div, style: const TextStyle(fontSize: 12)),
                        selected: _selectedDivision == div,
                        selectedColor: AppColors.mintGreen,
                        onSelected: (_) =>
                            setState(() => _selectedDivision = div),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.55,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _filteredRegions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final region = _filteredRegions[i];
                    final isCached = _downloadedPacks.contains(region.id);
                    final isDownloading = _downloadingId == region.id;
                    final isExpanded = _viewingRegion?.id == region.id;

                    return Card(
                      color: context.forest.surfaceFor(const Color(0xFF1E3326)),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isCached
                              ? AppColors.mintGreen.withValues(alpha: 0.4)
                              : Colors.transparent,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isCached
                                  ? AppColors.mintGreen
                                  : context.forest.text24,
                              foregroundColor: isCached
                                  ? AppColors.darkGreen
                                  : context.forest.text,
                              child: Icon(
                                isCached
                                    ? Icons.check_circle_rounded
                                    : Icons.map_rounded,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              isBn ? region.nameBn : region.nameEn,
                              style: TextStyle(
                                color: context.forest.text,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              '${region.division} · ~${region.estimatedMb} MB · ${region.waypoints.length} ওয়েপয়েন্ট',
                              style: TextStyle(
                                  color: context.forest.text54, fontSize: 12),
                            ),
                            trailing: isDownloading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.mintGreen,
                                    ),
                                  )
                                : IconButton(
                                    icon: Icon(
                                      isCached
                                          ? Icons.delete_outline_rounded
                                          : Icons.download_rounded,
                                      color: isCached
                                          ? context.forest
                                              .readable(Colors.redAccent)
                                          : AppColors.mintGreen,
                                    ),
                                    tooltip: isCached
                                        ? (isBn ? 'ক্যাশ মুছুন' : 'Delete')
                                        : (isBn ? 'ডাউনলোড' : 'Download'),
                                    onPressed: () => _toggleDownload(region),
                                  ),
                            onTap: () {
                              setState(() {
                                _viewingRegion = isExpanded ? null : region;
                              });
                            },
                          ),
                          if (isExpanded) ...[
                            const Divider(height: 1, indent: 16, endIndent: 16),
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isBn
                                        ? 'জরুরি যোগাযোগ ও সহায়তা নম্বর:'
                                        : 'Emergency Helplines:',
                                    style: TextStyle(
                                      color: context.forest.accentText,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  for (final contact in region.contacts)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '• ${isBn ? contact.titleBn : contact.titleEn} (${contact.phone})',
                                              style: TextStyle(
                                                color: context.forest.text70,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            constraints: const BoxConstraints(),
                                            padding: const EdgeInsets.all(4),
                                            icon: const Icon(
                                              Icons.phone_in_talk_rounded,
                                              size: 16,
                                              color: AppColors.mintGreen,
                                            ),
                                            onPressed: () =>
                                                _callEmergency(contact.phone),
                                          ),
                                        ],
                                      ),
                                    ),
                                  const SizedBox(height: 6),
                                  Text(
                                    isBn
                                        ? 'অফলাইন ওয়েপয়েন্টস (ভিউ ও ক্যাম্প):'
                                        : 'Offline Waypoints:',
                                    style: TextStyle(
                                      color: context.forest.accentText,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  for (final wp in region.waypoints)
                                    Text(
                                      '📍 ${isBn ? wp.nameBn : wp.nameEn} [${wp.lat.toStringAsFixed(4)}, ${wp.lng.toStringAsFixed(4)}]',
                                      style: TextStyle(
                                        color: context.forest.text54,
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
