import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../../core/audio/call_audio_session.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/call_quality.dart';
import 'call_ice_config.dart';
import 'call_log_repository.dart';
import 'call_media.dart';
import 'vps_chat_service.dart';

export '../domain/call_quality.dart' show CallLinkSample, CallNetworkQuality;

/// How long an incoming call rings before it counts as missed. The native ring
/// screen, the in-app dialog and the caller's timer all use this.
const int kCallRingSeconds = 45;

/// How long a call waits on the call server before it gives up.
const Duration _serverTimeout = Duration(seconds: 8);

/// How long an answered call may take to connect its media before it fails.
const Duration _connectTimeout = Duration(seconds: 30);

/// How long a dropped link may stay down before the call starts to rebuild it.
/// A link that recovers inside this time needs no rebuild.
const Duration _reconnectGrace = Duration(seconds: 4);

/// How long one rebuild may wait for the other side before the call ends.
const Duration _reconnectTimeout = Duration(seconds: 15);

/// How often a rebuild request is sent again until the other side answers. The
/// relay drops what is sent while a socket is down, so one request is not enough.
const Duration _reconnectResend = Duration(seconds: 3);

/// How long after a rebuild's answer the connection state is checked. A link
/// that stayed up may raise no event, so this check is what finishes the rebuild.
const Duration _settleDelay = Duration(seconds: 2);

/// How long a link must stay up before the rebuild budget starts again.
const Duration _stableLinkPeriod = Duration(seconds: 60);

/// How often the link is measured while the call is up.
const Duration _statsInterval = Duration(seconds: 4);

/// The signals that offer something the other side must act on. If the relay
/// refuses one, the call cannot go on.
const _offerSignals = {'offer', 'reoffer', 'renegotiate'};

/// The key that identifies an ICE candidate. The same candidate arrives over
/// the relay and over Firestore, and it is kept once.
String candidateKey(String candidate, String? sdpMid, int? sdpMLineIndex) =>
    '${sdpMid ?? ''}|${sdpMLineIndex ?? ''}|$candidate';

/// The reason a setup stops when the user hung up or left before it finished.
/// It is never shown, since nobody is looking at the call any more.
const String kCallCancelledMessage = 'This call was cancelled.';

/// Whether a call document still describes a ringing call: it exists, it is
/// still 'calling', and it was created recently enough to be ringing.
bool callShouldRing(Map<String, dynamic>? data, DateTime now) {
  if (data == null || data['status'] != 'calling') return false;
  final createdAt = data['createdAt'];
  if (createdAt is Timestamp) {
    final age = now.difference(createdAt.toDate());
    if (age > const Duration(seconds: kCallRingSeconds + 15)) return false;
  }
  return true;
}

/// The members' emails stored on a call, by uid, or null when they are missing.
Map<String, String>? callMemberEmails(Object? value) {
  if (value is! Map) return null;
  final emails = <String, String>{};
  value.forEach((key, email) {
    if (key is String && email is String && email.isNotEmpty) {
      emails[key] = email;
    }
  });
  return emails.length == 2 ? emails : null;
}

/// What the caller is told when the server cannot be reached to ring the callee.
const String kCallUnreachableMessage =
    'Could not reach the call server. Check your connection and try again.';

/// The first [count] characters of [text]. Runes are counted, so an emoji is never split.
String _firstCharacters(String text, int count) =>
    String.fromCharCodes(text.runes.take(count));

/// What the caller is told when the call document cannot be written. The rules
/// refuse a call that is not between two active members of the tour, and they do
/// so with a permission error. Any other failure means the server did not answer.
String _callWriteFailure(Object error) {
  if (error is FirebaseException && error.code == 'permission-denied') {
    return 'This call was refused. Check that you are both still members of this tour, then try again.';
  }
  return kCallUnreachableMessage;
}

/// A call that cannot start or be answered. [message] can be shown to the user.
class CallSetupException implements Exception {
  const CallSetupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// WebRTC signaling for a 1:1 audio or video call.
///
/// The fast path is the chat server's WebSocket relay. The durable path is the
/// Firestore call document, which also rings the callee's phone through
/// sendCallPushNotification. The caller writes that document before anything
/// else, so the callee can always find the offer and the candidates.
///
/// Rebuilding a dropped link. Only the caller makes offers, so the two sides
/// never offer at once. When the link drops, the caller sends a new offer with
/// an ICE restart over the relay, and the callee answers it. A callee that
/// notices the drop asks the caller to offer ('renegotiate'). The new SDP
/// never touches the call document, whose offer and answer are fixed once
/// written. The candidates still go to the subcollections as before.
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

  /// Declines a call that is still ringing. It needs no call screen or relay,
  /// so the native ring screen can decline from a background isolate. The call
  /// document is updated first, and the decline is logged only when that
  /// update goes through, so the call is never logged twice.
  static Future<void> declineRingingCall({
    required String callId,
    required String calleeUid,
    required String callerId,
    required bool isVideo,
  }) =>
      _closeRingingCall(
        callId: callId,
        calleeUid: calleeUid,
        callerId: callerId,
        isVideo: isVideo,
        documentStatus: 'declined',
        logStatus: 'declined',
      );

