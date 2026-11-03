import 'dart:async';

import 'package:bhromon/app/di/injection.dart';
import 'package:bhromon/core/security/hive_encryption_service.dart';
import 'package:hive/hive.dart';

import '../../../core/utils/app_logger.dart';

/// The scope of a discussion channel's draft. Each channel in each tour has its
/// own draft, and no draft is shared with a 1:1 chat.
String channelDraftScope(String tourId, String channelId) =>
    'channel:$tourId:$channelId';

/// The scope of a 1:1 chat's draft.
String chatDraftScope(String chatId) => 'chat:$chatId';

/// Unsent composer text, kept in an encrypted box so it survives a restart.
///
/// [save] waits [debounce] before it writes, so typing does not write on every
/// key press. Blank text removes the draft.
class ChatDraftStore {
  ChatDraftStore({
    HiveEncryptionService? encryption,
    this.debounce = const Duration(milliseconds: 400),
  }) : _encryption = encryption;

  static const String boxName = 'chat_drafts';

  final HiveEncryptionService? _encryption;
  final Duration debounce;
  final Map<String, Timer> _timers = {};

  Future<Box<String>> _box() {
    final service = _encryption ?? getIt<HiveEncryptionService>();
    return service.openEncryptedBox<String>(boxName);
  }

  /// The saved draft for [scope], or an empty string.
  Future<String> read(String scope) async {
    try {
      return (await _box()).get(scope) ?? '';
    } catch (e, st) {
      logWarning('Error reading draft for $scope', e, st);
      return '';
    }
  }

  /// Saves [text] for [scope] now. Blank text removes the draft.
  Future<void> write(String scope, String text) async {
    try {
      final box = await _box();
      if (text.trim().isEmpty) {
        await box.delete(scope);
      } else {
        await box.put(scope, text);
      }
    } catch (e, st) {
      logWarning('Error saving draft for $scope', e, st);
    }
  }

  /// Saves the text that [current] returns, after [debounce]. A later call for
  /// the same [scope] replaces the earlier one. Nothing is written while
  /// [shouldSave] returns false, which is how an edit keeps its text out of the
  /// draft.
  void save(
    String scope,
    String Function() current, {
    bool Function()? shouldSave,
  }) {
    _timers[scope]?.cancel();
    _timers[scope] = Timer(debounce, () {
      _timers.remove(scope);
      if (shouldSave != null && !shouldSave()) return;
      unawaited(write(scope, current()));
    });
  }

  /// Cancels pending saves. Call it when the screen goes away.
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }
}
