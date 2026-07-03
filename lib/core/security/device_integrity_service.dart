import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_jailbreak_detection/flutter_jailbreak_detection.dart';

class DeviceIntegrityService {
  /// Checks whether the device is compromised (jailbroken/rooted).
  /// Returns false if the device is safe or if running on unsupported platforms.
  static Future<bool> isDeviceCompromised() async {
    if (kIsWeb) return false;
    if (!Platform.isAndroid && !Platform.isIOS) return false;

    try {
      final bool jailbroken = await FlutterJailbreakDetection.jailbroken;
      return jailbroken;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Checks whether developer mode is active (only relevant for Android).
  static Future<bool> isDeveloperModeActive() async {
    if (kIsWeb) return false;
    if (!Platform.isAndroid) return false;

    try {
      final bool developerMode = await FlutterJailbreakDetection.developerMode;
      return developerMode;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
