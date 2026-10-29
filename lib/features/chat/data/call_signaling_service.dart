import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../../core/utils/app_logger.dart';
import 'call_ice_config.dart';
import 'call_media.dart';
import 'vps_chat_service.dart';

/// How long an incoming call rings before it counts as missed. The native ring
/// screen, the in-app dialog and the caller's timer all use this.
const int kCallRingSeconds = 45;

/// How long a call waits on the call server before it gives up.
const Duration _serverTimeout = Duration(seconds: 8);

enum CallNetworkQuality {
  good,
  fair,
  poor,
}

/// A call that cannot start or be answered. [message] can be shown to the user.
class CallSetupException implements Exception {
  const CallSetupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The key that identifies an ICE candidate. The same candidate arrives over
/// the relay and over Firestore, and it is kept once.
String candidateKey(String candidate, String? sdpMid, int? sdpMLineIndex) =>
    '${sdpMid ?? ''}|${sdpMLineIndex ?? ''}|$candidate';

/// WebRTC signaling for a 1:1 audio or video call.
///
/// The fast path is the chat server's WebSocket relay. The durable path is the
/// Firestore call document, which also rings the callee's phone through
/// sendCallPushNotification. The caller writes that document before anything
/// else, so the callee can always find the offer and the candidates.
///
/// Firestore schema
/// ────────────────
/// calls/{callId}
///   callerId      : String
///   calleeId      : String
///   offer         : {type: String, sdp: String}
///   answer        : {type: String, sdp: String}   (set by the callee)
///   status        : 'calling' | 'answered' | 'declined' | 'missed' | 'ended'
///   createdAt     : Timestamp
///   endedAt       : Timestamp   (optional)
///   durationSeconds : int       (optional)
///
/// calls/{callId}/offerCandidates/{autoId}     (written by the caller)
/// calls/{callId}/answerCandidates/{autoId}    (written by the callee)
///   candidate, sdpMid, sdpMLineIndex
class CallSignalingService {
  /// The call this app is in, if any. Used to decline a second call while busy.
  static String? _activeCallId;

  static String? get activeCallId => _activeCallId;

  static bool get isInCall => _activeCallId != null;

  // ── Internal state ─────────────────────────────────────────────────────────

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  String? _callId;
  String? _remoteUid;
  bool _isCaller = false;
  bool _finished = false;
  bool _remoteDescriptionSet = false;
  bool _remoteAnswerApplied = false;
  bool _audioEnabled = true;
  bool _videoEnabled = true;
  bool _hasLocalVideo = false;
  final List<RTCIceCandidate> _pendingIceCandidates = [];
  final Set<String> _seenCandidates = {};
  Timer? _statsTimer;
  Timer? _ringTimer;
  StreamSubscription<Map<String, dynamic>>? _vpsSignalingSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _offerCandidatesSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _answerCandidatesSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callDocSub;

  final ValueNotifier<CallNetworkQuality> networkQuality =
      ValueNotifier(CallNetworkQuality.good);

  // ── Public callbacks ───────────────────────────────────────────────────────

  /// Fired as soon as the local camera/mic stream is ready.
  void Function(MediaStream)? onLocalStream;

  /// Fired when the remote peer's track arrives.
  void Function(MediaStream)? onRemoteStream;

  /// Fired on each call-state change: `'calling'`, `'answered'`, `'ended'`,
  /// `'declined'`, `'missed'`, or `'failed'` when setup did not succeed.
  void Function(String)? onCallStateChange;

  /// Fired once when the call has ended and its resources are released.
  void Function()? onCallEnded;

  // ── Firestore shorthand ────────────────────────────────────────────────────

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _callDoc(String callId) =>
      _db.collection('calls').doc(callId);

  CollectionReference<Map<String, dynamic>> _offerCandidates(String callId) =>
      _callDoc(callId).collection('offerCandidates');

  CollectionReference<Map<String, dynamic>> _answerCandidates(String callId) =>
      _callDoc(callId).collection('answerCandidates');

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Starts an outgoing call from [localUid] to [remoteUid].
  ///
  /// Order matters. The call document is written before the local description
  /// is set, so the first candidates land on a document that exists. The offer
  /// goes out over the relay last. Throws [CallSetupException] when the call
  /// cannot be set up.
  Future<void> startCall(
    String callId,
    String localUid,
    String remoteUid, {
    bool videoEnabled = true,
    String? callerName,
    String? callerAvatar,
  }) async {
    _begin(callId, remoteUid, isCaller: true);
    _attachVpsSignalingListener();
    try {
      await _getUserMedia(videoEnabled);
      await _createPeerConnection();
      final offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': videoEnabled ? 1 : 0,
      });

