import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Centralised runtime-permission helper with mandatory rationale dialogs.
///
/// Call the static convenience methods ([requestLocation], [requestCamera],
/// [requestMicrophone], [requestNotifications]) from any widget that needs a
/// permission. Each method shows a rationale before requesting so that users
/// understand *why* the app needs access — required for Play Store compliance.
class PermissionHelper {
  /// Shows a rationale dialog, then requests [permission].
  ///
  /// Returns `true` if the permission ends up granted.
  /// Returns `false` if the user dismissed the rationale or denied the request.
  static Future<bool> requestWithRationale({
    required BuildContext context,
    required Permission permission,
    required String title,
    required String rationale,
    required String permissionName,
  }) async {
    final status = await permission.status;
    if (status.isGranted) return true;

    // If already permanently denied, skip the rationale and jump straight to
    // the settings prompt so the user isn't confused by a stale dialog.
    if (status.isPermanentlyDenied) {
      if (context.mounted) {
        await _showSettingsDialog(context, permissionName);
      }
      return false;
    }

    if (!context.mounted) return false;

    final shouldRequest = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(rationale),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Not Now'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Allow'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldRequest) return false;

    final result = await permission.request();

    if (result.isPermanentlyDenied && context.mounted) {
      await _showSettingsDialog(context, permissionName);
    }

    return result.isGranted;
  }

  /// Shows a dialog directing the user to open app settings.
  static Future<void> _showSettingsDialog(
      BuildContext context, String permissionName) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$permissionName Required'),
        content: Text(
          'Please enable $permissionName in your device settings to use this feature.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  // ── Convenience helpers ────────────────────────────────────────────────────

  /// Requests [Permission.locationWhenInUse] with a Bhromon-specific rationale.
  static Future<bool> requestLocation(BuildContext context) =>
      requestWithRationale(
        context: context,
        permission: Permission.locationWhenInUse,
        title: 'Location Access',
        rationale:
            'Bhromon uses your location to show nearby destinations, pins on '
            'the map, and to record your travel route. Your location is only '
            'used while the app is open.',
        permissionName: 'Location',
      );

  /// Requests [Permission.camera] with a Bhromon-specific rationale.
  static Future<bool> requestCamera(BuildContext context) =>
      requestWithRationale(
        context: context,
        permission: Permission.camera,
        title: 'Camera Access',
        rationale:
            'Bhromon needs camera access to let you take photos and videos '
            'for your trip logs and profile.',
        permissionName: 'Camera',
      );

  /// Requests [Permission.microphone] with a Bhromon-specific rationale.
  static Future<bool> requestMicrophone(BuildContext context) =>
      requestWithRationale(
        context: context,
        permission: Permission.microphone,
        title: 'Microphone Access',
        rationale:
            'Bhromon uses your microphone to record audio notes for trip logs.',
        permissionName: 'Microphone',
      );

  /// Requests [Permission.notification] with a Bhromon-specific rationale.
  static Future<bool> requestNotifications(BuildContext context) =>
      requestWithRationale(
        context: context,
        permission: Permission.notification,
        title: 'Notifications',
        rationale:
            'Enable notifications to receive alerts about new content from '
            'explorers you follow, safety warnings, and community updates.',
        permissionName: 'Notifications',
      );
}
