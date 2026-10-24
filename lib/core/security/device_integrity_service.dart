import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DeviceIntegrityService {
  static const MethodChannel _channel =
      MethodChannel('com.bhromon.app/integrity');

  /// Checks whether the device is compromised (jailbroken/rooted).
  /// Returns false if the device is safe or if running on unsupported platforms.
  static Future<bool> isDeviceCompromised() async {
    if (kIsWeb) return false;
    if (!Platform.isAndroid && !Platform.isIOS) return false;

    try {
      if (Platform.isAndroid) {
        return await _checkAndroidRoot();
      } else if (Platform.isIOS) {
        return await _checkIOSJailbreak();
      }
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
      final bool? devMode =
          await _channel.invokeMethod<bool>('isDeveloperMode');
      return devMode ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _checkAndroidRoot() async {
    const rootPaths = [
      '/system/app/Superuser.apk',
      '/sbin/su',
      '/system/bin/su',
      '/system/xbin/su',
      '/data/local/xbin/su',
      '/data/local/bin/su',
      '/system/sd/xbin/su',
      '/system/bin/failsafe/su',
      '/data/local/su',
      '/su/bin/su',
    ];

    for (final path in rootPaths) {
      if (File(path).existsSync()) return true;
    }

    try {
      final bool? isRooted = await _channel.invokeMethod<bool>('isRooted');
      if (isRooted == true) return true;
    } catch (_) {}

    return false;
  }

  static Future<bool> _checkIOSJailbreak() async {
    const jailbreakPaths = [
      '/Applications/Cydia.app',
      '/Library/MobileSubstrate/MobileSubstrate.dylib',
      '/bin/bash',
      '/usr/sbin/sshd',
      '/etc/apt',
      '/private/var/lib/apt/',
    ];

    for (final path in jailbreakPaths) {
      if (File(path).existsSync()) return true;
    }

    return false;
  }
}
