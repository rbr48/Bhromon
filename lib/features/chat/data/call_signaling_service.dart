import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'vps_chat_service.dart';

enum CallNetworkQuality {
  good,
  fair,
  poor,
}

/// WebRTC signaling service that uses Firestore as the signaling channel
/// for peer-to-peer audio/video calls between two users.
///
/// Firestore schema
/// ────────────────
/// calls/{callId}
///   callerId      : String
///   calleeId      : String
///   offer         : {type: String, sdp: String}
///   answer        : {type: String, sdp: String}
///   status        : 'calling' | 'answered' | 'ended' | 'declined'
///   createdAt     : Timestamp
///
/// calls/{callId}/offerCandidates/{autoId}
///   candidate     : String
///   sdpMid        : String
///   sdpMLineIndex : int
///
/// calls/{callId}/answerCandidates/{autoId}
///   candidate     : String
///   sdpMid        : String
///   sdpMLineIndex : int
class CallSignalingService {
  // ── ICE / STUN / TURN configuration ───────────────────────────────────────

  static const String _turnHost = String.fromEnvironment(
    'BHROMON_TURN_HOST',
    defaultValue: '148.135.137.245:3478',
  );

  static final Map<String, dynamic> _iceConfig = {
    'iceServers': [
      // Primary STUN servers
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
          'stun:stun2.l.google.com:19302',
          'stun:stun.cloudflare.com:3478',
        ],
      },
      // OpenRelay Public TURN Server (worldwide high-availability WebRTC relay)
      {
        'urls': [
          'turn:openrelay.metered.ca:80',
          'turn:openrelay.metered.ca:443',
          'turn:openrelay.metered.ca:443?transport=tcp',
        ],
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      // VPS Coturn Dedicated Relay
      {
        'urls': [
          'turn:$_turnHost?transport=udp',
          'turn:$_turnHost?transport=tcp',
        ],
        'username': '2030000000:bhromon',
        'credential': 'f99sT/qs6uiwqv32z/j1RYx+m0A=',
      },
    ],
    'sdpSemantics': 'unified-plan',
  };

  // ── Internal state ─────────────────────────────────────────────────────────

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  String? _callId;
  String? _remoteUid;
  bool _isCaller = false;
  bool _remoteDescriptionSet = false;
  final List<RTCIceCandidate> _pendingIceCandidates = [];
  StreamSubscription<Map<String, dynamic>>? _vpsSignalingSub;
  Timer? _statsTimer;
  final ValueNotifier<CallNetworkQuality> networkQuality =
      ValueNotifier(CallNetworkQuality.good);

  // ── Public callbacks ───────────────────────────────────────────────────────

  /// Fired as soon as the local camera/mic stream is ready.
  void Function(MediaStream)? onLocalStream;

  /// Fired when the remote peer's track arrives.
  void Function(MediaStream)? onRemoteStream;

  /// Fired on call-state transitions: `'calling'`, `'answered'`, `'ended'`,
  /// `'declined'`.
  void Function(String)? onCallStateChange;

  /// Fired when the call has fully ended and resources have been released.
  void Function()? onCallEnded;

  // ── Firestore stream subscriptions ────────────────────────────────────────

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _offerCandidatesSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _answerCandidatesSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callDocSub;

  // ── Firestore shorthand ────────────────────────────────────────────────────

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _callDoc(String callId) =>
      _db.collection('calls').doc(callId);

  CollectionReference<Map<String, dynamic>> _offerCandidates(String callId) =>
      _callDoc(callId).collection('offerCandidates');

  CollectionReference<Map<String, dynamic>> _answerCandidates(String callId) =>
      _callDoc(callId).collection('answerCandidates');

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Initiates an outgoing call from [localUid] to [remoteUid].
  ///
  /// Creates a peer connection, captures local media, generates an SDP offer,
  /// writes the call document to Firestore, and watches for the callee's
  /// answer.
  Future<void> startCall(
    String callId,
    String localUid,
    String remoteUid, {
    bool videoEnabled = true,
    String? callerName,
    String? callerAvatar,
  }) async {
    _callId = callId;
    _remoteUid = remoteUid;
    _isCaller = true;
    _remoteDescriptionSet = false;
    _pendingIceCandidates.clear();
    _attachVpsSignalingListener();

    await _getUserMedia(videoEnabled);
    await _createPeerConnection();

    // Create SDP offer with explicit audio receive.
    final offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': videoEnabled ? 1 : 0,
    });
    await _peerConnection!.setLocalDescription(offer);

    // Relay call offer via VPS WebSocket (<15ms, zero Firestore quota)
    VpsChatService().sendCallSignal(
      recipientId: remoteUid,
      signalType: 'offer',
      payload: {'type': offer.type, 'sdp': offer.sdp},
      callId: callId,
      isVideo: videoEnabled,
      callerName: callerName,
      avatarUrl: callerAvatar,
    );

    // Best-effort Firestore call document write
    try {
      await _callDoc(callId).set({
        'callerId': localUid,
        'calleeId': remoteUid,
        'participants': [localUid, remoteUid],
        'isVideo': videoEnabled,
        if (callerName != null) 'callerName': callerName,
        if (callerAvatar != null) 'callerAvatar': callerAvatar,
        'offer': {
          'type': offer.type,
          'sdp': offer.sdp,
        },
        'status': 'calling',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[CallSignaling] Firestore call doc set skipped/quota: $e');
    }

    onCallStateChange?.call('calling');

    // Subscribe to ICE candidates sent by the callee.
    _answerCandidatesSub = _answerCandidates(callId).snapshots().listen(
      (snapshot) {
        for (final change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            _addIceCandidate(change.doc.data());
          }
        }
      },
      onError: (Object e, StackTrace st) {
        if (kDebugMode) {
          debugPrint('CallSignalingService: answerCandidates error: $e\n$st');
        }
      },
    );

    // Watch the call document for the callee's answer SDP.
    _callDocSub = _callDoc(callId).snapshots().listen(
      (snapshot) async {
        final data = snapshot.data();
        if (data == null) return;

        final status = data['status'] as String?;
        if (status != null) {
          onCallStateChange?.call(status);
        }

        final answerMap = data['answer'] as Map<String, dynamic>?;
        if (answerMap != null &&
            _peerConnection?.signalingState !=
                RTCSignalingState.RTCSignalingStateStable) {
          final answer = RTCSessionDescription(
            answerMap['sdp'] as String,
            answerMap['type'] as String,
          );
          try {
            await _peerConnection!.setRemoteDescription(answer);
            await _drainPendingIceCandidates();
          } catch (e) {
            if (kDebugMode) {
              debugPrint('CallSignalingService: setRemoteDescription error: $e');
            }
          }
        }

        if (status == 'ended' || status == 'declined') {
          _releaseResources();
          onCallEnded?.call();
        }
      },
      onError: (Object e, StackTrace st) {
        if (kDebugMode) {
          debugPrint('CallSignalingService: callDoc error: $e\n$st');
        }
      },
    );
  }

  /// Answers an incoming call identified by [callId].
  ///
  /// Reads the caller's SDP offer from Firestore, captures local media,
  /// creates an answer, and writes it back. Also watches for the caller's
  /// ICE candidates.
  Future<void> answerCall(
    String callId,
    String localUid, {
    bool videoEnabled = true,
  }) async {
    _callId = callId;
    _isCaller = false;
    _remoteDescriptionSet = false;
    _pendingIceCandidates.clear();
    _attachVpsSignalingListener();

    // Read the existing call document to get the offer.
    final callSnapshot = await _callDoc(callId).get();
    final callData = callSnapshot.data();
    if (callData == null) {
      throw StateError(
          'CallSignalingService: call document $callId does not exist.');
    }

    final offerMap = callData['offer'] as Map<String, dynamic>?;
    if (offerMap == null) {
      throw StateError(
          'CallSignalingService: call document $callId has no offer.');
    }

    final callerId = callData['callerId'] as String? ?? '';
    if (callerId.isNotEmpty) {
      _remoteUid = callerId;
    }

    await _getUserMedia(videoEnabled);
    await _createPeerConnection();

    // Set the caller's offer as the remote description and drain queued candidates.
    final offer = RTCSessionDescription(
      offerMap['sdp'] as String,
      offerMap['type'] as String,
    );
    await _peerConnection!.setRemoteDescription(offer);
    await _drainPendingIceCandidates();

    // Create and set our answer with explicit audio receive.
    final answer = await _peerConnection!.createAnswer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': videoEnabled ? 1 : 0,
    });
    await _peerConnection!.setLocalDescription(answer);

    if (callerId.isNotEmpty) {
      VpsChatService().sendCallSignal(
        recipientId: callerId,
        signalType: 'answer',
        payload: {'type': answer.type, 'sdp': answer.sdp},
        callId: callId,
      );
    }

    // Best-effort Firestore answer update
    try {
      await _callDoc(callId).update({
        'answer': {
          'type': answer.type,
          'sdp': answer.sdp,
        },
        'status': 'answered',
      });
    } catch (e) {
      debugPrint('[CallSignaling] Firestore answer update skipped/quota: $e');
    }

    onCallStateChange?.call('answered');

    // Subscribe to ICE candidates from the caller.
    _offerCandidatesSub = _offerCandidates(callId).snapshots().listen(
      (snapshot) {
        for (final change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            _addIceCandidate(change.doc.data());
          }
        }
      },
      onError: (Object e, StackTrace st) {
        if (kDebugMode) {
          debugPrint('CallSignalingService: offerCandidates error: $e\n$st');
        }
      },
    );

    // Watch the call document for status changes (e.g. caller ends the call).
    _callDocSub = _callDoc(callId).snapshots().listen(
      (snapshot) {
        final data = snapshot.data();
        if (data == null) return;

        final status = data['status'] as String?;
        if (status == 'ended' || status == 'declined') {
          onCallStateChange?.call(status!);
          _releaseResources();
          onCallEnded?.call();
        }
      },
      onError: (Object e, StackTrace st) {
        if (kDebugMode) {
          debugPrint('CallSignalingService: callDoc error: $e\n$st');
        }
      },
    );
  }

  /// Ends the call, notifies the remote peer via Firestore, and releases all
  /// resources.
  Future<void> endCall({int? durationSeconds}) async {
    if (_remoteUid != null && _remoteUid!.isNotEmpty) {
      VpsChatService().sendCallSignal(
        recipientId: _remoteUid!,
        signalType: 'end',
        payload: {'durationSeconds': durationSeconds},
        callId: _callId,
      );
    }
    if (_callId != null) {
      try {
        await _callDoc(_callId!).update({
          'status': 'ended',
          'endedAt': FieldValue.serverTimestamp(),
          if (durationSeconds != null) 'durationSeconds': durationSeconds,
        });
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
              'CallSignalingService: endCall Firestore update error: $e');
        }
      }
    }
    await _releaseResources();
    onCallEnded?.call();
  }

  /// Declines an incoming call before answering.
  Future<void> declineCall(String callId, {String? callerId}) async {
    final targetId = callerId ?? _remoteUid;
    if (targetId != null && targetId.isNotEmpty) {
      VpsChatService().sendCallSignal(
        recipientId: targetId,
        signalType: 'declined',
        payload: <String, dynamic>{},
        callId: callId,
      );
    }
    try {
      await _callDoc(callId).update({
        'status': 'declined',
        'endedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            'CallSignalingService: declineCall Firestore update error: $e');
      }
    }
  }

  /// Enables or disables all audio tracks on the local stream.
  Future<void> toggleAudio(bool enabled) async {
    final stream = _localStream;
    if (stream == null) return;
    for (final track in stream.getAudioTracks()) {
      track.enabled = enabled;
    }
  }

  /// Enables or disables all video tracks on the local stream.
  Future<void> toggleVideo(bool enabled) async {
    final stream = _localStream;
    if (stream == null) return;
    for (final track in stream.getVideoTracks()) {
      track.enabled = enabled;
    }
  }

  /// Switches between the front and rear cameras on mobile.
  ///
  /// No-op on web (camera switching is not supported via the Helper API).
  Future<void> switchCamera() async {
    if (kIsWeb) return;
    final stream = _localStream;
    if (stream == null) return;
    final videoTracks = stream.getVideoTracks();
    if (videoTracks.isEmpty) return;
    await Helper.switchCamera(videoTracks.first);
  }

  /// Disposes of the service. Should be called when the owning widget or
  /// service is permanently destroyed.
  void dispose() {
    if (_peerConnection != null) {
      endCall();
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Captures audio (and optionally video) from the local device.
  Future<void> _getUserMedia(bool videoEnabled) async {
    final mediaConstraints = <String, dynamic>{
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': videoEnabled
          ? <String, dynamic>{
              'facingMode': 'user',
              'width': {'ideal': 640},
              'height': {'ideal': 480},
              'frameRate': {'ideal': 30},
            }
          : false,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    for (final track in _localStream!.getTracks()) {
      track.enabled = true;
    }
    onLocalStream?.call(_localStream!);
  }

  /// Creates the [RTCPeerConnection], adds local tracks, and wires up
  /// ICE-candidate and track-received event handlers.
  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection(_iceConfig);

    // Add all local tracks to the peer connection and ensure enabled.
    final localStream = _localStream;
    if (localStream != null) {
      for (final track in localStream.getTracks()) {
        track.enabled = true;
        await _peerConnection!.addTrack(track, localStream);
      }
    }

    // ICE candidate handler — write candidates to the appropriate subcollection.
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (_callId == null) return;
      final candidateData = {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      };
      if (_remoteUid != null && _remoteUid!.isNotEmpty) {
        VpsChatService().sendCallSignal(
          recipientId: _remoteUid!,
          signalType: 'candidate',
          payload: candidateData,
          callId: _callId,
        );
      }
      if (_isCaller) {
        unawaited(_writeCandidate(
            _offerCandidates(_callId!), candidateData, 'offerCandidate'));
      } else {
        unawaited(_writeCandidate(
            _answerCandidates(_callId!), candidateData, 'answerCandidate'));
      }
    };

    // Capture the genuine remote peer's media stream.
    _peerConnection!.onTrack = (RTCTrackEvent event) async {
      MediaStream stream;
      if (event.streams.isNotEmpty) {
        stream = event.streams.first;
      } else {
        _remoteStream ??= await createLocalMediaStream('remoteStream');
        _remoteStream!.addTrack(event.track);
        stream = _remoteStream!;
      }
      event.track.enabled = true;
      for (final track in stream.getTracks()) {
        track.enabled = true;
      }
      _remoteStream = stream;
      onRemoteStream?.call(stream);
    };

    // Log connection-state changes and track live network quality.
    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      if (kDebugMode) {
        debugPrint('CallSignalingService: connectionState → $state');
      }
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _updateNetworkQuality(CallNetworkQuality.good);
          _startStatsMonitoring();
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
          _updateNetworkQuality(CallNetworkQuality.fair);
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _updateNetworkQuality(CallNetworkQuality.poor);
          break;
        default:
          break;
      }
    };

    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      if (kDebugMode) {
        debugPrint('CallSignalingService: iceConnectionState → $state');
      }
      if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _updateNetworkQuality(CallNetworkQuality.poor);
      }
    };
  }

  /// Parses a candidate map and adds it to the peer connection or queues it.
  Future<void> _addIceCandidate(Map<String, dynamic>? data) async {
    if (data == null) return;
    final candStr = data['candidate'] as String?;
    if (candStr == null || candStr.trim().isEmpty) return;

    final candidate = RTCIceCandidate(
      candStr,
      data['sdpMid'] as String?,
      (data['sdpMLineIndex'] as num?)?.toInt(),
    );

    if (!_remoteDescriptionSet ||
        _peerConnection == null ||
        _peerConnection!.signalingState ==
            RTCSignalingState.RTCSignalingStateClosed) {
      _pendingIceCandidates.add(candidate);
      return;
    }

    try {
      await _peerConnection!.addCandidate(candidate);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CallSignalingService: addCandidate error: $e');
      }
    }
  }

  /// Flushes all queued ICE candidates once the remote description is active.
  Future<void> _drainPendingIceCandidates() async {
    _remoteDescriptionSet = true;
    if (_peerConnection == null) return;
    final queued = List<RTCIceCandidate>.from(_pendingIceCandidates);
    _pendingIceCandidates.clear();
    for (final candidate in queued) {
      try {
        await _peerConnection!.addCandidate(candidate);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('CallSignalingService: queued addCandidate error: $e');
        }
      }
    }
  }

  Future<void> _writeCandidate(
    CollectionReference<Map<String, dynamic>> col,
    Map<String, dynamic> data,
    String label,
  ) async {
    try {
      await col.add(data);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CallSignalingService: failed to write $label: $e');
      }
    }
  }

  void _startStatsMonitoring() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      final pc = _peerConnection;
      if (pc == null) return;
      try {
        final stats = await pc.getStats();
        int packetsLost = 0;
        int packetsReceived = 0;
        for (final report in stats) {
          if (report.values['type'] == 'inbound-rtp') {
            packetsLost += (report.values['packetsLost'] as num?)?.toInt() ?? 0;
            packetsReceived +=
                (report.values['packetsReceived'] as num?)?.toInt() ?? 0;
          }
        }
        if (packetsReceived > 0) {
          final total = packetsLost + packetsReceived;
          final lossRatio = packetsLost / total;
          if (lossRatio > 0.15) {
            _updateNetworkQuality(CallNetworkQuality.poor);
          } else if (lossRatio > 0.05) {
            _updateNetworkQuality(CallNetworkQuality.fair);
          } else {
            _updateNetworkQuality(CallNetworkQuality.good);
          }
        }
      } catch (_) {}
    });
  }

  void _updateNetworkQuality(CallNetworkQuality q) {
    if (networkQuality.value != q) {
      networkQuality.value = q;
    }
  }

  void _attachVpsSignalingListener() {
    _vpsSignalingSub?.cancel();
    _vpsSignalingSub = VpsChatService().callSignalStream.listen((event) async {
      final cId = event['callId']?.toString();
      if (cId != _callId) return;
      final signalType = event['signalType'] as String?;
      final payload = event['payload'];

      if (signalType == 'answer' && _isCaller && payload is Map) {
        final answerMap = Map<String, dynamic>.from(payload);
        if (_peerConnection?.signalingState !=
            RTCSignalingState.RTCSignalingStateStable) {
          final sdp = answerMap['sdp'] as String? ?? '';
          final type = answerMap['type'] as String? ?? 'answer';
          try {
            await _peerConnection!
                .setRemoteDescription(RTCSessionDescription(sdp, type));
            await _drainPendingIceCandidates();
            onCallStateChange?.call('answered');
          } catch (e) {
            if (kDebugMode) {
              debugPrint('CallSignalingService: vps answer error: $e');
            }
          }
        }
      } else if (signalType == 'candidate' && payload is Map) {
        await _addIceCandidate(Map<String, dynamic>.from(payload));
      } else if (signalType == 'end' || signalType == 'declined') {
        onCallStateChange?.call(signalType!);
        _releaseResources();
        onCallEnded?.call();
      }
    });
  }

  /// Cancels all subscriptions, closes the peer connection, and stops all tracks.
  Future<void> _releaseResources() async {
    _statsTimer?.cancel();
    _statsTimer = null;
    networkQuality.value = CallNetworkQuality.good;
    await _offerCandidatesSub?.cancel();
    await _answerCandidatesSub?.cancel();
    await _callDocSub?.cancel();
    await _vpsSignalingSub?.cancel();
    _offerCandidatesSub = null;
    _answerCandidatesSub = null;
    _callDocSub = null;
    _vpsSignalingSub = null;
    _pendingIceCandidates.clear();
    _remoteDescriptionSet = false;

    await _peerConnection?.close();
    _peerConnection = null;

    _localStream?.getTracks().forEach((track) => track.stop());
    await _localStream?.dispose();
    _localStream = null;

    await _remoteStream?.dispose();
    _remoteStream = null;

    _callId = null;
    _remoteUid = null;
    _isCaller = false;
  }
}
