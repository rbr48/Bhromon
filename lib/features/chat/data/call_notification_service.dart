import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
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
import 'call_signaling_service.dart';
import 'vps_chat_service.dart';

/// A call older than this when it is seen is not rung.
const Duration _staleCallAge = Duration(seconds: 60);

/// Remembers which calls have been handled, so the push, the relay and the
/// Firestore listener cannot ring or answer the same call twice.
class IncomingCallRegistry {
  IncomingCallRegistry({this.window = const Duration(minutes: 2)});

  final Duration window;
  final Map<String, DateTime> _seenAt = {};

  /// True the first time [callId] is seen within [window]. Later sightings return false.
  bool claim(String callId, DateTime now) {
    _seenAt.removeWhere((_, at) => now.difference(at) > window);
    if (_seenAt.containsKey(callId)) return false;
    _seenAt[callId] = now;
    return true;
  }
}

/// Top-level WebRTC incoming call listener and VoIP manager.
///
/// Calls reach the phone three ways: the chat server's relay (while the app is
/// open), the Firestore call document (which the Cloud Function pushes), and
/// the data-only push itself, which shows the native call screen even when the
/// app is closed. Every path goes through [_presentIncomingCall], so one call
/// shows one screen.
class CallNotificationService {
  static final CallNotificationService _instance =
      CallNotificationService._internal();
  factory CallNotificationService() => _instance;
  CallNotificationService._internal();

  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _callsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _emailCallsSub;
  StreamSubscription<CallEvent?>? _callkitSub;
  StreamSubscription<Map<String, dynamic>>? _vpsCallSub;

  String? _currentListeningUid;
  String? _activeIncomingCallId;
  bool _isCallDialogShowing = false;
  Timer? _dialogTimeout;

  final IncomingCallRegistry _shown = IncomingCallRegistry();
  final IncomingCallRegistry _settled = IncomingCallRegistry();

  /// The calls each Firestore query reported as ringing last time. A call that
  /// drops out of the list has been answered, declined or ended.
  final Map<String, Set<String>> _ringingBySource = {};

  /// An Accept that arrived before the app's navigator was ready (a cold start).
  Timer? _pendingAcceptTimer;

