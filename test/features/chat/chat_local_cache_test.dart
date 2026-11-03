import 'dart:convert';
import 'dart:io';

import 'package:bhromon/core/security/hive_encryption_service.dart';
import 'package:bhromon/features/chat/data/chat_local_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import '../../helpers/perf_fixtures.dart';

/// Whether [needle] appears in [haystack] as a run of bytes.
bool _containsBytes(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var matches = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}

void main() {
  late Directory dir;
  late CountingSecureStorage storage;
  late HiveEncryptionService service;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bhromon_chat_cache_');
    Hive.init(dir.path);
    storage = CountingSecureStorage();
    service = HiveEncryptionService.withStorage(storage);
  });

  tearDown(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File boxFile(String name) => File('${dir.path}/$name.hive');

  bool onDiskContains(String box, String text) =>
      _containsBytes(boxFile(box).readAsBytesSync(), utf8.encode(text));

  Map<String, dynamic> message(String id, String text) => {
        'id': id,
        'text': text,
        'senderId': 'u1',
        'timestamp': DateTime(2026, 1, 2, 9, 30).toIso8601String(),
      };

  test('cached messages are not readable as text on disk', () async {
    final cache = ChatLocalCache.withEncryption(service);
    await cache.cacheMessages('c1', [message('m1', 'hello-secret-123')]);

    expect(boxFile('chat_cache_msgs_c1').existsSync(), isTrue);
    expect(onDiskContains('chat_cache_msgs_c1', 'hello-secret-123'), isFalse);

    final read = await cache.getCachedMessages('c1');
    expect(read.single['text'], 'hello-secret-123');
  });

  test('a plaintext box from an older version is encrypted on its next open',
      () async {
    final legacy =
        await Hive.openBox<Map<dynamic, dynamic>>('chat_cache_msgs_c2');
    await legacy.put('m1', {'id': 'm1', 'text': 'legacy-text-456'});
    await legacy.close();
    expect(onDiskContains('chat_cache_msgs_c2', 'legacy-text-456'), isTrue);

    final cache = ChatLocalCache.withEncryption(service);
    final read = await cache.getCachedMessages('c2');

    expect(read.single['text'], 'legacy-text-456');
    expect(onDiskContains('chat_cache_msgs_c2', 'legacy-text-456'), isFalse);
  });

  test('conversations and lock flags survive a restart with the same key',
      () async {
    final first = ChatLocalCache.withEncryption(service);
    await first.init();
    await first
        .cacheConversation('c3', {'title': 'Rahim', 'lastMessage': 'ok'});
    await first.setChatLocked('c3', true);
    await Hive.close();

    expect(onDiskContains('chat_cache_conversations', 'Rahim'), isFalse);

    final second = ChatLocalCache.withEncryption(
        HiveEncryptionService.withStorage(storage));
    await second.init();
    final conversations = await second.getCachedConversations();

    expect(conversations.single['title'], 'Rahim');
    expect(second.isChatLocked('c3'), isTrue);
  });
}
