import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keeps a game table in portrait while it is on screen. The table layouts are
/// built around a tall board, so phones rotate back to portrait on entry and
/// the app's default orientations are restored on exit.
mixin GameZonePortraitLock<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      SystemChrome.setPreferredOrientations(
          const [DeviceOrientation.portraitUp]);
    }
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      SystemChrome.setPreferredOrientations(const []);
    }
    super.dispose();
  }
}

/// Asks the player to confirm an action that throws away the game in progress.
Future<bool> confirmDiscardGame(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Start over',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E2429),
      title: Text(title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold)),
      content: Text(message, style: const TextStyle(color: Colors.white70)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Keep playing',
              style: TextStyle(color: Colors.white70)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber, foregroundColor: Colors.black87),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
