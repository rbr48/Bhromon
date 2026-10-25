import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

typedef VoiceRecordCallback = void Function(String filePath, Duration duration);

/// WhatsApp-style voice message recorder bar.
///
/// Provides live duration count, waveform pulses, slide-to-cancel,
/// and lock mode for hands-free recording.
class VoiceMessageRecorder extends StatefulWidget {
  final VoiceRecordCallback onVoiceSent;
  final VoidCallback onCancel;

  const VoiceMessageRecorder({
    super.key,
    required this.onVoiceSent,
    required this.onCancel,
  });

  @override
  State<VoiceMessageRecorder> createState() => _VoiceMessageRecorderState();
}

class _VoiceMessageRecorderState extends State<VoiceMessageRecorder>
    with SingleTickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();

  bool _isLocked = false;
  Duration _recordDuration = Duration.zero;
  Timer? _timer;
  String? _tempPath;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnimation =
        Tween<double>(begin: 0.8, end: 1.2).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _startRecording();
  }

  Future<void> _startRecording() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        widget.onCancel();
        return;
      }

      String savePath = '';
      if (!kIsWeb) {
        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        savePath = '${tempDir.path}/voice_$timestamp.m4a';
        _tempPath = savePath;
      }

      const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      );

      if (kIsWeb) {
        await _recorder.start(config, path: '');
      } else {
        await _recorder.start(config, path: savePath);
      }

      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {
            _recordDuration += const Duration(seconds: 1);
          });
        }
      });
    } catch (e) {
      debugPrint('VoiceMessageRecorder start error: $e');
      widget.onCancel();
    }
  }

  Future<void> _stopAndSend() async {
    _timer?.cancel();
    try {
      final path = await _recorder.stop();
      final finalPath = path ?? _tempPath;
      if (finalPath != null && finalPath.isNotEmpty) {
        // If recording was less than 1 second, discard it
        if (_recordDuration.inSeconds < 1) {
          _cleanupFile(finalPath);
          widget.onCancel();
        } else {
          widget.onVoiceSent(finalPath, _recordDuration);
        }
      } else {
        widget.onCancel();
      }
    } catch (e) {
      debugPrint('VoiceMessageRecorder stop error: $e');
      widget.onCancel();
    }
  }

  Future<void> _cancelRecording() async {
    _timer?.cancel();
    try {
      final path = await _recorder.stop();
      final finalPath = path ?? _tempPath;
      if (finalPath != null) {
        _cleanupFile(finalPath);
      }
    } catch (_) {}
    widget.onCancel();
  }

  void _cleanupFile(String path) {
    if (!kIsWeb) {
      try {
        final file = File(path);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {}
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString();
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF202C33), // WhatsApp message bubble slate
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // ── Red Pulsing Record Indicator ──────────────────────────────────
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // ── Duration Timer ───────────────────────────────────────────────
          Text(
            _formatDuration(_recordDuration),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 12),

          // ── Animated Waveform bars ───────────────────────────────────────
          Expanded(
            child: _buildAnimatedWaveform(),
          ),

          // ── Action Controls (Lock / Cancel / Send) ──────────────────────
          if (!_isLocked) ...[
            // Slide to cancel / Lock hint
            GestureDetector(
              onTap: () {
                setState(() => _isLocked = true);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline, color: Colors.white70, size: 14),
                    SizedBox(width: 4),
                    Text('Lock',
                        style: TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white60, size: 20),
              tooltip: 'Cancel',
              onPressed: _cancelRecording,
            ),
            GestureDetector(
              onTap: _stopAndSend,
              child: const CircleAvatar(
                radius: 18,
                backgroundColor: Color(0xFF00A884),
                child: Icon(Icons.send, color: Colors.white, size: 16),
              ),
            ),
          ] else ...[
            // Locked hands-free mode: delete trash or send
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: Colors.redAccent, size: 22),
              tooltip: 'Delete recording',
              onPressed: _cancelRecording,
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: _stopAndSend,
              child: const CircleAvatar(
                radius: 20,
                backgroundColor: Color(0xFF00A884),
                child: Icon(Icons.send, color: Colors.white, size: 18),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAnimatedWaveform() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final val = _pulseController.value;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(14, (index) {
            // Generates staggered dancing waveform bars
            final height = 6.0 + 16.0 * ((index % 3 == 0 ? val : (1.0 - val)));
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 2.5,
              height: height.clamp(4.0, 22.0),
              decoration: BoxDecoration(
                color: index % 2 == 0
                    ? const Color(0xFF00A884)
                    : const Color(0xFF53BDEB),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}
