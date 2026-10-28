import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/utils/image_sizing.dart';
import '../../data/call_signaling_service.dart';

/// Full-screen audio & video calling screen with WhatsApp styling.
class CallScreen extends StatefulWidget {
  final String callId;
  final String localUid;
  final String remoteUid;
  final String remoteUserName;
  final String? remoteAvatarUrl;
  final bool isCaller;
  final bool isVideoCall;
  final String? localUserName;
  final String? localAvatarUrl;

  const CallScreen({
    super.key,
    required this.callId,
    required this.localUid,
    required this.remoteUid,
    required this.remoteUserName,
    this.remoteAvatarUrl,
    required this.isCaller,
    required this.isVideoCall,
    this.localUserName,
    this.localAvatarUrl,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final CallSignalingService _signaling = CallSignalingService();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  bool _isAudioMuted = false;
  bool _isVideoOff = false;
  late bool _isSpeakerOn;
  bool _remoteVideoConnected = false;
  bool _controlsVisible = true;
  bool _hasExited = false;
  String _callStatusText = 'Calling...';

  Duration _callDuration = Duration.zero;
  Timer? _durationTimer;
  Timer? _controlsHideTimer;

  void _safeExit() {
    if (!mounted || _hasExited) return;
    _hasExited = true;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/chats');
    }
  }

  // Draggable PIP local video offset
  Offset _pipOffset = const Offset(20, 60);

  @override
  void initState() {
    super.initState();
    _isSpeakerOn = widget.isVideoCall;
    if (!kIsWeb) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      Helper.setSpeakerphoneOn(_isSpeakerOn);
    }
    _initCall();
  }

  Future<void> _initCall() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    // Request permissions
    if (!kIsWeb) {
      await Permission.microphone.request();
      if (widget.isVideoCall) {
        await Permission.camera.request();
      }
      await Helper.setSpeakerphoneOn(_isSpeakerOn);
    }

    _signaling.onLocalStream = (stream) {
      if (mounted) {
        setState(() {
          _localRenderer.srcObject = stream;
        });
      }
    };

    _signaling.onRemoteStream = (stream) {
      if (mounted) {
        setState(() {
          _remoteRenderer.srcObject = stream;
          _remoteVideoConnected = true;
          _callStatusText = 'Connected';
        });
        _startDurationTimer();
      }
    };

    _signaling.onCallStateChange = (state) {
      if (!mounted) return;
      setState(() {
        if (state == 'calling') {
          _callStatusText = widget.isCaller ? 'Ringing...' : 'Incoming call...';
        } else if (state == 'answered') {
          _callStatusText = 'Connected';
          _startDurationTimer();
        } else if (state == 'ended' || state == 'declined') {
          _callStatusText = 'Call ended';
          Future.delayed(const Duration(milliseconds: 300), _safeExit);
        }
      });
    };

    _signaling.onCallEnded = () {
      _safeExit();
    };

