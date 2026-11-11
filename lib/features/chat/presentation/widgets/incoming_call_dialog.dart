import 'dart:async';

import 'package:bhromon/core/media/media_access.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/utils/image_sizing.dart';
import '../../domain/call_display.dart';

/// The in-app dialog for an incoming call while the app is on screen.
///
/// [waiting] is set when the call rings during another call. The dialog then
/// shows the call-waiting label, and Accept ends the current call first.
class IncomingCallDialog extends StatelessWidget {
  final String callerName;
  final String? avatarUrl;
  final bool isVideo;
  final bool waiting;
  final Future<void> Function() onAccept;
  final Future<void> Function() onDecline;

  const IncomingCallDialog({
    super.key,
    required this.callerName,
    required this.avatarUrl,
    required this.isVideo,
    required this.waiting,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl;
    final hasAvatar = url != null && url.isNotEmpty;
    return AlertDialog(
      backgroundColor: AppColors.chatPanel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: AppColors.chatGreen,
            backgroundImage: hasAvatar
                ? CachedNetworkImageProvider(signedMediaUrl(url),
                    maxWidth: kMaxDecodeDimension)
                : null,
            child: hasAvatar
                ? null
                : Text(
                    callInitial(callerName),
                    style: const TextStyle(
                        fontSize: 32,
                        color: Colors.white,
                        fontWeight: FontWeight.bold),
                  ),
          ),
          const SizedBox(height: 16),
          Text(
            callerName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isVideo ? Icons.videocam : Icons.call,
                color: AppColors.chatGreen,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                context.l10n.translate(
                    isVideo ? 'call_incoming_video' : 'call_incoming_voice'),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
          if (waiting) ...[
            const SizedBox(height: 8),
            Text(
              context.l10n.translate('call_waiting'),
              key: const ValueKey('call-waiting-label'),
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              GestureDetector(
                onTap: () => unawaited(onDecline()),
                child: Column(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.call_end,
                          color: Colors.white, size: 26),
                    ),
                    const SizedBox(height: 6),
                    Text(context.l10n.translate('call_decline'),
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 12)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => unawaited(onAccept()),
                child: Column(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: const BoxDecoration(
                        color: AppColors.chatGreen,
                        shape: BoxShape.circle,
                      ),
                      child:
                          const Icon(Icons.call, color: Colors.white, size: 26),
                    ),
                    const SizedBox(height: 6),
                    Text(
                        context.l10n.translate(
                            waiting ? 'call_end_and_answer' : 'call_accept'),
                        style: const TextStyle(
                            color: AppColors.chatGreen, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
