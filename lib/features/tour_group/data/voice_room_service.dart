import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/utils/app_logger.dart';
import '../../chat/data/call_ice_config.dart';
import '../../chat/data/call_media.dart';
import '../domain/models/channel_models.dart';
import '../domain/models/date_codec.dart';

/// Thrown when a voice room already holds [capacity] people.
class VoiceRoomFullException implements Exception {
  final int capacity;
  const VoiceRoomFullException(this.capacity);
}

/// Represents a member currently connected to a voice channel.
class VoiceParticipant {
  final String email;
  final String displayName;
  final String? photoUrl;
  final String uid;
  final bool isAudioMuted;
  final bool isVideoOn;
  final DateTime joinedAt;

  /// Identifies one join. A member who leaves and comes back gets a new one, so
  /// the others reconnect to the new join instead of keeping the old connection.
  final String sessionId;

  const VoiceParticipant({
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.uid = '',
    this.isAudioMuted = false,
    this.isVideoOn = false,
    required this.joinedAt,
    this.sessionId = '',
  });

  factory VoiceParticipant.fromMap(Map<String, dynamic> map) {
    return VoiceParticipant(
      email: normalizeEmail(map['email'] as String? ?? ''),
      displayName: (map['displayName'] as String?)?.trim() ?? 'Explorer',
      photoUrl: map['photoUrl'] as String?,
      uid: map['uid'] as String? ?? '',
      isAudioMuted: map['isAudioMuted'] == true,
      isVideoOn: map['isVideoOn'] == true,
      joinedAt: readDate(map['joinedAt']) ?? DateTime.now(),
      sessionId: map['sessionId'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': normalizeEmail(email),
      'displayName': displayName,
      if (photoUrl != null && photoUrl!.isNotEmpty) 'photoUrl': photoUrl,
      'uid': uid,
      'isAudioMuted': isAudioMuted,
      'isVideoOn': isVideoOn,
      'joinedAt': writeDate(joinedAt),
      if (sessionId.isNotEmpty) 'sessionId': sessionId,
    };
  }
}

/// Discord-style drop-in/drop-out voice and video channels.
///
/// Every pair of members in a room shares one WebRTC connection. Each side
/// refreshes its seat every 45 seconds, and a seat that goes quiet for three
/// minutes is treated as empty. Signaling uses one Firestore document per pair,
/// and the offer and answer carry the join session of each side, so a stale
/// offer from an earlier join is never answered.
class VoiceRoomService {
  static final VoiceRoomService _instance = VoiceRoomService._internal();
  factory VoiceRoomService() => _instance;
  VoiceRoomService._internal();

  static const Duration _heartbeatEvery = Duration(seconds: 45);
  static const Duration _retryAfter = Duration(seconds: 5);

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _seats(
          String tourId, String channelId) =>
      _db
          .collection('tours')
          .doc(tourId)
          .collection('channels')
          .doc(channelId)
          .collection('voice_participants');

  CollectionReference<Map<String, dynamic>> _signals(
          String tourId, String channelId) =>
      _db
          .collection('tours')
          .doc(tourId)
          .collection('channels')
          .doc(channelId)
          .collection('voice_signals');

  // Active room state
  String? _activeTourId;
  String? _activeChannelId;
  String? _myEmail;
  String? _myName;
  String? _myUid;
  String? _myPhotoUrl;
  String? _mySession;

  bool _isAudioMuted = false;
  bool _isVideoOn = false;
  bool _isSpeakerOn = false;

  MediaStream? _localStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  bool _localRendererInitialized = false;

  // Remote peers, keyed by email
  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  final Map<String, StreamSubscription<dynamic>> _signalSubs = {};
  // The join session each connection was made for.
  final Map<String, String> _peerSessions = {};
  // The video sender of each connection, so the camera can be switched on later.
  final Map<String, RTCRtpSender> _videoSenders = {};
  // Peers whose connection is being set up. Stops a second attempt while the first is still waiting.
  final Set<String> _connecting = {};

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _participantsSub;
  QuerySnapshot<Map<String, dynamic>>? _lastSeats;
  Timer? _heartbeat;
  Timer? _retryTimer;

  final StreamController<void> _changeNotifier =
      StreamController<void>.broadcast();
  Stream<void> get changes => _changeNotifier.stream;

  bool get isConnected => _activeChannelId != null;
  String? get currentChannelId => _activeChannelId;
  String? get currentTourId => _activeTourId;
  bool get isAudioMuted => _isAudioMuted;
  bool get isVideoOn => _isVideoOn;
  bool get isSpeakerOn => _isSpeakerOn;

