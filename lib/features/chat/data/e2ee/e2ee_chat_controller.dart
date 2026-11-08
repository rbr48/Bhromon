import 'package:bhromon/app/di/injection.dart';
import 'package:bhromon/core/config/feature_flags.dart';
import 'package:bhromon/core/security/hive_encryption_service.dart';
import 'package:bhromon/core/utils/app_logger.dart';
import 'package:bhromon/features/chat/data/e2ee/e2ee_firestore_keys.dart';
import 'package:bhromon/features/chat/data/e2ee/e2ee_local_store.dart';
import 'package:bhromon/features/chat/data/e2ee/olm_native.dart';
import 'package:bhromon/features/chat/domain/e2ee/e2ee_service.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// Gives the chat screens the encryption service of the signed-in user
/// (E2EE_DESIGN.md, section 9).
///
/// Encryption exists only where the build turns it on (`kE2eeOneToOne`), on a
/// platform with the native library. Everywhere else [serviceFor] returns null, and
/// the chats behave as they did before encryption existed.
class E2eeChatController {
  E2eeChatController._();

  static final E2eeChatController instance = E2eeChatController._();

  E2eeService? _service;
  String? _uid;
  bool _unavailable = false;

  /// Whether this build can use encryption at all: the flag is on, and the
  /// platform is not the web (decision D3).
  static bool get enabledInBuild => kE2eeOneToOne && !kIsWeb;

  /// The service for [uid], made on first use. Null when encryption is off in this
  /// build, or the native library cannot be opened on this device.
  E2eeService? serviceFor(String uid) {
    if (!enabledInBuild || uid.isEmpty) {
      return null;
    }
    if (_uid == uid) {
      return _unavailable ? null : _service;
    }
    _service?.dispose();
    _service = null;
    _uid = uid;
    _unavailable = false;
    try {
      _service = E2eeService(
        userId: uid,
        engine: openOlmEngine(),
        keys: FirestoreE2eeKeyStore(),
        local: HiveE2eeLocalStore(
          getIt<HiveEncryptionService>(),
          userId: uid,
        ),
        pickleKeys: SecureE2eePickleKeyVault(),
        newDeviceId: () => const Uuid().v4(),
        now: DateTime.now,
      );
    } catch (error, stackTrace) {
      _unavailable = true;
      logWarning(
          'End-to-end encryption is not available here', error, stackTrace);
      return null;
    }
    return _service;
  }

  /// Frees the native account of the current user. Call when a different account
  /// signs in, or when encryption is no longer needed.
  void release() {
    _service?.dispose();
    _service = null;
    _uid = null;
    _unavailable = false;
  }
}
