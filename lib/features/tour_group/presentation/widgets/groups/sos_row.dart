import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:flutter/material.dart';

/// The safety row on a group page: the family's alerts, locations and SOS, one step
/// from the group. Shown under the same condition as the safety tile (not a managed
/// office or campus).
class SosRow extends StatelessWidget {
  const SosRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.hasActiveAlert = false,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool hasActiveAlert;

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFEF4444);
    final borderColor = hasActiveAlert
        ? red.withValues(alpha: 0.5)
        : context.forest.text.withValues(alpha: 0.12);
    final iconColor = hasActiveAlert ? red : context.forest.accentText;

    return Semantics(
      button: true,
      label: title,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: context.forest.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Icon(Icons.shield_rounded, color: iconColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              color: context.forest.text,
                              fontWeight: FontWeight.bold)),
                      Text(subtitle,
                          style: TextStyle(
                              color: context.forest.text54, fontSize: 12)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: context.forest.text54),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
