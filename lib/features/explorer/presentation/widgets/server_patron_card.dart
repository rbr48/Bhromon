import 'package:flutter/material.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';

/// A transparent, non-intrusive patronage card encouraging community support
/// to keep Bhromon's self-hosted VPS and open-source infrastructure running.
///
/// Donations go through one Bangla QR code, which bKash, Nagad, Rocket and bank apps
/// can all scan. It is shown on white, so it scans from the dark card.
class ServerPatronCard extends StatelessWidget {
  const ServerPatronCard({super.key});

  static const String donationQrAsset =
      'assets/donation/krishi_bank_bangla_qr.png';
  static const String githubRepoUrl = 'https://github.com/rbr48/Bhromon';

  void _openSupportSheet(BuildContext context) {
    final l10n = context.l10n;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.forest.surfaceFor(const Color(0xFF14241B)),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.mintGreen.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.volunteer_activism_rounded,
                        color: context.forest.accentText,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n.translate('server_patron_title'),
                        style: TextStyle(
                          color: context.forest.text,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  l10n.translate('server_patron_desc'),
                  style: TextStyle(
                    color: context.forest.text70,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                Center(child: _buildQr(context)),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    l10n.translate('server_patron_qr_caption'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.forest.text70,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      launchUrl(
                        Uri.parse(githubRepoUrl),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    icon: Icon(Icons.code_rounded,
                        color: context.forest.accentText, size: 18),
                    label: Text(
                      l10n.translate('server_patron_github'),
                      style: TextStyle(color: context.forest.accentText),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The Bangla QR on a white tile, so it scans from the dark card.
  Widget _buildQr(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Image.asset(
        donationQrAsset,
        width: 220,
        height: 220,
        semanticLabel: context.l10n.translate('server_patron_qr_chip'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isBn = Localizations.localeOf(context).languageCode == 'bn';

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1B4332).withValues(alpha: 0.9),
            const Color(0xFF14241B),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.mintGreen.withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Heart Icon
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.mintGreen.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.volunteer_activism_rounded,
                  color: AppColors.mintGreen,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.translate('server_patron_title'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isBn ? 'স্বেচ্ছাসেবী' : 'Open Source',
                  style: const TextStyle(
                    color: AppColors.mintGreen,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Description
          Text(
            l10n.translate('server_patron_desc'),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),

          // The donation QR opens from here, and so does the details sheet.
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _openSupportSheet(context),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    decoration: BoxDecoration(
                      color: AppColors.mintGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.mintGreen.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.qr_code_2_rounded,
                            color: AppColors.mintGreen, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          l10n.translate('server_patron_qr_chip'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Details & GitHub Button
              InkWell(
                onTap: () => _openSupportSheet(context),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.mintGreen,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
