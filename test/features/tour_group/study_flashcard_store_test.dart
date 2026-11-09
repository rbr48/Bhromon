import 'dart:convert';
import 'dart:io';

import 'package:bhromon/core/security/hive_encryption_service.dart';
import 'package:bhromon/features/tour_group/data/study_flashcard_store.dart';
import 'package:bhromon/features/tour_group/domain/models/study_flashcard_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import '../../helpers/perf_fixtures.dart';

// The flashcards a member keeps on the device. A card must survive a restart, and its text must not be readable in
// the box file on disk: the box is encrypted with the device key.

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
    dir = await Directory.systemTemp.createTemp('bhromon_flashcards_');
    Hive.init(dir.path);
    storage = CountingSecureStorage();
  });

  tearDown(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  StudyFlashcardStore store() => StudyFlashcardStore(
        encryption: HiveEncryptionService.withStorage(storage),
      );

  const card = StudyFlashcard(
    id: 'c1',
    deckId: 'b1',
    front: 'secret-question-417',
    back: 'secret-answer-903',
    box: 2,
    dueOn: '2026-11-13',
    termId: 't1',
  );

  test('cards written to the device are read back as they were', () async {
    await store().putAll([card]);

    final loaded = await store().loadAll();

    expect(loaded, hasLength(1));
    expect(loaded.single.id, 'c1');
    expect(loaded.single.front, 'secret-question-417');
    expect(loaded.single.back, 'secret-answer-903');
    expect(loaded.single.box, 2);
    expect(loaded.single.dueOn, '2026-11-13');
    expect(loaded.single.termId, 't1');
  });

  test('a card is not readable in the box file on disk', () async {
    await store().putAll([card]);

    final bytes = File('${dir.path}/${StudyFlashcardStore.boxName}.hive')
        .readAsBytesSync();

    expect(_containsBytes(bytes, utf8.encode('secret-question-417')), isFalse);
    expect(_containsBytes(bytes, utf8.encode('secret-answer-903')), isFalse);
  });

  test('cards survive a restart of the app', () async {
    await store().putAll([card]);

    await Hive.close();

    final afterRestart = await store().loadAll();
    expect(afterRestart.map((c) => c.front), ['secret-question-417']);
  });

  test('a card written again replaces the one with the same id', () async {
    await store().putAll([card]);
    await store().putAll([card.copyWith(box: 3, dueOn: '2026-11-17')]);

    final loaded = await store().loadAll();

    expect(loaded, hasLength(1));
    expect(loaded.single.box, 3);
    expect(loaded.single.dueOn, '2026-11-17');
  });

  test('a deleted card is gone after a restart', () async {
    await store().putAll([
      card,
      const StudyFlashcard(
        id: 'c2',
        deckId: 'b1',
        front: 'Keep me',
        back: 'Kept',
        dueOn: '2026-11-09',
      ),
    ]);
    await store().delete('c1');

    await Hive.close();

    final afterRestart = await store().loadAll();
    expect(afterRestart.map((c) => c.id), ['c2']);
  });
}
