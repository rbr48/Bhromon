import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

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

  const VoiceParticipant({
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.uid = '',
    this.isAudioMuted = false,
    this.isVideoOn = false,
    required this.joinedAt,
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
    };
  }
}

/// Service managing Discord-style drop-in/drop-out WebRTC group voice & video
/// channels using Firestore for mesh signaling and active participant state.
class VoiceRoomService {
  static final VoiceRoomService _instance = VoiceRoomService._internal();
  factory VoiceRoomService() => _instance;
  VoiceRoomService._internal();

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

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  // Active room state
  String? _activeTourId;
  String? _activeChannelId;
  String? _myEmail;
  String? _myName;
  String? _myUid;
  String? _myPhotoUrl;

  bool _isAudioMuted = false;
  bool _isVideoOn = false;
  bool _isSpeakerOn = false;

  MediaStream? _localStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  bool _localRendererInitialized = false;

  // Remote peers: peerEmail -> RTCPeerConnection
  final Map<String, RTCPeerConnection> _peerConnections = {};
  // Remote renderers: peerEmail -> RTCVideoRenderer
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  final Map<String, StreamSubscription<dynamic>> _signalSubs = {};

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _participantsSub;

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
    return _db
        .collection('tours')
        .doc(tourId)
        .collection('channels')
        .doc(channelId)
        .collection('voice_participants')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => VoiceParticipant.fromMap(d.data())).toList());
  }

  /// Connects to a voice channel.
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
    // no state set. Two people joining at the same moment can still overshoot
    // by one; the room is small enough that this is acceptable.
    final seated = await _db
        .collection('tours')
        .doc(tourId)
        .collection('channels')
        .doc(channelId)
        .collection('voice_participants')
        .get();
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
    _isAudioMuted = false;
    _isVideoOn = enableVideo;

    // Permissions on mobile
    if (!kIsWeb) {
      await Permission.microphone.request();
      if (enableVideo) {
        await Permission.camera.request();
      }
    }

    // Initialize local renderer
    if (!_localRendererInitialized) {
      await _localRenderer.initialize();
      _localRendererInitialized = true;
    }

    // Get user media
    await _setupLocalMedia(enableVideo: enableVideo);

    // Register participant document in Firestore
    final p = VoiceParticipant(
      email: _myEmail!,
      displayName: _myName!,
      photoUrl: _myPhotoUrl,
      uid: _myUid ?? '',
      isAudioMuted: _isAudioMuted,
      isVideoOn: _isVideoOn,
      joinedAt: DateTime.now(),
    );

    final participantRef = _db
        .collection('tours')
        .doc(tourId)
        .collection('channels')
        .doc(channelId)
        .collection('voice_participants')
        .doc(_myEmail!);

    await participantRef.set(p.toMap());

    // Watch other participants to establish mesh peer connections
    _participantsSub = _db
        .collection('tours')
        .doc(tourId)
        .collection('channels')
        .doc(channelId)
        .collection('voice_participants')
        .snapshots()
        .listen(_onParticipantsChanged);

    _notify();
  }

  Future<void> _setupLocalMedia({required bool enableVideo}) async {
    final mediaConstraints = <String, dynamic>{
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
        'highpassFilter': true,
      },
      'video': enableVideo
          ? <String, dynamic>{
              'facingMode': 'user',
              'width': {'ideal': 640},
              'height': {'ideal': 480},
              'frameRate': {'ideal': 30},
            }
          : false,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    _localRenderer.srcObject = _localStream;

    // Default to speakerphone for group voice rooms on mobile
    if (!kIsWeb) {
      _isSpeakerOn = true;
      await Helper.setSpeakerphoneOn(true);
    }
  }

  void _onParticipantsChanged(QuerySnapshot<Map<String, dynamic>> snap) {
    if (!isConnected || _myEmail == null) return;

    final currentRemoteEmails = <String>{};
    for (final doc in snap.docs) {
      final email = normalizeEmail(doc.data()['email'] as String? ?? doc.id);
      if (email.isNotEmpty && email != _myEmail) {
        currentRemoteEmails.add(email);
        if (!_peerConnections.containsKey(email)) {
          _connectToPeer(email);
        }
      }
    }

    // Disconnect peers who left
    final removed = _peerConnections.keys
        .where((k) => !currentRemoteEmails.contains(k))
        .toList();
    for (final email in removed) {
      _disconnectFromPeer(email);
    }

    _notify();
  }

  String _signalDocId(String peerA, String peerB) {
    final sorted = [peerA, peerB]..sort();
    return '${sorted[0]}__${sorted[1]}';
  }

  Future<void> _connectToPeer(String remoteEmail) async {
    final tourId = _activeTourId;
    final channelId = _activeChannelId;
    final myEmail = _myEmail;
    if (tourId == null || channelId == null || myEmail == null) return;

    try {
      final pc = await createPeerConnection(_iceConfig);
      _peerConnections[remoteEmail] = pc;

      // Add local stream tracks
      if (_localStream != null) {
        for (final track in _localStream!.getTracks()) {
          await pc.addTrack(track, _localStream!);
        }
      }

      // Initialize remote renderer
      final remoteRenderer = RTCVideoRenderer();
      await remoteRenderer.initialize();
      _remoteRenderers[remoteEmail] = remoteRenderer;

      pc.onTrack = (RTCTrackEvent event) {
        for (final track in event.streams.isNotEmpty
            ? event.streams.first.getTracks()
            : [event.track]) {
          track.enabled = true;
        }
        if (event.streams.isNotEmpty) {
          remoteRenderer.srcObject = event.streams.first;
        }
        _notify();
      };

      final signalDocId = _signalDocId(myEmail, remoteEmail);
      final signalsCol = _db
          .collection('tours')
          .doc(tourId)
          .collection('channels')
          .doc(channelId)
          .collection('voice_signals');
      final signalRef = signalsCol.doc(signalDocId);

      // Deterministic role: alphabetically smaller email is the offerer
      final isOfferer = myEmail.compareTo(remoteEmail) < 0;

      // ICE candidates
      pc.onIceCandidate = (RTCIceCandidate candidate) {
        final candsCol = signalRef
            .collection(isOfferer ? 'offerCandidates' : 'answerCandidates');
        unawaited(() async {
          try {
            await candsCol.add({
              'candidate': candidate.candidate,
              'sdpMid': candidate.sdpMid,
              'sdpMLineIndex': candidate.sdpMLineIndex,
            });
          } catch (_) {}
        }());
      };

      // Watch peer's candidates
      final peerCandsCol = signalRef
          .collection(isOfferer ? 'answerCandidates' : 'offerCandidates');
      final candSub = peerCandsCol.snapshots().listen((snap) {
        for (final change in snap.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final d = change.doc.data();
            if (d != null) {
              final cand = RTCIceCandidate(
                d['candidate'] as String?,
                d['sdpMid'] as String?,
                d['sdpMLineIndex'] as int?,
              );
              pc.addCandidate(cand).catchError((_) {});
            }
          }
        }
      });
      _signalSubs['${remoteEmail}_cand'] = candSub;

      if (isOfferer) {
        // Create offer
        final offer = await pc.createOffer();
        await pc.setLocalDescription(offer);

        await signalRef.set({
          'offer': {'type': offer.type, 'sdp': offer.sdp},
          'offerer': myEmail,
          'answerer': remoteEmail,
          'createdAt': FieldValue.serverTimestamp(),
        });

        // Listen for answer
        final sigSub = signalRef.snapshots().listen((snap) async {
          final data = snap.data();
          if (data == null) return;
          final answerMap = data['answer'] as Map<String, dynamic>?;
          if (answerMap != null &&
              pc.signalingState != RTCSignalingState.RTCSignalingStateStable) {
            final answer = RTCSessionDescription(
              answerMap['sdp'] as String,
              answerMap['type'] as String,
            );
            await pc.setRemoteDescription(answer).catchError((_) {});
          }
        });
        _signalSubs['${remoteEmail}_sig'] = sigSub;
      } else {
        // Answerer: listen for offer, then create answer
        bool hasAnswered = false;
        final sigSub = signalRef.snapshots().listen((snap) async {
          final data = snap.data();
          if (data == null || hasAnswered) return;
          final offerMap = data['offer'] as Map<String, dynamic>?;
          if (offerMap != null) {
            hasAnswered = true;
            final offer = RTCSessionDescription(
              offerMap['sdp'] as String,
              offerMap['type'] as String,
            );
            await pc.setRemoteDescription(offer).catchError((_) {});

            final answer = await pc.createAnswer();
            await pc.setLocalDescription(answer);

            await signalRef.update({
              'answer': {'type': answer.type, 'sdp': answer.sdp},
            }).catchError((_) {});
          }
        });
        _signalSubs['${remoteEmail}_sig'] = sigSub;
      }
    } catch (e) {
      debugPrint('VoiceRoomService: connectToPeer error for $remoteEmail: $e');
    }
  }

  void _disconnectFromPeer(String remoteEmail) {
    _signalSubs['${remoteEmail}_sig']?.cancel();
    _signalSubs.remove('${remoteEmail}_sig');
    _signalSubs['${remoteEmail}_cand']?.cancel();
    _signalSubs.remove('${remoteEmail}_cand');

    final pc = _peerConnections.remove(remoteEmail);
    pc?.close();

    final r = _remoteRenderers.remove(remoteEmail);
    r?.dispose();
  }

  /// Toggles local microphone.
  Future<void> toggleAudio([bool? forceState]) async {
    _isAudioMuted = forceState ?? !_isAudioMuted;
    if (_localStream != null) {
      for (final track in _localStream!.getAudioTracks()) {
        track.enabled = !_isAudioMuted;
      }
    }
    _updateParticipantField('isAudioMuted', _isAudioMuted);
    _notify();
  }

  /// Toggles local video.
  Future<void> toggleVideo([bool? forceState]) async {
    _isVideoOn = forceState ?? !_isVideoOn;

    if (_localStream != null) {
      if (_isVideoOn) {
        if (!kIsWeb) {
          await Permission.camera.request();
        }
        try {
          final videoStream = await navigator.mediaDevices.getUserMedia({
            'audio': false,
            'video': {'facingMode': 'user'}
          });
          final newTrack = videoStream.getVideoTracks().first;
          _localStream!.addTrack(newTrack);

          for (final pc in _peerConnections.values) {
            await pc.addTrack(newTrack, _localStream!);
          }
        } catch (e) {
          debugPrint('Error enabling video in voice room: $e');
        }
      } else {
        for (final track in _localStream!.getVideoTracks()) {
          track.stop();
          _localStream!.removeTrack(track);
        }
      }
    }

    _updateParticipantField('isVideoOn', _isVideoOn);
    _notify();
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

  void _updateParticipantField(String key, dynamic value) {
    final tourId = _activeTourId;
    final channelId = _activeChannelId;
    final myEmail = _myEmail;
    if (tourId == null || channelId == null || myEmail == null) return;

    _db
        .collection('tours')
        .doc(tourId)
        .collection('channels')
        .doc(channelId)
        .collection('voice_participants')
        .doc(myEmail)
        .update({key: value}).catchError((_) {});
  }

  /// Disconnects and leaves the voice channel, releasing all media and network
  /// resources.
  Future<void> leaveVoiceRoom() async {
    final tourId = _activeTourId;
    final channelId = _activeChannelId;
    final myEmail = _myEmail;

    if (tourId != null && channelId != null && myEmail != null) {
      try {
        await _db
            .collection('tours')
            .doc(tourId)
            .collection('channels')
            .doc(channelId)
            .collection('voice_participants')
            .doc(myEmail)
            .delete();
      } catch (_) {}
    }

    await _participantsSub?.cancel();
    _participantsSub = null;

    for (final s in _signalSubs.values) {
      await s.cancel();
    }
    _signalSubs.clear();

    for (final pc in _peerConnections.values) {
      await pc.close();
    }
    _peerConnections.clear();

    for (final r in _remoteRenderers.values) {
      await r.dispose();
    }
    _remoteRenderers.clear();

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
