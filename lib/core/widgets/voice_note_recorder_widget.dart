import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../theme/colors.dart';

/// 🎙️ Voice Note recorder widget — records, plays back, and returns the local file path.
/// Uses `record` package for recording and `audioplayers` for playback.
/// Both packages are already in pubspec.yaml.
class VoiceNoteRecorderWidget extends StatefulWidget {
  /// Called when recording is finished with the local file path and duration in seconds.
  final void Function(String localPath, int durationSeconds)
      onRecordingComplete;

  const VoiceNoteRecorderWidget({
    super.key,
    required this.onRecordingComplete,
  });

  @override
  State<VoiceNoteRecorderWidget> createState() =>
      _VoiceNoteRecorderWidgetState();
}

class _VoiceNoteRecorderWidgetState extends State<VoiceNoteRecorderWidget>
    with SingleTickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  bool _isRecording = false;
  bool _hasRecording = false;
  bool _isPlaying = false;
  String? _filePath;
  int _recordingSeconds = 0;
  int _durationSeconds = 0;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return;

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${const Uuid().v4()}.m4a';

    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path);

    setState(() {
      _isRecording = true;
      _filePath = path;
      _recordingSeconds = 0;
    });

    // Tick every second to show duration
    _tickTimer();
  }

  void _tickTimer() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted || !_isRecording) return;
      setState(() => _recordingSeconds++);
      _tickTimer();
    });
  }

  Future<void> _stopRecording() async {
    await _recorder.stop();
    setState(() {
      _isRecording = false;
      _hasRecording = true;
      _durationSeconds = _recordingSeconds;
    });
    if (_filePath != null) {
      widget.onRecordingComplete(_filePath!, _durationSeconds);
    }
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _player.stop();
    } else if (_filePath != null) {
      await _player.play(DeviceFileSource(_filePath!));
    }
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isRecording
              ? AppColors.amber.withValues(alpha: 0.6)
              : AppColors.mintGreen.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text('🎙️', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ভয়েস নোট',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    _isRecording
                        ? 'রেকর্ডিং হচ্ছে...'
                        : _hasRecording
                            ? 'রেকর্ডিং সম্পন্ন'
                            : 'ট্যাপ করে রেকর্ড শুরু করুন',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
              const Spacer(),
              if (_isRecording || _hasRecording)
                Text(
                  _formatDuration(
                      _isRecording ? _recordingSeconds : _durationSeconds),
                  style: TextStyle(
                    color: _isRecording ? AppColors.amber : Colors.white54,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Record / Stop button
              ScaleTransition(
                scale: _isRecording
                    ? _pulseAnim
                    : const AlwaysStoppedAnimation(1.0),
                child: GestureDetector(
                  onTap: _isRecording ? _stopRecording : _startRecording,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isRecording
                          ? AppColors.amber
                          : AppColors.mintGreen.withValues(alpha: 0.15),
                      border: Border.all(
                        color: _isRecording
                            ? AppColors.amber
                            : AppColors.mintGreen,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                      color: _isRecording ? Colors.white : AppColors.mintGreen,
                      size: 30,
                    ),
                  ),
                ),
              ),
              if (_hasRecording && !_isRecording) ...[
                const SizedBox(width: 20),
                // Playback button
                GestureDetector(
                  onTap: _togglePlayback,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.05),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Icon(
                      _isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white70,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
