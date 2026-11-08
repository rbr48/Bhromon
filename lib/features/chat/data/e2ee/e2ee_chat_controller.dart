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

  /// The longest a release waits for encryption work that is already running. Sign-out
  /// must not wait on a network call; the native account is freed once that work ends.
  static const Duration _releaseWait = Duration(seconds: 3);

  /// Releases the native account of the current user from memory. The keys stay on
  /// the device, so the next sign-in continues the same encrypted chats.
  Future<void> release() async {
    final service = _service;
    _service = null;
    _uid = null;
    _unavailable = false;
    if (service == null) return;
    try {
      await service.close().timeout(_releaseWait);
    } catch (error, stackTrace) {
      logWarning('Could not release the encryption account', error, stackTrace);
    }
  }

  /// Test seam: makes [service] the account's service, as [serviceFor] does when the
  /// build turns encryption on, which a test build does not.
  @visibleForTesting
  void useServiceForTest(E2eeService service, String uid) {
    _service = service;
    _uid = uid;
    _unavailable = false;
  }

  /// Deletes the encryption state of a closed account from this device: its service,
  /// keys, sessions, pinned contacts and the text it kept. A failure is logged, and
  /// does not stop the account from closing.
  Future<void> deleteAccountState(String uid) async {
    if (uid.isEmpty) return;
    if (_uid == uid) await release();
    try {
      await HiveE2eeLocalStore(
        getIt<HiveEncryptionService>(),
        userId: uid,
      ).erase();
    } catch (error, stackTrace) {
      logWarning(
        'Could not delete the encryption state of a closed account',
        error,
        stackTrace,
      );
    }
  }
}
