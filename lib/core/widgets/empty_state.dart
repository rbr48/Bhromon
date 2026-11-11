import 'package:bhromon/core/theme/app_motion.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:flutter/material.dart';

/// What a list page shows when it has nothing yet: an icon in a soft circle
/// above one centred message. The icon is decoration, so a screen reader
/// reads the message alone.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const EmptyState({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final palette = context.forest;
    return FadeIn(
        child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.accentText.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 32, color: palette.accentText),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.text70, fontSize: 14),
            ),
          ],
        ),
      ),
    ));
  }
}
