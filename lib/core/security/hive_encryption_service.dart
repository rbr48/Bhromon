import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:injectable/injectable.dart';

/// Opens Hive boxes encrypted with a key kept in the platform keystore.
///
/// Two things this guards against:
/// - It never encrypts with a key anyone can read. Earlier versions fell back
///   to a fixed key, compiled into the app, whenever secure storage failed.
///   Without a key now, boxes are kept in memory for the session and nothing
///   is written to disk.
/// - It never opens a box with a key that might be wrong. With Hive's default
///   crash recovery a wrong key makes every frame look corrupt and the file is
///   truncated to nothing; with recovery off a failed open leaves stray async
///   errors behind. So readability is probed on a throwaway copy, and a box
///   written with the old fixed key (or unencrypted) is re-encrypted with the
///   device key through a temporary copy, so a crash can't lose it.
@lazySingleton
class HiveEncryptionService {
  final FlutterSecureStorage _secureStorage;
  final String _keyName = 'hive_encryption_key';

  HiveEncryptionService() : _secureStorage = const FlutterSecureStorage();

  @visibleForTesting
  HiveEncryptionService.withStorage(this._secureStorage);

  /// The key older versions used when secure storage failed. Only ever used
  /// to read (and migrate away from) data written that way.
  static final HiveAesCipher _legacyFallbackCipher =
      HiveAesCipher(List<int>.generate(32, (i) => (i * 7 + 13) % 256));

  static const String _migrationSuffix = '__rekey';
  static const String _probeSuffix = '__probe';

  /// Unencrypted box mapping box name -> fingerprint of the key it was last
  /// opened with, so the probing happens once per box, not on every launch.
  static const String _keyMarksBox = 'hive_key_marks';

  // The key lives in the platform keystore; reading it is a platform-channel
  // round trip, so it's read once per process instead of on every box open.
  Future<_DeviceKey?>? _key;

  // In-flight and completed opens, so concurrent callers share one open.
  final Map<String, Future<Box<dynamic>>> _boxes = {};

  final Set<String> _inMemoryBoxes = {};

  /// True once any box was kept in memory because there was no device key.
  @visibleForTesting
  bool get usedInMemoryFallback => _inMemoryBoxes.isNotEmpty;

  /// The app's encryption key, or null if secure storage can't provide one.
  Future<HiveAesCipher?> getCipher() async => (await _deviceKey())?.cipher;

  Future<_DeviceKey?> _deviceKey() => _key ??= _readKey();

  Future<_DeviceKey?> _readKey() async {
    String? base64Key;
    try {
      base64Key = await _secureStorage.read(key: _keyName);
    } catch (e) {
      // Can't tell whether a key exists. Generating one could orphan data
      // encrypted with the real key, so run without one this session.
      debugPrint('[HiveEncryption] Secure storage read failed: $e');
      return null;
    }
    if (base64Key != null) {
      try {
        return _DeviceKey(base64Decode(base64Key));
      } catch (e) {
        debugPrint('[HiveEncryption] Stored key is unreadable: $e');
        return null;
      }
    }
    // First run: create the key, and use it only once it's safely stored.
    final key = Hive.generateSecureKey();
    try {
      await _secureStorage.write(key: _keyName, value: base64Encode(key));
    } catch (e) {
      debugPrint('[HiveEncryption] Could not store a new key: $e');
      return null;
    }
    return _DeviceKey(key);
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

    // On Web, Hive stores data in IndexedDB — no filesystem or migration probes exist.
    if (kIsWeb) {
      final key = await _deviceKey();
      if (key == null) return _openInMemory<T>(boxName);
      return await Hive.openBox<T>(boxName, encryptionCipher: key.cipher);
    }

    final key = await _deviceKey();
    if (key == null) return _openInMemory<T>(boxName);

    await _finishInterruptedMigration(boxName, key);

    final marks = await Hive.openBox<dynamic>(_keyMarksBox);
    await _resolveHome();
    final knownGood = marks.get(boxName) == key.fingerprint;
    if (knownGood || !await Hive.boxExists(boxName)) {
      final box = await Hive.openBox<T>(boxName, encryptionCipher: key.cipher);
      await marks.put(boxName, key.fingerprint);
      return box;
    }

    // First open of an existing box since it was last marked: find out which
    // key it was written with, without touching the file itself.
    final Box<T> box;
    if (await _readableWith(boxName, key.cipher) != null) {
      box = await Hive.openBox<T>(boxName, encryptionCipher: key.cipher);
    } else {
      final legacy = await _readableWith(boxName, _legacyFallbackCipher) ??
          await _readableWith(boxName, null);
      if (legacy != null) {
        box = await _reencrypt<T>(boxName, key, legacy);
      } else {
        // Unreadable with every key we know (genuinely corrupt, or encrypted
        // with a keystore key that no longer exists): let Hive recover it.
        debugPrint('[HiveEncryption] $boxName is unreadable; recovering');
        box = await Hive.openBox<T>(boxName, encryptionCipher: key.cipher);
      }
    }
    await marks.put(boxName, key.fingerprint);
    return box;
  }