  RTCVideoRenderer get localRenderer => _localRenderer;
  Map<String, RTCVideoRenderer> get remoteRenderers => _remoteRenderers;

  /// Watch active participants in any voice channel in the tour.
  Stream<List<VoiceParticipant>> watchParticipants(
      String tourId, String channelId) {
    return _seats(tourId, channelId).snapshots().map((snap) =>
        snap.docs.map((d) => VoiceParticipant.fromMap(d.data())).toList());
  }

  /// Connects to a voice channel.
  ///
  /// If anything fails while joining, the room is left again before the error
  /// is rethrown. A half-joined room would otherwise report itself as connected.
  Future<void> joinVoiceRoom({
    required String tourId,
    required String channelId,
    required String myEmail,
    required String myName,
    String? photoUrl,
    required String myUid,
    bool enableVideo = false,
  }) async {
    // If already in a room, leave it first
    if (isConnected) {
      if (_activeTourId == tourId && _activeChannelId == channelId) {
        return; // already connected to this channel
      }
      await leaveVoiceRoom();
    }

    // A full room is refused before anything changes: no microphone prompt and
    // no state set.
    final seated = await _seats(tourId, channelId).get();
    final taken = countSeatedVoiceParticipants(
      {for (final doc in seated.docs) doc.id: doc.data()},
      exceptEmail: normalizeEmail(myEmail),
      now: DateTime.now(),
    );
    if (taken >= kVoiceRoomMaxParticipants) {
      throw const VoiceRoomFullException(kVoiceRoomMaxParticipants);
    }

    _activeTourId = tourId;
    _activeChannelId = channelId;
    _myEmail = normalizeEmail(myEmail);
    _myName = myName;
    _myPhotoUrl = photoUrl;
    _myUid = myUid;
    _mySession = const Uuid().v4();
    _isAudioMuted = false;
    _isVideoOn = enableVideo;

    try {
      // Permissions on mobile. The media call below reports a refusal.
      if (!kIsWeb) {
        await Permission.microphone.request();
        if (enableVideo) {
          await Permission.camera.request();
        }
      }

      if (!_localRendererInitialized) {
        await _localRenderer.initialize();
        _localRendererInitialized = true;
      }

      await _setupLocalMedia(enableVideo: enableVideo);

      final seat = VoiceParticipant(
        email: _myEmail!,
        displayName: _myName!,
        photoUrl: _myPhotoUrl,
        uid: _myUid ?? '',
        isAudioMuted: _isAudioMuted,
        isVideoOn: _isVideoOn,
        joinedAt: DateTime.now(),
        sessionId: _mySession!,
      );
      await _seats(tourId, channelId).doc(_myEmail!).set({
        ...seat.toMap(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      });

      _participantsSub =
          _seats(tourId, channelId).snapshots().listen(_onParticipantsChanged);
      _heartbeat =
          Timer.periodic(_heartbeatEvery, (_) => _updateSeat(const {}));
    } catch (e) {
      await leaveVoiceRoom();
      rethrow;
    }

    _notify();
  }

  Future<void> _setupLocalMedia({required bool enableVideo}) async {
    final media = await captureCallMedia<MediaStream>(
      wantVideo: enableVideo,
      getUserMedia: (constraints) =>
          navigator.mediaDevices.getUserMedia(constraints),
    );
    // A camera that could not be opened joins on audio. The camera button can
    // still switch video on later.
    _isVideoOn = media.hasVideo;
    final stream = media.stream;
    _localStream = stream;
    for (final track in stream.getTracks()) {
      track.enabled = true;
    }
    _localRenderer.srcObject = stream;

    // Default to speakerphone for group voice rooms on mobile
    if (!kIsWeb) {
      _isSpeakerOn = true;
      await Helper.setSpeakerphoneOn(true);
    }
  }

  /// Connects to live seats that are new, and disconnects from those that left
  /// or joined again under a new session.
  void _onParticipantsChanged(QuerySnapshot<Map<String, dynamic>> snap) {
    if (!isConnected || _myEmail == null) return;
    _lastSeats = snap;

    final now = DateTime.now();
    final live = <String, String>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final email = normalizeEmail(data['email'] as String? ?? doc.id);
      if (email.isEmpty || email == _myEmail) continue;
      if (!isVoiceSeatLive(data, now: now)) continue;
      live[email] = data['sessionId'] as String? ?? '';
    }

    for (final email in _peerConnections.keys.toList()) {
      if (!live.containsKey(email) || _peerSessions[email] != live[email]) {
        _disconnectFromPeer(email);
      }
    }

    for (final entry in live.entries) {
      if (!_peerConnections.containsKey(entry.key) &&
          !_connecting.contains(entry.key)) {
        unawaited(_connectToPeer(entry.key, entry.value));
      }
    }

    _notify();
  }

