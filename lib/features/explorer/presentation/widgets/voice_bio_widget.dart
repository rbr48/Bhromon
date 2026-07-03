import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:bhromon/app/di/injection.dart';
import 'package:bhromon/core/network/secure_network_client.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/services/media_upload_service.dart';
import '../../../../core/theme/colors.dart';

class VoiceBioWidget extends StatefulWidget {
  final String uid;
  final bool isOwnProfile;

  const VoiceBioWidget({
    super.key,
    required this.uid,
    required this.isOwnProfile,
  });

  @override
  State<VoiceBioWidget> createState() => _VoiceBioWidgetState();
}

class _VoiceBioWidgetState extends State<VoiceBioWidget>
    with TickerProviderStateMixin {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioRecorder _recorder = AudioRecorder();

  bool _isRecording = false;
  bool _isPlaying = false;
  bool _isLoading = false;
  String? _voiceUrl;
  Duration _playPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  late AnimationController _waveController;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _loadVoiceUrl();
    _audioPlayer.onPositionChanged.listen((p) {
      if (mounted) setState(() => _playPosition = p);
    });
    _audioPlayer.onDurationChanged.listen((d) {
      if (mounted) setState(() => _totalDuration = d);
    });
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isPlaying = false);
    });
  }

  Future<void> _loadVoiceUrl() async {
    try {
      final url = 'https://app.bhromon.fun/uploads/voice_bios/${widget.uid}/bio.m4a';
      final secureClient = getIt<SecureNetworkClient>();
      final response = await secureClient.dio.head<void>(url);
      if (response.statusCode == 200) {
        if (mounted) setState(() => _voiceUrl = url);
      }
    } catch (_) {
      // No voice bio yet
    }
  }

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission denied.')),
        );
      }
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_bio_temp.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
      path: path,
    );
    setState(() => _isRecording = true);
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    setState(() {
      _isRecording = false;
      _isLoading = true;
    });
    if (path == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final file = File(path);
      final url = await MediaUploadService.uploadFile(
        file: file,
        path: 'voice_bios/${widget.uid}/bio.m4a',
      );
      setState(() {
        _voiceUrl = url;
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Voice bio saved!')),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    }
  }

  Future<void> _togglePlay() async {
    if (_voiceUrl == null) return;
    if (_isPlaying) {
      await _audioPlayer.pause();
      setState(() => _isPlaying = false);
    } else {
      await _audioPlayer.play(UrlSource(_voiceUrl!));
      setState(() => _isPlaying = true);
    }
  }

  Future<void> _deleteVoiceBio() async {
    setState(() {
      _isLoading = true;
      _isPlaying = false;
    });
    try {
      await _audioPlayer.stop();
      try {
        await MediaUploadService.deleteFile(path: 'voice_bios/${widget.uid}/bio.m4a');
      } catch (err) {
        debugPrint('Storage deletion warning: $err');
      }
      setState(() {
        _voiceUrl = null;
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Voice bio deleted successfully.')),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete voice bio: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _waveController.dispose();
    _pulseController.dispose();
    _audioPlayer.dispose();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.mic, color: AppColors.mintGreen, size: 18),
              const SizedBox(width: 8),
              const Text(
                'VOICE BIO',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              if (widget.isOwnProfile)
                GestureDetector(
                  onTap: _isLoading
                      ? null
                      : (_isRecording ? _stopRecording : _startRecording),
                  child: AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _isRecording
                              ? Colors.redAccent
                                  .withOpacity(0.1 + _pulseController.value * 0.1)
                              : AppColors.mintGreen.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _isRecording
                                ? Colors.redAccent.withOpacity(0.5)
                                : AppColors.mintGreen.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isRecording ? Icons.stop : Icons.fiber_manual_record,
                              color: _isRecording
                                  ? Colors.redAccent
                                  : AppColors.mintGreen,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                             Text(
                              _isRecording ? 'Stop' : (_voiceUrl != null ? 'Re-record' : 'Record'),
                              style: TextStyle(
                                color: _isRecording
                                    ? Colors.redAccent
                                    : AppColors.mintGreen,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            const Center(
              child: SizedBox(
                height: 48,
                child:
                    CircularProgressIndicator(color: AppColors.mintGreen),
              ),
            )
          else if (_isRecording)
            _buildRecordingVisualizer()
          else if (_voiceUrl != null)
            _buildPlayerBar()
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.02),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.mic_none, color: Colors.white30, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.isOwnProfile
                          ? 'No voice bio yet. Tap "Record" to add a 30-second introduction!'
                          : 'This explorer hasn\'t added a voice bio yet.',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecordingVisualizer() {
    return AnimatedBuilder(
      animation: _waveController,
      builder: (context, child) {
        return Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.redAccent.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.fiber_manual_record,
                  color: Colors.redAccent, size: 12),
              const SizedBox(width: 8),
              const Text(
                'Recording...',
                style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              ...List.generate(20, (i) {
                final phase = (i / 20) * 2 * pi;
                final height = 8 +
                    16 *
                        (sin(_waveController.value * 2 * pi + phase).abs());
                return Container(
                  width: 3,
                  height: height,
                  margin: const EdgeInsets.only(right: 2),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.5 + 0.5 * sin(_waveController.value * 2 * pi + phase).abs()),
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlayerBar() {
    final progress = _totalDuration.inMilliseconds > 0
        ? _playPosition.inMilliseconds / _totalDuration.inMilliseconds
        : 0.0;
    final posStr =
        '${_playPosition.inMinutes}:${(_playPosition.inSeconds % 60).toString().padLeft(2, '0')}';
    final durStr =
        '${_totalDuration.inMinutes}:${(_totalDuration.inSeconds % 60).toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _togglePlay,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.mintGreen.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.mintGreen.withOpacity(0.4)),
              ),
              child: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: AppColors.mintGreen,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    backgroundColor: Colors.white.withOpacity(0.05),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.mintGreen),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(posStr,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 10)),
                    Text(durStr,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
          if (widget.isOwnProfile) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
              onPressed: _deleteVoiceBio,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
          // Waveform bars (static decorative)
          const SizedBox(width: 12),
          ...List.generate(12, (i) {
            final heights = [12.0, 18.0, 10.0, 22.0, 14.0, 20.0, 8.0, 16.0, 24.0, 12.0, 18.0, 10.0];
            return Container(
              width: 3,
              height: heights[i % heights.length],
              margin: const EdgeInsets.only(right: 2),
              decoration: BoxDecoration(
                color: AppColors.mintGreen.withOpacity(_isPlaying ? 0.6 : 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ],
      ),
    );
  }
}
