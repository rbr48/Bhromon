import 'dart:typed_data';

import 'package:bhromon/features/chat/domain/e2ee/e2ee_device.dart';
import 'package:bhromon/features/chat/domain/e2ee/e2ee_stores.dart';
import 'package:bhromon/features/chat/domain/e2ee/peer_key_state.dart';
import 'package:bhromon/features/chat/domain/e2ee/prekey_bundle.dart';

// In-memory stores for the service, with the rules the real stores keep: one claim
// per one-time key, removals by the owner only, and no overwrite of a key. Shared by
// the service and the screen tests.

class MemoryKeyStore implements E2eeKeyStore {
  final Map<String, PublishedBundleRecord> bundles = {};
  final Map<String, Map<String, OneTimeKeyRecord>> oneTime = {};

  /// Simulates the server being unreachable for removals.
  bool failDeletes = false;

  @override
  Future<String?> publishedDeviceId(String uid) async => bundles[uid]?.deviceId;

  @override
  Future<E2eePrekeyBundle?> fetchBundle(String uid) async {
    final stored = bundles[uid];
    if (stored == null) {
      return null;
    }
    final docs = [
      for (final doc in (oneTime[uid] ?? const {}).values)
        if (doc.deviceId == stored.deviceId && doc.claimedBy == null) doc.key,
    ].take(40).toList();
    return E2eePrekeyBundle(
      userId: uid,
      deviceId: stored.deviceId,
      curve25519Key: stored.curve25519Key,
      ed25519Key: stored.ed25519Key,
      identitySignature: stored.identitySignature,
      oneTimeKeys: docs,
      fallbackKey: stored.fallbackKey,
    );
  }

  @override
  Future<void> publishBundle({
    required String uid,
    required E2eePrekeyBundle bundle,
    required bool withFallback,
  }) async {
    final previous = bundles[uid];
    bundles[uid] = PublishedBundleRecord(
      deviceId: bundle.deviceId,
      curve25519Key: bundle.curve25519Key,
      ed25519Key: bundle.ed25519Key,
      identitySignature: bundle.identitySignature,
      fallbackKey: withFallback
          ? (bundle.fallbackKey ?? previous?.fallbackKey)
          : previous?.fallbackKey,
    );
  }

  @override
  Future<void> uploadOneTimeKeys({
    required String uid,
    required String deviceId,
    required List<E2eeSignedKey> keys,
  }) async {
    final docs = oneTime.putIfAbsent(uid, () => {});
    for (final key in keys) {
      if (docs.containsKey(key.keyId)) {
        throw Exception('the key ${key.keyId} already exists');
      }
      docs[key.keyId] = OneTimeKeyRecord(deviceId, key);
    }
  }

  @override
  Future<int> unclaimedOneTimeKeyCount({
    required String uid,
    required String deviceId,
  }) async {
    return [
      for (final doc in (oneTime[uid] ?? const {}).values)
        if (doc.deviceId == deviceId && doc.claimedBy == null) doc,
    ].length;
  }

  @override
  Future<bool> claimOneTimeKey({
    required String ownerUid,
    required String keyId,
    required String claimerUid,
  }) async {
    final doc = oneTime[ownerUid]?[keyId];
    if (doc == null || doc.claimedBy != null) {
      return false;
    }
    doc.claimedBy = claimerUid;
    return true;
  }

  @override
  Future<void> deleteOneTimeKey({
    required String uid,
    required String keyId,
  }) async {
    if (failDeletes) {
      throw Exception('unavailable');
    }
    oneTime[uid]?.remove(keyId);
  }

  @override
  Future<void> deleteOneTimeKeysOfOtherDevices({
    required String uid,
    required String deviceId,
  }) async {
    oneTime[uid]?.removeWhere((_, doc) => doc.deviceId != deviceId);
  }

  /// The keys of [uid] still on the server, claimed or not.
  int keyCount(String uid) => oneTime[uid]?.length ?? 0;

  /// The keys of [uid] that someone has claimed and that are still on the server.
  int claimedCount(String uid) => [
        for (final doc in (oneTime[uid] ?? const {}).values)
          if (doc.claimedBy != null) doc
      ].length;

  String? fallbackKeyId(String uid) => bundles[uid]?.fallbackKey?.keyId;

  /// The device id published for [uid], without awaiting, for assertions.
  String? publishedDeviceIdSync(String uid) => bundles[uid]?.deviceId;
}

class PublishedBundleRecord {
  PublishedBundleRecord({
    required this.deviceId,
    required this.curve25519Key,
    required this.ed25519Key,
    required this.identitySignature,
    required this.fallbackKey,
  });

  final String deviceId;
  final Uint8List curve25519Key;
  final Uint8List ed25519Key;
  final Uint8List identitySignature;
  final E2eeSignedKey? fallbackKey;
}

class OneTimeKeyRecord {
  OneTimeKeyRecord(this.deviceId, this.key);

  final String deviceId;
  final E2eeSignedKey key;
  String? claimedBy;
}

class MemoryLocalStore implements E2eeLocalStore {
  String? deviceId;
  Uint8List? account;
  List<SessionSnapshot> sessions = const [];
  final Map<String, PeerKeyState> peers = {};
  final Map<String, String> plaintexts = {};
  DateTime? fallbackAt;
  List<String> pending = const [];

  @override
  Future<String?> readDeviceId() async => deviceId;

  @override
  Future<void> writeDeviceId(String value) async => deviceId = value;

  @override
  Future<Uint8List?> readAccountPickle() async => account;

  @override
  Future<void> writeAccountPickle(Uint8List pickle) async => account = pickle;

  @override
  Future<List<SessionSnapshot>> readSessions() async => sessions;

  @override
  Future<void> writeSessions(List<SessionSnapshot> value) async {
    sessions = value;
  }

  @override
  Future<PeerKeyState> readPeerState(String uid) async {
    return peers[uid] ?? const PeerKeyState();
  }

  @override
  Future<void> writePeerState(String uid, PeerKeyState state) async {
    peers[uid] = state;
  }

  @override
  Future<String?> readPlaintext(String chatId, String messageId) async {
    return plaintexts['$chatId/$messageId'];
  }

  @override
  Future<void> writePlaintext(
      String chatId, String messageId, String text) async {
    plaintexts['$chatId/$messageId'] = text;
  }

  @override
  Future<DateTime?> readFallbackPublishedAt() async => fallbackAt;

  @override
  Future<void> writeFallbackPublishedAt(DateTime at) async => fallbackAt = at;

  @override
  Future<List<String>> readPendingKeyDeletions() async => pending;

  @override
  Future<void> writePendingKeyDeletions(List<String> keyIds) async {
    pending = keyIds;
  }
}

class FixedPickleKeyVault implements E2eePickleKeyVault {
  @override
  Future<Uint8List> readOrCreate() async =>
      Uint8List.fromList(List.filled(32, 9));
}
