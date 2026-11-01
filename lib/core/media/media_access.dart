import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'media_signing.dart';

/// [url] signed for the signed-in person, so the media server serves a private file to them.
/// Until the key is known, [url] comes back unchanged and the server refuses it.
String signedMediaUrl(String url) => MediaAccess.instance.sign(url);

/// The signed-in person's media key. It is kept on this device, refreshed from the media server
/// when someone signs in, and cleared when they sign out.
class MediaAccess {
  MediaAccess._();

  static final MediaAccess instance = MediaAccess._();

  static const String _accessKeyUrl =
      'https://bhromon.fun/api/media/access-key';
  static const String _uidName = 'media_access_uid';
  static const String _keyName = 'media_access_key';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  String? _uid;
  String? _key;

  /// [url] signed with the key, or [url] itself while no key is known.
  String sign(String url) {
    final uid = _uid;
    final key = _key;
    if (uid == null || key == null) return url;
    return signMediaUrl(url, uid: uid, key: key);
  }

  /// Loads the saved key, and when someone is signed in, refreshes it. The refresh waits at
  /// most a few seconds, so the first screens can already show private media.
  Future<void> startUp() async {
    await restore().timeout(const Duration(seconds: 3), onTimeout: () {});
    if (_currentUser() == null) return;
    await refresh().timeout(const Duration(seconds: 4), onTimeout: () {});
  }

  /// Loads the key saved on this device. Nothing is sent over the network.
  Future<void> restore() async {
    try {
      final uid = await _storage.read(key: _uidName);
      final key = await _storage.read(key: _keyName);
      if (uid != null && key != null) {
        _uid = uid;
        _key = key;
      }
    } catch (_) {
      // Storage can be unavailable (a private browser window, for one). The key is fetched again.
    }
  }

  /// Fetches the key for the signed-in person and saves it. A key already held is kept when the
  /// server cannot be reached, as long as it belongs to the same person.
  Future<void> refresh() async {
    final user = _currentUser();
    if (user == null) {
      await clear();
      return;
    }
    try {
      final token = await user.getIdToken();
      if (token == null || token.isEmpty) return;
      // Bounded, so a slow server cannot hold up sign-in. A timed-out fetch keeps the saved key.
      final response = await _dio
          .post<Map<String, dynamic>>(
            _accessKeyUrl,
            options: Options(headers: {'Authorization': 'Bearer $token'}),
          )
          .timeout(const Duration(seconds: 6));
      final data = response.data;
      final Object? uidValue = data?['uid'];
      final Object? keyValue = data?['key'];
      if (uidValue is String && keyValue is String && uidValue == user.uid) {
        _uid = uidValue;
        _key = keyValue;
        await _storage.write(key: _uidName, value: uidValue);
        await _storage.write(key: _keyName, value: keyValue);
      }
    } catch (_) {
      // Offline, or the server is busy. A key held for this same person still works.
      if (_uid != user.uid) {
        _uid = null;
        _key = null;
      }
    }
  }

  /// Forgets the key, when the person signs out.
  Future<void> clear() async {
    _uid = null;
    _key = null;
    try {
      await _storage.delete(key: _uidName);
      await _storage.delete(key: _keyName);
    } catch (_) {
      // The key is no longer held in memory, so nothing else needs doing.
    }
  }

  User? _currentUser() {
    try {
      return FirebaseAuth.instance.currentUser;
    } catch (_) {
      // Firebase is not set up in this run, so nobody can be signed in.
      return null;
    }
  }
}
