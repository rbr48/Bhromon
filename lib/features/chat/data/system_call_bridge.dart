import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../../../core/utils/app_logger.dart';

/// How long an incoming call rings. Kept here as well as in the signaling
/// service so the native screen and the app agree without an import cycle.
const int kSystemRingSeconds = 45;

/// The parameters the phone's own call screen is shown with. The same call id
/// is used everywhere, so the phone shows one call, not two.
CallKitParams buildCallKitParams({
  required String callId,
  required String callerId,
  required String callerName,
  required String? callerAvatar,
  required bool isVideo,
}) {
  return CallKitParams(
    id: callId,
    nameCaller: callerName,
    appName: 'Bhromon',
    avatar: callerAvatar,
    handle: isVideo ? 'Bhromon Video Call' : 'Bhromon Voice Call',
    type: isVideo ? 1 : 0,
    duration: kSystemRingSeconds * 1000,
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
      ringtonePath: 'ringtone_default',
      backgroundColor: '#075E54',
      actionColor: '#00A884',
      textColor: '#FFFFFF',
      incomingCallNotificationChannelName: 'Bhromon Incoming Calls',
      missedCallNotificationChannelName: 'Bhromon Missed Calls',
      isShowFullLockedScreen: true,
      isImportant: true,
      isFullScreen: false,
    ),
    ios: const IOSParams(
      iconName: 'AppIcon',
      handleType: 'generic',
      supportsVideo: true,
      maximumCallGroups: 1,
      maximumCallsPerCallGroup: 1,
      audioSessionMode: 'videoChat',
      supportsHolding: true,
    ),
  );
}

/// Ties a Bhromon call to the phone's own call system: Telecom on Android and
/// CallKit on iOS. While a call is registered there, the phone treats it as a
/// real call: an ordinary phone call puts it on hold instead of talking over
/// it, and headset and car buttons answer and hang up.
class SystemCallBridge {
  SystemCallBridge._();

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Whether the phone's call system holds [callId], for example because it was
  /// answered on the phone's own ring screen.
  static Future<bool> isActive(String callId) async {
    if (!supported || callId.isEmpty) return false;
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      return calls.any((call) => call.id == callId);
    } catch (e) {
      logInfo('SystemCallBridge: active calls unavailable: $e');
      return false;
    }
  }

  /// Registers an outgoing call. Returns false when the phone refused it, and
  /// the call then runs without the phone's call system.
  static Future<bool> startOutgoing({
    required String callId,
    required String calleeId,
    required String calleeName,
    required String? calleeAvatar,
    required bool isVideo,
  }) async {
    if (!supported) return false;
    try {
      await FlutterCallkitIncoming.startCall(buildCallKitParams(
        callId: callId,
        callerId: calleeId,
        callerName: calleeName,
        callerAvatar: calleeAvatar,
        isVideo: isVideo,
      ));
      return true;
    } catch (e) {
      logWarning('SystemCallBridge: outgoing call not registered: $e');
      return false;
    }
  }

  /// Tells the phone the media is up, so it counts the call as in progress.
  static Future<void> markConnected(String callId) async {
    if (!supported) return;
    try {
      await FlutterCallkitIncoming.setCallConnected(callId);
    } catch (e) {
      logInfo('SystemCallBridge: connected mark skipped: $e');
    }
  }

  /// Ends the call in the phone's call system.
  static Future<void> end(String callId) async {
    if (!supported || callId.isEmpty) return;
    try {
      await FlutterCallkitIncoming.endCall(callId);
    } catch (e) {
      logInfo('SystemCallBridge: end skipped: $e');
    }
  }
}

/// The call on screen, as the phone's call system and the notification can
/// reach it. The call screen sets these while it is open.
class ActiveCallControls {
  ActiveCallControls._();

  static String? callId;

  /// Hangs up the call on screen.
  static VoidCallback? hangUp;

  /// Mutes or unmutes the microphone (the phone's mute button, or hold).
  static void Function(bool muted)? setMuted;

  static void attach({
    required String id,
    required VoidCallback onHangUp,
    required void Function(bool muted) onMute,
  }) {
    callId = id;
    hangUp = onHangUp;
    setMuted = onMute;
  }

  static void detach(String id) {
    if (callId != id) return;
    callId = null;
    hangUp = null;
    setMuted = null;
  }
}
