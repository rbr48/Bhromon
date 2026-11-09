import 'dart:typed_data';

import 'package:bhromon/features/chat/domain/e2ee/e2ee_device.dart';
import 'package:bhromon/features/chat/domain/e2ee/peer_key_state.dart';
import 'package:bhromon/features/chat/domain/e2ee/prekey_bundle.dart';

/// The public keys on the server: `e2ee_keys/{uid}` and its `oneTimeKeys`
/// subcollection (E2EE_DESIGN.md, section 6). Its rules are in `firestore.rules`.
abstract interface class E2eeKeyStore {
  /// The device id of the published bundle, or null when nothing is published.
  Future<String?> publishedDeviceId(String uid);

  /// The published bundle of [uid], with its unclaimed one-time keys, or null when
  /// nothing is published.
  Future<E2eePrekeyBundle?> fetchBundle(String uid);

  /// Writes the identity of [bundle]. The fallback key is written only when
  /// [withFallback] is set. Fields not written keep their stored values.
  Future<void> publishBundle({
    required String uid,
    required E2eePrekeyBundle bundle,
    required bool withFallback,
  });

  /// Adds one-time keys for [deviceId]. Each key is one document.
  Future<void> uploadOneTimeKeys({
    required String uid,
    required String deviceId,
    required List<E2eeSignedKey> keys,
  });

  /// How many one-time keys of [deviceId] nobody has claimed yet.
  Future<int> unclaimedOneTimeKeyCount({
    required String uid,
    required String deviceId,
  });

  /// Claims one of [ownerUid]'s one-time keys for [claimerUid]. Returns false if
  /// the key is gone or someone else has claimed it, so a key starts at most one
  /// session.
  Future<bool> claimOneTimeKey({
    required String ownerUid,
    required String keyId,
    required String claimerUid,
  });

  /// Removes one of the owner's one-time keys, after it has been used.
  Future<void> deleteOneTimeKey({required String uid, required String keyId});

  /// Removes every one-time key of [uid] that belongs to a device other than
  /// [deviceId], when this device takes over the account's keys.
  Future<void> deleteOneTimeKeysOfOtherDevices({
    required String uid,
    required String deviceId,
  });

  /// Removes claimed one-time keys of [uid] that were claimed before [olderThan]
  /// but never deleted by an incoming message establishment.
  Future<int> deleteStaleClaimedOneTimeKeys({
    required String uid,
    required DateTime olderThan,
  });
}

/// What this device keeps on the device itself. The values are written to an
/// encrypted store. Pickles are encrypted again under the pickle key.
abstract interface class E2eeLocalStore {
  Future<String?> readDeviceId();
  Future<void> writeDeviceId(String deviceId);

  Future<Uint8List?> readAccountPickle();
  Future<void> writeAccountPickle(Uint8List pickle);

  Future<List<SessionSnapshot>> readSessions();
  Future<void> writeSessions(List<SessionSnapshot> sessions);

  /// The pinned keys of [uid]. An unseen contact has an empty state.
  Future<PeerKeyState> readPeerState(String uid);
  Future<void> writePeerState(String uid, PeerKeyState state);

  /// The decrypted text of a message, kept because a message key is used once.
  Future<String?> readPlaintext(String chatId, String messageId);
  Future<void> writePlaintext(String chatId, String messageId, String text);

  /// When the published fallback key was last rotated, or null before the first.
  Future<DateTime?> readFallbackPublishedAt();
  Future<void> writeFallbackPublishedAt(DateTime at);

  /// One-time key ids the server still holds after they were used. Each is removed
  /// on the next run that can reach the server.
  Future<List<String>> readPendingKeyDeletions();
  Future<void> writePendingKeyDeletions(List<String> keyIds);
}

/// The 32-byte key that encrypts the Olm pickles. It is kept in the platform
/// keystore and never leaves the device.
abstract interface class E2eePickleKeyVault {
  Future<Uint8List> readOrCreate();
}
