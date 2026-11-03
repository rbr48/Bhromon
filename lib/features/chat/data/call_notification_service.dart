import 'dart:async';
import 'package:bhromon/core/media/media_access.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../app/router.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/image_sizing.dart';
import '../../../firebase_options.dart';
import '../domain/call_display.dart';
import 'call_signaling_service.dart';
import 'system_call_bridge.dart';
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

/// Top-level background callback invoked by flutter_callkit_incoming when
/// user interacts with call screen while app is in background or terminated.
@pragma('vm:entry-point')
Future<void> callkitBackgroundCallback(CallEvent event) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
    }
  }
  switch (event) {
    case CallEventActionCallDecline(:final callKitParams):
      final extra = callKitParams.extra ?? {};
      final callId = extra['callId']?.toString() ?? callKitParams.id;
      if (callId.isNotEmpty) {
        await FlutterCallkitIncoming.endCall(callId);
        // Declined here, not just dismissed, so the caller stops ringing now.
        final calleeUid = await _signedInUid();
        if (calleeUid != null) {
          await CallSignalingService.declineRingingCall(
            callId: callId,
            calleeUid: calleeUid,
            callerId: extra['callerId']?.toString() ?? '',
            isVideo: extra['isVideo'] == true,
          );
        }
      }
      break;
    default:
      break;
  }
}

