import 'package:bhromon/features/tour_group/data/tour_media_journal.dart';
import 'package:flutter_test/flutter_test.dart';

const _hex = '0123456789abcdef0123456789abcdef';
final _start = DateTime(2026, 3, 1, 10);

TourMediaRef _ref([String id = _hex]) =>
    TourMediaRef(tourId: 't1', folder: 'posts', filename: '$id.jpg');

JournalEntry _entry(JournalKind kind) => JournalEntry(
      url: _ref().url,
      tourId: 't1',
      folder: 'posts',
      filename: '$_hex.jpg',
      kind: kind,
      since: _start,
    );

void main() {
  group('planSweepEntry', () {
    final old = _start.add(kPendingGrace + const Duration(minutes: 1));
    final young = _start.add(const Duration(minutes: 5));

    test('an unreferenced pending file that is old is deleted', () {
      expect(
        planSweepEntry(_entry(JournalKind.pending),
            now: old, inFlight: false, referenced: false),
        SweepDecision.deleteFile,
      );
    });

    test('a pending file a post or story uses is dropped, not deleted', () {
      expect(
        planSweepEntry(_entry(JournalKind.pending),
            now: old, inFlight: false, referenced: true),
        SweepDecision.drop,
      );
    });

    test('a file of an upload still running in this session is kept', () {
      expect(
        planSweepEntry(_entry(JournalKind.pending),
            now: old, inFlight: true, referenced: false),
        SweepDecision.keep,
      );
    });

    test('a young file is kept, whatever the reference check says', () {
      expect(
        planSweepEntry(_entry(JournalKind.pending),
            now: young, inFlight: false, referenced: false),
        SweepDecision.keep,
      );
      expect(
        planSweepEntry(_entry(JournalKind.delete),
            now: young, inFlight: false, referenced: null),
        SweepDecision.keep,
      );
    });

    test('when the reference check cannot run, the file is kept', () {
      expect(
        planSweepEntry(_entry(JournalKind.pending),
            now: old, inFlight: false, referenced: null),
        SweepDecision.keep,
      );
    });

    test('an old file marked for deletion is deleted', () {
      expect(
        planSweepEntry(_entry(JournalKind.delete),
            now: old, inFlight: false, referenced: null),
        SweepDecision.deleteFile,
      );
    });
  });

  group('TourMediaJournal', () {
    late MemoryJournalStore store;
    late DateTime now;
    late TourMediaJournal journal;

    setUp(() {
      store = MemoryJournalStore();
      now = _start;
      journal = TourMediaJournal(store: store, clock: () => now);
    });

    test('a recorded upload is saved and forgotten once it is committed',
        () async {
      await journal.recordPending(_ref());
      expect(journal.pendingCount, 1);
      expect(store.saved, hasLength(1));

      await journal.resolve(_ref().url);
      expect(journal.pendingCount, 0);
      expect(store.saved, isEmpty);
    });

    test('entries survive a restart', () async {
      await journal.recordPending(_ref());
      final restarted = TourMediaJournal(store: store, clock: () => now);
      now = _start.add(kPendingGrace + const Duration(minutes: 1));
      final removed = <String>[];
      await restarted.sweep(
        isReferenced: (_) async => false,
        deleteRemote: (url) async {
          removed.add(url);
          return true;
        },
      );
      expect(removed, [_ref().url]);
    });

    test('the sweep removes an old unreferenced file and forgets it', () async {
      await journal.recordPending(_ref());
      now = _start.add(kPendingGrace + const Duration(minutes: 1));
      // A new launch: nothing is in flight any more.
      journal = TourMediaJournal(store: store, clock: () => now);
      final removed = <String>[];
      await journal.sweep(
        isReferenced: (_) async => false,
        deleteRemote: (url) async {
          removed.add(url);
          return true;
        },
      );
      expect(removed, [_ref().url]);
      expect(journal.pendingCount, 0);
    });

    test('the sweep keeps a file that a post uses', () async {
      await journal.recordPending(_ref());
      now = _start.add(kPendingGrace + const Duration(minutes: 1));
      journal = TourMediaJournal(store: store, clock: () => now);
      var deleted = false;
      await journal.sweep(
        isReferenced: (_) async => true,
        deleteRemote: (_) async {
          deleted = true;
          return true;
        },
      );
      expect(deleted, isFalse);
      expect(journal.pendingCount, 0, reason: 'dropped from the journal');
      expect(store.saved, isEmpty);
    });

    test('a removal the server refuses stays in the journal for the next sweep',
        () async {
      await journal.recordPending(_ref());
      await journal.markDelete(_ref());
      now = _start.add(kPendingGrace + const Duration(minutes: 1));
      journal = TourMediaJournal(store: store, clock: () => now);
      await journal.sweep(
        isReferenced: (_) async => false,
        deleteRemote: (_) async => false,
      );
      expect(journal.pendingCount, 1);
    });

    test('a discarded upload is removed at once when the upload has settled',
        () async {
      await journal.recordPending(_ref());
      await journal.markDelete(_ref());
      await journal.resolve(_ref().url);
      expect(journal.pendingCount, 0);
    });

    test('concurrent changes are all kept', () async {
      final refs = [
        for (var i = 0; i < 20; i++) _ref(i.toRadixString(16).padLeft(32, '0')),
      ];
      await Future.wait([for (final r in refs) journal.recordPending(r)]);
      expect(journal.pendingCount, 20);
      expect(store.saved, hasLength(20));
    });

    test('a journal the store cannot read starts empty and still works',
        () async {
      final broken = TourMediaJournal(store: _BrokenStore(), clock: () => now);
      await broken.recordPending(_ref());
      expect(broken.pendingCount, 1);
    });
  });
}

class _BrokenStore implements JournalStore {
  @override
  Future<List<Object?>> read() async => throw StateError('no disk');

  @override
  Future<void> write(List<Map<String, dynamic>> entries) async =>
      throw StateError('no disk');
}
