import 'package:bhromon/core/theme/colors.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/media/media_access.dart';
import '../../../../core/utils/image_sizing.dart';
import '../../data/call_signaling_service.dart';
import '../../domain/call_display.dart';

/// WhatsApp deep theme tokens
class WhatsAppCallTheme {
  WhatsAppCallTheme._();

  static const Color background = Color(0xFF0B141A);
  static const Color surface = AppColors.chatPanel;
  static const Color surfaceElevated = Color(0xFF2A3942);
  static const Color primary = AppColors.chatGreen;
  static const Color primaryDark = Color(0xFF075E54);
  static const Color accentRed = Color(0xFFEA4335);
  static const Color textMuted = Color(0xFF8696A0);
}

/// Concentric pulsing ripple animation around avatar when ringing or active.
class WhatsAppPulsingAvatar extends StatefulWidget {
  final String userName;
  final String? avatarUrl;
  final bool isRingingOrActive;

  const WhatsAppPulsingAvatar({
    super.key,
    required this.userName,
    this.avatarUrl,
    required this.isRingingOrActive,
  });

  @override
  State<WhatsAppPulsingAvatar> createState() => _WhatsAppPulsingAvatarState();
}

class _WhatsAppPulsingAvatarState extends State<WhatsAppPulsingAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    if (widget.isRingingOrActive) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(WhatsAppPulsingAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRingingOrActive && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isRingingOrActive && _controller.isAnimating) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const avatarSize = 136.0;
    final initials = callInitial(widget.userName);

    return SizedBox(
      width: 220,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer ripple ring
          if (widget.isRingingOrActive)
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final scale = 1.0 + (_controller.value * 0.45);
                final opacity =
                    (1.0 - _controller.value).clamp(0.0, 1.0) * 0.28;
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: avatarSize + 40,
                    height: avatarSize + 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: WhatsAppCallTheme.primary
                            .withValues(alpha: opacity),
                        width: 2.0,
                      ),
                      color: WhatsAppCallTheme.primary
                          .withValues(alpha: opacity * 0.3),
                    ),
                  ),
                );
              },
            ),

          // Mid ripple ring
          if (widget.isRingingOrActive)
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final midProgress = (_controller.value + 0.45) % 1.0;
                final scale = 1.0 + (midProgress * 0.32);
                final opacity = (1.0 - midProgress).clamp(0.0, 1.0) * 0.22;
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: avatarSize + 20,
                    height: avatarSize + 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: WhatsAppCallTheme.primary
                          .withValues(alpha: opacity * 0.25),
                    ),
                  ),
                );
              },
            ),

          // Central Profile Avatar
          Container(
            width: avatarSize,
            height: avatarSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: WhatsAppCallTheme.primaryDark,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipOval(
              child: (widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: signedMediaUrl(widget.avatarUrl!),
                      fit: BoxFit.cover,
                      memCacheWidth: context.decodeWidth(avatarSize),
                      placeholder: (_, __) => _initialsWidget(initials),
                      errorWidget: (_, __, ___) => _initialsWidget(initials),
                    )
                  : _initialsWidget(initials),
            ),
          ),
        ],
      ),
    );
  }

  Widget _initialsWidget(String initials) => Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 46,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
}

