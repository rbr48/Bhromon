import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../app/router.dart';
import '../../../core/utils/image_sizing.dart';

/// Top-level WebRTC incoming call listener and VoIP manager.
///
/// Listens to incoming calls from anywhere in the application,
/// rings native CallKit/ConnectionService on Android/iOS,
/// and displays a WhatsApp-styled incoming call modal.
class CallNotificationService {
  static final CallNotificationService _instance =
      CallNotificationService._internal();
  factory CallNotificationService() => _instance;
  CallNotificationService._internal();

  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _callsSub;
  StreamSubscription<CallEvent?>? _callkitSub;

  String? _currentListeningUid;
  String? _activeIncomingCallId;
  bool _isCallDialogShowing = false;

  void init() {
    _authSub?.cancel();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _startListening(user.uid);
      } else {
        _stopListening();
      }
    });

    if (!kIsWeb) {
      _initCallkitEvents();
    }
  }

  void _initCallkitEvents() {
    _callkitSub?.cancel();
    _callkitSub = FlutterCallkitIncoming.onEvent.listen((event) async {
      if (event == null) return;
      switch (event) {
        case CallEventActionCallAccept(:final callKitParams):
          final extra = callKitParams.extra ?? {};
          final callId = extra['callId']?.toString() ?? callKitParams.id;
          final callerId = extra['callerId']?.toString() ?? '';
          final callerName = extra['callerName']?.toString() ??
              (callKitParams.nameCaller ?? 'Traveler');
          final avatarUrl =
              extra['avatarUrl']?.toString() ?? callKitParams.avatar;
          final isVideo = extra['isVideo'] == true || callKitParams.type == 1;

          if (callId.isNotEmpty) {
            await _acceptCall(
              callId: callId,
              callerId: callerId,
              callerName: callerName,
              avatarUrl: avatarUrl,
              isVideo: isVideo,
            );
          }
          break;

        case CallEventActionCallDecline(:final callKitParams):
          final extra = callKitParams.extra ?? {};
          final callId = extra['callId']?.toString() ?? callKitParams.id;
          if (callId.isNotEmpty) {
            await _declineCall(callId);
          }
          break;

        case CallEventActionCallEnded():
        case CallEventActionCallTimeout():
          _dismissIncomingUI();
          break;

        default:
          break;
      }
    });
  }

  void _startListening(String uid) {
    if (_currentListeningUid == uid) return;
    _currentListeningUid = uid;
    _callsSub?.cancel();

    _callsSub = FirebaseFirestore.instance
        .collection('calls')
        .where('calleeId', isEqualTo: uid)
        .where('status', isEqualTo: 'calling')
        .snapshots()
        .listen((snap) async {
      if (snap.docs.isEmpty) {
        _dismissIncomingUI();
        return;
      }

      final callDoc = snap.docs.first;
      final callId = callDoc.id;
      if (_activeIncomingCallId == callId) return;

      final data = callDoc.data();
      final createdAt = data['createdAt'] as Timestamp?;
      if (createdAt != null) {
        final age = DateTime.now().difference(createdAt.toDate());
        if (age.inSeconds > 60) {
          // Stale call; ignore or auto-decline
          _declineCall(callId);
          return;
        }
      }

      _activeIncomingCallId = callId;
      final callerId = data['callerId'] as String? ?? '';
      final offerMap = data['offer'] as Map<String, dynamic>?;
      final sdp = offerMap?['sdp'] as String? ?? '';
      final bool isVideo = sdp.contains('m=video');

      // Fetch caller details
      String callerName = 'Traveler';
      String? callerAvatar;
      try {
        final profileSnap = await FirebaseFirestore.instance
            .collection('explorer_profiles')
            .doc(callerId)
            .get();
        if (profileSnap.exists) {
          final pData = profileSnap.data();
          callerName = (pData?['displayName'] as String?) ?? 'Traveler';
          callerAvatar = pData?['avatarUrl'] as String?;
        }
      } catch (e) {
        debugPrint('Error fetching caller profile: $e');
      }

      // 1. Show CallKit if mobile native
      if (!kIsWeb) {
        final callKitParams = CallKitParams(
          id: callId,
          nameCaller: callerName,
          appName: 'Bhromon',
          avatar: callerAvatar,
          handle: isVideo ? 'Bhromon Video Call' : 'Bhromon Voice Call',
          type: isVideo ? 1 : 0,
          duration: 30000,
          extra: <String, dynamic>{
            'callId': callId,
            'callerId': callerId,
            'callerName': callerName,
            'avatarUrl': callerAvatar,
            'isVideo': isVideo,
          },
          android: const AndroidParams(
            isCustomNotification: true,
            isShowLogo: false,
            ringtonePath: 'system_ringtone_default',
            backgroundColor: '#075E54',
            actionColor: '#00A884',
            textColor: '#FFFFFF',
          ),
          ios: const IOSParams(
            iconName: 'AppIcon',
            handleType: 'generic',
            supportsVideo: true,
            maximumCallGroups: 1,
            maximumCallsPerCallGroup: 1,
            audioSessionMode: 'videoChat',
          ),
        );
        await FlutterCallkitIncoming.showCallkitIncoming(callKitParams);
      }

      // 2. Show in-app overlay dialog if context is available
      final context = AppRouter.navigatorKey.currentContext;
      if (context != null && context.mounted && !_isCallDialogShowing) {
        _showInAppCallDialog(
          context: context,
          callId: callId,
          callerId: callerId,
          callerName: callerName,
          avatarUrl: callerAvatar,
          isVideo: isVideo,
        );
      }
    });
  }

  void _showInAppCallDialog({
    required BuildContext context,
    required String callId,
    required String callerId,
    required String callerName,
    required String? avatarUrl,
    required bool isVideo,
  }) {
    _isCallDialogShowing = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F2C34),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: const Color(0xFF00A884),
              backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                  ? CachedNetworkImageProvider(avatarUrl,
                      maxWidth: kMaxDecodeDimension)
                  : null,
              child: (avatarUrl == null || avatarUrl.isEmpty)
                  ? Text(
                      callerName.isNotEmpty
                          ? callerName.substring(0, 1).toUpperCase()
                          : 'T',
                      style: const TextStyle(
                          fontSize: 32,
                          color: Colors.white,
                          fontWeight: FontWeight.bold),
                    )
                  : null,
            ),
            const SizedBox(height: 16),
            Text(
              callerName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isVideo ? Icons.videocam : Icons.call,
                  color: const Color(0xFF00A884),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  isVideo ? 'Incoming Video Call...' : 'Incoming Voice Call...',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Decline button
                GestureDetector(
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    _isCallDialogShowing = false;
                    await _declineCall(callId);
                  },
                  child: Column(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.call_end,
                            color: Colors.white, size: 26),
                      ),
                      const SizedBox(height: 6),
                      const Text('Decline',
                          style:
                              TextStyle(color: Colors.redAccent, fontSize: 12)),
                    ],
                  ),
                ),
                // Accept button
                GestureDetector(
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    _isCallDialogShowing = false;
                    await _acceptCall(
                      callId: callId,
                      callerId: callerId,
                      callerName: callerName,
                      avatarUrl: avatarUrl,
                      isVideo: isVideo,
                    );
                  },
                  child: Column(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: const BoxDecoration(
                          color: Color(0xFF00A884),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.call,
                            color: Colors.white, size: 26),
                      ),
                      const SizedBox(height: 6),
                      const Text('Accept',
                          style: TextStyle(
                              color: Color(0xFF00A884), fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ).then((_) {
      _isCallDialogShowing = false;
    });
  }

  Future<void> _acceptCall({
    required String callId,
    required String callerId,
    required String callerName,
    required String? avatarUrl,
    required bool isVideo,
  }) async {
    _activeIncomingCallId = null;
    if (!kIsWeb) {
      await FlutterCallkitIncoming.endAllCalls();
    }

    try {
      await FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .update({'status': 'answered'});
    } catch (e) {
      debugPrint('Error updating call status to answered: $e');
    }

    final context = AppRouter.navigatorKey.currentContext;
    if (context != null && context.mounted) {
      final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      GoRouter.of(context).push(
        '/call/$callId',
        extra: {
          'localUid': currentUid,
          'remoteUid': callerId,
          'remoteUserName': callerName,
          'remoteAvatarUrl': avatarUrl,
          'isCaller': false,
          'isVideoCall': isVideo,
        },
      );
    }
  }

  Future<void> _declineCall(String callId) async {
    _activeIncomingCallId = null;
    if (!kIsWeb) {
      await FlutterCallkitIncoming.endAllCalls();
    }

    try {
      await FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .update({'status': 'declined'});
    } catch (e) {
      debugPrint('Error declining call: $e');
    }
  }

  void _dismissIncomingUI() {
    _activeIncomingCallId = null;
    if (!kIsWeb) {
      FlutterCallkitIncoming.endAllCalls();
    }
    if (_isCallDialogShowing) {
      final context = AppRouter.navigatorKey.currentContext;
      if (context != null && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      _isCallDialogShowing = false;
    }
  }

  void _stopListening() {
    _currentListeningUid = null;
    _callsSub?.cancel();
    _dismissIncomingUI();
  }

  void dispose() {
    _authSub?.cancel();
    _callsSub?.cancel();
    _callkitSub?.cancel();
  }
}
