import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class HiveEncryptionService {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final String _keyName = 'hive_encryption_key';

  Future<HiveAesCipher> getCipher() async {
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
    try {
      final cipher = await getCipher();
      return await Hive.openBox<T>(boxName, encryptionCipher: cipher);
    } catch (e) {
      // Fallback to unencrypted box on secure storage failure/web limits
      return await Hive.openBox<T>(boxName);
    }
  }
}
