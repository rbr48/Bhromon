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