/// The signed-in uid. A background isolate may need a moment for the session to
/// come back from storage, so it waits briefly.
Future<String?> _signedInUid() async {
  final current = FirebaseAuth.instance.currentUser?.uid;
  if (current != null) return current;
  try {
    final user = await FirebaseAuth.instance
        .authStateChanges()
        .first
        .timeout(const Duration(seconds: 3));
    return user?.uid;
  } catch (error, stackTrace) {
    logSkipped(error, stackTrace);
    return null;
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

  AudioPlayer? _inAppRingtonePlayer;

  /// The call the in-app dialog is ringing for, so the native screen can take
  /// over if the app leaves the foreground while it rings.
  ({
    String callId,
    String callerId,
    String callerName,
    String? avatarUrl,
    bool isVideo,
  })? _inAppCall;

  AppLifecycleListener? _lifecycleListener;

  /// Calls this app has closed in the phone's call system itself (accepted in
  /// the app, declined, or dismissed). The phone reports those as "ended", which
  /// must not be read as the user hanging up the call on screen.
  final Set<String> _closedByApp = {};

  /// Closes a call in the phone's call system, and remembers it was this app.
  Future<void> _closeSystemCall(String callId) async {
    if (kIsWeb || callId.isEmpty) return;
    _closedByApp.add(callId);
    await FlutterCallkitIncoming.endCall(callId);
  }

  void _onAppLifecycleChanged(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!kIsWeb) {
        unawaited(checkPendingAcceptedCall());
      }
      return;
    }
    if (kIsWeb) return;
    final pending = _inAppCall;
    if (pending == null || !_isCallDialogShowing) return;
    // The native screen rings from here on, so the in-app ringtone stops to
    // keep the phone from ringing twice.
    _stopInAppRingtone();
    unawaited(showNativeIncomingCall(
      callId: pending.callId,
      callerId: pending.callerId,
      callerName: pending.callerName,
      callerAvatar: pending.avatarUrl,
      isVideo: pending.isVideo,
    ));
  }

  void _startInAppRingtone() {
    try {
      _inAppRingtonePlayer ??= AudioPlayer();
      _inAppRingtonePlayer?.setReleaseMode(ReleaseMode.loop);
      _inAppRingtonePlayer?.play(AssetSource('audio/ringtone_default.mp3'));
    } catch (e, st) {
      logWarning(
          '[CallNotificationService] Failed to play in-app ringtone', e, st);
    }
  }

  void _stopInAppRingtone() {
    try {
      _inAppRingtonePlayer?.stop();
      _inAppRingtonePlayer?.dispose();
      _inAppRingtonePlayer = null;
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
    }
  }

  void init() {
    _lifecycleListener ??=
        AppLifecycleListener(onStateChange: _onAppLifecycleChanged);
    if (Firebase.apps.isEmpty) return;
    _authSub?.cancel();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _startListening(user.uid);
        unawaited(checkPendingAcceptedCall());
      } else {
        _stopListening();
      }
    });

    if (!kIsWeb) {
      _initCallkitEvents();
      unawaited(checkPendingAcceptedCall());
      unawaited(_registerVoipToken());
      unawaited(ensureFullScreenIntentPermission());
      try {
        FlutterCallkitIncoming.onBackgroundMessage(callkitBackgroundCallback);
      } catch (e, st) {
        logWarning('[CallNotificationService] Failed to set background handler',
            e, st);
      }
    }
  }

  /// Checks whether Android 14+ full-screen intent is granted, and requests it if needed.
  static Future<bool> ensureFullScreenIntentPermission() async {
    if (kIsWeb ||
        !defaultTargetPlatform.name.toLowerCase().contains('android')) {
      return true;
    }
    try {
      final canUse = await FlutterCallkitIncoming.canUseFullScreenIntent();
      if (!canUse) {
        await FlutterCallkitIncoming.requestFullIntentPermission();
        return await FlutterCallkitIncoming.canUseFullScreenIntent();
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  /// Registers this iPhone's PushKit token with the call server, which rings
  /// the system call screen through Apple even when the app is closed.
  Future<void> _registerVoipToken() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      final token = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
      if (token is String && token.isNotEmpty) {
        await VpsChatService().registerDeviceToken(token, platform: 'ios-voip');
      }
    } catch (e, st) {
      logWarning('[CallNotificationService] VoIP token not registered', e, st);
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

    await FlutterCallkitIncoming.showCallkitIncoming(buildCallKitParams(
      callId: callId,
      callerId: callerId,
      callerName: callerName,
      callerAvatar: callerAvatar,
      isVideo: isVideo,
    ));
  }

  /// Checks whether a call was accepted while the app was backgrounded or locked,
  /// and opens its call screen if it is not already being displayed.
  Future<void> checkPendingAcceptedCall() async {
    if (kIsWeb) return;
    try {
      final active = await FlutterCallkitIncoming.activeCalls();
      for (final call in active) {
        if (!call.isAccepted) continue;
        final extra = call.extra ?? {};
        final callId = extra['callId']?.toString() ?? call.id;
        if (callId.isEmpty) continue;
        if (ActiveCallControls.callId == callId ||
            CallSignalingService.activeCallId == callId) {
          continue;
        }

        await _acceptCall(
          callId: callId,
          callerId: extra['callerId']?.toString() ?? '',
          callerName: extra['callerName']?.toString() ??
              (call.nameCaller ?? 'Member'),
          avatarUrl: extra['avatarUrl']?.toString() ?? call.avatar,
          isVideo: extra['isVideo'] == true || call.type == 1,
          fromSystem: true,
        );
        break;
      }
    } catch (e, st) {
      logWarning(
          '[CallNotificationService] checkPendingAcceptedCall error', e, st);
    }
  }

  void _initCallkitEvents() {
    try {
      FlutterCallkitIncoming.acceptCallHandle((data) {
        unawaited(checkPendingAcceptedCall());
      });
    } catch (e, st) {
      logWarning(
          '[CallNotificationService] Failed to set acceptCallHandle', e, st);
    }
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
                (callKitParams.nameCaller ?? 'Member'),
            avatarUrl: extra['avatarUrl']?.toString() ?? callKitParams.avatar,
            isVideo: extra['isVideo'] == true || callKitParams.type == 1,
            // Answered on the phone's own screen: the phone keeps the call,
            // so it is treated as a real call until it ends.
            fromSystem: true,
          );
          break;

        case CallEventActionCallDecline(:final callKitParams):
          final extra = callKitParams.extra ?? {};
          final callId = extra['callId']?.toString() ?? callKitParams.id;
          if (callId.isNotEmpty) {
            await _declineCall(
              callId,
              callerId: extra['callerId']?.toString(),
              isVideo: extra['isVideo'] == true,
            );
          }
          break;

        case CallEventActionCallEnded(:final callKitParams):
          final id =
              callKitParams.extra?['callId']?.toString() ?? callKitParams.id;
          if (_closedByApp.remove(id)) {
            // This app closed the call in the phone's call system, so the call
            // on screen is not hung up.
            break;
          }
          if (id.isNotEmpty && ActiveCallControls.callId == id) {
            // Ended by the phone: its hang-up button, a headset or car button,
            // or the phone's own call screen.
            ActiveCallControls.hangUp?.call();
          } else {
            // A ringing call closed. The caller's own timer marks it missed, so
            // nothing is written here.
            _dismissIncomingUI();
          }
          break;

        case CallEventActionCallTimeout():
          _dismissIncomingUI();
          break;

        case CallEventActionDidUpdateDevicePushTokenVoip():
          await _registerVoipToken();
          break;

        case CallEventActionCallToggleMute(:final id, :final isMuted):
          if (ActiveCallControls.callId == id) {
            ActiveCallControls.setMuted?.call(isMuted);
          }
          break;

        case CallEventActionCallToggleHold(:final id, :final isOnHold):
          // An ordinary phone call took over: this one goes silent until the
          // phone gives it back.
          if (ActiveCallControls.callId == id) {
            ActiveCallControls.setMuted?.call(isOnHold);
          }
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
    // The PushKit token belongs to whoever is signed in now.
    unawaited(_registerVoipToken());
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
          logWarning('[CallNotification] Firestore call sub error', e);
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
            logWarning('[CallNotification] Firestore email call sub error', e);
          },
        );
      }
    } catch (e, st) {
      logWarning('[CallNotification] Firestore listeners failed', e, st);
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

    final callerId = data['callerId'] as String? ?? '';
    final sdp =
        (data['offer'] as Map<String, dynamic>?)?['sdp'] as String? ?? '';
    final isVideo = data['isVideo'] is bool
        ? data['isVideo'] as bool
        : sdp.contains('m=video');

    final createdAt = data['createdAt'] as Timestamp?;
    if (createdAt != null &&
        DateTime.now().difference(createdAt.toDate()) > _staleCallAge) {
      // The caller's app went away without ending it. This phone never rang
      // for it, so it is closed as missed rather than declined.
      unawaited(_expireStaleCall(callId, callerId: callerId, isVideo: isVideo));
      return;
    }
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
    // An offer can arrive after the call was answered elsewhere, declined or
    // ended. Only a call that is still ringing rings here.
    if (!await CallSignalingService.isStillRinging(callId)) return;
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
      } catch (e, st) {
        logWarning('Error fetching caller profile', e, st);
      }
    }
    final name = fallbackName?.trim();
    return ((name == null || name.isEmpty) ? 'Member' : name, fallbackAvatar);
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
    // The phone already rings for this call (the background push did), or the
    // call has been answered or ended: a second ring is never shown.
    if (await SystemCallBridge.isActive(callId)) return;
    if (!await CallSignalingService.isStillRinging(callId)) return;

    final waiting = CallSignalingService.isInCall &&
        CallSignalingService.activeCallId != callId;
    if (waiting && kIsWeb && !_canShowInAppDialog()) {
      // A browser has no native screen to ring a second call on.
      await CallSignalingService().declineCall(
        callId,
        callerId: callerId,
        isVideo: isVideo,
      );
      return;
    }

    _activeIncomingCallId = callId;
    // One ring per call. While the app is on screen, the in-app dialog rings and
    // the native screen stays away, so the phone does not ring twice. In the
    // background the native screen rings. The web has no native screen.
    final showsInApp =
        _canShowInAppDialog() && (kIsWeb || _isAppInForeground());
    if (!kIsWeb && !showsInApp) {
      await showNativeIncomingCall(
        callId: callId,
        callerId: callerId,
        callerName: callerName,
        callerAvatar: callerAvatar,
        isVideo: isVideo,
      );
    }

    final context = AppRouter.navigatorKey.currentContext;
    if (showsInApp && context != null && context.mounted) {
      _showInAppCallDialog(
        context: context,
        callId: callId,
        callerId: callerId,
        callerName: callerName,
        avatarUrl: callerAvatar,
        isVideo: isVideo,
        waiting: waiting,
      );
    }
  }

  bool _canShowInAppDialog() {
    final context = AppRouter.navigatorKey.currentContext;
    return context != null && context.mounted && !_isCallDialogShowing;
  }

  /// Whether the app is on screen. A null state means no lifecycle change has
  /// arrived yet, which happens only while the app is starting, so it counts as on screen.
  static bool _isAppInForeground() {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  void _showInAppCallDialog({
    required BuildContext context,
    required String callId,
    required String callerId,
    required String callerName,
    required String? avatarUrl,
    required bool isVideo,
    bool waiting = false,
  }) {
    _isCallDialogShowing = true;
    _inAppCall = (
      callId: callId,
      callerId: callerId,
      callerName: callerName,
      avatarUrl: avatarUrl,
      isVideo: isVideo,
    );
    // A second call during a call does not ring over the conversation.
    if (!waiting) _startInAppRingtone();
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
                  ? CachedNetworkImageProvider(signedMediaUrl(avatarUrl),
                      maxWidth: kMaxDecodeDimension)
                  : null,
              child: (avatarUrl == null || avatarUrl.isEmpty)
                  ? Text(
                      callInitial(callerName),
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
                  ctx.l10n.translate(
                      isVideo ? 'call_incoming_video' : 'call_incoming_voice'),
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
                    await _declineCall(
                      callId,
                      callerId: callerId,
                      isVideo: isVideo,
                    );
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
                      Text(ctx.l10n.translate('call_decline'),
                          style: const TextStyle(
                              color: Colors.redAccent, fontSize: 12)),
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
                      Text(
                          ctx.l10n.translate(
                              waiting ? 'call_end_and_answer' : 'call_accept'),
                          style: const TextStyle(
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
      _inAppCall = null;
      _dialogTimeout?.cancel();
    });
  }

  Future<void> _acceptCall({
    required String callId,
    required String callerId,
    required String callerName,
    required String? avatarUrl,
    required bool isVideo,
    bool fromSystem = false,
  }) async {
    // Native and in-app buttons can both report the same Accept.
    if (!_settled.claim('accept:$callId', DateTime.now())) {
      if (ActiveCallControls.callId != callId &&
          CallSignalingService.activeCallId != callId) {
        _openCall(
          callId: callId,
          callerId: callerId,
          callerName: callerName,
          avatarUrl: avatarUrl,
          isVideo: isVideo,
        );
      }
      return;
    }
    _activeIncomingCallId = null;
    _closeInAppDialog();
    // A call answered on the phone's own screen stays in its call system until
    // it ends. One answered in the app was never there, so only a stray native
    // ring is closed.
    if (!kIsWeb && !fromSystem) {
      await _closeSystemCall(callId);
    }
    await _endCallInProgressFor(callId);
    _openCall(
      callId: callId,
      callerId: callerId,
      callerName: callerName,
      avatarUrl: avatarUrl,
      isVideo: isVideo,
    );
  }

  /// Hangs up the call on screen before another is answered, and waits for its
  /// screen to close.
  Future<void> _endCallInProgressFor(String callId) async {
    final current = CallSignalingService.activeCallId;
    if (current == null || current == callId) return;
    ActiveCallControls.hangUp?.call();
    for (var i = 0; i < 30 && CallSignalingService.isInCall; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }

  /// Opens the call screen. A cold start from the native screen can get here
  /// before the navigator exists, so the Accept waits for it for up to 30 seconds.
  void _openCall({
    required String callId,
    required String callerId,
    required String callerName,
    required String? avatarUrl,
    required bool isVideo,
  }) {
    if (ActiveCallControls.callId == callId ||
        CallSignalingService.activeCallId == callId) {
      _pendingAcceptTimer?.cancel();
      return;
    }

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
      } else if (attempts >= 120) {
        // The app never came up. Decline so the caller is not left ringing.
        timer.cancel();
        unawaited(_declineCall(callId, callerId: callerId, isVideo: isVideo));
      }
    });
  }

  Future<void> _expireStaleCall(
    String callId, {
    required String callerId,
    required bool isVideo,
  }) async {
    if (!_settled.claim('expire:$callId', DateTime.now())) return;
    final calleeUid = FirebaseAuth.instance.currentUser?.uid;
    if (calleeUid == null) return;
    await CallSignalingService.expireStaleCall(
      callId: callId,
      calleeUid: calleeUid,
      callerId: callerId,
      isVideo: isVideo,
    );
  }

  Future<void> _declineCall(
    String callId, {
    String? callerId,
    bool isVideo = false,
  }) async {
    if (!_settled.claim('decline:$callId', DateTime.now())) return;
    if (_activeIncomingCallId == callId) _activeIncomingCallId = null;
    await _closeSystemCall(callId);
    await CallSignalingService().declineCall(
      callId,
      callerId: callerId,
      isVideo: isVideo,
    );
  }

  // ── Dismissing ─────────────────────────────────────────────────────────────

  /// Stops the ring for [callId] on this phone: the native screen and the
  /// in-app dialog. Used when the server says the call stopped ringing.
  void dismissRingingCall(String callId) {
    if (callId.isEmpty) return;
    _dismissIncomingUI(callId: callId);
    unawaited(endNativeIncomingCall(callId));
  }

  /// Closes the call screen and native ring for the call on screen. When
  /// [callId] is given, only that call is closed.
  void _dismissIncomingUI({String? callId}) {
    final active = _activeIncomingCallId;
    if (callId != null && callId != active) return;
    _activeIncomingCallId = null;
    if (!kIsWeb && active != null) {
      unawaited(_closeSystemCall(active));
    }
    _closeInAppDialog();
  }

  void _closeInAppDialog() {
    _stopInAppRingtone();
    _inAppCall = null;
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
    _stopInAppRingtone();
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
    _authSub?.cancel();
    _callsSub?.cancel();
    _emailCallsSub?.cancel();
    _callkitSub?.cancel();
    _vpsCallSub?.cancel();
    _pendingAcceptTimer?.cancel();
    _dialogTimeout?.cancel();
  }
}