  String _signalDocId(String peerA, String peerB) {
    final sorted = [peerA, peerB]..sort();
    return '${sorted[0]}__${sorted[1]}';
  }

  /// Whether a connection to [remoteEmail] for [remoteSession] is still wanted.
  bool _stillWanted(String remoteEmail, String remoteSession) =>
      isConnected && _peerSessions[remoteEmail] == remoteSession;

  Future<void> _connectToPeer(String remoteEmail, String remoteSession) async {
    final tourId = _activeTourId;
    final channelId = _activeChannelId;
    final myEmail = _myEmail;
    final mySession = _mySession;
    if (tourId == null ||
        channelId == null ||
        myEmail == null ||
        mySession == null) {
      return;
    }

    _connecting.add(remoteEmail);
    _peerSessions[remoteEmail] = remoteSession;
    try {
      final iceConfig = await CallIceConfig.shared.current();
      if (!_stillWanted(remoteEmail, remoteSession)) return;

      final pc = await createPeerConnection(iceConfig);
      _peerConnections[remoteEmail] = pc;

      // A video section is always negotiated, so the camera can be turned on
      // later with replaceTrack and no new offer.
      final videoTransceiver = await pc.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendRecv),
      );
      _videoSenders[remoteEmail] = videoTransceiver.sender;
      final localVideo = _localVideoTrack();
      if (localVideo != null) {
        await videoTransceiver.sender.replaceTrack(localVideo);
      }

      final localStream = _localStream;
      if (localStream != null) {
        for (final track in localStream.getAudioTracks()) {
          await pc.addTrack(track, localStream);
        }
      }

      final remoteRenderer = RTCVideoRenderer();
      await remoteRenderer.initialize();
      _remoteRenderers[remoteEmail] = remoteRenderer;

      pc.onTrack = (RTCTrackEvent event) async {
        event.track.enabled = true;
        for (final track in event.streams.isNotEmpty
            ? event.streams.first.getTracks()
            : [event.track]) {
          track.enabled = true;
        }
        if (event.streams.isNotEmpty) {
          remoteRenderer.srcObject = event.streams.first;
        } else {
          final existing = remoteRenderer.srcObject;
          if (existing != null) {
            existing.addTrack(event.track);
          } else {
            final s = await createLocalMediaStream('remote_$remoteEmail');
            s.addTrack(event.track);
            remoteRenderer.srcObject = s;
          }
        }
        _notify();
      };

      final isOfferer = myEmail.compareTo(remoteEmail) < 0;
      final signalRef =
          _signals(tourId, channelId).doc(_signalDocId(myEmail, remoteEmail));
      final ownCandidates = signalRef
          .collection(isOfferer ? 'offerCandidates' : 'answerCandidates');
      final peerCandidates = signalRef
          .collection(isOfferer ? 'answerCandidates' : 'offerCandidates');

      // ICE candidates that arrive before the remote description wait here.
      final pendingCandidates = <RTCIceCandidate>[];
      var remoteDescriptionSet = false;

      Future<void> drainCandidates() async {
        remoteDescriptionSet = true;
        for (final cand in List<RTCIceCandidate>.from(pendingCandidates)) {
          await pc.addCandidate(cand).catchError((_) {});
        }
        pendingCandidates.clear();
      }

      pc.onIceCandidate = (RTCIceCandidate candidate) {
        unawaited(_addQuietly(ownCandidates, {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
          'session': mySession,
        }));
      };

      _signalSubs['${remoteEmail}_cand'] =
          peerCandidates.snapshots().listen((snap) async {
        for (final change in snap.docChanges) {
          if (change.type != DocumentChangeType.added) continue;
          final d = change.doc.data();
          // A candidate from an earlier join of this peer does not belong to this connection.
          if (d == null || d['session'] != remoteSession) continue;
          final candStr = d['candidate'] as String?;
          if (candStr == null || candStr.trim().isEmpty) continue;
          final cand = RTCIceCandidate(
            candStr,
            d['sdpMid'] as String?,
            (d['sdpMLineIndex'] as num?)?.toInt(),
          );
          if (!remoteDescriptionSet) {
            pendingCandidates.add(cand);
          } else {
            await pc.addCandidate(cand).catchError((_) {});
          }
        }
      });

