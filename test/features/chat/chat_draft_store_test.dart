import 'dart:convert';
import 'dart:io';

import 'package:bhromon/core/security/hive_encryption_service.dart';
import 'package:bhromon/features/chat/data/chat_draft_store.dart';
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

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bhromon_drafts_');
    Hive.init(dir.path);
    storage = CountingSecureStorage();
  });

  tearDown(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  ChatDraftStore store({Duration debounce = const Duration(milliseconds: 20)}) {
    return ChatDraftStore(
      encryption: HiveEncryptionService.withStorage(storage),
      debounce: debounce,
    );
  }

  test('a saved draft survives a restart and is not readable on disk',
      () async {
    final scope = chatDraftScope('chat-1');
    await store().write(scope, 'draft-secret-789');

    expect(
      _containsBytes(
        File('${dir.path}/${ChatDraftStore.boxName}.hive').readAsBytesSync(),
        utf8.encode('draft-secret-789'),
      ),
      isFalse,
    );

    await Hive.close();
    expect(await store().read(scope), 'draft-secret-789');
  });

  test('blank text removes the draft', () async {
    final draftStore = store();
    final scope = chatDraftScope('chat-1');
    await draftStore.write(scope, 'almost sent');
    await draftStore.write(scope, '   ');

    expect(await draftStore.read(scope), '');
  });

  test('drafts for different chats and channels never mix', () async {
    final draftStore = store();
    await draftStore.write(chatDraftScope('chat-1'), 'one-to-one');
    await draftStore.write(channelDraftScope('tour-1', 'general'), 'channel');

    expect(await draftStore.read(chatDraftScope('chat-1')), 'one-to-one');
    expect(await draftStore.read(chatDraftScope('chat-2')), '');
    expect(await draftStore.read(channelDraftScope('tour-1', 'general')),
        'channel');
    expect(await draftStore.read(channelDraftScope('tour-2', 'general')), '');
    expect(await draftStore.read(channelDraftScope('tour-1', 'food')), '');
  });

  test('save waits for a pause and keeps only the latest text', () async {
    final draftStore = store();
    final scope = chatDraftScope('chat-1');
    var text = '';
    for (final typed in ['h', 'he', 'hel', 'hello']) {
      text = typed;
      draftStore.save(scope, () => text);
    }
    expect(await draftStore.read(scope), '');

    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(await draftStore.read(scope), 'hello');
    draftStore.dispose();
  });

  test('nothing is saved while an edit is open', () async {
    final draftStore = store();
    final scope = chatDraftScope('chat-1');
    await draftStore.write(scope, 'kept draft');

    draftStore.save(
      scope,
      () => 'edit text',
      shouldSave: () => false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(await draftStore.read(scope), 'kept draft');
    draftStore.dispose();
  });

  test('dispose cancels a save that has not run yet', () async {
    final draftStore = store(debounce: const Duration(milliseconds: 50));
    final scope = chatDraftScope('chat-1');
    draftStore.save(scope, () => 'never written');
    draftStore.dispose();

    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(await draftStore.read(scope), '');
  });

  test('a channel draft is scoped to its tour as well as its channel', () {
    expect(channelDraftScope('tour-1', 'general'),
        isNot(channelDraftScope('tour-2', 'general')));
    expect(channelDraftScope('tour-1', 'general'),
        isNot(chatDraftScope('tour-1:general')));
  });
}
