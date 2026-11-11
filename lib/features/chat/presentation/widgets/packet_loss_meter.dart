import 'package:flutter/material.dart';

import 'package:bhromon/core/theme/forest_palette.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../domain/call_quality.dart';

/// Interactive Network Quality HUD for WebRTC audio and video calls.
///
/// Displays real-time connection status (HD, Fair, Weak) with dynamic
/// packet loss percentage, round-trip latency (RTT), and outbound bit-rate.
class CallQualityHud extends StatefulWidget {
  const CallQualityHud({
    super.key,
    required this.qualityNotifier,
    required this.sampleNotifier,
    this.initiallyExpanded = false,
    this.onTapDetails,
  });

  final ValueNotifier<CallNetworkQuality> qualityNotifier;
  final ValueNotifier<CallLinkSample?> sampleNotifier;
  final bool initiallyExpanded;
  final VoidCallback? onTapDetails;

  @override
  State<CallQualityHud> createState() => _CallQualityHudState();
}

class _CallQualityHudState extends State<CallQualityHud> {
  late bool _expanded = widget.initiallyExpanded;

  Color _badgeColor(CallNetworkQuality quality) => switch (quality) {
        CallNetworkQuality.good => const Color(0xFF00E676),
        CallNetworkQuality.fair => const Color(0xFFFFD600),
        CallNetworkQuality.poor => const Color(0xFFFF1744),
      };

  String _qualityLabel(AppLocalizations l10n, CallNetworkQuality quality) =>
      switch (quality) {
        CallNetworkQuality.good => l10n.translate('chat_quality_hd'),
        CallNetworkQuality.fair => l10n.translate('chat_quality_fair'),
        CallNetworkQuality.poor => l10n.translate('chat_quality_weak'),
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return ValueListenableBuilder<CallNetworkQuality>(
      valueListenable: widget.qualityNotifier,
      builder: (context, quality, _) {
        final color = _badgeColor(quality);
        final label = _qualityLabel(l10n, quality);

        return ValueListenableBuilder<CallLinkSample?>(
          valueListenable: widget.sampleNotifier,
          builder: (context, sample, _) {
            final lossRatio = sample?.lossRatio;
            final isHighLoss = lossRatio != null && lossRatio >= 0.08;

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      if (widget.onTapDetails != null) {
                        widget.onTapDetails!();
                      } else {
                        setState(() => _expanded = !_expanded);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: color.withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.6),
                                  blurRadius: 3,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            label,
                            style: TextStyle(
                              color: color,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (lossRatio != null) ...[
                            const SizedBox(width: 4),
                            Text(
                              '· ${(lossRatio * 100).toStringAsFixed(0)}% loss',
                              style: TextStyle(
                                color: color.withValues(alpha: 0.9),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          const SizedBox(width: 4),
                          Icon(
                            _expanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 14,
                            color: color,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_expanded && sample != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (sample.roundTripMs != null) ...[
                          _HudItem(
                            label: 'RTT',
                            value: '${sample.roundTripMs!.round()} ms',
                            color: context.forest.text70,
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (sample.lossRatio != null) ...[
                          _HudItem(
                            label: 'Loss',
                            value:
                                '${(sample.lossRatio! * 100).toStringAsFixed(1)}%',
                            color: isHighLoss ? Colors.redAccent : color,
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (sample.outboundKbps != null)
                          _HudItem(
                            label: 'Rate',
                            value: '${sample.outboundKbps!.round()} k',
                            color: context.forest.text70,
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

class _HudItem extends StatelessWidget {
  const _HudItem({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
