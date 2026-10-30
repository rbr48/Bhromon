import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../../core/utils/app_logger.dart';

/// Ultra-fast local offline storage for Bhromon 1-on-1 Chat.
///
/// Stores recent messages, conversation metadata, and biometric locked chat
/// states locally so chats load with 0ms latency even in remote hill tracts
/// or with zero network.
class ChatLocalCache {
  static final ChatLocalCache _instance = ChatLocalCache._internal();
  factory ChatLocalCache() => _instance;
  ChatLocalCache._internal();

  static const String _kMessagesBoxPrefix = 'chat_cache_msgs_';
  static const String _kConversationsBox = 'chat_cache_conversations';
  static const String _kLockedChatsBox = 'chat_locked_chats';

  bool _initialized = false;
  Box<Map<dynamic, dynamic>>? _convBox;
  Box<bool>? _lockedBox;

  Future<void> init() async {
    if (_initialized) return;
    try {
      _convBox = await Hive.openBox<Map<dynamic, dynamic>>(_kConversationsBox);
      _lockedBox = await Hive.openBox<bool>(_kLockedChatsBox);
      _initialized = true;
    } catch (e, st) {
      logWarning('Error initializing ChatLocalCache', e, st);
    }
  }

  /// Sanitizes Firestore Timestamps and nested objects so Hive can serialize them without missing adapters
  Map<String, dynamic> _sanitizeForHive(Map<dynamic, dynamic> raw) {
    final clean = <String, dynamic>{};
    raw.forEach((key, value) {
      final strKey = key.toString();
      if (value is Timestamp) {
        clean[strKey] = value.toDate().toIso8601String();
      } else if (value is DateTime) {
        clean[strKey] = value.toIso8601String();
      } else if (value is Map) {
        clean[strKey] = _sanitizeForHive(value);
      } else if (value is List) {
        clean[strKey] = value.map((item) {
          if (item is Timestamp) return item.toDate().toIso8601String();
          if (item is DateTime) return item.toIso8601String();
          if (item is Map) return _sanitizeForHive(item);
          return item;
        }).toList();
      } else {
        clean[strKey] = value;
      }
    });
    return clean;
  }

  /// Caches the latest messages for [chatId].
  Future<void> cacheMessages(
      String chatId, List<Map<String, dynamic>> messages) async {
    try {
      final box = await Hive.openBox<Map<dynamic, dynamic>>(
          '$_kMessagesBoxPrefix$chatId');
      final Map<String, Map<String, dynamic>> mapToStore = {};
      for (final msg in messages) {
        final id = msg['id'] as String?;
        if (id != null && id.isNotEmpty) {
          mapToStore[id] = _sanitizeForHive(msg);
        }
      }
      await box.putAll(mapToStore);
    } catch (e, st) {
      logWarning('Error caching messages for $chatId', e, st);
    }
  }

  /// Retrieves cached messages for [chatId].
  Future<List<Map<String, dynamic>>> getCachedMessages(String chatId) async {
    try {
      final box = await Hive.openBox<Map<dynamic, dynamic>>(
          '$_kMessagesBoxPrefix$chatId');
      final list = <Map<String, dynamic>>[];
      for (final val in box.values) {
        list.add(Map<String, dynamic>.from(val));
      }
      return list;
    } catch (e, st) {
      logWarning('Error reading cached messages for $chatId', e, st);
      return [];
    }
  }

  /// Caches conversation metadata for the chat list.
  Future<void> cacheConversation(
      String chatId, Map<String, dynamic> data) async {
    try {
      await init();
      await _convBox?.put(chatId, _sanitizeForHive(data));
    } catch (e, st) {
      logWarning('Error caching conversation $chatId', e, st);
    }
  }

  /// Retrieves all cached conversations for offline chat list.
  Future<List<Map<String, dynamic>>> getCachedConversations() async {
    try {
      await init();
      final list = <Map<String, dynamic>>[];
      if (_convBox != null) {
        for (final val in _convBox!.values) {
          list.add(Map<String, dynamic>.from(val));
        }
      }
      return list;
    } catch (e, st) {
      logWarning('Error reading cached conversations', e, st);
      return [];
    }
  }

  /// Checks if [chatId] is marked as locked behind biometric authentication.
  bool isChatLocked(String chatId) {
    return _lockedBox?.get(chatId) ?? false;
  }

  /// Sets the biometric lock state for [chatId].
  Future<void> setChatLocked(String chatId, bool locked) async {
    try {
      await init();
      await _lockedBox?.put(chatId, locked);
    } catch (e, st) {
      logWarning('Error setting chat lock for $chatId', e, st);
    }
  }

  /// Returns the set of all locked chat IDs.
  Set<String> getLockedChatIds() {
    if (_lockedBox == null) return {};
    try {
      return _lockedBox!.keys
          .cast<String>()
          .where((id) => _lockedBox!.get(id) == true)
          .toSet();
    } catch (e, st) {
      logWarning('Error getting locked chat IDs', e, st);
      return {};
    }
  }
}