  /// Closes a call that is still marked as ringing long after it should have
  /// stopped, because the caller's app went away. The callee never saw it, so it
  /// is logged as missed, not declined.
  static Future<void> expireStaleCall({
    required String callId,
    required String calleeUid,
    required String callerId,
    required bool isVideo,
  }) =>
      _closeRingingCall(
        callId: callId,
        calleeUid: calleeUid,
        callerId: callerId,
        isVideo: isVideo,
        documentStatus: 'ended',
        logStatus: 'missed',
      );

  static Future<void> _closeRingingCall({
    required String callId,
    required String calleeUid,
    required String callerId,
    required bool isVideo,
    required String documentStatus,
    required String logStatus,
  }) async {
    // The tour the call was placed in is read first, so the log can open the
    // chat when the two have never messaged.
    Map<String, dynamic>? data;
    try {
      data = (await _callDocRef(callId).get().timeout(_serverTimeout)).data();
    } catch (e) {
      logInfo('CallSignalingService: call read before closing skipped: $e');
    }
    var closed = false;
    try {
      await _callDocRef(callId).update({
        'status': documentStatus,
        'endedAt': FieldValue.serverTimestamp(),
      }).timeout(_serverTimeout);
      closed = true;
    } catch (e) {
      logWarning('CallSignalingService: closing a ringing call failed: $e');
    }
    final caller =
        callerId.isNotEmpty ? callerId : (data?['callerId'] as String? ?? '');
    if (!closed || caller.isEmpty) return;
    await _writeCallLog(
      writerUid: calleeUid,
      callerId: caller,
      calleeId: calleeUid,
      callId: callId,
      isVideo: isVideo,
      status: logStatus,
      sharedTourId: data?['sharedTourId'] as String?,
      memberEmails: callMemberEmails(data?['memberEmails']),
    );
  }

