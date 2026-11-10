import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/utils/app_logger.dart';

/// The action button displayed in the Group Hub AppBar (on Web and mobile-web view)
/// linking directly to Bhromon's Google Play Store listing.
class GooglePlayActionButton extends StatelessWidget {
  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.bhromon.app&pli=1';

  final VoidCallback? onTap;

  const GooglePlayActionButton({super.key, this.onTap});

  Future<void> _handleTap(BuildContext context) async {
    if (onTap != null) {
      onTap!();
      return;
    }
    try {
      final uri = Uri.parse(playStoreUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e, st) {
      logWarning('[GooglePlayActionButton] Failed to launch Play Store listing',
          e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: context.l10n.translate('hub_google_play_tooltip'),
      icon: const GooglePlayLogo(size: 20),
      onPressed: () => _handleTap(context),
    );
  }
}

/// A crisp, vector-rendered representation of the official 4-color Google Play logo.
class GooglePlayLogo extends StatelessWidget {
  final double size;

  const GooglePlayLogo({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size(size, size),
        painter: const _GooglePlayLogoPainter(),
      ),
    );
  }
}

class _GooglePlayLogoPainter extends CustomPainter {
  const _GooglePlayLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Proportional vertices matching the Google Play triangle
    final pTopLeft = Offset(w * 0.08, h * 0.06);
    final pBottomLeft = Offset(w * 0.08, h * 0.94);
    final pRightTip = Offset(w * 0.94, h * 0.50);
    final pCenter = Offset(w * 0.54, h * 0.50);
    final pTopCross = Offset(w * 0.68, h * 0.34);
    final pBottomCross = Offset(w * 0.68, h * 0.66);

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // 1. Blue triangle: Left base to center
    paint.color = const Color(0xFF00C3FF);
    final bluePath = Path()
      ..moveTo(pTopLeft.dx, pTopLeft.dy)
      ..lineTo(pBottomLeft.dx, pBottomLeft.dy)
      ..lineTo(pCenter.dx, pCenter.dy)
      ..close();
    canvas.drawPath(bluePath, paint);

    // 2. Green triangle: Top diagonal to center
    paint.color = const Color(0xFF00E676);
    final greenPath = Path()
      ..moveTo(pTopLeft.dx, pTopLeft.dy)
      ..lineTo(pTopCross.dx, pTopCross.dy)
      ..lineTo(pCenter.dx, pCenter.dy)
      ..close();
    canvas.drawPath(greenPath, paint);

    // 3. Red triangle: Bottom diagonal to center
    paint.color = const Color(0xFFFF334B);
    final redPath = Path()
      ..moveTo(pBottomLeft.dx, pBottomLeft.dy)
      ..lineTo(pBottomCross.dx, pBottomCross.dy)
      ..lineTo(pCenter.dx, pCenter.dy)
      ..close();
    canvas.drawPath(redPath, paint);

    // 4. Yellow triangle: Right arrow tip
    paint.color = const Color(0xFFFFCE00);
    final yellowPath = Path()
      ..moveTo(pTopCross.dx, pTopCross.dy)
      ..lineTo(pRightTip.dx, pRightTip.dy)
      ..lineTo(pBottomCross.dx, pBottomCross.dy)
      ..lineTo(pCenter.dx, pCenter.dy)
      ..close();
    canvas.drawPath(yellowPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