    try {
      if (widget.isCaller) {
        await _signaling.startCall(
          widget.callId,
          widget.localUid,
          widget.remoteUid,
          videoEnabled: widget.isVideoCall,
          callerName: widget.localUserName,
          callerAvatar: widget.localAvatarUrl,
        );
      } else {
        await _signaling.answerCall(
          widget.callId,
          widget.localUid,
          videoEnabled: widget.isVideoCall,
        );
      }
    } catch (e) {
      debugPrint('CallScreen initialization error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to establish call: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
        _safeExit();
      }
    }
  }

  void _startDurationTimer() {
    if (_durationTimer != null) return;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _callDuration += const Duration(seconds: 1);
        });
      }
    });
  }

  void _toggleAudio() {
    setState(() {
      _isAudioMuted = !_isAudioMuted;
    });
    _signaling.toggleAudio(!_isAudioMuted);
  }

  void _toggleVideo() {
    setState(() {
      _isVideoOff = !_isVideoOff;
    });
    _signaling.toggleVideo(!_isVideoOff);
  }

  void _toggleSpeaker() {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
    });
    if (!kIsWeb) {
      Helper.setSpeakerphoneOn(_isSpeakerOn);
    }
  }

  void _switchCamera() {
    _signaling.switchCamera();
  }

  void _endCall() {
    _signaling.endCall(durationSeconds: _callDuration.inSeconds);
    _safeExit();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _toggleControlsVisibility() {
    setState(() {
      _controlsVisible = !_controlsVisible;
    });
    _resetControlsTimer();
  }

  void _resetControlsTimer() {
    _controlsHideTimer?.cancel();
    if (widget.isVideoCall && _controlsVisible) {
      _controlsHideTimer = Timer(const Duration(seconds: 5), () {
        if (mounted && _remoteVideoConnected) {
          setState(() {
            _controlsVisible = false;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _durationTimer?.cancel();
    _controlsHideTimer?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _signaling.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.isVideoCall;

    return PopScope(
        canPop: context.canPop(),
        onPopInvokedWithResult: (didPop, result) {
          _hasExited = true;
          _signaling.endCall(durationSeconds: _callDuration.inSeconds);
          if (!didPop) {
            context.go('/chats');
          }
        },
        child: Scaffold(
          backgroundColor: const Color(0xFF0B141A), // WhatsApp dark background
          body: SizedBox.expand(
            child: GestureDetector(
              onTap: isVideo ? _toggleControlsVisibility : null,
              behavior: HitTestBehavior.opaque,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // ── Background / Remote Video Layer ───────────────────────────────
                  if (isVideo && _remoteVideoConnected && !_isVideoOff)
                    Positioned.fill(
                      child: RTCVideoView(
                        _remoteRenderer,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                    )
                  else
                    _buildAudioOrPlaceholderBackground(),

                  // ── Top Header (Name, Status / Duration) ──────────────────────────
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 250),
                      opacity: _controlsVisible ? 1.0 : 0.0,
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back,
                                    color: Colors.white, size: 24),
                                onPressed: _endCall,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      widget.remoteUserName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black87,
                                            blurRadius: 4,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _callDuration > Duration.zero
                                          ? _formatDuration(_callDuration)
                                          : _callStatusText,
                                      style: TextStyle(
                                        color: _callDuration > Duration.zero
                                            ? const Color(0xFF00A884)
                                            : Colors.white70,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        shadows: const [
                                          Shadow(
                                            color: Colors.black87,
                                            blurRadius: 4,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isVideo)
                                IconButton(
                                  icon: const Icon(Icons.cameraswitch,
                                      color: Colors.white, size: 24),
                                  onPressed: _switchCamera,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // ── Local Video PIP (Picture-In-Picture for Video Calls) ─────────
                if (isVideo && !_isVideoOff)
                  Positioned(
                    right: _pipOffset.dx,
                    top: _pipOffset.dy,
                    child: GestureDetector(
                      onPanUpdate: (details) {
                        setState(() {
                          _pipOffset = Offset(
                            (_pipOffset.dx - details.delta.dx).clamp(
                                10, MediaQuery.of(context).size.width - 120),
                            (_pipOffset.dy + details.delta.dy).clamp(
                                60, MediaQuery.of(context).size.height - 200),
                          );
                        });
                      },
                      child: Container(
                        width: 100,
                        height: 145,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1F2C34),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                const Color(0xFF00A884).withValues(alpha: 0.5),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: RTCVideoView(
                          _localRenderer,
                          mirror: true,
                          objectFit:
                              RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        ),
                      ),
                    ),
                  ),

                // ── Bottom Action Controls Bar ────────────────────────────────────
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 250),
                  bottom: _controlsVisible ? 36 : -120,
                  left: 20,
                  right: 20,
                  child: SafeArea(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F2C34).withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Speaker Toggle
                          _buildCallActionBtn(
                            icon: _isSpeakerOn
                                ? Icons.volume_up
                                : Icons.volume_down_rounded,
                            color: _isSpeakerOn
                                ? const Color(0xFF00A884)
                                : Colors.white,
                            bgColor: _isSpeakerOn
                                ? Colors.white.withValues(alpha: 0.15)
                                : const Color(0xFF2A3942),
                            tooltip: 'Speaker',
                            onTap: _toggleSpeaker,
                          ),

                          // Mute Audio Toggle
                          _buildCallActionBtn(
                            icon: _isAudioMuted ? Icons.mic_off : Icons.mic,
                            color:
                                _isAudioMuted ? Colors.redAccent : Colors.white,
                            bgColor: _isAudioMuted
                                ? Colors.white.withValues(alpha: 0.15)
                                : const Color(0xFF2A3942),
                            tooltip: _isAudioMuted ? 'Unmute' : 'Mute',
                            onTap: _toggleAudio,
                          ),

                          // Video Toggle (only for video calls)
                          if (isVideo)
                            _buildCallActionBtn(
                              icon: _isVideoOff
                                  ? Icons.videocam_off
                                  : Icons.videocam,
                              color:
                                  _isVideoOff ? Colors.redAccent : Colors.white,
                              bgColor: _isVideoOff
                                  ? Colors.white.withValues(alpha: 0.15)
                                  : const Color(0xFF2A3942),
                              tooltip: _isVideoOff
                                  ? 'Turn Video On'
                                  : 'Turn Video Off',
                              onTap: _toggleVideo,
                            ),

                          // End Call Button (Red Circle)
                          _buildCallActionBtn(
                            icon: Icons.call_end,
                            color: Colors.white,
                            bgColor: Colors.redAccent,
                            isEndCall: true,
                            tooltip: 'End Call',
                            onTap: _endCall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAudioOrPlaceholderBackground() {
    final initials = widget.remoteUserName.isNotEmpty
        ? widget.remoteUserName.substring(0, 1).toUpperCase()
        : 'T';

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1F2C34),
            Color(0xFF0B141A),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Avatar
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF005C4B),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00A884).withValues(alpha: 0.3),
                    blurRadius: 30,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: ClipOval(
                child: (widget.remoteAvatarUrl != null &&
                        widget.remoteAvatarUrl!.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: widget.remoteAvatarUrl!,
                        fit: BoxFit.cover,
                        memCacheWidth: context.decodeWidth(140),
                        placeholder: (_, __) => Center(
                          child: Text(
                            initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Center(
                          child: Text(
                            initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      )
                    : Center(
                        child: Text(
                          initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              widget.remoteUserName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _callDuration > Duration.zero
                  ? _formatDuration(_callDuration)
                  : _callStatusText,
              style: TextStyle(
                color: _callDuration > Duration.zero
                    ? const Color(0xFF00A884)
                    : Colors.white60,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallActionBtn({
    required IconData icon,
    required Color color,
    required Color bgColor,
    required String tooltip,
    required VoidCallback onTap,
    bool isEndCall = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: isEndCall ? 60 : 50,
          height: isEndCall ? 60 : 50,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            boxShadow: isEndCall
                ? [
                    BoxShadow(
                      color: Colors.redAccent.withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            color: color,
            size: isEndCall ? 28 : 22,
          ),
        ),
      ),
    );
  }
}