  /// Whether [callId] should still ring on this phone. A push or relay offer
  /// can arrive after the call was answered, declined or ended, or after the
  /// user already declined it here, and must not ring again. When the call
  /// cannot be read, it rings, so a slow network never hides a real call.
  static Future<bool> isStillRinging(String callId) async {
    if (callId.isEmpty) return false;
    try {
      // In a background isolate the session is restored from storage a moment
      // after start-up, and the rules let only the two people read the call.
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance
            .authStateChanges()
            .firstWhere((user) => user != null)
            .timeout(const Duration(seconds: 3));
      }
      final snapshot =
          await _callDocRef(callId).get().timeout(const Duration(seconds: 4));
      return callShouldRing(snapshot.data(), DateTime.now());
    } catch (e) {
      logInfo('CallSignalingService: ringing check skipped: $e');
      return true;
    }
  }

  // ── Internal state ─────────────────────────────────────────────────────────

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  String? _callId;
  String? _remoteUid;
  String? _localUid;
  bool _callIsVideo = false;
  bool _isCaller = false;
  bool _finished = false;

  /// Set when the user hangs up or leaves before the call has finished setting
  /// up. A setup still waiting on a permission prompt or the network then stops
  /// instead of starting a call nobody is looking at.
  bool _cancelled = false;

  /// The tour the call belongs to and both members' emails, so the call log can
  /// open the chat when the two have never messaged.
  String? _sharedTourId;
  Map<String, String>? _memberEmails;

  /// Restarts the rebuild budget once a link has stayed up for a while, so a
  /// long call is not ended by drops that are far apart.
  Timer? _stableTimer;

  /// The stream remote tracks join when the other side sends no stream of its
  /// own. A future, so two tracks arriving together share one stream.
  Future<MediaStream>? _fallbackRemoteStream;
  bool _remoteDescriptionSet = false;
  bool _remoteAnswerApplied = false;
  bool _audioEnabled = true;
  bool _videoEnabled = true;
  bool _hasLocalVideo = false;
  final List<RTCIceCandidate> _pendingIceCandidates = [];
  final Set<String> _seenCandidates = {};
  Timer? _statsTimer;
  Timer? _ringTimer;
  Timer? _connectTimer;
  Timer? _reconnectGraceTimer;
  Timer? _reconnectTimer;
  Timer? _settleTimer;
  Timer? _rebuildResendTimer;
  StreamSubscription<Map<String, dynamic>>? _vpsSignalingSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _offerCandidatesSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _answerCandidatesSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callDocSub;

  /// When the media first connected. Null until then, and reset when the call ends.
  DateTime? _connectedAt;
  bool _reconnecting = false;
  final CallReconnectPolicy _reconnectPolicy = CallReconnectPolicy();

  /// The caller's offer for a rebuild, kept until the callee answers it.
  Map<String, dynamic>? _rebuildOffer;

  /// The callee's last answered rebuild offer. A repeated offer is not applied again.
  String? _lastRebuildOfferSdp;

  /// The answer sent for [_lastRebuildOfferSdp], sent again if the offer repeats.
  Map<String, dynamic>? _lastRebuildAnswer;

  double _remoteGain = 1.0;
  int? _appliedVideoBitrateCap;
  CallLinkSample? _linkSample;
  final OutboundBitrateMeter _bitrateMeter = OutboundBitrateMeter();
  final PacketLossMeter _lossMeter = PacketLossMeter();

  final ValueNotifier<CallNetworkQuality> networkQuality =
      ValueNotifier(CallNetworkQuality.good);

  // ── Public callbacks ───────────────────────────────────────────────────────

  /// Fired as soon as the local camera/mic stream is ready.
  void Function(MediaStream)? onLocalStream;

  /// Fired when the remote peer's track arrives.
  void Function(MediaStream)? onRemoteStream;

  /// Fired on each call-state change: `'calling'`, `'answered'` (accepted, media
  /// still connecting), `'connected'`, `'reconnecting'`, `'ended'`, `'declined'`,
  /// `'missed'`, or `'failed'` when setup or the connection did not succeed.
  void Function(String)? onCallStateChange;

  /// Fired once when the call has ended and its resources are released.
  void Function()? onCallEnded;

  /// Fired when the other side turns its camera on or off.
  void Function(bool on)? onRemoteCamera;

  // ── Firestore shorthand ────────────────────────────────────────────────────

  static DocumentReference<Map<String, dynamic>> _callDocRef(String callId) =>
      FirebaseFirestore.instance.collection('calls').doc(callId);

  CollectionReference<Map<String, dynamic>> _offerCandidates(String callId) =>
      _callDocRef(callId).collection('offerCandidates');

  CollectionReference<Map<String, dynamic>> _answerCandidates(String callId) =>
      _callDocRef(callId).collection('answerCandidates');

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Whole seconds the media has been connected. Zero before it connects.
  int get connectedSeconds => callConnectedSeconds(
        connectedAt: _connectedAt,
        now: DateTime.now(),
      );

  /// The latest link figures, or null before the first poll that had media.
  CallLinkSample? get linkSample => _linkSample;

  /// The remote audio multiplier. 1 is normal.
  double get remoteGain => _remoteGain;

  /// Makes the other side louder or quieter. 1 is normal and up to 10 is the
  /// loudest the platform allows. Applied now and to a stream that arrives later.
  Future<void> setRemoteGain(double gain) async {
    _remoteGain = gain.clamp(0.0, 10.0).toDouble();
    for (final track
        in _remoteStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      await _applyRemoteGain(track);
    }
  }

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
    required String? sharedTourId,
    required String localEmail,
    required String? remoteEmail,
  }) async {
    // The rules accept a call only between two members of the tour they share.
    if (sharedTourId == null || remoteEmail == null || remoteEmail.isEmpty) {
      throw const CallSetupException(
        'You can only call members of a tour you share.',
      );
    }
    _begin(callId, remoteUid, isCaller: true);
    _localUid = localUid;
    _callIsVideo = videoEnabled;
    _sharedTourId = sharedTourId;
    _memberEmails = {localUid: localEmail, remoteUid: remoteEmail};
    _attachVpsSignalingListener();
    try {
      await _getUserMedia(videoEnabled);
      await _createPeerConnection();
      final offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': 1,
        // Always: a voice call can become a video call without a new offer.
        'offerToReceiveVideo': 1,
      });

      // The rules refuse a name over 80 characters or an avatar link over 512, so
      // an over-long value is cut or left out instead of refusing the whole call.
      final sentName =
          callerName == null ? null : _firstCharacters(callerName, 80);
      final sentAvatar = callerAvatar != null && callerAvatar.length <= 512
          ? callerAvatar
          : null;
      try {
        await _callDocRef(callId).set({
          'callerId': localUid,
          'calleeId': remoteUid,
          'participants': [localUid, remoteUid],
          'sharedTourId': sharedTourId,
          'memberEmails': {localUid: localEmail, remoteUid: remoteEmail},
          'isVideo': videoEnabled,
          if (sentName != null) 'callerName': sentName,
          if (sentAvatar != null) 'callerAvatar': sentAvatar,
          'offer': {'type': offer.type, 'sdp': offer.sdp},
          'status': 'calling',
          'createdAt': FieldValue.serverTimestamp(),
        }).timeout(_serverTimeout);
      } catch (e, st) {
        logWarning('CallSignalingService: call document write failed', e, st);
        throw CallSetupException(_callWriteFailure(e));
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
        () => unawaited(_onRingTimeout()),
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
    _localUid = localUid;
    _attachVpsSignalingListener();
    try {
      final callData =
          (await _callDocRef(callId).get().timeout(_serverTimeout)).data();
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
      _callIsVideo = callData['isVideo'] == true;
      _sharedTourId = callData['sharedTourId'] as String?;
      _memberEmails = callMemberEmails(callData['memberEmails']);

      await _getUserMedia(videoEnabled);
      await _createPeerConnection();
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(
            offerMap['sdp'] as String, offerMap['type'] as String),
      );
      await _allowVideoUpgrade();
      await _drainPendingIceCandidates();

      final answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': 1,
        // Always: a voice call can become a video call without a new offer.
        'offerToReceiveVideo': 1,
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
      _startConnectTimer();
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

  /// Hangs up and tells the other side. Safe to call more than once. The
  /// connected time is recorded here, so every way of ending a call logs it.
  Future<void> endCall() {
    _cancelled = true;
    return _end(
      state: 'ended',
      remoteSignal: 'end',
      documentStatus: 'ended',
    );
  }

  /// True once the user has hung up or left, even before the call started.
  bool get wasCancelled => _cancelled;

  /// Declines an incoming call before it is answered. The caller's phone stops ringing.
  Future<void> declineCall(
    String callId, {
    String? callerId,
    bool isVideo = false,
  }) async {
    final targetId = callerId ?? _remoteUid;
    if (targetId != null && targetId.isNotEmpty) {
      VpsChatService().sendCallSignal(
        recipientId: targetId,
        signalType: 'declined',
        payload: <String, dynamic>{},
        callId: callId,
      );
    }
    final calleeId = FirebaseAuth.instance.currentUser?.uid;
    if (calleeId == null) return;
    await declineRingingCall(
      callId: callId,
      calleeUid: calleeId,
      callerId: targetId ?? '',
      isVideo: isVideo,
    );
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
    _relay('camera', payload: {'on': enabled && _hasLocalVideo});
  }

  /// Turns the camera on in a call that has none yet, so a voice call becomes a
  /// video call. Returns false when the camera cannot be opened or the other
  /// side's app has no video section to send it on.
  Future<bool> startCamera() async {
    if (_hasLocalVideo) {
      await toggleVideo(true);
      return true;
    }
    final pc = _peerConnection;
    final local = _localStream;
    if (pc == null || local == null || _finished) return false;
    MediaStream? camera;
    try {
      camera = await navigator.mediaDevices.getUserMedia(<String, dynamic>{
        'audio': false,
        'video': callMediaConstraints(video: true)['video'],
      });
      final tracks = camera.getVideoTracks();
      final transceiver = await _videoTransceiver();
      if (tracks.isEmpty || transceiver == null || _finished) {
        for (final track in camera.getTracks()) {
          await track.stop();
        }
        return false;
      }
      final track = tracks.first;
      await transceiver.sender.replaceTrack(track);
      await local.addTrack(track);
      _hasLocalVideo = true;
      _videoEnabled = true;
      onLocalStream?.call(local);
      _relay('camera', payload: {'on': true});
      return true;
    } catch (e, st) {
      logWarning('CallSignalingService: camera could not be started', e, st);
      for (final track in camera?.getTracks() ?? const <MediaStreamTrack>[]) {
        await track.stop();
      }
      return false;
    }
  }

  /// The connection's video section, or null when the other side sent none.
  Future<RTCRtpTransceiver?> _videoTransceiver() async {
    final pc = _peerConnection;
    if (pc == null) return null;
    for (final transceiver in await pc.getTransceivers()) {
      if (transceiver.receiver.track?.kind == 'video' ||
          transceiver.sender.track?.kind == 'video') {
        return transceiver;
      }
    }
    return null;
  }

  /// The callee's side of the video section in a voice call: two-way, so its
  /// camera can be turned on later.
  Future<void> _allowVideoUpgrade() async {
    if (_hasLocalVideo) return;
    try {
      final transceiver = await _videoTransceiver();
      await transceiver?.setDirection(TransceiverDirection.SendRecv);
    } catch (e) {
      logInfo('CallSignalingService: video section stays receive-only: $e');
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
    _cancelled = true;
    if (_callId != null && !_finished) {
      unawaited(endCall());
    } else {
      unawaited(_releaseResources());
    }
  }

  // ── Call lifecycle ─────────────────────────────────────────────────────────

  void _begin(String callId, String? remoteUid, {required bool isCaller}) {
    if (_cancelled) {
      // The user hung up or left while the call was being prepared.
      throw const CallSetupException(kCallCancelledMessage);
    }
    _finished = false;
    _callId = callId;
    _remoteUid = remoteUid;
    _isCaller = isCaller;
    _remoteDescriptionSet = false;
    _remoteAnswerApplied = false;
    _pendingIceCandidates.clear();
    _seenCandidates.clear();
    _connectedAt = null;
    _reconnecting = false;
    _activeCallId = callId;
  }

  /// Ends this call once. Later calls do nothing. [remoteSignal] goes to the
  /// other side over the relay, [documentStatus] is written to the call
  /// document, and [state] is reported to the UI. The call is logged in the
  /// chat by the side whose update reaches the call document.
  Future<void> _end({
    required String state,
    String? remoteSignal,
    String? documentStatus,
  }) async {
    if (_finished) return;
    _finished = true;
    final callId = _callId;
    final remoteUid = _remoteUid;
    final localUid = _localUid;
    final isCaller = _isCaller;
    final isVideo = _callIsVideo;
    final sharedTourId = _sharedTourId;
    final memberEmails = _memberEmails;
    // Read before the release clears the connection time.
    final seconds = connectedSeconds;
    final durationSeconds = seconds > 0 ? seconds : null;
    await _releaseResources();

    if (callId != null && remoteUid != null && remoteSignal != null) {
      VpsChatService().sendCallSignal(
        recipientId: remoteUid,
        signalType: remoteSignal,
        payload: <String, dynamic>{},
        callId: callId,
      );
    }
    if (callId != null && documentStatus != null) {
      var ended = false;
      try {
        await _callDocRef(callId).update({
          'status': documentStatus,
          'endedAt': FieldValue.serverTimestamp(),
          if (durationSeconds != null) 'durationSeconds': durationSeconds,
        }).timeout(_serverTimeout);
        ended = true;
      } catch (e) {
        // The other side has usually ended it already, which the rules refuse.
        logInfo('CallSignalingService: end update skipped: $e');
      }
      if (ended && localUid != null && remoteUid != null) {
        unawaited(_writeCallLog(
          writerUid: localUid,
          callerId: isCaller ? localUid : remoteUid,
          calleeId: isCaller ? remoteUid : localUid,
          callId: callId,
          isVideo: isVideo,
          status: documentStatus,
          durationSeconds: durationSeconds,
          sharedTourId: sharedTourId,
          memberEmails: memberEmails,
        ));
      }
    }

    onCallStateChange?.call(state);
    onCallEnded?.call();
  }

  /// Ends the call when the other side has ended it, without telling them again.
  void _endFromRemote(String state) {
    unawaited(_end(state: state));
  }

  // ── Connection health ──────────────────────────────────────────────────────

  /// The callee did not answer in time. Their answer may have just been written,
  /// so the call document is read first: an answer there wins over the timeout.
  Future<void> _onRingTimeout() async {
    final callId = _callId;
    if (callId == null || _finished || _remoteAnswerApplied) return;
    try {
      final data =
          (await _callDocRef(callId).get().timeout(_serverTimeout)).data();
      final answer = data?['answer'];
      if (data?['status'] == 'answered' && answer is Map) {
        await _applyRemoteAnswer(
          answer['sdp'] as String? ?? '',
          answer['type'] as String? ?? 'answer',
        );
      }
    } catch (e) {
      logInfo('CallSignalingService: answer check at ring timeout skipped: $e');
    }
    if (_finished || _remoteAnswerApplied) return;
    await _end(
      state: 'missed',
      remoteSignal: 'end',
      documentStatus: 'missed',
    );
  }

  /// Ends the call if the media never connects after the answer.
  void _startConnectTimer() {
    _connectTimer?.cancel();
    _connectTimer = Timer(_connectTimeout, () {
      if (_connectedAt != null || _finished) return;
      unawaited(_end(
        state: 'failed',
        remoteSignal: 'end',
        documentStatus: 'ended',
      ));
    });
  }

  /// The link dropped. Before the first connection, the connect timer decides.
  /// A plain disconnect waits a short grace period, since links often recover on
  /// their own. A failed link is rebuilt at once.
  void _linkDropped({required bool immediate}) {
    if (_finished || _connectedAt == null) return;
    _stableTimer?.cancel();
    _stableTimer = null;
    _updateNetworkQuality(CallNetworkQuality.poor);
    if (immediate) {
      _startRebuild();
      return;
    }
    _reconnectGraceTimer ??= Timer(_reconnectGrace, _startRebuild);
  }

  void _onLinkConnected() {
    _connectTimer?.cancel();
    _connectTimer = null;
    _reconnectGraceTimer?.cancel();
    _reconnectGraceTimer = null;
    _settleTimer?.cancel();
    _settleTimer = null;
    _reconnecting = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    // A rebuild offer still waiting for its answer keeps being sent, so both
    // sides end on the same description.
    if (_rebuildOffer == null) _stopRebuildResend();
    // Candidates held during a rebuild stay held: they belong to the new
    // description, and the path that applies it drains them.
    if (_connectedAt == null) {
      // The other side shows video only while the camera is really on.
      _relay('camera', payload: {'on': _hasLocalVideo && _videoEnabled});
    }
    _connectedAt ??= DateTime.now();
    _stableTimer?.cancel();
    _stableTimer = Timer(_stableLinkPeriod, _reconnectPolicy.reset);
    _startStatsMonitoring();
    _updateNetworkQuality(CallNetworkQuality.good);
    onCallStateChange?.call('connected');
  }

  /// Starts a rebuild of a dropped link. The caller offers. The callee asks.
  void _startRebuild() {
    _reconnectGraceTimer?.cancel();
    _reconnectGraceTimer = null;
    if (_finished || _callId == null || _reconnecting || _connectedAt == null) {
      return;
    }
    if (_isCaller && !_reconnectPolicy.startAttempt()) {
      unawaited(_end(
        state: 'failed',
        remoteSignal: 'end',
        documentStatus: 'ended',
      ));
      return;
    }
    _enterRebuild();
    if (_isCaller) {
      unawaited(_sendRebuildOffer());
    } else {
      _startRebuildResend();
    }
  }

  /// Holds incoming candidates until the new description is in, so none of them
  /// are applied to the old session. Ends the call if the rebuild never finishes.
  void _enterRebuild() {
    _reconnecting = true;
    _remoteDescriptionSet = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectTimeout, () {
      if (!_reconnecting || _finished) return;
      // The link may have come back without an event saying so. Only a link
      // that is still down ends the call.
      if (_isLinkUp) {
        _onLinkConnected();
        return;
      }
      unawaited(_end(
        state: 'failed',
        remoteSignal: 'end',
        documentStatus: 'ended',
      ));
    });
    _updateNetworkQuality(CallNetworkQuality.poor);
    onCallStateChange?.call('reconnecting');
  }

  bool get _isLinkUp =>
      _peerConnection?.connectionState ==
      RTCPeerConnectionState.RTCPeerConnectionStateConnected;

  /// Once an answer is in, a link that is up may not raise any event. This
  /// checks the connection state a moment later and finishes the rebuild if it is up.
  void _scheduleSettle() {
    _settleTimer?.cancel();
    _settleTimer = Timer(_settleDelay, () {
      _settleTimer = null;
      if (_reconnecting && !_finished && _isLinkUp) _onLinkConnected();
    });
  }

  void _stopRebuildResend() {
    _rebuildResendTimer?.cancel();
    _rebuildResendTimer = null;
  }

  void _cancelRebuild() {
    _reconnecting = false;
    _rebuildOffer = null;
    _lastRebuildAnswer = null;
    _settleTimer?.cancel();
    _settleTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopRebuildResend();
  }

  Future<void> _sendRebuildOffer() async {
    final pc = _peerConnection;
    if (pc == null || _callId == null) return;
    try {
      final offer = await pc.createOffer({
        'iceRestart': true,
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 1,
      });
      await pc.setLocalDescription(offer);
      // Sent even if the link has come back in the meantime, so the connection
      // is never left waiting on an answer nobody asked for.
      if (_finished) return;
      _rebuildOffer = {'type': offer.type, 'sdp': offer.sdp};
      _startRebuildResend();
    } catch (e, st) {
      logWarning('CallSignalingService: rebuild offer error', e, st);
      unawaited(_end(
        state: 'failed',
        remoteSignal: 'end',
        documentStatus: 'ended',
      ));
    }
  }

  /// Sends the rebuild request now, and again until the other side answers.
  void _startRebuildResend() {
    _rebuildResendTimer?.cancel();
    _sendRebuildRequest();
    _rebuildResendTimer = Timer.periodic(
      _reconnectResend,
      (_) => _sendRebuildRequest(),
    );
  }

  void _sendRebuildRequest() {
    if (_isCaller) {
      final offer = _rebuildOffer;
      if (offer != null) _relay('reoffer', payload: offer);
    } else if (_reconnecting) {
      _relay('renegotiate');
    }
  }

  void _relay(String signalType, {Map<String, dynamic>? payload}) {
    final callId = _callId;
    final remoteUid = _remoteUid;
    if (callId == null || remoteUid == null || remoteUid.isEmpty) return;
    VpsChatService().sendCallSignal(
      recipientId: remoteUid,
      signalType: signalType,
      payload: payload ?? <String, dynamic>{},
      callId: callId,
    );
  }

  /// The callee's side of a rebuild: apply the caller's new offer, answer it.
  Future<void> _answerRebuildOffer(String sdp, String type) async {
    final pc = _peerConnection;
    if (pc == null || _finished || sdp.isEmpty) return;
    if (sdp == _lastRebuildOfferSdp) {
      // The caller repeats its offer until it hears back, so the answer is
      // repeated too, in case the first one was lost.
      final answer = _lastRebuildAnswer;
      if (answer != null) _relay('reanswer', payload: answer);
      return;
    }
    _lastRebuildOfferSdp = sdp;
    _enterRebuild();
    _stopRebuildResend();
    try {
      await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
      await _drainPendingIceCandidates();
      final answer = await pc.createAnswer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 1,
      });
      await pc.setLocalDescription(answer);
      _lastRebuildAnswer = {'type': answer.type, 'sdp': answer.sdp};
      _relay('reanswer', payload: _lastRebuildAnswer);
      _scheduleSettle();
    } catch (e, st) {
      logWarning('CallSignalingService: rebuild answer error', e, st);
      unawaited(_end(
        state: 'failed',
        remoteSignal: 'end',
        documentStatus: 'ended',
      ));
    }
  }

  /// The caller's side of a rebuild: apply the callee's answer to its offer.
  Future<void> _applyRebuildAnswer(String sdp, String type) async {
    final pc = _peerConnection;
    if (pc == null || _finished || _rebuildOffer == null || sdp.isEmpty) {
      return;
    }
    _rebuildOffer = null;
    _stopRebuildResend();
    try {
      await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
      await _drainPendingIceCandidates();
      _scheduleSettle();
    } catch (e, st) {
      logWarning('CallSignalingService: rebuild answer apply error', e, st);
      unawaited(_end(
        state: 'failed',
        remoteSignal: 'end',
        documentStatus: 'ended',
      ));
    }
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
        case 'reoffer':
          if (!_isCaller && payload is Map) {
            unawaited(_answerRebuildOffer(
              payload['sdp'] as String? ?? '',
              payload['type'] as String? ?? 'offer',
            ));
          }
        case 'reanswer':
          if (_isCaller && payload is Map) {
            unawaited(_applyRebuildAnswer(
              payload['sdp'] as String? ?? '',
              payload['type'] as String? ?? 'answer',
            ));
          }
        case 'renegotiate':
          if (_isCaller) _startRebuild();
        case 'camera':
          if (payload is Map) onRemoteCamera?.call(payload['on'] == true);
        case 'end':
          _endFromRemote('ended');
        case 'declined':
          _endFromRemote('declined');
        case 'refused':
          // The relay refused one of our signals. An offer that did not reach
          // the callee must end the call, or the callee would keep ringing.
          if (_offerSignals.contains(event['refusedSignal'])) {
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
    _callDocSub = _callDocRef(callId).snapshots().listen(
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
        logWarning('CallSignalingService: callDoc error', e, st);
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
        logWarning('CallSignalingService: answerCandidates error', e, st);
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
        logWarning('CallSignalingService: offerCandidates error', e, st);
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
      _startConnectTimer();
      onCallStateChange?.call('answered');
    } catch (e, st) {
      // Let the other channel try again.
      _remoteAnswerApplied = false;
      logWarning('CallSignalingService: setRemoteDescription error', e, st);
    }
  }

  /// Writes the answer. Returns false when the rules refuse it, which means the
  /// call has already ended. Other failures return true, and the relay carries the answer.
  Future<bool> _writeAnswer(String callId, RTCSessionDescription answer) async {
    try {
      await _callDocRef(callId).update({
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
    if (_finished || _cancelled) {
      // Hung up while the camera or microphone was opening: nothing may stay on.
      for (final track in stream.getTracks()) {
        await track.stop();
      }
      await stream.dispose();
      await CallAudioSession.release();
      throw const CallSetupException(kCallCancelledMessage);
    }
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
    if (_finished || _cancelled) {
      throw const CallSetupException(kCallCancelledMessage);
    }
    final peer = await createPeerConnection(iceConfig);
    if (_finished || _cancelled) {
      // Hung up while the connection was being made: close it, or it keeps the
      // audio session on.
      await peer.close();
      await peer.dispose();
      throw const CallSetupException(kCallCancelledMessage);
    }
    _peerConnection = peer;

    final localStream = _localStream;
    if (localStream != null) {
      for (final track in localStream.getTracks()) {
        await _peerConnection!.addTrack(track, localStream);
      }
    }
    // A voice call still negotiates a video section, so either side can turn
    // its camera on later without a new offer. The caller adds it here; the
    // callee gets it from the offer and opens it in [_allowVideoUpgrade].
    if (_isCaller && !_hasLocalVideo) {
      await _peerConnection!.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendRecv),
      );
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
        // A sender without a stream: its tracks share one stream. The future is
        // shared, so tracks that arrive together cannot make two streams.
        _fallbackRemoteStream ??= createLocalMediaStream('remoteStream');
        stream = await _fallbackRemoteStream!;
        await stream.addTrack(event.track);
      }
      event.track.enabled = true;
      for (final track in stream.getTracks()) {
        track.enabled = true;
      }
      _remoteStream = stream;
      if (event.track.kind == 'audio') {
        unawaited(_applyRemoteGain(event.track));
      }
      onRemoteStream?.call(stream);
    };

    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      logDebug('CallSignalingService: connectionState → $state');
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _onLinkConnected();
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
          if (_connectedAt == null) {
            _updateNetworkQuality(CallNetworkQuality.fair);
          }
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          _linkDropped(immediate: false);
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _linkDropped(immediate: true);
          break;
        default:
          break;
      }
    };

    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      logDebug('CallSignalingService: iceConnectionState → $state');
    };
  }

  Future<void> _applyRemoteGain(MediaStreamTrack track) async {
    try {
      await Helper.setVolume(_remoteGain, track);
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
    }
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
    } catch (e, st) {
      logWarning('CallSignalingService: addCandidate error', e, st);
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
      } catch (e, st) {
        logWarning('CallSignalingService: queued addCandidate error', e, st);
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
    } catch (e, st) {
      logWarning('CallSignalingService: failed to write $label', e, st);
    }
  }

  // ── Link quality ───────────────────────────────────────────────────────────

  void _startStatsMonitoring() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(_statsInterval, (_) => _measureLink());
  }

  /// Reads the link and updates the quality and the video bitrate cap. While a
  /// rebuild is running the old figures say nothing about the new link, so they are skipped.
  Future<void> _measureLink() async {
    final pc = _peerConnection;
    if (pc == null || _finished || _reconnecting) return;
    try {
      final reports = await pc.getStats();
      final raw = callLinkSampleFromStats(
        reports.map((report) => <String, dynamic>{
              for (final entry in report.values.entries)
                entry.key.toString(): entry.value,
              'type': report.type,
            }),
      );
      final sentBytes = raw.sentBytes;
      final lost = raw.packetsLost;
      final received = raw.packetsReceived;
      // The loss of the last interval, not of the whole call. Until there are
      // two readings the running figure is all there is.
      final intervalLoss = lost == null || received == null
          ? null
          : _lossMeter.lossSince(lost, received);
      final sample = raw
          .withOutboundKbps(
            sentBytes == null
                ? null
                : _bitrateMeter.kbpsAt(sentBytes, DateTime.now()),
          )
          .withLossRatio(intervalLoss ?? raw.lossRatio);
      if (!sample.hasIncomingMedia) return;
      _linkSample = sample;
      final quality = classifyCallLink(sample);
      _updateNetworkQuality(quality);
      await _applyVideoBitrateCap(quality);
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
    }
  }

  /// Caps the video this device sends for the link's quality, so a weak link
  /// gets a smaller picture rather than a frozen one.
  Future<void> _applyVideoBitrateCap(CallNetworkQuality quality) async {
    final pc = _peerConnection;
    final cap = videoBitrateCapFor(quality);
    if (pc == null || cap == _appliedVideoBitrateCap) return;
    _appliedVideoBitrateCap = cap;
    try {
      for (final sender in await pc.getSenders()) {
        if (sender.track?.kind != 'video') continue;
        final parameters = sender.parameters;
        final encodings = parameters.encodings;
        if (encodings == null || encodings.isEmpty) continue;
        for (final encoding in encodings) {
          encoding.maxBitrate = cap;
        }
        await sender.setParameters(parameters);
      }
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
    }
  }

  void _updateNetworkQuality(CallNetworkQuality q) {
    if (networkQuality.value != q) {
      networkQuality.value = q;
    }
  }

  // ── Teardown ───────────────────────────────────────────────────────────────

  /// Cancels everything this call started. Idempotent.
  Future<void> _releaseResources() async {
    final releasedCallId = _callId;
    if (releasedCallId != null && _activeCallId == releasedCallId) {
      _activeCallId = null;
    }

    _ringTimer?.cancel();
    _ringTimer = null;
    _connectTimer?.cancel();
    _connectTimer = null;
    _statsTimer?.cancel();
    _statsTimer = null;
    _reconnectGraceTimer?.cancel();
    _reconnectGraceTimer = null;
    _stableTimer?.cancel();
    _stableTimer = null;
    _cancelRebuild();
    _connectedAt = null;
    _lastRebuildOfferSdp = null;
    _linkSample = null;
    _appliedVideoBitrateCap = null;
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

    final peer = _peerConnection;
    _peerConnection = null;
    if (peer != null) {
      // Closing alone leaves the plugin's audio session on. Disposing the last
      // connection is what hands the audio back to the system.
      try {
        await peer.close();
      } catch (error, stackTrace) {
        logSkipped(error, stackTrace);
      }
      try {
        await peer.dispose();
      } catch (error, stackTrace) {
        logSkipped(error, stackTrace);
      }
    } else {
      // Audio may have been opened before any connection existed.
      await CallAudioSession.release();
    }

    _localStream?.getTracks().forEach((track) => track.stop());
    await _localStream?.dispose();
    _localStream = null;

    await _remoteStream?.dispose();
    _remoteStream = null;
    _fallbackRemoteStream = null;

    _callId = null;
    _remoteUid = null;
    _isCaller = false;
  }
}

/// Writes a finished call into its chat. A failure is logged and never shown,
/// since the call has already ended.
Future<void> _writeCallLog({
  required String writerUid,
  required String callerId,
  required String calleeId,
  required String callId,
  required bool isVideo,
  required String status,
  int? durationSeconds,
  String? sharedTourId,
  Map<String, String>? memberEmails,
}) async {
  try {
    await CallLogRepository().record(
      writerUid: writerUid,
      callerId: callerId,
      calleeId: calleeId,
      callId: callId,
      isVideo: isVideo,
      status: status,
      durationSeconds: durationSeconds,
      sharedTourId: sharedTourId,
      memberEmails: memberEmails,
    );
  } catch (e) {
    logWarning('CallSignalingService: call log not written: $e');
  }
}