  int _probes = 0;

  /// Every entry of [boxName] if it can be read with [cipher] (null = no
  /// encryption), else null. Works on a copy of the file: a failed Hive open
  /// leaves an unawaited close and an unlistened error behind, which must
  /// not reach the real box or the app's error reporting.
  Future<Map<dynamic, dynamic>?> _readableWith(
      String boxName, HiveCipher? cipher) async {
    final source = _boxFile(boxName);
    if (source == null || !source.existsSync()) return null;
    final probe = '$boxName$_probeSuffix${_probes++}';
    final probeFile = File('${source.parent.path}/$probe.hive');
    source.copySync(probeFile.path);

    final result = Completer<Map<dynamic, dynamic>?>();
    runZonedGuarded(() async {
      try {
        final box = await Hive.openBox<dynamic>(probe,
            encryptionCipher: cipher, crashRecovery: false);
        final entries = box.toMap();
        await box.close();
        if (!result.isCompleted) result.complete(entries);
      } on HiveError {
        if (!result.isCompleted) result.complete(null);
      }
    }, (_, __) {
      // Stray errors from Hive's failed open of the probe copy.
      if (!result.isCompleted) result.complete(null);
    });
    final entries = await result.future;
    try {
      if (probeFile.existsSync()) probeFile.deleteSync();
    } catch (_) {}
    return entries;
  }

  /// The .hive file Hive uses for [boxName], once Hive has been initialised.
  File? _boxFile(String boxName) {
    final home = _hiveHome;
    if (home == null) return null;
    return File('$home/${boxName.toLowerCase()}.hive');
  }

  String? _hiveHome;

  /// Records where Hive keeps its files (`Hive.init` / `Hive.initFlutter`).
  Future<void> _resolveHome() async {
    if (_hiveHome != null) return;
    final marks = await Hive.openBox<dynamic>(_keyMarksBox);
    final path = marks.path;
    if (path != null) _hiveHome = File(path).parent.path;
  }

  Future<Box<T>> _reencrypt<T>(
      String boxName, _DeviceKey key, Map<dynamic, dynamic> entries) async {
    final temp = '$boxName$_migrationSuffix';
    // 1. A durable copy under the device key...
    final copy =
        await Hive.openBox<dynamic>(temp, encryptionCipher: key.cipher);
    await copy.clear();
    await copy.putAll(entries);
    await copy.close();
    // 2. ...then replace the original with it...
    await Hive.deleteBoxFromDisk(boxName);
    final box = await Hive.openBox<T>(boxName, encryptionCipher: key.cipher);
    await box.putAll(entries.cast<dynamic, T>());
    // 3. ...and drop the copy.
    await Hive.deleteBoxFromDisk(temp);
    debugPrint('[HiveEncryption] Re-encrypted $boxName with the device key');
    return box;
  }

  /// Completes a re-encryption that was cut short after step 1.
  Future<void> _finishInterruptedMigration(
      String boxName, _DeviceKey key) async {
    final temp = '$boxName$_migrationSuffix';
    if (!await Hive.boxExists(temp)) return;
    await _resolveHome();
    final entries = await _readableWith(temp, key.cipher);
    if (entries != null) {
      await Hive.deleteBoxFromDisk(boxName);
      final box =
          await Hive.openBox<dynamic>(boxName, encryptionCipher: key.cipher);
      await box.putAll(entries);
      await box.close();
      final marks = await Hive.openBox<dynamic>(_keyMarksBox);
      await marks.put(boxName, key.fingerprint);
    }
    await Hive.deleteBoxFromDisk(temp);
  }

  /// A session-only box when there's no device key. Data readable with the
  /// old fixed key (or unencrypted) is loaded into it; the file isn't touched.
  Future<Box<T>> _openInMemory<T>(String boxName) async {
    debugPrint(
        '[HiveEncryption] No device key; keeping $boxName in memory this session');
    if (kIsWeb) {
      final box = await Hive.openBox<T>(boxName);
      _inMemoryBoxes.add(boxName);
      return box;
    }
    Map<dynamic, dynamic>? existing;
    if (await Hive.boxExists(boxName)) {
      await _resolveHome();
      existing = await _readableWith(boxName, _legacyFallbackCipher) ??
          await _readableWith(boxName, null);
    }
    final box = await Hive.openBox<T>(boxName, bytes: Uint8List(0));
    if (existing != null) await box.putAll(existing.cast<dynamic, T>());
    _inMemoryBoxes.add(boxName);
    return box;
  }
}

class _DeviceKey {
  _DeviceKey(List<int> bytes)
      : cipher = HiveAesCipher(bytes),
        // Identifies the key in the (unencrypted) marks box without
        // revealing it.
        fingerprint = sha256
            .convert(utf8.encode('bhromon-hive-key:') + bytes)
            .toString()
            .substring(0, 16);

  final HiveAesCipher cipher;
  final String fingerprint;
}
