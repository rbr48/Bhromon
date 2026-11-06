import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/logger.dart';
import '../domain/shared_file.dart';

/// What another app shared, as the Android side collected it.
class ShareBatch {
  const ShareBatch({this.files = const [], this.hasText = false});

  final List<SharedFile> files;

  /// True when the share carried text. Bhromon cannot send text this way yet.
  final bool hasText;

  bool get isEmpty => files.isEmpty && !hasText;
}

/// Receives files shared into Bhromon from other apps. Android is the only platform
/// with a share target so far. Everywhere else [takePending] is always empty.
class ShareIntakeChannel {
  ShareIntakeChannel._();

  static final ShareIntakeChannel instance = ShareIntakeChannel._();

  static const MethodChannel _channel =
      MethodChannel('com.bhromon.app/share_intake');

  final StreamController<void> _changes = StreamController<void>.broadcast();
  bool _attached = false;

  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Fires when a share arrives while the app is open. Call [takePending] after it.
  Stream<void> get changes {
    _attach();
    return _changes.stream;
  }

  void _attach() {
    if (_attached || !supported) return;
    _attached = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharesReady') _changes.add(null);
    });
  }

  /// The shares that arrived since the last call. Empty when there are none.
  Future<ShareBatch> takePending() async {
    if (!supported) return const ShareBatch();
    try {
      final raw = await _channel
          .invokeListMethod<Map<Object?, Object?>>('takePendingShares');
      if (raw == null || raw.isEmpty) return const ShareBatch();
      final files = <SharedFile>[];
      var hasText = false;
      for (final item in raw) {
        if (item['text'] != null) {
          hasText = true;
        } else {
          files.add(SharedFile.fromMap(item));
        }
      }
      return ShareBatch(files: files, hasText: hasText);
    } on PlatformException catch (e, st) {
      logWarning('[ShareIntake] could not read the shared files', e, st);
      return const ShareBatch();
    } on MissingPluginException {
      return const ShareBatch();
    }
  }
}
