import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

const String _pushDeviceBoxName = 'push_device_meta';
const String _pushDeviceIdKey = 'device_id';
String? _fallbackSessionDeviceId;

/// The Firestore document id for one device's push token, under
/// `fcm_tokens/{uid}/devices`. A hash keeps the id short and clear of the
/// characters a document id cannot hold.
String pushDeviceId(String token) =>
    sha256.convert(utf8.encode(token)).toString();

/// Stable per-installation device identifier sent to the VPS token endpoint so
/// rotated FCM/PushKit tokens overwrite the same device row instead of creating
/// duplicate tokens on every refresh.
Future<String> getOrCreatePushDeviceId({
  Future<String?> Function()? reader,
  Future<void> Function(String)? writer,
}) async {
  if (reader != null && writer != null) {
    final existing = await reader();
    if (existing != null && existing.trim().isNotEmpty) {
      return existing.trim();
    }
    final generated = const Uuid().v4();
    await writer(generated);
    return generated;
  }

  try {
    final box = await Hive.openBox<String>(_pushDeviceBoxName);
    final existing = box.get(_pushDeviceIdKey);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing.trim();
    }
    final generated = const Uuid().v4();
    await box.put(_pushDeviceIdKey, generated);
    return generated;
  } catch (_) {
    return _fallbackSessionDeviceId ??= const Uuid().v4();
  }
}
