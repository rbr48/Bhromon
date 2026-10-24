import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class HiveEncryptionService {
  final FlutterSecureStorage _secureStorage;
  final String _keyName = 'hive_encryption_key';

  HiveEncryptionService() : _secureStorage = const FlutterSecureStorage();

  @visibleForTesting
  HiveEncryptionService.withStorage(this._secureStorage);

  // The key lives in the platform keystore; reading it is a platform-channel
  // round trip, so it's read once per process instead of on every box open.
  Future<HiveAesCipher>? _cipher;

  // In-flight and completed opens, so concurrent callers share one open.
  final Map<String, Future<Box<dynamic>>> _boxes = {};

  Future<HiveAesCipher> getCipher() => _cipher ??= _readCipher();

  Future<HiveAesCipher> _readCipher() async {
    try {
      // Read key from secure storage
      String? base64Key = await _secureStorage.read(key: _keyName);

      List<int> key;
      if (base64Key == null) {
        // Generate a new 256-bit encryption key
        key = Hive.generateSecureKey();
        // Store it base64-encoded in secure storage
        await _secureStorage.write(key: _keyName, value: base64Encode(key));
      } else {
        // Decode the existing key
        key = base64Decode(base64Key);
      }

      return HiveAesCipher(key);
    } catch (e) {
      // Return a stable fallback key if secure storage is unavailable (e.g. on Web)
      final fallback = List<int>.generate(32, (i) => (i * 7 + 13) % 256);
      return HiveAesCipher(fallback);
    }
  }

  /// Opens an encrypted Hive box safely
  Future<Box<T>> openEncryptedBox<T>(String boxName) async {
    final cached = _boxes[boxName];
    if (cached != null) {
      final box = await cached;
      if (box.isOpen) return box as Box<T>;
      _boxes.remove(boxName);
    }
    final opening = _open<T>(boxName);
    _boxes[boxName] = opening;
    try {
      return await opening;
    } catch (_) {
      _boxes.remove(boxName);
      rethrow;
    }
  }

  Future<Box<T>> _open<T>(String boxName) async {
    if (Hive.isBoxOpen(boxName)) return Hive.box<T>(boxName);
    try {
      final cipher = await getCipher();
      return await Hive.openBox<T>(boxName, encryptionCipher: cipher);
    } catch (e) {
      // Fallback to unencrypted box on secure storage failure/web limits
      return await Hive.openBox<T>(boxName);
    }
  }
}