/// Circular styled WhatsApp call action button with icon and text label.
class WhatsAppCallActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final Color bgColor;
  final VoidCallback onTap;
  final bool isEndCall;

  const WhatsAppCallActionBtn({
    super.key,
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.bgColor,
    required this.onTap,
    this.isEndCall = false,
  });

  @override
  Widget build(BuildContext context) {
    final buttonSize = isEndCall ? 62.0 : 52.0;

    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: buttonSize,
              height: buttonSize,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: isEndCall
                        ? Colors.redAccent.withValues(alpha: 0.45)
                        : Colors.black.withValues(alpha: 0.3),
                    blurRadius: isEndCall ? 14 : 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: isEndCall ? 30 : 24,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              style: TextStyle(
                color:
                    isEndCall ? Colors.redAccent : WhatsAppCallTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Floating draggable local video preview tile with corner-docking physics.
class WhatsAppDraggablePip extends StatefulWidget {
  final RTCVideoRenderer renderer;
  final VoidCallback onDoubleTapOrTapFlip;

  const WhatsAppDraggablePip({
    super.key,
    required this.renderer,
    required this.onDoubleTapOrTapFlip,
  });

  @override
  State<WhatsAppDraggablePip> createState() => _WhatsAppDraggablePipState();
}

class _WhatsAppDraggablePipState extends State<WhatsAppDraggablePip> {
  Offset _position = const Offset(16, 72);
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final size = MediaQuery.of(context).size;
      // Default initial position: top-right corner
      _position = Offset(size.width - 126, 72);
      _initialized = true;
    }
  }

  void _snapToNearestCorner(Size screenSize) {
    const tileWidth = 110.0;
    const tileHeight = 160.0;
    const margin = 16.0;
    final topMargin = MediaQuery.of(context).padding.top + 50.0;
    final bottomMargin = MediaQuery.of(context).padding.bottom + 120.0;

    final targetX = (_position.dx + (tileWidth / 2)) < (screenSize.width / 2)
        ? margin
        : screenSize.width - tileWidth - margin;

    final targetY = (_position.dy + (tileHeight / 2)) < (screenSize.height / 2)
        ? topMargin
        : screenSize.height - tileHeight - bottomMargin;

    setState(() {
      _position = Offset(targetX, targetY);
    });
  }

  @override
  Widget build(BuildContext context) {
    const tileWidth = 110.0;
    const tileHeight = 160.0;
    final size = MediaQuery.of(context).size;

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _position = Offset(
              (_position.dx + details.delta.dx)
                  .clamp(8.0, size.width - tileWidth - 8.0),
              (_position.dy + details.delta.dy)
                  .clamp(40.0, size.height - tileHeight - 60.0),
            );
          });
        },
        onPanEnd: (_) => _snapToNearestCorner(size),
        onTap: widget.onDoubleTapOrTapFlip,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: tileWidth,
          height: tileHeight,
          decoration: BoxDecoration(
            color: WhatsAppCallTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.25),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.hardEdge,
          child: Stack(
            fit: StackFit.expand,
            children: [
              RTCVideoView(
                widget.renderer,
                mirror: true,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
              Positioned(
                bottom: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.cameraswitch_rounded,
                    color: Colors.white,
                    size: 14,
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

/// Call details modal displaying network metrics, RTT, jitter, and remote volume control.
void showWhatsAppCallDetailsSheet({
  required BuildContext context,
  required CallSignalingService signaling,
}) {
  final sample = signaling.linkSample;
  final l10n = context.l10n;

  String figure(double? val, String unit, {int digits = 0}) => val == null
      ? l10n.translate('call_quality_no_data')
      : '${val.toStringAsFixed(digits)} $unit';

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: WhatsAppCallTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (sheetContext, setModalState) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        color: WhatsAppCallTheme.primary, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      l10n.translate('call_quality_title'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: WhatsAppCallTheme.textMuted, size: 20),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const Divider(color: Colors.white12, height: 24),
                _sheetRow(l10n.translate('call_quality_rtt'),
                    figure(sample?.roundTripMs, 'ms')),
                _sheetRow(l10n.translate('chat_quality_jitter'),
                    figure(sample?.jitterMs, 'ms')),
                _sheetRow(
                  l10n.translate('call_quality_loss'),
                  sample?.lossRatio == null
                      ? l10n.translate('call_quality_no_data')
                      : '${(sample!.lossRatio! * 100).toStringAsFixed(1)} %',
                ),
                _sheetRow(l10n.translate('chat_quality_sending'),
                    figure(sample?.outboundKbps, 'kbps')),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.translate('chat_quality_loudness'),
                      style: const TextStyle(
                          color: WhatsAppCallTheme.textMuted, fontSize: 13),
                    ),
                    Row(
                      children: [1.0, 2.0, 3.0].map((gain) {
                        final isSelected =
                            (signaling.remoteGain - gain).abs() < 0.1;
                        return Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: InkWell(
                            onTap: () {
                              signaling.setRemoteGain(gain);
                              setModalState(() {});
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? WhatsAppCallTheme.primary
                                    : WhatsAppCallTheme.surfaceElevated,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                '${gain.toInt()}x',
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : WhatsAppCallTheme.textMuted,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Widget _sheetRow(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: WhatsAppCallTheme.textMuted, fontSize: 13)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