  void init() {
    if (Firebase.apps.isEmpty) return;
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

  // ── Native call screen ─────────────────────────────────────────────────────

  static Future<void> endNativeIncomingCall(String callId) async {
    if (kIsWeb || callId.isEmpty) return;
    await FlutterCallkitIncoming.endCall(callId);
  }

  /// Shows the native incoming-call screen for a call. Also runs in the
  /// background isolate when a call push arrives, so it touches no app state.
  /// A call that is already on screen is not shown again.
  static Future<void> showNativeIncomingCall({
    required String callId,
    required String callerId,
    required String callerName,
    required String? callerAvatar,
    required bool isVideo,
  }) async {
    if (kIsWeb || callId.isEmpty) return;
    final active = await FlutterCallkitIncoming.activeCalls();
    if (active.any((call) => call.id == callId)) return;

    await FlutterCallkitIncoming.showCallkitIncoming(
      CallKitParams(
        id: callId,
        nameCaller: callerName,
        appName: 'Bhromon',
        avatar: callerAvatar,
        handle: isVideo ? 'Bhromon Video Call' : 'Bhromon Voice Call',
        type: isVideo ? 1 : 0,
        duration: kCallRingSeconds * 1000,
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
      ),
    );
  }

  void _initCallkitEvents() {
    _callkitSub?.cancel();
    _callkitSub = FlutterCallkitIncoming.onEvent.listen((event) async {
      if (event == null) return;
      switch (event) {
        case CallEventActionCallAccept(:final callKitParams):
          final extra = callKitParams.extra ?? {};
          final callId = extra['callId']?.toString() ?? callKitParams.id;
          if (callId.isEmpty) break;
          await _acceptCall(
            callId: callId,
            callerId: extra['callerId']?.toString() ?? '',
            callerName: extra['callerName']?.toString() ??
                (callKitParams.nameCaller ?? 'Traveler'),
            avatarUrl: extra['avatarUrl']?.toString() ?? callKitParams.avatar,
            isVideo: extra['isVideo'] == true || callKitParams.type == 1,
          );
          break;

        case CallEventActionCallDecline(:final callKitParams):
          final extra = callKitParams.extra ?? {};
          final callId = extra['callId']?.toString() ?? callKitParams.id;
          if (callId.isNotEmpty) {
            await _declineCall(callId, callerId: extra['callerId']?.toString());
          }
          break;

        case CallEventActionCallEnded():
        case CallEventActionCallTimeout():
          // The native screen timed out or closed. The caller's own timer marks
          // the call missed, so nothing is written here.
          _dismissIncomingUI();
          break;

        default:
          break;
      }
    });
  }

  // ── Listening ──────────────────────────────────────────────────────────────

  void _startListening(String uid) {
    if (_currentListeningUid == uid) return;
    _currentListeningUid = uid;
    _callsSub?.cancel();
    _emailCallsSub?.cancel();
    _vpsCallSub?.cancel();
    _ringingBySource.clear();

    // 1. The chat server relay, while the app is open.
    _vpsCallSub = VpsChatService().callSignalStream.listen((event) {
      final signalType = event['signalType'] as String?;
      final callId = event['callId']?.toString() ?? '';
      if (signalType == 'offer') {
        unawaited(_presentFromRelay(event, callId));
      } else if (signalType == 'end' || signalType == 'declined') {
        _dismissIncomingUI(callId: callId);
      }
    });

    // 2. The call document, which the Cloud Function also pushes for.
    try {
      _callsSub = FirebaseFirestore.instance
          .collection('calls')
          .where('calleeId', isEqualTo: uid)
          .where('status', isEqualTo: 'calling')
          .snapshots()
          .listen(
        (snap) => _handleIncomingCallSnap(snap, 'uid'),
        onError: (Object e) {
          debugPrint('[CallNotification] Firestore call sub error: $e');
        },
      );

      final email =
          FirebaseAuth.instance.currentUser?.email?.toLowerCase().trim();
      if (email != null && email.isNotEmpty && email != uid) {
        _emailCallsSub = FirebaseFirestore.instance
            .collection('calls')
            .where('calleeId', isEqualTo: email)
            .where('status', isEqualTo: 'calling')
            .snapshots()
            .listen(
          (snap) => _handleIncomingCallSnap(snap, 'email'),
          onError: (Object e) {
            debugPrint('[CallNotification] Firestore email call sub error: $e');
          },
        );
      }
    } catch (e) {
      debugPrint('[CallNotification] Firestore listeners failed: $e');
    }
  }

  Future<void> _handleIncomingCallSnap(
      QuerySnapshot<Map<String, dynamic>> snap, String source) async {
    final ringing = snap.docs.map((doc) => doc.id).toSet();
    final previous = _ringingBySource[source] ?? const <String>{};
    _ringingBySource[source] = ringing;

    // A call that stopped ringing was answered, declined or ended. Only a call
    // this query had reported as ringing counts, so a first empty snapshot
    // cannot dismiss a call that is already on screen.
    final stopped = previous.difference(ringing);
    final active = _activeIncomingCallId;
    if (active != null && stopped.contains(active)) {
      _dismissIncomingUI();
    }

    if (snap.docs.isEmpty) return;
    final callDoc = snap.docs.first;
    final callId = callDoc.id;
    final data = callDoc.data();

    final createdAt = data['createdAt'] as Timestamp?;
    if (createdAt != null &&
        DateTime.now().difference(createdAt.toDate()) > _staleCallAge) {
      unawaited(_declineCall(callId, callerId: data['callerId'] as String?));
      return;
    }

    final callerId = data['callerId'] as String? ?? '';
    final sdp =
        (data['offer'] as Map<String, dynamic>?)?['sdp'] as String? ?? '';
    final isVideo = data['isVideo'] is bool
        ? data['isVideo'] as bool
        : sdp.contains('m=video');
    final (callerName, callerAvatar) = await _resolveCaller(
      callerId,
      fallbackName: data['callerName'] as String?,
      fallbackAvatar: data['callerAvatar'] as String?,
    );

    await _presentIncomingCall(
      callId: callId,
      callerId: callerId,
      callerName: callerName,
      callerAvatar: callerAvatar,
      isVideo: isVideo,
    );
  }

  Future<void> _presentFromRelay(
      Map<String, dynamic> event, String callId) async {
    if (callId.isEmpty) return;
    final callerId = event['callerId']?.toString() ?? '';
    final (callerName, callerAvatar) = await _resolveCaller(
      callerId,
      fallbackName: event['callerName']?.toString(),
      fallbackAvatar: event['avatarUrl']?.toString(),
    );
    await _presentIncomingCall(
      callId: callId,
      callerId: callerId,
      callerName: callerName,
      callerAvatar: callerAvatar,
      isVideo: event['isVideo'] == true,
    );
  }

  /// The caller's name and photo come from their profile. The name sent with
  /// the call is used only when the profile cannot be read.
  Future<(String, String?)> _resolveCaller(
    String callerId, {
    String? fallbackName,
    String? fallbackAvatar,
  }) async {
    if (callerId.isNotEmpty) {
      try {
        final profile = await FirebaseFirestore.instance
            .collection('explorer_profiles')
            .doc(callerId)
            .get()
            .timeout(const Duration(seconds: 4));
        final data = profile.data();
        final name = (data?['displayName'] as String?)?.trim();
        if (name != null && name.isNotEmpty) {
          return (name, (data?['avatarUrl'] as String?) ?? fallbackAvatar);
        }
      } catch (e) {
        debugPrint('Error fetching caller profile: $e');
      }
    }
    final name = fallbackName?.trim();
    return ((name == null || name.isEmpty) ? 'Traveler' : name, fallbackAvatar);
  }

  // ── Presenting and answering ───────────────────────────────────────────────

  Future<void> _presentIncomingCall({
    required String callId,
    required String callerId,
    required String callerName,
    required String? callerAvatar,
    required bool isVideo,
  }) async {
    if (!_shown.claim(callId, DateTime.now())) return;

    if (CallSignalingService.isInCall &&
        CallSignalingService.activeCallId != callId) {
      // Already on a call: refuse this one so the caller is not left ringing.
      await CallSignalingService().declineCall(callId, callerId: callerId);
      return;
    }

    _activeIncomingCallId = callId;
    if (!kIsWeb) {
      await showNativeIncomingCall(
        callId: callId,
        callerId: callerId,
        callerName: callerName,
        callerAvatar: callerAvatar,
        isVideo: isVideo,
      );
    }

    final showsInApp = _canShowInAppDialog();
    final context = AppRouter.navigatorKey.currentContext;
    if (showsInApp &&
        context != null &&
        context.mounted &&
        !_isCallDialogShowing) {
      _showInAppCallDialog(
        context: context,
        callId: callId,
        callerId: callerId,
        callerName: callerName,
        avatarUrl: callerAvatar,
        isVideo: isVideo,
      );
    }
  }

  bool _canShowInAppDialog() {
    final context = AppRouter.navigatorKey.currentContext;
    return context != null && context.mounted && !_isCallDialogShowing;
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
    _dialogTimeout?.cancel();
    _dialogTimeout = Timer(const Duration(seconds: kCallRingSeconds), () {
      if (_activeIncomingCallId == callId) _dismissIncomingUI();
    });
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
                    await _declineCall(callId, callerId: callerId);
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
      _dialogTimeout?.cancel();
    });
  }

  Future<void> _acceptCall({
    required String callId,
    required String callerId,
    required String callerName,
    required String? avatarUrl,
    required bool isVideo,
  }) async {
    // Native and in-app buttons can both report the same Accept.
    if (!_settled.claim('accept:$callId', DateTime.now())) return;
    _activeIncomingCallId = null;
    _closeInAppDialog();
    if (!kIsWeb) {
      await FlutterCallkitIncoming.endCall(callId);
    }
    _openCall(
      callId: callId,
      callerId: callerId,
      callerName: callerName,
      avatarUrl: avatarUrl,
      isVideo: isVideo,
    );
  }

  /// Opens the call screen. A cold start from the native screen can get here
  /// before the navigator exists, so the Accept waits for it for up to 15 seconds.
  void _openCall({
    required String callId,
    required String callerId,
    required String callerName,
    required String? avatarUrl,
    required bool isVideo,
  }) {
    final context = AppRouter.navigatorKey.currentContext;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (context != null && context.mounted && uid.isNotEmpty) {
      _pendingAcceptTimer?.cancel();
      GoRouter.of(context).push(
        '/call/$callId',
        extra: {
          'localUid': uid,
          'remoteUid': callerId,
          'remoteUserName': callerName,
          'remoteAvatarUrl': avatarUrl,
          'isCaller': false,
          'isVideoCall': isVideo,
        },
      );
      return;
    }

    _pendingAcceptTimer?.cancel();
    var attempts = 0;
    _pendingAcceptTimer =
        Timer.periodic(const Duration(milliseconds: 250), (timer) {
      attempts++;
      final ready = AppRouter.navigatorKey.currentContext != null &&
          FirebaseAuth.instance.currentUser != null;
      if (ready) {
        timer.cancel();
        _openCall(
          callId: callId,
          callerId: callerId,
          callerName: callerName,
          avatarUrl: avatarUrl,
          isVideo: isVideo,
        );
      } else if (attempts >= 60) {
        // The app never came up. Decline so the caller is not left ringing.
        timer.cancel();
        unawaited(_declineCall(callId, callerId: callerId));
      }
    });
  }

  Future<void> _declineCall(String callId, {String? callerId}) async {
    if (!_settled.claim('decline:$callId', DateTime.now())) return;
    if (_activeIncomingCallId == callId) _activeIncomingCallId = null;
    if (!kIsWeb) {
      await FlutterCallkitIncoming.endCall(callId);
    }
    await CallSignalingService().declineCall(callId, callerId: callerId);
  }

  // ── Dismissing ─────────────────────────────────────────────────────────────

  /// Closes the call screen and native ring for the call on screen. When
  /// [callId] is given, only that call is closed.
  void _dismissIncomingUI({String? callId}) {
    final active = _activeIncomingCallId;
    if (callId != null && callId != active) return;
    _activeIncomingCallId = null;
    if (!kIsWeb && active != null) {
      unawaited(FlutterCallkitIncoming.endCall(active));
    }
    _closeInAppDialog();
  }

  void _closeInAppDialog() {
    _dialogTimeout?.cancel();
    _dialogTimeout = null;
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
    _callsSub = null;
    _emailCallsSub?.cancel();
    _emailCallsSub = null;
    _vpsCallSub?.cancel();
    _vpsCallSub = null;
    _ringingBySource.clear();
    _pendingAcceptTimer?.cancel();
    _dismissIncomingUI();
  }

  void dispose() {
    _authSub?.cancel();
    _callsSub?.cancel();
    _emailCallsSub?.cancel();
    _callkitSub?.cancel();
    _vpsCallSub?.cancel();
    _pendingAcceptTimer?.cancel();
    _dialogTimeout?.cancel();
  }
}
