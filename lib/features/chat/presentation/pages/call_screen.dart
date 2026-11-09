import 'dart:async';
import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/audio/call_audio_session.dart';
import '../../../../core/services/battery_guidance.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../../core/utils/logger.dart';
import '../../data/call_signaling_service.dart';
import '../../data/call_telemetry.dart';
import '../../data/system_call_bridge.dart';
import '../../domain/call_display.dart';
import '../../domain/call_ringback_audio.dart';
import '../../domain/speaker_route.dart';
import '../widgets/packet_loss_meter.dart';
import '../widgets/whatsapp_call_widgets.dart';
import '../../../tour_group/data/tour_group_repository.dart';
import '../../../tour_group/domain/services/call_partner.dart';

/// Full-screen audio & video calling screen with WhatsApp styling.
class CallScreen extends StatefulWidget {
  final String callId;
  final String localUid;
  final String remoteUid;

  /// The other person's email and the tour they share with us. A call can only
  /// be placed between two members of one tour.
  final String? remoteEmail;
  final String? sharedTourId;
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
    this.remoteEmail,
    this.sharedTourId,
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

  /// Whether the other side's camera is on. A video call starts with it on;
  /// either side can turn a camera on or off at any time.
  late bool _remoteCameraOn;

  /// Whether the phone's own call system (Telecom, CallKit) holds this call.
  bool _systemCall = false;

  /// True while the call is shrunk into a picture-in-picture window.
  bool _inPip = false;

  /// The audio output the user picked, or null for speaker/earpiece by the
  /// speaker button.
  String? _outputDeviceId;

  /// Whether the call shows video: it started as a video call, or a camera has
  /// been turned on since.
  bool get _videoMode =>
      widget.isVideoCall ||
      _remoteCameraOn ||
      (_signaling.hasLocalVideo && !_isVideoOff);

  /// The translation key of the status line shown until the call connects.
  String _statusKey = 'call_status_calling';

  /// True while the media is up. The clock and the link badge show only then.
  bool _isConnected = false;

  Duration _callDuration = Duration.zero;
  Timer? _durationTimer;
  Timer? _controlsHideTimer;
  AudioPlayer? _ringbackPlayer;

  Future<void> _startRingback() async {
    if (!widget.isCaller || _ringbackPlayer != null) return;
    try {
      final player = AudioPlayer();
      _ringbackPlayer = player;
      if (!kIsWeb) {
        await player.setAudioContext(
          buildRingbackAudioContext(isSpeaker: _isSpeakerOn),
        );
      }
      // If the call connected or exited while the player was initializing,
      // dispose immediately to prevent ringing after connection.
      if (!mounted || _ringbackPlayer != player || _hasExited || _isConnected) {
        await player.dispose();
        return;
      }
      await player.setReleaseMode(ReleaseMode.loop);
      await player.setVolume(1.0);
      await player.play(AssetSource('audio/ringback.mp3'));
    } catch (e, st) {
      logWarning('Failed to start ringback tone: $e', e, st);
    }
  }

  void _syncRingbackAudioRoute() {
    if (kIsWeb || _ringbackPlayer == null) return;
    try {
      unawaited(_ringbackPlayer?.setAudioContext(
        buildRingbackAudioContext(isSpeaker: _isSpeakerOn),
      ));
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
    }
  }

  void _stopRingback() {
    try {
      final player = _ringbackPlayer;
      _ringbackPlayer = null;
      if (player != null) {
        unawaited(player.stop());
        unawaited(player.dispose());
      }
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
    }
  }

  void _safeExit() {
    _stopRingback();
    if (!mounted || _hasExited) return;
    _hasExited = true;
    if (context.canPop()) {
      context.pop();
    } else if (widget.sharedTourId != null && widget.sharedTourId!.isNotEmpty) {
      context.go('/group/${widget.sharedTourId}/channels');
    } else {
      context.go('/chats');
    }
  }