      if (isOfferer) {
        final offer = await pc.createOffer({
          'offerToReceiveAudio': 1,
          'offerToReceiveVideo': 1,
        });
        await pc.setLocalDescription(offer);
        if (!_stillWanted(remoteEmail, remoteSession)) return;

        await signalRef.set({
          'offer': {'type': offer.type, 'sdp': offer.sdp},
          'offerer': myEmail,
          'answerer': remoteEmail,
          'offerSession': mySession,
          'createdAt': FieldValue.serverTimestamp(),
        });

        _signalSubs['${remoteEmail}_sig'] =
            signalRef.snapshots().listen((snap) async {
          final data = snap.data();
          // Only the answer to this offer counts. An answer from an earlier join is ignored.
          if (data == null || data['answerSession'] != remoteSession) return;
          final answerMap = data['answer'] as Map<String, dynamic>?;
          if (answerMap == null ||
              pc.signalingState == RTCSignalingState.RTCSignalingStateStable) {
            return;
          }
          await pc
              .setRemoteDescription(RTCSessionDescription(
                answerMap['sdp'] as String,
                answerMap['type'] as String,
              ))
              .catchError((_) {});
          await drainCandidates();
        });
      } else {
        var answered = false;
        _signalSubs['${remoteEmail}_sig'] =
            signalRef.snapshots().listen((snap) async {
          final data = snap.data();
          if (data == null || answered) return;
          final offerMap = data['offer'] as Map<String, dynamic>?;
          // Only the peer's current join is answered. An offer from an earlier join is ignored.
          if (offerMap == null || data['offerSession'] != remoteSession) return;
          answered = true;

          await pc
              .setRemoteDescription(RTCSessionDescription(
                offerMap['sdp'] as String,
                offerMap['type'] as String,
              ))
              .catchError((_) {});
          await drainCandidates();

          final answer = await pc.createAnswer({
            'offerToReceiveAudio': 1,
            'offerToReceiveVideo': 1,
          });
          await pc.setLocalDescription(answer);

          await signalRef.update({
            'answer': {'type': answer.type, 'sdp': answer.sdp},
            'answerSession': mySession,
          }).catchError((_) {});
        });
      }
    } catch (e, st) {
      logWarning(
          'VoiceRoomService: connectToPeer error for $remoteEmail', e, st);
      _disconnectFromPeer(remoteEmail);
      _scheduleRetry();
    } finally {
      _connecting.remove(remoteEmail);
    }
  }

  /// Tries the peers that failed again shortly, since no seat change may come to trigger it.
  void _scheduleRetry() {
    if (_retryTimer != null) return;
    _retryTimer = Timer(_retryAfter, () {
      _retryTimer = null;
      final snap = _lastSeats;
      if (isConnected && snap != null) _onParticipantsChanged(snap);
    });
  }

  Future<void> _addQuietly(
    CollectionReference<Map<String, dynamic>> col,
    Map<String, dynamic> data,
  ) async {
    try {
      await col.add(data);
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
    }
  }

  void _disconnectFromPeer(String remoteEmail) {
    _peerSessions.remove(remoteEmail);
    _videoSenders.remove(remoteEmail);
    unawaited(_closePeer(remoteEmail));
  }

  /// Closes one connection. The map entries are removed first, so a seat
  /// change that arrives while this runs can start a fresh connection.
  Future<void> _closePeer(String remoteEmail) async {
    final sigSub = _signalSubs.remove('${remoteEmail}_sig');
    final candSub = _signalSubs.remove('${remoteEmail}_cand');
    final pc = _peerConnections.remove(remoteEmail);
    final renderer = _remoteRenderers.remove(remoteEmail);
    await sigSub?.cancel();
    await candSub?.cancel();
    await pc?.close();
    await renderer?.dispose();
  }

  /// Toggles local microphone.
  Future<void> toggleAudio([bool? forceState]) async {
    _isAudioMuted = forceState ?? !_isAudioMuted;
    for (final track
        in _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = !_isAudioMuted;
    }
    _updateSeat({'isAudioMuted': _isAudioMuted});
    _notify();
  }

  /// Toggles local video. Every connection already carries a video section,
  /// so this only switches which track it sends.
  Future<void> toggleVideo([bool? forceState]) async {
    final turnOn = forceState ?? !_isVideoOn;
    if (turnOn) {
      final track = await _startCamera();
      _isVideoOn = track != null;
      if (track != null) {
        for (final sender in _videoSenders.values) {
          await sender.replaceTrack(track);
        }
      }
    } else {
      _isVideoOn = false;
      final stream = _localStream;
      if (stream != null) {
        for (final track
            in List<MediaStreamTrack>.of(stream.getVideoTracks())) {
          await stream.removeTrack(track);
          await track.stop();
        }
      }
      for (final sender in _videoSenders.values) {
        await sender.replaceTrack(null);
      }
    }
    _updateSeat({'isVideoOn': _isVideoOn});
    _notify();
  }

  MediaStreamTrack? _localVideoTrack() {
    final tracks = _localStream?.getVideoTracks() ?? const <MediaStreamTrack>[];
    return tracks.isEmpty ? null : tracks.first;
  }

  /// The camera track for the local stream, starting the camera if needed.
  /// Null when there is no stream or the camera is refused.
  Future<MediaStreamTrack?> _startCamera() async {
    final existing = _localVideoTrack();
    if (existing != null) return existing;
    final stream = _localStream;
    if (stream == null) return null;
    if (!kIsWeb && !(await Permission.camera.request()).isGranted) return null;
    try {
      final camera = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {'facingMode': 'user'},
      });
      final track = camera.getVideoTracks().first;
      stream.addTrack(track);
      _localRenderer.srcObject = stream;
      return track;
    } catch (e, st) {
      logWarning('Error enabling video in voice room', e, st);
      return null;
    }
  }

  /// Toggles device speakerphone on mobile.
  Future<void> toggleSpeaker() async {
    _isSpeakerOn = !_isSpeakerOn;
    if (!kIsWeb) {
      Helper.setSpeakerphoneOn(_isSpeakerOn);
    }
    _notify();
  }

  /// Switches front/back camera on mobile.
  Future<void> switchCamera() async {
    if (kIsWeb) return;
    if (_localStream != null) {
      final videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        await Helper.switchCamera(videoTracks.first);
      }
    }
  }

  /// Writes fields to this member's seat, and refreshes its heartbeat in the same write.
  void _updateSeat(Map<String, dynamic> fields) {
    final tourId = _activeTourId;
    final channelId = _activeChannelId;
    final myEmail = _myEmail;
    if (tourId == null || channelId == null || myEmail == null) return;

    unawaited(_seats(tourId, channelId).doc(myEmail).update({
      ...fields,
      'lastSeenAt': FieldValue.serverTimestamp(),
    }).catchError((_) {}));
  }

  /// Disconnects and leaves the voice channel, releasing all media and network resources.
  Future<void> leaveVoiceRoom() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    _retryTimer?.cancel();
    _retryTimer = null;

    final tourId = _activeTourId;
    final channelId = _activeChannelId;
    final myEmail = _myEmail;

    if (tourId != null && channelId != null && myEmail != null) {
      try {
        await _seats(tourId, channelId).doc(myEmail).delete();
      } catch (error, stackTrace) {
        logSkipped(error, stackTrace);
      }
    }

    await _participantsSub?.cancel();
    _participantsSub = null;
    _lastSeats = null;

    for (final email in _peerConnections.keys.toList()) {
      await _closePeer(email);
    }
    _peerSessions.clear();
    _videoSenders.clear();
    _connecting.clear();
    for (final sub in _signalSubs.values) {
      await sub.cancel();
    }
    _signalSubs.clear();

    _localStream?.getTracks().forEach((track) => track.stop());
    await _localStream?.dispose();
    _localStream = null;

    _localRenderer.srcObject = null;

    _activeTourId = null;
    _activeChannelId = null;
    _myEmail = null;
    _myName = null;
    _myUid = null;
    _myPhotoUrl = null;
    _mySession = null;
    _isAudioMuted = false;
    _isVideoOn = false;
    _isSpeakerOn = false;

    _notify();
  }

  void _notify() {
    if (!_changeNotifier.isClosed) {
      _changeNotifier.add(null);
    }
  }

  void dispose() {
    leaveVoiceRoom();
    if (_localRendererInitialized) {
      _localRenderer.dispose();
      _localRendererInitialized = false;
    }
    _changeNotifier.close();
  }
}
