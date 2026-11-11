import 'package:flutter/material.dart';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:bhromon/features/tour_group/domain/models/study_offline_vault_models.dart';

/// Card displayed at the top of study book chapters screen, providing one-tap
/// zero-network offline caching of the full subject book, all chapters, and examiner-grade solutions.
class StudyOfflineVaultCard extends StatelessWidget {
  final StudyOfflinePackage? package;
  final bool isDownloading;
  final VoidCallback onDownload;
  final VoidCallback onRemove;

  const StudyOfflineVaultCard({
    super.key,
    required this.package,
    this.isDownloading = false,
    required this.onDownload,
    required this.onRemove,
  });

  bool get isCached => package != null;

  @override
  Widget build(BuildContext context) {
    final palette = context.forest;
    final l10n = context.l10n;

    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isCached
              ? palette.accentText.withValues(alpha: 0.4)
              : palette.divider12,
          width: isCached ? 1.0 : 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isCached
                        ? (palette.isDark
                            ? const Color(0xFF1E3A2B)
                            : const Color(0xFFE8F5E9))
                        : palette.divider10,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isCached
                          ? palette.accentText.withValues(alpha: 0.5)
                          : palette.divider12,
                      width: 0.8,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    isCached
                        ? Icons.offline_pin_rounded
                        : Icons.cloud_download_outlined,
                    color: isCached ? palette.accentText : palette.text70,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              l10n.translate('study_offline_vault_title'),
                              style: TextStyle(
                                color: palette.text,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isCached) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color:
                                    palette.accentText.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color:
                                      palette.accentText.withValues(alpha: 0.4),
                                  width: 0.6,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: palette.accentText,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    l10n.translate('study_offline_saved_badge'),
                                    style: TextStyle(
                                      color: palette.accentText,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isCached
                            ? l10n.translate('study_offline_vault_cached_desc',
                                args: {
                                    'count': '${package!.materialCount}',
                                    'size': package!.formattedSize,
                                  })
                            : l10n
                                .translate('study_offline_vault_uncached_desc'),
                        style: TextStyle(
                          color: palette.text70,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isDownloading)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                else if (isCached)
                  PopupMenuButton<String>(
                    tooltip: l10n.translate('study_offline_vault_title'),
                    icon: Icon(Icons.more_vert_rounded,
                        color: palette.text70, size: 20),
                    onSelected: (choice) {
                      if (choice == 'update') {
                        onDownload();
                      } else if (choice == 'remove') {
                        onRemove();
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem<String>(
                        value: 'update',
                        child: Row(
                          children: [
                            Icon(Icons.refresh_rounded,
                                color: palette.accentText, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l10n.translate('study_offline_update'),
                                style: TextStyle(
                                  color: palette.isDark
                                      ? Colors.white
                                      : AppColors.darkText,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'remove',
                        child: Row(
                          children: [
                            const Icon(Icons.delete_outline_rounded,
                                color: Colors.red, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l10n.translate('study_offline_remove'),
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  ElevatedButton.icon(
                    onPressed: onDownload,
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: Text(
                      l10n.translate('study_offline_save_button'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.isDark
                          ? const Color(0xFF1E3A2B)
                          : const Color(0xFFE8F5E9),
                      foregroundColor: palette.isDark
                          ? AppColors.mintGreen
                          : const Color(0xFF1B5E20),
                      elevation: 0,
                      side: BorderSide(
                        color: palette.accentText.withValues(alpha: 0.5),
                        width: 0.8,
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      minimumSize: const Size(0, 36),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
