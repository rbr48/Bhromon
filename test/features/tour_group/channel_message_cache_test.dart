import 'dart:convert';
import 'dart:io';

import 'package:bhromon/core/security/hive_encryption_service.dart';
import 'package:bhromon/features/tour_group/data/channel_message_cache.dart';
import 'package:bhromon/features/tour_group/domain/models/channel_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import '../../helpers/perf_fixtures.dart';

ChannelMessage _message(String id, String text, DateTime at,
        {bool pending = false}) =>
    ChannelMessage(
      id: id,
      senderEmail: 'asha@example.com',
      senderName: 'Asha',
      text: text,
      timestamp: at,
      isPending: pending,
    );

bool _onDisk(Directory dir, String text) {
  final needle = utf8.encode(text);
  for (final file in dir.listSync(recursive: true).whereType<File>()) {
    final bytes = file.readAsBytesSync();
    for (var i = 0; i + needle.length <= bytes.length; i++) {
      var same = true;
      for (var j = 0; j < needle.length; j++) {
        if (bytes[i + j] != needle[j]) {
          same = false;
          break;
        }
      }
      if (same) return true;
    }
  }
  return false;
}

void main() {
  late Directory dir;
  late ChannelMessageCache cache;
  final now = DateTime(2026, 11, 2, 9);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bhromon_channel_cache_');
    Hive.init(dir.path);
    final service = HiveEncryptionService.withStorage(CountingSecureStorage());
    cache = ChannelMessageCache(encryption: service);
  });

  tearDown(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('a channel reads back the messages written for it, in the order given',
      () async {
    await cache.write('t1', 'general', [
      _message('m2', 'second', now.add(const Duration(minutes: 1))),
      _message('m1', 'first', now),
    ]);

    final read = await cache.read('t1', 'general');
    expect([for (final m in read) m.text], ['second', 'first']);
    expect(read.first.timestamp, now.add(const Duration(minutes: 1)));
  });

  test('tours and channels keep their own messages', () async {
    await cache
        .write('t1', 'general', [_message('a', 'tour one general', now)]);
    await cache.write('t1', 'food', [_message('b', 'tour one food', now)]);
    await cache
        .write('t2', 'general', [_message('c', 'tour two general', now)]);

    expect([for (final m in await cache.read('t1', 'general')) m.text],
        ['tour one general']);
    expect([for (final m in await cache.read('t1', 'food')) m.text],
        ['tour one food']);
    expect([for (final m in await cache.read('t2', 'general')) m.text],
        ['tour two general']);
    expect(await cache.read('t2', 'food'), isEmpty);
  });

  test('pending messages are not kept, and only the newest hundred are',
      () async {
    final many = [
      for (var i = 0; i < 120; i++)
        _message('m$i', 'text $i', now.add(Duration(minutes: i))),
    ];
    await cache.write('t1', 'general', [
      _message('p', 'still sending', now, pending: true),
      ...many,
    ]);

    final read = await cache.read('t1', 'general');
    expect(read.length, ChannelMessageCache.maxMessages);
    expect(read.any((m) => m.text == 'still sending'), isFalse);
    expect(read.first.text, 'text 0');
  });

  test('the cached text is not readable as plain text on disk', () async {
    await cache.write(
        't1', 'general', [_message('m1', 'a very private sentence', now)]);
    await Hive.close();

    expect(_onDisk(dir, 'a very private sentence'), isFalse);
  });

  test('clearTour forgets one tour and keeps the others', () async {
    await cache.write('t1', 'general', [_message('a', 'one', now)]);
    await cache.write('t2', 'general', [_message('b', 'two', now)]);

    await cache.clearTour('t1');

    expect(await cache.read('t1', 'general'), isEmpty);
    expect(
        [for (final m in await cache.read('t2', 'general')) m.text], ['two']);
  });

  test('clearAll forgets every channel, and a later write works again',
      () async {
    await cache.write('t1', 'general', [_message('a', 'one', now)]);
    await cache.write('t2', 'food', [_message('b', 'two', now)]);

    await cache.clearAll();
    expect(await cache.read('t1', 'general'), isEmpty);
    expect(await cache.read('t2', 'food'), isEmpty);

    await cache.write('t1', 'general', [_message('c', 'three', now)]);
    expect(
        [for (final m in await cache.read('t1', 'general')) m.text], ['three']);
  });
}
