import 'package:flutter/material.dart';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:bhromon/features/tour_group/domain/services/study_tts_controller.dart';

/// Floating audio player dock for hands-free listening to exam solutions.
/// Allows banking candidates to review solutions during traffic commutes and walks.
class StudyCommuteAudioBar extends StatelessWidget {
  final StudyTtsController controller;
  final VoidCallback onClose;
  final ValueChanged<int>? onTrackChanged;

  const StudyCommuteAudioBar({
    super.key,
    required this.controller,
    required this.onClose,
    this.onTrackChanged,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.forest;
    final l10n = context.l10n;

    return ValueListenableBuilder<StudyAudioState>(
      valueListenable: controller.stateNotifier,
      builder: (context, state, _) {
        return ValueListenableBuilder<int>(
          valueListenable: controller.currentIndexNotifier,
          builder: (context, currentIndex, _) {
            final track = controller.currentTrack;
            final isPlaying = state == StudyAudioState.playing;
            final total = controller.totalTracks;
            final counter = total > 0 ? '${currentIndex + 1}/$total' : '';

            return Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: palette.isDark
                    ? const Color(0xFF16251D)
                    : const Color(0xFFF7FBF8),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isPlaying
                      ? palette.accentText.withValues(alpha: 0.6)
                      : palette.divider12,
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top Row: Track counter, title & dismiss
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: palette.accentText.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isPlaying
                                  ? Icons.graphic_eq_rounded
                                  : Icons.headphones_rounded,
                              size: 14,
                              color: palette.accentText,
                            ),
                            if (counter.isNotEmpty) ...[
                              const SizedBox(width: 4),
                              Text(
                                counter,
                                style: TextStyle(
                                  color: palette.accentText,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          track?.title ?? l10n.translate('study_audio_player'),
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded,
                            size: 18, color: palette.text54),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: l10n.translate('study_cancel'),
                        onPressed: () {
                          controller.stop();
                          onClose();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Bottom Controls Row: Speed, Rewind, Play/Pause, Fast Forward, Sleep Timer
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Speed Toggle Button
                      ValueListenableBuilder<double>(
                        valueListenable: controller.speedNotifier,
                        builder: (context, speed, _) {
                          return _speedButton(context, speed, palette);
                        },
                      ),

                      // Player Controls
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.skip_previous_rounded),
                            color: currentIndex > 0
                                ? palette.text
                                : palette.text54.withValues(alpha: 0.3),
                            iconSize: 26,
                            onPressed: currentIndex > 0
                                ? () {
                                    controller.previousTrack();
                                    onTrackChanged?.call(
                                        controller.currentIndexNotifier.value);
                                  }
                                : null,
                          ),
                          const SizedBox(width: 4),
                          IconButton.filled(
                            style: IconButton.styleFrom(
                              backgroundColor: AppColors.darkGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(10),
                            ),
                            icon: Icon(
                              isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 26,
                            ),
                            onPressed: () {
                              if (isPlaying) {
                                controller.pause();
                              } else {
                                controller.play();
                              }
                            },
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.skip_next_rounded),
                            color: currentIndex + 1 < total
                                ? palette.text
                                : palette.text54.withValues(alpha: 0.3),
                            iconSize: 26,
                            onPressed: currentIndex + 1 < total
                                ? () {
                                    controller.nextTrack();
                                    onTrackChanged?.call(
                                        controller.currentIndexNotifier.value);
                                  }
                                : null,
                          ),
                        ],
                      ),

                      // Sleep Timer Button
                      ValueListenableBuilder<int?>(
                        valueListenable: controller.sleepTimerRemainingNotifier,
                        builder: (context, remainingMinutes, _) {
                          return _sleepTimerButton(
                              context, remainingMinutes, palette, l10n);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _speedButton(
    BuildContext context,
    double speed,
    ForestPalette palette,
  ) {
    return PopupMenuButton<double>(
      initialValue: speed,
      tooltip: context.l10n.translate('study_audio_speed'),
      onSelected: (newSpeed) => controller.setSpeed(newSpeed),
      itemBuilder: (context) => [
        for (final s in [0.75, 1.0, 1.25, 1.5])
          PopupMenuItem(
            value: s,
            child: Text(
              '${s}x',
              style: TextStyle(
                fontWeight: s == speed ? FontWeight.bold : FontWeight.normal,
                color: s == speed ? AppColors.darkGreen : null,
              ),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: palette.divider10,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '${speed}x',
          style: TextStyle(
            color: palette.text,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _sleepTimerButton(
    BuildContext context,
    int? remaining,
    ForestPalette palette,
    AppLocalizations l10n,
  ) {
    final isActive = remaining != null && remaining > 0;
    return PopupMenuButton<int?>(
      tooltip: l10n.translate('study_audio_sleep_timer'),
      onSelected: (minutes) => controller.setSleepTimer(minutes),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: null,
          child: Text(l10n.translate('study_audio_timer_off')),
        ),
        for (final m in [15, 30, 45, 60])
          PopupMenuItem(
            value: m,
            child: Text(
              l10n.translate('study_audio_minutes', args: {'count': '$m'}),
              style: TextStyle(
                fontWeight:
                    remaining == m ? FontWeight.bold : FontWeight.normal,
                color: remaining == m ? AppColors.darkGreen : null,
              ),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive
              ? palette.accentText.withValues(alpha: 0.15)
              : palette.divider10,
          borderRadius: BorderRadius.circular(8),
          border: isActive
              ? Border.all(
                  color: palette.accentText.withValues(alpha: 0.5),
                  width: 0.8,
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bedtime_outlined,
              size: 13,
              color: isActive ? palette.accentText : palette.text54,
            ),
            const SizedBox(width: 4),
            Text(
              isActive ? '${remaining}m' : 'Timer',
              style: TextStyle(
                color: isActive ? palette.accentText : palette.text54,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
