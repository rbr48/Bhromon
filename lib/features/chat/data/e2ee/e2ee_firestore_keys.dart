import 'dart:convert';
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:bhromon/features/chat/domain/e2ee/e2ee_stores.dart';
import 'package:bhromon/features/chat/domain/e2ee/prekey_bundle.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// The public keys in Firestore (`e2ee_keys/{uid}`, `oneTimeKeys/{keyId}`), with
/// the rules in `firestore.rules`. Each one-time key is one document. A key is
/// claimed by a sender with one transaction, so two senders never start a session
/// from the same key. The owner removes a key after it has been used.
class FirestoreE2eeKeyStore implements E2eeKeyStore {
  FirestoreE2eeKeyStore({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  /// How many unclaimed one-time keys one fetch reads. A sender needs one.
  static const int fetchLimit = 40;

  /// Firestore accepts up to 500 writes in a batch. A little below that.
  static const int batchLimit = 400;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _bundles =>
      _db.collection('e2ee_keys');

  CollectionReference<Map<String, dynamic>> _oneTimeKeys(String uid) =>
      _bundles.doc(uid).collection('oneTimeKeys');

  @override
  Future<String?> publishedDeviceId(String uid) async {
    final snapshot = await _bundles.doc(uid).get();
    final deviceId = snapshot.data()?['deviceId'];
    return deviceId is String ? deviceId : null;
  }

  @override
  Future<E2eePrekeyBundle?> fetchBundle(String uid) async {
    final snapshot = await _bundles.doc(uid).get();
    final data = snapshot.data();
    if (data == null) {
      return null;
    }
    final deviceId = data['deviceId'] as String;
    final keys = await _oneTimeKeys(uid)
        .where('claimedBy', isNull: true)
        .limit(fetchLimit)
        .get();
    final fallback = data['fallbackKey'];
    return E2eePrekeyBundle(
      userId: uid,
      deviceId: deviceId,
      curve25519Key: base64Url.decode(data['curve25519Key'] as String),
      ed25519Key: base64Url.decode(data['ed25519Key'] as String),
      identitySignature: base64Url.decode(data['identitySignature'] as String),
      oneTimeKeys: [
        for (final doc in keys.docs)
          if (doc.data()['deviceId'] == deviceId) _signedKeyOf(doc.data()),
      ],
      fallbackKey:
          fallback is Map<String, dynamic> ? _signedKeyOf(fallback) : null,
    );
  }

  @override
  Future<void> publishBundle({
    required String uid,
    required E2eePrekeyBundle bundle,
    required bool withFallback,
  }) async {
    final fallback = bundle.fallbackKey;
    await _bundles.doc(uid).set(
      {
        'deviceId': bundle.deviceId,
        'curve25519Key': base64Url.encode(bundle.curve25519Key),
        'ed25519Key': base64Url.encode(bundle.ed25519Key),
        'identitySignature': base64Url.encode(bundle.identitySignature),
        'updatedAt': FieldValue.serverTimestamp(),
        if (withFallback && fallback != null)
          'fallbackKey': _signedKeyJson(fallback),
      },
      SetOptions(merge: true),
    );
  }

  @override
  Future<void> uploadOneTimeKeys({
    required String uid,
    required String deviceId,
    required List<E2eeSignedKey> keys,
  }) async {
    for (var start = 0; start < keys.length; start += batchLimit) {
      final batch = _db.batch();
      final end = min(start + batchLimit, keys.length);
      for (final key in keys.sublist(start, end)) {
        batch.set(_oneTimeKeys(uid).doc(key.keyId), {
          'deviceId': deviceId,
          'keyId': key.keyId,
          'key': base64Url.encode(key.key),
          'signature': base64Url.encode(key.signature),
          'claimedBy': null,
        });
      }
      await batch.commit();
    }
  }

  @override
  Future<int> unclaimedOneTimeKeyCount({
    required String uid,
    required String deviceId,
  }) async {
    final query = _oneTimeKeys(uid)
        .where('deviceId', isEqualTo: deviceId)
        .where('claimedBy', isNull: true);
    final snapshot = await query.count().get();
    return snapshot.count ?? 0;
  }

  @override
  Future<bool> claimOneTimeKey({
    required String ownerUid,
    required String keyId,
    required String claimerUid,
  }) {
    final ref = _oneTimeKeys(ownerUid).doc(keyId);
    return _db.runTransaction<bool>((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (data == null || data['claimedBy'] != null) {
        return false;
      }
      transaction.update(ref, {
        'claimedBy': claimerUid,
        'claimedAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
  }

  @override
  Future<void> deleteOneTimeKey({
    required String uid,
    required String keyId,
  }) {
    return _oneTimeKeys(uid).doc(keyId).delete();
  }

  @override
  Future<void> deleteOneTimeKeysOfOtherDevices({
    required String uid,
    required String deviceId,
  }) async {
    final stale =
        await _oneTimeKeys(uid).where('deviceId', isNotEqualTo: deviceId).get();
    for (var start = 0; start < stale.docs.length; start += batchLimit) {
      final batch = _db.batch();
      final end = min(start + batchLimit, stale.docs.length);
      for (final doc in stale.docs.sublist(start, end)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  @override
  Future<int> deleteStaleClaimedOneTimeKeys({
    required String uid,
    required DateTime olderThan,
  }) async {
    final staleQuery = await _oneTimeKeys(uid)
        .where('claimedAt', isLessThan: Timestamp.fromDate(olderThan))
        .get();
    if (staleQuery.docs.isEmpty) return 0;
    for (var start = 0; start < staleQuery.docs.length; start += batchLimit) {
      final batch = _db.batch();
      final end = min(start + batchLimit, staleQuery.docs.length);
      for (final doc in staleQuery.docs.sublist(start, end)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
    return staleQuery.docs.length;
  }

  static E2eeSignedKey _signedKeyOf(Map<String, dynamic> data) {
    final key = base64Url.decode(data['key'] as String);
    return E2eeSignedKey(
      keyId: data['keyId'] as String,
      key: Uint8List.fromList(key),
      signature: Uint8List.fromList(
        base64Url.decode(data['signature'] as String),
      ),
    );
  }

  static Map<String, Object> _signedKeyJson(E2eeSignedKey key) => {
        'keyId': key.keyId,
        'key': base64Url.encode(key.key),
        'signature': base64Url.encode(key.signature),
      };
}
