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
    }
    _initCall();
  }

  void _applyAudioRouting() {
    if (!kIsWeb) {
      Helper.setSpeakerphoneOn(_isSpeakerOn);
    }
  }

  Future<void> _initCall() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    if (!mounted) return;

    // The messenger outlives this screen, so an error can still be shown after it closes.
    final messenger = ScaffoldMessenger.maybeOf(context);

    // Without a microphone there is no call. A refused camera turns a video
    // call into an audio call instead of failing it.
    var videoEnabled = widget.isVideoCall;
    if (!kIsWeb) {
      final micStatus = await Permission.microphone.request();
      if (micStatus.isDenied || micStatus.isPermanentlyDenied) {
        await _failCall(
          'Microphone permission is required for calls.',
          messenger,
        );
        return;
      }
      if (widget.isVideoCall) {
        videoEnabled = (await Permission.camera.request()).isGranted;
      }
      _applyAudioRouting();
    }

    _signaling.onLocalStream = (stream) {
      if (mounted) {
        setState(() {
          _localRenderer.srcObject = stream;
          // A camera that could not be opened leaves the call with video off.
          _isVideoOff = !_signaling.hasLocalVideo;
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
        _applyAudioRouting();
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
          _applyAudioRouting();
          _startDurationTimer();
        } else if (state == 'declined' ||
            state == 'missed' ||
            state == 'ended' ||
            state == 'failed') {
          _callStatusText = switch (state) {
            'declined' => 'Call declined',
            'missed' => 'No answer',
            _ => 'Call ended',
          };
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
          videoEnabled: videoEnabled,
          callerName: widget.localUserName,
          callerAvatar: widget.localAvatarUrl,
        );
      } else {
        await _signaling.answerCall(
          widget.callId,
          widget.localUid,
          videoEnabled: videoEnabled,
        );
      }
      _applyAudioRouting();
    } catch (e) {
      // The signaling service has already ended the call and closed this screen.
      debugPrint('CallScreen initialization error: $e');
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            e is CallSetupException
                ? e.message
                : 'Could not connect the call. Please try again.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      _safeExit();
    }
  }

  /// Ends the call from this side, says why, and leaves the screen. A callee
  /// who has not answered declines, so the caller stops ringing.
  Future<void> _failCall(
    String message,
    ScaffoldMessengerState? messenger,
  ) async {
    if (widget.isCaller) {
      await _signaling.endCall();
    } else {
      await _signaling.declineCall(widget.callId, callerId: widget.remoteUid);
    }
    messenger?.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
    _safeExit();
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
    // A call that started without a camera has no video track to switch on.
    if (_isVideoOff && !_signaling.hasLocalVideo) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('The camera is not available for this call.'),
        ),
      );
      return;
    }
    setState(() {
      _isVideoOff = !_isVideoOff;
    });
    _signaling.toggleVideo(!_isVideoOff);
  }

  void _toggleSpeaker() {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
    });
    _applyAudioRouting();
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
    // Show the other person's video whenever they send it. Our own camera
    // being off must not hide it.
    final remoteHasVideo =
        _remoteRenderer.srcObject?.getVideoTracks().isNotEmpty ?? false;
    final canPop = Navigator.of(context).canPop();

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        _hasExited = true;
        _signaling.endCall(durationSeconds: _callDuration.inSeconds);
        if (!didPop) {
          try {
            context.go('/chats');
          } catch (_) {}
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
                if (isVideo && _remoteVideoConnected && remoteHasVideo)
                  Positioned.fill(
                    child: RTCVideoView(
                      _remoteRenderer,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  )
                else ...[
                  _buildAudioOrPlaceholderBackground(),
                  // Invisible 1x1 audio sink ensures RTCVideoRenderer is mounted in the widget tree so WebRTC audio flows reliably on all platforms (especially Web).
                  Positioned(
                    left: 0,
                    top: 0,
                    width: 1,
                    height: 1,
                    child: Opacity(
                      opacity: 0.01,
                      child: RTCVideoView(_remoteRenderer),
                    ),
                  ),
                ],

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
                                  Row(
                                    children: [
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
                                      if (_callDuration > Duration.zero) ...[
                                        const SizedBox(width: 8),
                                        ValueListenableBuilder<
                                            CallNetworkQuality>(
                                          valueListenable:
                                              _signaling.networkQuality,
                                          builder: (ctx, quality, _) {
                                            Color dotColor;
                                            String label;
                                            switch (quality) {
                                              case CallNetworkQuality.good:
                                                dotColor =
                                                    const Color(0xFF00E676);
                                                label = 'HD';
                                                break;
                                              case CallNetworkQuality.fair:
                                                dotColor =
                                                    const Color(0xFFFFD600);
                                                label = 'Fair';
                                                break;
                                              case CallNetworkQuality.poor:
                                                dotColor =
                                                    const Color(0xFFFF1744);
                                                label = 'Weak';
                                                break;
                                            }
                                            return Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 1),
                                              decoration: BoxDecoration(
                                                color: dotColor.withValues(
                                                    alpha: 0.15),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                    color: dotColor.withValues(
                                                        alpha: 0.4),
                                                    width: 0.8),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Container(
                                                    width: 6,
                                                    height: 6,
                                                    decoration: BoxDecoration(
                                                      color: dotColor,
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    label,
                                                    style: TextStyle(
                                                      color: dotColor,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ],
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