  @override
  void initState() {
    super.initState();
    // Calls start on the loudspeaker. The earpiece is much quieter, and a phone
    // lying on a table is the common case. The speaker button switches back.
    _isSpeakerOn = true;
    _remoteCameraOn = widget.isVideoCall;
    // The phone's hang-up, mute and hold buttons reach this call.
    ActiveCallControls.attach(
      id: widget.callId,
      onHangUp: _endCall,
      onMute: _setMutedFromSystem,
    );
    CallAudioSession.setPipListener((inPip) {
      if (mounted) setState(() => _inPip = inPip);
    });
    // A video call keeps the screen on, or the phone sleeps in the middle of it.
    if (widget.isVideoCall && !kIsWeb) {
      unawaited(WakelockPlus.enable());
    }
    if (!kIsWeb) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    // A call answered on a locked phone opens over the lock screen, and the
    // notification's Hang up button ends it.
    unawaited(CallAudioSession.showOverLockScreen(true));
    CallAudioSession.setHangUpHandler(_endCall);
    // The setup reads the app's language, which is only available once the
    // screen is in the tree, so it starts after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_initCall());
    });
  }

  void _applyAudioRouting() {
    if (kIsWeb) return;
    final picked = _outputDeviceId;
    if (picked != null) {
      // Bluetooth or headphones the user chose stay chosen.
      unawaited(Helper.selectAudioOutput(picked));
    } else {
      unawaited(_routeToSpeaker(_isSpeakerOn));
    }
  }

  /// Reads the phone's route once a connected call has settled, while the speaker is on.
  /// A route that is not the loudspeaker is applied once more, and the outcome goes to
  /// the call's Crashlytics keys. A route that still did not take is also recorded as a
  /// non-fatal, with the route as it was found.
  Future<void> _checkSpeakerRoute() async {
    if (kIsWeb || !_isConnected || !_isSpeakerOn || _outputDeviceId != null) {
      return;
    }
    final first = await CallAudioSession.routeSnapshot();
    if (!mounted || first == null) return;
    if (readSpeakerRoute(first) == SpeakerRoute.onSpeaker) {
      await CallTelemetry.speakerRoute(outcome: 'ok', systemCall: _systemCall);
      return;
    }
    _applyAudioRouting();
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    final second = await CallAudioSession.routeSnapshot();
    final outcome = second == null
        ? 'unknown'
        : readSpeakerRoute(second) == SpeakerRoute.onSpeaker
            ? 'retry_ok'
            : 'failed';
    await CallTelemetry.speakerRoute(
      outcome: outcome,
      systemCall: _systemCall,
      detail: describeSpeakerRoute(first),
    );
    if (outcome == 'failed') {
      logWarning('The loudspeaker route did not take on a connected call');
    }
  }

  /// Puts the call on the loudspeaker, or off it. On Android, the phone's own audio
  /// manager configures the platform communication device and routing mode, while
  /// the WebRTC plugin's AudioSwitch must also be synchronized so it does not
  /// override the route back to the earpiece when tracks activate.
  Future<void> _routeToSpeaker(bool speaker) async {
    try {
      await CallAudioSession.setSpeakerphone(speaker);
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
    }
    try {
      await Helper.setSpeakerphoneOn(speaker);
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
    }
  }

  Future<void> _initCall() async {
    final l10n = context.l10n;
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    if (!mounted) return;

    // The messenger outlives this screen, so an error can still be shown after it closes.
    final messenger = ScaffoldMessenger.maybeOf(context);

    // Without a microphone there is no call. A refused camera turns a video
    // call into an audio call instead of failing it.
    var videoEnabled = widget.isVideoCall;
    if (!kIsWeb) {
      var micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        micStatus = await Permission.microphone.request();
      }
      // Left while the prompt was open: the call must not start.
      if (!mounted) return;
      if (micStatus.isDenied || micStatus.isPermanentlyDenied) {
        await _failCall(
          l10n.translate('call_mic_required'),
          messenger,
        );
        return;
      }
      if (widget.isVideoCall) {
        var camStatus = await Permission.camera.status;
        if (!camStatus.isGranted) {
          camStatus = await Permission.camera.request();
        }
        videoEnabled = camStatus.isGranted;
        if (!mounted) return;
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
      _stopRingback();
      if (mounted) {
        setState(() {
          _remoteRenderer.srcObject = stream;
          _remoteVideoConnected = true;
        });
        _applyAudioRouting();
        // Reaffirm speaker routing after remote WebRTC audio track initializes.
        Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted) _applyAudioRouting();
        });
      }
    };

    _signaling.onCallStateChange = (state) {
      if (!mounted) return;
      setState(() {
        switch (state) {
          case 'calling':
            _statusKey =
                widget.isCaller ? 'call_status_ringing' : 'call_incoming';
            if (widget.isCaller) {
              unawaited(_startRingback());
            }
          case 'answered':
            // Accepted, but the media has not connected yet.
            _stopRingback();
            _statusKey = 'call_status_connecting';
            _applyAudioRouting();
          case 'connected':
            _stopRingback();
            _isConnected = true;
            unawaited(BatteryGuidance.markCallAnswered());
            _statusKey = 'chat_connected';
            _applyAudioRouting();
            // Reaffirm speaker routing after connection settles.
            Future.delayed(const Duration(milliseconds: 250), () {
              if (mounted) _applyAudioRouting();
            });
            // Checks the route once the re-applications above have settled.
            Future.delayed(const Duration(milliseconds: 1500), () {
              if (mounted) unawaited(_checkSpeakerRoute());
            });
            _startDurationTimer();
            if (_systemCall) {
              unawaited(SystemCallBridge.markConnected(widget.callId));
            }
            _onVideoModeChanged();
          case 'reconnecting':
            _isConnected = false;
            _statusKey = 'call_status_reconnecting';
          case 'declined' || 'missed' || 'ended' || 'failed':
            _stopRingback();
            _statusKey = switch (state) {
              'declined' => 'call_status_declined',
              'missed' => 'call_status_no_answer',
              'failed' => 'call_status_failed',
              _ => 'call_status_ended',
            };
            unawaited(HapticFeedback.mediumImpact());
            Future.delayed(const Duration(milliseconds: 1200), _safeExit);
        }
      });
    };

    _signaling.onCallEnded = () {
      _safeExit();
    };

    _signaling.onRemoteCamera = (on) {
      if (!mounted) return;
      setState(() => _remoteCameraOn = on);
      _onVideoModeChanged();
    };

    try {
      if (widget.isCaller) {
        final tourId = await _confirmCanCall();
        if (!mounted) return;
        // The phone's own call system holds the call, so an ordinary phone call
        // puts it on hold and headset buttons work.
        _systemCall = await SystemCallBridge.startOutgoing(
          callId: widget.callId,
          calleeId: widget.remoteUid,
          calleeName: widget.remoteUserName,
          calleeAvatar: widget.remoteAvatarUrl,
          isVideo: widget.isVideoCall,
        );
        if (!mounted) return;
        await _signaling.startCall(
          widget.callId,
          widget.localUid,
          widget.remoteUid,
          videoEnabled: videoEnabled,
          callerName: widget.localUserName,
          callerAvatar: widget.localAvatarUrl,
          sharedTourId: tourId ?? widget.sharedTourId,
          localEmail: TourGroupRepository().currentEmail,
          remoteEmail: widget.remoteEmail,
        );
      } else {
        // Answered on the phone's own ring screen: the phone keeps the call.
        _systemCall = await SystemCallBridge.isActive(widget.callId);
        if (!mounted) return;
        await _signaling.answerCall(
          widget.callId,
          widget.localUid,
          videoEnabled: videoEnabled,
        );
      }
      _applyAudioRouting();
      // Keeps the microphone (and camera) running when the app goes to the
      // background mid-call.
      // The phone's call system runs its own in-call service and notification.
      if (mounted && !_systemCall) {
        final l10n = context.l10n;
        unawaited(CallAudioSession.startOngoing(
          camera: _signaling.hasLocalVideo,
          title: l10n.translate('call_ongoing_title'),
          text: l10n.translate('call_ongoing_text',
              args: {'name': widget.remoteUserName}),
          hangUp: l10n.translate('call_hang_up'),
        ));
        _updateProximity();
      }
    } catch (e) {
      // A call that started has already been ended by the signaling service. A setup
      // that failed before any connection may still hold the audio mode, so the
      // session is handed back here as well.
      logError('CallScreen initialization error: $e');
      await CallAudioSession.release();
      // A setup stopped because the user hung up or left needs no message.
      if (!mounted || _signaling.wasCancelled) return;
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            e is CallSetupException
                ? e.message
                : l10n.translate('call_connect_failed'),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      _safeExit();
    }
  }

  /// Finds a tour that both people are still active in, and returns it for the call.
  /// The tour the chat names is tried first, then any other tour they share. When
  /// there is none, the call says why instead of failing with a generic message.
  /// Returns null when there is no partner email, which startCall refuses on its own.
  Future<String?> _confirmCanCall() async {
    final l10n = context.l10n;
    final remoteEmail = widget.remoteEmail;
    if (remoteEmail == null || remoteEmail.isEmpty) return null;
    final ({String? tourId, CallPartnerStatus status}) resolved;
    try {
      resolved = await TourGroupRepository().resolveCallTour(
        preferredTourId: widget.sharedTourId,
        partnerUid: widget.remoteUid,
        partnerEmail: remoteEmail,
      );
    } catch (error, stack) {
      logWarning('CallScreen: membership check failed', error, stack);
      throw const CallSetupException(kCallUnreachableMessage);
    }
    final tourId = resolved.tourId;
    if (tourId != null) return tourId;
    final typedName = widget.remoteUserName.trim();
    final name =
        typedName.isEmpty ? l10n.translate('call_this_person') : typedName;
    final problem = switch (resolved.status) {
      CallPartnerStatus.ready => null,
      CallPartnerStatus.youLeft => l10n.translate('call_not_member_self'),
      CallPartnerStatus.partnerLeft =>
        l10n.translate('call_peer_not_member', args: {'name': name}),
      CallPartnerStatus.partnerNotLinked =>
        l10n.translate('call_peer_not_signed_in', args: {'name': name}),
      CallPartnerStatus.noSharedTour =>
        l10n.translate('call_peer_no_shared_group', args: {'name': name}),
    };
    throw CallSetupException(problem ?? kCallUnreachableMessage);
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
      await _signaling.declineCall(
        widget.callId,
        callerId: widget.remoteUid,
        isVideo: widget.isVideoCall,
      );
    }
    messenger?.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
    _safeExit();
  }

  /// Ticks the clock from the service's connected time, so the length shown is the
  /// length that is logged, and it keeps counting through a reconnect.
  void _startDurationTimer() {
    if (_durationTimer != null) return;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _callDuration = Duration(seconds: _signaling.connectedSeconds);
        });
      }
    });
  }

  /// The link figures behind the quality badge, shown in a WhatsApp details sheet.
  void _showLinkDetails() {
    showWhatsAppCallDetailsSheet(context: context, signaling: _signaling);
  }

  void _toggleAudio() {
    setState(() {
      _isAudioMuted = !_isAudioMuted;
    });
    _signaling.toggleAudio(!_isAudioMuted);
  }

  Future<void> _toggleVideo() async {
    if (!_signaling.hasLocalVideo) {
      // No camera yet: a voice call (or a video call that started without
      // one) turns its camera on.
      final granted = kIsWeb || (await Permission.camera.request()).isGranted;
      final started = granted && await _signaling.startCamera();
      if (!mounted) return;
      if (!started) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(context.l10n.translate('call_camera_unavailable')),
          ),
        );
        return;
      }
      setState(() => _isVideoOff = false);
      _onVideoModeChanged();
      return;
    }
    setState(() {
      _isVideoOff = !_isVideoOff;
    });
    await _signaling.toggleVideo(!_isVideoOff);
    _onVideoModeChanged();
  }

  /// Keeps the screen, the background service, the ear sensor and the
  /// picture-in-picture window in step with whether the call shows video.
  void _onVideoModeChanged() {
    if (!mounted) return;
    final video = _videoMode;
    if (!kIsWeb) {
      unawaited(video ? WakelockPlus.enable() : WakelockPlus.disable());
    }
    _updateProximity();
    unawaited(CallAudioSession.setPipAllowed(video && _isConnected));
    if (!_systemCall && _signaling.hasLocalVideo && _isConnected) {
      // The background service now has to keep the camera running too.
      final l10n = context.l10n;
      unawaited(CallAudioSession.startOngoing(
        camera: true,
        title: l10n.translate('call_ongoing_title'),
        text: l10n.translate('call_ongoing_text',
            args: {'name': widget.remoteUserName}),
        hangUp: l10n.translate('call_hang_up'),
      ));
    }
  }

  /// The phone's mute button, or hold while an ordinary phone call is on.
  void _setMutedFromSystem(bool muted) {
    if (!mounted) return;
    setState(() => _isAudioMuted = muted);
    _signaling.toggleAudio(!muted);
  }

  /// The speaker button. With Bluetooth or headphones connected it asks where
  /// the sound should go; otherwise it switches between speaker and earpiece.
  Future<void> _onSpeakerTap() async {
    if (kIsWeb) {
      _toggleSpeaker();
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Bluetooth devices are listed only with this permission (Android 12+).
      await Permission.bluetoothConnect.request();
    }
    List<MediaDeviceInfo> outputs;
    try {
      outputs = await Helper.audiooutputs;
    } catch (e) {
      outputs = const [];
    }
    if (!mounted) return;
    final hasExternal = outputs.any((o) {
      final kind = audioOutputKind(o.deviceId, o.label);
      return kind == AudioOutputKind.bluetooth ||
          kind == AudioOutputKind.headset;
    });
    if (!hasExternal) {
      _outputDeviceId = null;
      _toggleSpeaker();
      return;
    }
    final chosen = await showModalBottomSheet<MediaDeviceInfo>(
      context: context,
      backgroundColor: const Color(0xFF1F2C34),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                sheetContext.l10n.translate('call_audio_output'),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            for (final output in outputs)
              ListTile(
                leading: Icon(
                  switch (audioOutputKind(output.deviceId, output.label)) {
                    AudioOutputKind.bluetooth => Icons.bluetooth_audio,
                    AudioOutputKind.headset => Icons.headphones,
                    AudioOutputKind.earpiece => Icons.phone_in_talk,
                    _ => Icons.volume_up,
                  },
                  color: output.deviceId == _outputDeviceId
                      ? const Color(0xFF00A884)
                      : Colors.white70,
                ),
                title: Text(
                  _outputName(sheetContext, output),
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.of(sheetContext).pop(output),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    final kind = audioOutputKind(chosen.deviceId, chosen.label);
    setState(() {
      _isSpeakerOn = kind == AudioOutputKind.speaker;
      _outputDeviceId =
          (kind == AudioOutputKind.bluetooth || kind == AudioOutputKind.headset)
              ? chosen.deviceId
              : null;
    });
    if (_outputDeviceId != null) {
      await Helper.selectAudioOutput(chosen.deviceId);
    } else {
      _applyAudioRouting();
    }
    _updateProximity();
    _syncRingbackAudioRoute();
  }

  String _outputName(BuildContext context, MediaDeviceInfo output) {
    final l10n = context.l10n;
    final label = output.label.trim();
    return switch (audioOutputKind(output.deviceId, output.label)) {
      AudioOutputKind.speaker => l10n.translate('call_output_speaker'),
      AudioOutputKind.earpiece => l10n.translate('call_output_earpiece'),
      AudioOutputKind.bluetooth =>
        label.isEmpty ? l10n.translate('call_output_bluetooth') : label,
      AudioOutputKind.headset =>
        label.isEmpty ? l10n.translate('call_output_headset') : label,
      AudioOutputKind.other => label.isEmpty ? output.deviceId : label,
    };
  }

  void _toggleSpeaker() {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
    });
    _applyAudioRouting();
    _updateProximity();
    _syncRingbackAudioRoute();
  }

  /// On the earpiece of an audio call the phone is held to the ear, so the
  /// screen turns off when something is close, and cheeks press no buttons.
  void _updateProximity() {
    unawaited(CallAudioSession.setProximityScreenOff(!_videoMode &&
        !_isSpeakerOn &&
        _outputDeviceId == null &&
        !_hasExited));
  }

  void _switchCamera() {
    unawaited(_signaling.switchCamera());
  }

  void _endCall() {
    _signaling.endCall();
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
    _stopRingback();
    if (!kIsWeb) {
      unawaited(WakelockPlus.disable());
    }
    if (!kIsWeb) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _durationTimer?.cancel();
    _controlsHideTimer?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _signaling.dispose();
    unawaited(CallAudioSession.release());
    unawaited(CallAudioSession.stopOngoing());
    unawaited(CallAudioSession.setProximityScreenOff(false));
    unawaited(CallAudioSession.showOverLockScreen(false));
    CallAudioSession.setHangUpHandler(null);
    CallAudioSession.setPipListener(null);
    unawaited(CallAudioSession.setPipAllowed(false));
    ActiveCallControls.detach(widget.callId);
    if (_systemCall) unawaited(SystemCallBridge.end(widget.callId));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = _videoMode;
    final cameraOn = _signaling.hasLocalVideo && !_isVideoOff;
    // Show the other person's video whenever they send it. Our own camera
    // being off must not hide it.
    final remoteHasVideo =
        _remoteRenderer.srcObject?.getVideoTracks().isNotEmpty ?? false;
    final canPop = Navigator.of(context).canPop();

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        _hasExited = true;
        _signaling.endCall();
        if (!didPop) {
          try {
            if (widget.sharedTourId != null &&
                widget.sharedTourId!.isNotEmpty) {
              context.go('/group/${widget.sharedTourId}/channels');
            } else {
              context.go('/chats');
            }
          } catch (error, stackTrace) {
            logSkipped(error, stackTrace);
          }
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
                if (isVideo &&
                    _remoteCameraOn &&
                    _remoteVideoConnected &&
                    remoteHasVideo)
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
                    opacity: _controlsVisible && !_inPip ? 1.0 : 0.0,
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
                                  Row(
                                    children: [
                                      const Icon(Icons.lock_rounded,
                                          size: 11,
                                          color: WhatsAppCallTheme.primary),
                                      const SizedBox(width: 4),
                                      Text(
                                        context.l10n
                                            .translate('call_encrypted'),
                                        style: const TextStyle(
                                          color: WhatsAppCallTheme.textMuted,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
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
                                        _isConnected
                                            ? _formatDuration(_callDuration)
                                            : context.l10n
                                                .translate(_statusKey),
                                        style: TextStyle(
                                          color: _isConnected
                                              ? WhatsAppCallTheme.primary
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
                                      if (_isConnected) ...[
                                        const SizedBox(width: 8),
                                        CallQualityHud(
                                          qualityNotifier:
                                              _signaling.networkQuality,
                                          sampleNotifier:
                                              _signaling.linkSampleNotifier,
                                          onTapDetails: _showLinkDetails,
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (isVideo)
                              IconButton(
                                icon: const Icon(
                                  Icons.picture_in_picture_alt_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                                tooltip:
                                    context.l10n.translate('call_pip_tooltip'),
                                onPressed: () async {
                                  await CallAudioSession.enterPip();
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Local Video PIP (Picture-In-Picture for Video Calls) ─────────
                if (isVideo &&
                    _signaling.hasLocalVideo &&
                    !_isVideoOff &&
                    !_inPip)
                  WhatsAppDraggablePip(
                    renderer: _localRenderer,
                    onDoubleTapOrTapFlip: _switchCamera,
                  ),

                // ── Bottom Action Controls Bar ────────────────────────────────────
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 250),
                  bottom: _controlsVisible && !_inPip ? 36 : -120,
                  left: 20,
                  right: 20,
                  child: SafeArea(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color:
                            WhatsAppCallTheme.surface.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(36),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          if (cameraOn)
                            // Flip Camera
                            WhatsAppCallActionBtn(
                              icon: Icons.cameraswitch_rounded,
                              label:
                                  context.l10n.translate('call_switch_camera'),
                              iconColor: Colors.white,
                              bgColor: WhatsAppCallTheme.surfaceElevated,
                              onTap: _switchCamera,
                            )
                          else
                            // Speaker Toggle
                            WhatsAppCallActionBtn(
                              icon: _isSpeakerOn
                                  ? Icons.volume_up_rounded
                                  : Icons.volume_down_rounded,
                              label: context.l10n.translate('call_speaker'),
                              iconColor: _isSpeakerOn
                                  ? WhatsAppCallTheme.primary
                                  : Colors.white,
                              bgColor: _isSpeakerOn
                                  ? Colors.white.withValues(alpha: 0.15)
                                  : WhatsAppCallTheme.surfaceElevated,
                              onTap: _onSpeakerTap,
                            ),

                          // Camera On/Off
                          WhatsAppCallActionBtn(
                            icon: !cameraOn
                                ? Icons.videocam_off_rounded
                                : Icons.videocam_rounded,
                            label: !cameraOn
                                ? context.l10n.translate('call_video_on')
                                : context.l10n.translate('call_video_off'),
                            iconColor:
                                !cameraOn ? Colors.redAccent : Colors.white,
                            bgColor: WhatsAppCallTheme.surfaceElevated,
                            onTap: _toggleVideo,
                          ),

                          // Mute Audio Toggle
                          WhatsAppCallActionBtn(
                            icon: _isAudioMuted
                                ? Icons.mic_off_rounded
                                : Icons.mic_rounded,
                            label: _isAudioMuted
                                ? context.l10n.translate('chat_unmute')
                                : context.l10n.translate('chat_mute'),
                            iconColor:
                                _isAudioMuted ? Colors.redAccent : Colors.white,
                            bgColor: WhatsAppCallTheme.surfaceElevated,
                            onTap: _toggleAudio,
                          ),

                          // End Call Button (Red Circle)
                          WhatsAppCallActionBtn(
                            icon: Icons.call_end_rounded,
                            label: context.l10n.translate('call_end'),
                            iconColor: Colors.white,
                            bgColor: WhatsAppCallTheme.accentRed,
                            isEndCall: true,
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
    final isRingingOrActive = _isConnected ||
        _statusKey == 'call_status_ringing' ||
        _statusKey == 'call_status_connecting';

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            WhatsAppCallTheme.surface,
            WhatsAppCallTheme.background,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            WhatsAppPulsingAvatar(
              userName: widget.remoteUserName,
              avatarUrl: widget.remoteAvatarUrl,
              isRingingOrActive: isRingingOrActive,
            ),
            const SizedBox(height: 28),
            Text(
              widget.remoteUserName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(color: Colors.black54, blurRadius: 8),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_rounded,
                    size: 12, color: WhatsAppCallTheme.primary),
                const SizedBox(width: 5),
                Text(
                  context.l10n.translate('call_encrypted'),
                  style: const TextStyle(
                    color: WhatsAppCallTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _isConnected
                  ? _formatDuration(_callDuration)
                  : context.l10n.translate(_statusKey),
              style: TextStyle(
                color:
                    _isConnected ? WhatsAppCallTheme.primary : Colors.white70,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
