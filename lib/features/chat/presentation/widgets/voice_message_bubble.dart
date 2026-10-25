import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

/// WhatsApp-style voice message playback bubble.
///
/// Features:
/// - Circular Play / Pause toggle
/// - Audio buffering state indicator
/// - Interactive seek bar / progress waveform
/// - Position & duration timer (e.g. "0:14 / 0:45")
/// - Playback speed toggle (1x → 1.5x → 2x)
class VoiceMessageBubble extends StatefulWidget {
  final String audioUrl;
  final int? durationSeconds;
  final bool isMe;

  const VoiceMessageBubble({
    super.key,
    required this.audioUrl,
    this.durationSeconds,
    required this.isMe,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  final AudioPlayer _player = AudioPlayer();

  PlayerState _playerState = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _totalDuration = Duration.zero;
  double _playbackSpeed = 1.0;
  bool _isLoading = false;

  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void initState() {
    super.initState();
    if (widget.durationSeconds != null && widget.durationSeconds! > 0) {
      _totalDuration = Duration(seconds: widget.durationSeconds!);
    }

    _subs.add(_player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _playerState = state;
          _isLoading = false;
        });
      }
    }));

    _subs.add(_player.onPositionChanged.listen((pos) {
      if (mounted) {
        setState(() {
          _position = pos;
        });
      }
    }));

    _subs.add(_player.onDurationChanged.listen((dur) {
      if (mounted && dur > Duration.zero) {
        setState(() {
          _totalDuration = dur;
        });
      }
    }));
  }

  Future<void> _togglePlayPause() async {
    if (_isLoading) return;

    if (_playerState == PlayerState.playing) {
      await _player.pause();
    } else {
      setState(() => _isLoading = true);
      try {
        await _player.setPlaybackRate(_playbackSpeed);
        if (_playerState == PlayerState.paused) {
          await _player.resume();
        } else {
          await _player.play(UrlSource(widget.audioUrl));
        }
      } catch (e) {
        debugPrint('AudioPlayer error: $e');
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _cyclePlaybackSpeed() async {
    double nextSpeed = 1.0;
    if (_playbackSpeed == 1.0) {
      nextSpeed = 1.5;
    } else if (_playbackSpeed == 1.5) {
      nextSpeed = 2.0;
    } else {
      nextSpeed = 1.0;
    }

    setState(() => _playbackSpeed = nextSpeed);
    await _player.setPlaybackRate(nextSpeed);
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString();
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String get _speedLabel {
    if (_playbackSpeed == 1.0) return '1x';
    if (_playbackSpeed == 2.0) return '2x';
    return '${_playbackSpeed}x';
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = _playerState == PlayerState.playing;
    final total = _totalDuration > Duration.zero
        ? _totalDuration
        : const Duration(seconds: 1);
    final progress = (_position.inMilliseconds / total.inMilliseconds)
        .clamp(0.0, 1.0);

    return Container(
      width: 250,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // ── Play / Pause Button ──────────────────────────────────────
              GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: widget.isMe
                        ? const Color(0xFF00A884)
                        : const Color(0xFF53BDEB),
                    shape: BoxShape.circle,
                  ),
                  child: _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(
                          isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                ),
              ),
              const SizedBox(width: 8),

              // ── Interactive Progress Slider ──────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 10),
                        activeTrackColor: widget.isMe
                            ? const Color(0xFF00A884)
                            : const Color(0xFF53BDEB),
                        inactiveTrackColor: Colors.white24,
                        thumbColor: Colors.white,
                      ),
                      child: Slider(
                        value: progress,
                        onChanged: (val) {
                          final seekTo = Duration(
                              milliseconds:
                                  (val * total.inMilliseconds).toInt());
                          _player.seek(seekTo);
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(_position),
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 10),
                          ),
                          Text(
                            _formatDuration(_totalDuration),
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Speed Selector (1x, 1.5x, 2x) ────────────────────────────
              GestureDetector(
                onTap: _cyclePlaybackSpeed,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _speedLabel,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
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