      try {
        await _callDoc(callId).set({
          'callerId': localUid,
          'calleeId': remoteUid,
          'participants': [localUid, remoteUid],
          'isVideo': videoEnabled,
          if (callerName != null) 'callerName': callerName,
          if (callerAvatar != null) 'callerAvatar': callerAvatar,
          'offer': {'type': offer.type, 'sdp': offer.sdp},
          'status': 'calling',
          'createdAt': FieldValue.serverTimestamp(),
        }).timeout(_serverTimeout);
      } catch (e) {
        throw const CallSetupException(
          'Could not reach the call server. Check your connection and try again.',
        );
      }

      await _peerConnection!.setLocalDescription(offer);
      VpsChatService().sendCallSignal(
        recipientId: remoteUid,
        signalType: 'offer',
        payload: {'type': offer.type, 'sdp': offer.sdp},
        callId: callId,
        isVideo: videoEnabled,
        callerName: callerName,
        avatarUrl: callerAvatar,
      );

      onCallStateChange?.call('calling');
      _watchCallDocument(callId);
      _watchCalleeCandidates(callId);
      _ringTimer = Timer(
        const Duration(seconds: kCallRingSeconds),
        () => _end(
          state: 'missed',
          remoteSignal: 'end',
          documentStatus: 'missed',
        ),
      );
    } catch (e) {
      await _end(
        state: 'failed',
        remoteSignal: 'end',
        documentStatus: 'ended',
      );
      rethrow;
    }
  }

  /// Answers an incoming call identified by [callId].
  ///
  /// The call must still be ringing. If the caller has hung up, or the call was
  /// answered on another device, this throws [CallSetupException] and the callee
  /// sends nothing.
  Future<void> answerCall(
    String callId,
    String localUid, {
    bool videoEnabled = true,
  }) async {
    _begin(callId, null, isCaller: false);
    _attachVpsSignalingListener();
    try {
      final callData =
          (await _callDoc(callId).get().timeout(_serverTimeout)).data();
      if (callData == null) {
        throw const CallSetupException('This call is no longer available.');
      }
      if (callData['status'] != 'calling') {
        throw const CallSetupException('This call has already ended.');
      }

      final offerMap = callData['offer'];
      if (offerMap is! Map) {
        throw const CallSetupException('This call has no offer.');
      }
      final callerId = callData['callerId'] as String? ?? '';
      _remoteUid = callerId.isEmpty ? null : callerId;

      await _getUserMedia(videoEnabled);
      await _createPeerConnection();
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(
            offerMap['sdp'] as String, offerMap['type'] as String),
      );
      await _drainPendingIceCandidates();

      final answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': videoEnabled ? 1 : 0,
      });
      await _peerConnection!.setLocalDescription(answer);

      final accepted = await _writeAnswer(callId, answer);
      if (!accepted) {
        throw const CallSetupException('This call has already ended.');
      }

      if (callerId.isNotEmpty) {
        VpsChatService().sendCallSignal(
          recipientId: callerId,
          signalType: 'answer',
          payload: {'type': answer.type, 'sdp': answer.sdp},
          callId: callId,
        );
      }

      onCallStateChange?.call('answered');
      _watchCallDocument(callId);
      _watchCallerCandidates(callId);
    } catch (e) {
      await _end(
        state: 'failed',
        remoteSignal: 'declined',
        documentStatus: 'declined',
      );
      if (e is CallSetupException) rethrow;
      throw const CallSetupException(
          'Could not answer the call. Please try again.');
    }
  }

  /// Hangs up and tells the other side. Safe to call more than once.
  Future<void> endCall({int? durationSeconds}) => _end(
        state: 'ended',
        remoteSignal: 'end',
        documentStatus: 'ended',
        durationSeconds: durationSeconds,
      );

  /// Declines an incoming call before it is answered. The caller's phone stops ringing.
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
      }).timeout(_serverTimeout);
    } catch (e) {
      logWarning(
          'CallSignalingService: declineCall Firestore update error: $e');
    }
  }

  /// Turns the microphone on or off. Applies to the stream now, or when it starts.
  Future<void> toggleAudio(bool enabled) async {
    _audioEnabled = enabled;
    for (final track
        in _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = enabled;
    }
  }

  /// Whether this call sends the local camera. False for an audio call, and for
  /// a video call whose camera could not be opened.
  bool get hasLocalVideo => _hasLocalVideo;

  /// Turns the camera on or off. Applies to the stream now, or when it starts.
  Future<void> toggleVideo(bool enabled) async {
    _videoEnabled = enabled;
    for (final track
        in _localStream?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
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

  /// Ends a call that is still open when the owning screen goes away.
  void dispose() {
    if (_callId != null && !_finished) {
      unawaited(endCall());
    } else {
      unawaited(_releaseResources());
    }
  }

  // ── Call lifecycle ─────────────────────────────────────────────────────────

  void _begin(String callId, String? remoteUid, {required bool isCaller}) {
    _finished = false;
    _callId = callId;
    _remoteUid = remoteUid;
    _isCaller = isCaller;
    _remoteDescriptionSet = false;
    _remoteAnswerApplied = false;
    _pendingIceCandidates.clear();
    _seenCandidates.clear();
    _activeCallId = callId;
  }

  /// Ends this call once. Later calls do nothing. [remoteSignal] goes to the
  /// other side over the relay, [documentStatus] is written to the call
  /// document, and [state] is reported to the UI.
  Future<void> _end({
    required String state,
    String? remoteSignal,
    String? documentStatus,
    int? durationSeconds,
  }) async {
    if (_finished) return;
    _finished = true;
    final callId = _callId;
    final remoteUid = _remoteUid;
    await _releaseResources();

    if (callId != null && remoteUid != null && remoteSignal != null) {
      VpsChatService().sendCallSignal(
        recipientId: remoteUid,
        signalType: remoteSignal,
        payload: {
          if (durationSeconds != null) 'durationSeconds': durationSeconds
        },
        callId: callId,
      );
    }
    if (callId != null && documentStatus != null) {
      try {
        await _callDoc(callId).update({
          'status': documentStatus,
          'endedAt': FieldValue.serverTimestamp(),
          if (durationSeconds != null) 'durationSeconds': durationSeconds,
        }).timeout(_serverTimeout);
      } catch (e) {
        // The other side has usually ended it already, which the rules refuse.
        logInfo('CallSignalingService: end update skipped: $e');
      }
    }

    onCallStateChange?.call(state);
    onCallEnded?.call();
  }

  /// Ends the call when the other side has ended it, without telling them again.
  void _endFromRemote(String state) {
    unawaited(_end(state: state));
  }

  // ── Signal and document watchers ───────────────────────────────────────────

  void _attachVpsSignalingListener() {
    _vpsSignalingSub?.cancel();
    _vpsSignalingSub = VpsChatService().callSignalStream.listen((event) {
      if (event['callId']?.toString() != _callId) return;
      final signalType = event['signalType'] as String?;
      final payload = event['payload'];

      switch (signalType) {
        case 'answer':
          if (_isCaller && payload is Map) {
            unawaited(_applyRemoteAnswer(
              payload['sdp'] as String? ?? '',
              payload['type'] as String? ?? 'answer',
            ));
          }
        case 'candidate':
          if (payload is Map) {
            unawaited(_addIceCandidate(Map<String, dynamic>.from(payload)));
          }
        case 'end':
          _endFromRemote('ended');
        case 'declined':
          _endFromRemote('declined');
        case 'refused':
          // The relay refused our offer. The call document still exists, so
          // end it there as well, or the callee would keep ringing.
          if (event['refusedSignal'] == 'offer') {
            unawaited(_end(
              state: 'failed',
              documentStatus: 'ended',
            ));
          }
      }
    });
  }

  /// The caller watches the document for the callee's answer and for an end.
  void _watchCallDocument(String callId) {
    _callDocSub?.cancel();
    _callDocSub = _callDoc(callId).snapshots().listen(
      (snapshot) {
        final data = snapshot.data();
        if (data == null || _finished) return;
        final status = data['status'] as String?;

        if (_isCaller && status == 'answered') {
          final answer = data['answer'];
          if (answer is Map) {
            unawaited(_applyRemoteAnswer(
              answer['sdp'] as String? ?? '',
              answer['type'] as String? ?? 'answer',
            ));
          }
        }
        if (status == 'declined' || status == 'ended' || status == 'missed') {
          _endFromRemote(status!);
        }
      },
      onError: (Object e, StackTrace st) {
        if (kDebugMode) {
          debugPrint('CallSignalingService: callDoc error: $e\n$st');
        }
      },
    );
  }

  void _watchCalleeCandidates(String callId) {
    _answerCandidatesSub?.cancel();
    _answerCandidatesSub = _answerCandidates(callId).snapshots().listen(
      (snapshot) {
        for (final change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            unawaited(_addIceCandidate(change.doc.data()));
          }
        }
      },
      onError: (Object e, StackTrace st) {
        if (kDebugMode) {
          debugPrint('CallSignalingService: answerCandidates error: $e\n$st');
        }
      },
    );
  }

  void _watchCallerCandidates(String callId) {
    _offerCandidatesSub?.cancel();
    _offerCandidatesSub = _offerCandidates(callId).snapshots().listen(
      (snapshot) {
        for (final change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            unawaited(_addIceCandidate(change.doc.data()));
          }
        }
      },
      onError: (Object e, StackTrace st) {
        if (kDebugMode) {
          debugPrint('CallSignalingService: offerCandidates error: $e\n$st');
        }
      },
    );
  }

  /// Applies the callee's answer once. The relay and the document both carry it.
  Future<void> _applyRemoteAnswer(String sdp, String type) async {
    final pc = _peerConnection;
    if (pc == null || _finished || _remoteAnswerApplied || sdp.isEmpty) return;
    _remoteAnswerApplied = true;
    try {
      await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
      await _drainPendingIceCandidates();
      _ringTimer?.cancel();
      _ringTimer = null;
      onCallStateChange?.call('answered');
    } catch (e) {
      // Let the other channel try again.
      _remoteAnswerApplied = false;
      if (kDebugMode) {
        debugPrint('CallSignalingService: setRemoteDescription error: $e');
      }
    }
  }

  /// Writes the answer. Returns false when the rules refuse it, which means the
  /// call has already ended. Other failures return true, and the relay carries the answer.
  Future<bool> _writeAnswer(String callId, RTCSessionDescription answer) async {
    try {
      await _callDoc(callId).update({
        'answer': {'type': answer.type, 'sdp': answer.sdp},
        'status': 'answered',
      }).timeout(_serverTimeout);
      return true;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') return false;
      logWarning('CallSignalingService: answer write skipped: $e');
      return true;
    } catch (e) {
      logWarning('CallSignalingService: answer write skipped: $e');
      return true;
    }
  }

  // ── Media and peer connection ──────────────────────────────────────────────

  /// Captures audio, and video when the call asks for it. A camera that cannot
  /// be opened leaves the call on audio, and [hasLocalVideo] reports that.
  Future<void> _getUserMedia(bool videoEnabled) async {
    final media = await captureCallMedia<MediaStream>(
      wantVideo: videoEnabled,
      getUserMedia: (constraints) =>
          navigator.mediaDevices.getUserMedia(constraints),
    );
    final stream = media.stream;
    _localStream = stream;
    _hasLocalVideo = media.hasVideo;
    for (final track in stream.getAudioTracks()) {
      track.enabled = _audioEnabled;
    }
    for (final track in stream.getVideoTracks()) {
      track.enabled = _videoEnabled;
    }
    onLocalStream?.call(stream);
  }

  /// Creates the [RTCPeerConnection], adds local tracks, and wires up
  /// ICE-candidate and track-received event handlers.
  Future<void> _createPeerConnection() async {
    final iceConfig = await CallIceConfig.shared.current();
    if (_finished) throw const CallSetupException('This call was cancelled.');
    _peerConnection = await createPeerConnection(iceConfig);

    final localStream = _localStream;
    if (localStream != null) {
      for (final track in localStream.getTracks()) {
        await _peerConnection!.addTrack(track, localStream);
      }
    }

    // ICE candidates go over the relay for speed and into the call document
    // for the durable copy. The receiver keeps one of each.
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      final callId = _callId;
      if (callId == null || _finished) return;
      final candidateData = {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      };
      final remoteUid = _remoteUid;
      if (remoteUid != null && remoteUid.isNotEmpty) {
        VpsChatService().sendCallSignal(
          recipientId: remoteUid,
          signalType: 'candidate',
          payload: candidateData,
          callId: callId,
        );
      }
      if (_isCaller) {
        unawaited(_writeCandidate(
            _offerCandidates(callId), candidateData, 'offerCandidate'));
      } else {
        unawaited(_writeCandidate(
            _answerCandidates(callId), candidateData, 'answerCandidate'));
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

  /// Parses a candidate and adds it to the peer connection, or queues it until
  /// the remote description is set. A candidate already seen is skipped.
  Future<void> _addIceCandidate(Map<String, dynamic>? data) async {
    if (data == null || _finished) return;
    final candidateText = data['candidate'] as String?;
    if (candidateText == null || candidateText.trim().isEmpty) return;

    final sdpMid = data['sdpMid'] as String?;
    final sdpMLineIndex = (data['sdpMLineIndex'] as num?)?.toInt();
    if (!_seenCandidates
        .add(candidateKey(candidateText, sdpMid, sdpMLineIndex))) {
      return;
    }

    final candidate = RTCIceCandidate(candidateText, sdpMid, sdpMLineIndex);
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

  /// Flushes queued ICE candidates once the remote description is active.
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

  /// Cancels everything this call started. Idempotent.
  Future<void> _releaseResources() async {
    final releasedCallId = _callId;
    if (releasedCallId != null && _activeCallId == releasedCallId) {
      _activeCallId = null;
    }

    _ringTimer?.cancel();
    _ringTimer = null;
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
    _seenCandidates.clear();
    _remoteDescriptionSet = false;
    _remoteAnswerApplied = false;

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
