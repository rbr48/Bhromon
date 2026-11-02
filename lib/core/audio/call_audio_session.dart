import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/app_logger.dart';

/// Hands the Android audio session back to the system when a call or voice room
/// ends.
///
/// The WebRTC plugin puts the phone in its call audio mode while a call has
/// audio, and it switches back only when the last peer connection is disposed.
/// A setup that failed before its peer connection existed would keep the mode
/// until the next call, which is why the volume keys then control the call
/// stream instead of media. This asks the native side to end the session
/// directly. It does nothing off Android.
class CallAudioSession {
  CallAudioSession._();

  static const MethodChannel _channel =
      MethodChannel('com.bhromon.app/call_audio');

  /// Keeps the microphone, and the camera when [camera] is set, running while
  /// the app is in the background during a call. Android only. The texts are
  /// shown in the "call in progress" notification, whose [hangUp] button ends
  /// the call through [setHangUpHandler].
  static Future<void> startOngoing({
    required bool camera,
    required String title,
    required String text,
    required String hangUp,
  }) =>
      _invoke('startOngoing', {
        'camera': camera,
        'title': title,
        'text': text,
        'hangUp': hangUp,
      });

  /// Lets the call screen show over the lock screen and turn the display on,
  /// so a call answered on a locked phone opens without unlocking. Android only.
  static Future<void> showOverLockScreen(bool enabled) =>
      _invoke('showOverLockScreen', {'enabled': enabled});

  /// Turns the screen off while the phone is held to the ear. Android only.
  static Future<void> setProximityScreenOff(bool enabled) =>
      _invoke('setProximityScreenOff', {'enabled': enabled});

  /// Lets the call shrink into a picture-in-picture window when the user
  /// leaves the app during a video call. Android only.
  static Future<void> setPipAllowed(bool allowed) =>
      _invoke('setPipAllowed', {'allowed': allowed});

  static void Function()? _onHangUp;
  static void Function(bool inPip)? _onPipChanged;
  static bool _listening = false;

  /// Told when the app goes into or out of picture-in-picture. Null clears it.
  static void setPipListener(void Function(bool inPip)? listener) {
    _onPipChanged = listener;
    _listen();
  }

  /// Sets what the notification's Hang up button does. Null clears it.
  static void setHangUpHandler(void Function()? handler) {
    _onHangUp = handler;
    _listen();
  }

  static void _listen() {
    if (_listening ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'hangUp') _onHangUp?.call();
      if (call.method == 'pipChanged') {
        _onPipChanged?.call(call.arguments == true);
      }
    });
  }

  /// Stops what [startOngoing] started. Safe to call when nothing is running.
  static Future<void> stopOngoing() => _invoke('stopOngoing');

  static Future<void> _invoke(String method,
      [Map<String, Object?>? arguments]) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException catch (e) {
      logDebug('CallAudioSession: no native handler: $e');
    } on PlatformException catch (e) {
      logWarning('CallAudioSession: $method failed: ${e.message}');
    }
  }

  static Future<void> release() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('release');
    } on MissingPluginException catch (e) {
      logDebug('CallAudioSession: no native handler: $e');
    } on PlatformException catch (e) {
      logWarning('CallAudioSession: release failed: ${e.message}');
    }
  }
}
