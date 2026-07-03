import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../theme/colors.dart';

class VoiceNotePlayerWidget extends StatefulWidget {
  final String storageUrl;
  final String? localPath;
  final int durationSeconds;
  final String? transcript;
  final bool isDarkTheme;

  const VoiceNotePlayerWidget({
    super.key,
    required this.storageUrl,
    this.localPath,
    required this.durationSeconds,
    this.transcript,
    this.isDarkTheme = false,
  });

  @override
  State<VoiceNotePlayerWidget> createState() => _VoiceNotePlayerWidgetState();
}

class _VoiceNotePlayerWidgetState extends State<VoiceNotePlayerWidget>
    with SingleTickerProviderStateMixin {
  late AudioPlayer _player;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  late AnimationController _waveformController;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _duration = Duration(seconds: widget.durationSeconds);

    _waveformController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
          if (_isPlaying) {
            _waveformController.repeat(reverse: true);
          } else {
            _waveformController.stop();
          }
        });
      }
    });

    _player.onPositionChanged.listen((pos) {
      if (mounted) {
        setState(() {
          _position = pos;
        });
      }
    });

    _player.onDurationChanged.listen((dur) {
      if (mounted) {
        setState(() {
          _duration = dur;
        });
      }
    });

    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
          _waveformController.reset();
        });
      }
    });
  }

  @override
  void dispose() {
    _waveformController.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    try {
      if (_isPlaying) {
        await _player.pause();
      } else {
        Source source;
        final bool hasLocalFile = !kIsWeb &&
            widget.localPath != null &&
            widget.localPath!.isNotEmpty &&
            File(widget.localPath!).existsSync();

        if (hasLocalFile) {
          source = DeviceFileSource(widget.localPath!);
        } else if (widget.storageUrl.isNotEmpty) {
          source = UrlSource(widget.storageUrl);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('অডিও ফাইলটি পাওয়া যায়নি।')),
          );
          return;
        }
        await _player.play(source);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('প্লে করতে সমস্যা হয়েছে: $e')),
      );
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final themeBg = widget.isDarkTheme
        ? AppColors.cardDark
        : const Color(0xFFF4F6F4);
    final themeBorder = widget.isDarkTheme
        ? AppColors.mintGreen.withValues(alpha: 0.2)
        : AppColors.midGreen.withValues(alpha: 0.15);
    final iconColor = widget.isDarkTheme ? AppColors.mintGreen : AppColors.midGreen;
    final textColor = widget.isDarkTheme ? Colors.white : AppColors.darkText;
    final textMutedColor = widget.isDarkTheme ? Colors.white54 : AppColors.grayText;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: themeBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: themeBorder),
        boxShadow: widget.isDarkTheme
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                )
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Play/Pause circular button
              GestureDetector(
                onTap: _togglePlay,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: iconColor,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Waveform and progress bar area
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _formatDuration(_position),
                          style: TextStyle(
                            color: textMutedColor,
                            fontSize: 11,
                            fontFamily: 'Courier',
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _formatDuration(_duration),
                          style: TextStyle(
                            color: textMutedColor,
                            fontSize: 11,
                            fontFamily: 'Courier',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 3.0,
                        activeTrackColor: iconColor,
                        inactiveTrackColor: iconColor.withValues(alpha: 0.15),
                        thumbColor: iconColor,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
                      ),
                      child: Slider(
                        min: 0.0,
                        max: _duration.inMilliseconds.toDouble() > 0
                            ? _duration.inMilliseconds.toDouble()
                            : 100.0,
                        value: _position.inMilliseconds.toDouble().clamp(
                              0.0,
                              _duration.inMilliseconds.toDouble() > 0
                                  ? _duration.inMilliseconds.toDouble()
                                  : 100.0,
                            ),
                        onChanged: (val) async {
                          await _player.seek(Duration(milliseconds: val.toInt()));
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Subtle animated equalizer waves
              if (_isPlaying)
                AnimatedBuilder(
                  animation: _waveformController,
                  builder: (context, child) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(4, (index) {
                        final val = (index == 0 || index == 3)
                            ? _waveformController.value
                            : 1.0 - _waveformController.value;
                        return Container(
                          width: 3,
                          height: 6 + (val * 14),
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          decoration: BoxDecoration(
                            color: iconColor.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(1.5),
                          ),
                        );
                      }),
                    );
                  },
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(4, (index) {
                    return Container(
                      width: 3,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    );
                  }),
                ),
            ],
          ),
          if (widget.transcript != null && widget.transcript!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                '📝 ${widget.transcript}',
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.7),
                  fontSize: 12.5,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
