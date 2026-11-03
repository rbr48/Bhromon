import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../app/di/injection.dart';
import '../../../core/security/hive_encryption_service.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/models/channel_models.dart';

/// The newest messages of each channel, kept on this device so a channel opens
/// with its messages in place while the live query connects.
///
/// Each channel has its own box, opened encrypted, so its text is not readable
/// from the device's files. Every call is best effort: a failed read is an empty
/// list, and a failed write is dropped, because the live query is the source of
/// truth.
class ChannelMessageCache {
  /// Opens the boxes with [encryption] when it is given, and with the app's
  /// service otherwise.
  ChannelMessageCache({HiveEncryptionService? encryption})
      : _encryption = encryption;

  final HiveEncryptionService? _encryption;

  /// The newest messages kept per channel. The live query reads the same number.
  static const int maxMessages = 100;

  static const String _boxPrefix = 'channel_msgs_';
  static const String _indexBox = 'channel_msgs_index';
  static const String _messagesKey = 'messages';

  Future<Box<dynamic>> _open(String name) {
    final service = _encryption ?? getIt<HiveEncryptionService>();
    return service.openEncryptedBox<dynamic>(name);
  }

  /// The box name for one channel. The ids are base64url-encoded, so the name is
  /// safe on every file system.
  @visibleForTesting
  static String boxNameFor(String tourId, String channelId) {
    final key =
        base64Url.encode(utf8.encode('$tourId/$channelId')).replaceAll('=', '');
    return '$_boxPrefix$key';
  }

  /// The channel's cached messages, newest first. Empty when nothing is cached
  /// or the read fails.
  Future<List<ChannelMessage>> read(String tourId, String channelId) async {
    try {
      final box = await _open(boxNameFor(tourId, channelId));
      final raw = box.get(_messagesKey);
      if (raw is! List) return const [];
      return [
        for (final entry in raw)
          if (entry is Map)
            ChannelMessage.fromMap(
              entry['id'] as String? ?? '',
              Map<String, dynamic>.from(entry),
            ),
      ];
    } catch (e, st) {
      logWarning('[ChannelMessageCache] Could not read cached messages', e, st);
      return const [];
    }
  }

  /// Keeps the newest [maxMessages] of [messages], in the order given, without
  /// the ones still waiting for the server.
  Future<void> write(
    String tourId,
    String channelId,
    List<ChannelMessage> messages,
  ) async {
    try {
      final name = boxNameFor(tourId, channelId);
      final box = await _open(name);
      final kept = [
        for (final m in messages)
          if (!m.isPending) m.toCacheMap(),
      ].take(maxMessages).toList();
      await box.put(_messagesKey, kept);
      final index = await _open(_indexBox);
      await index.put(name, tourId);
    } catch (e, st) {
      logWarning(
          '[ChannelMessageCache] Could not write cached messages', e, st);
    }
  }

  /// Forgets every cached channel of one tour, when the person leaves it or it
  /// is deleted.
  Future<void> clearTour(String tourId) async {
    try {
      final index = await _open(_indexBox);
      final names = [
        for (final key in index.keys)
          if (index.get(key) == tourId) key as String,
      ];
      for (final name in names) {
        await Hive.deleteBoxFromDisk(name);
        await index.delete(name);
      }
    } catch (e, st) {
      logWarning('[ChannelMessageCache] Could not clear a tour', e, st);
    }
  }

  /// Forgets every cached channel, when the person signs out.
  Future<void> clearAll() async {
    try {
      final index = await _open(_indexBox);
      for (final key in index.keys.toList()) {
        await Hive.deleteBoxFromDisk(key as String);
      }
      await index.clear();
    } catch (e, st) {
      logWarning('[ChannelMessageCache] Could not clear the cache', e, st);
    }
  }
}
