import 'dart:async';

import 'package:bhromon/features/chat/data/call_history_stream.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Item = ({String id, String what});

void main() {
  group('mergeLatestLists', () {
    late StreamController<List<_Item>> first;
    late StreamController<List<_Item>> second;
    late List<List<_Item>> sent;

    setUp(() {
      first = StreamController<List<_Item>>();
      second = StreamController<List<_Item>>();
      sent = [];
    });

    tearDown(() async {
      await first.close();
      await second.close();
    });

    test('sends nothing until every source has sent a list', () async {
      final merged = mergeLatestLists<_Item>(
        [first.stream, second.stream],
        idOf: (item) => item.id,
      ).listen(sent.add);
      first.add([(id: 'a', what: 'call')]);
      await Future<void>.delayed(Duration.zero);
      expect(sent, isEmpty);
      second.add([(id: 'b', what: 'call')]);
      await Future<void>.delayed(Duration.zero);
      expect(sent, hasLength(1));
      await merged.cancel();
    });

    test('merges the lists, and keeps an item that both sources send once',
        () async {
      final merged = mergeLatestLists<_Item>(
        [first.stream, second.stream],
        idOf: (item) => item.id,
      ).listen(sent.add);
      first.add([(id: 'a', what: 'made'), (id: 'shared', what: 'both')]);
      second.add([(id: 'b', what: 'received'), (id: 'shared', what: 'both')]);
      await Future<void>.delayed(Duration.zero);
      expect(sent.last.map((i) => i.id).toSet(), {'a', 'b', 'shared'});
      expect(sent.last, hasLength(3));
      await merged.cancel();
    });

    test('sends again when one source sends a new list', () async {
      final merged = mergeLatestLists<_Item>(
        [first.stream, second.stream],
        idOf: (item) => item.id,
      ).listen(sent.add);
      first.add([(id: 'a', what: 'made')]);
      second.add([(id: 'b', what: 'received')]);
      await Future<void>.delayed(Duration.zero);
      first.add([(id: 'a', what: 'made'), (id: 'c', what: 'new call')]);
      await Future<void>.delayed(Duration.zero);
      expect(sent, hasLength(2));
      expect(sent.last.map((i) => i.id).toSet(), {'a', 'b', 'c'});
      await merged.cancel();
    });

    test('passes an error from a source on', () async {
      final errors = <Object>[];
      final merged = mergeLatestLists<_Item>(
        [first.stream, second.stream],
        idOf: (item) => item.id,
      ).listen(sent.add, onError: errors.add);
      second.addError(StateError('denied'));
      await Future<void>.delayed(Duration.zero);
      expect(errors.single, isA<StateError>());
      await merged.cancel();
    });

    test('cancelling the merged stream cancels both sources', () async {
      final merged = mergeLatestLists<_Item>(
        [first.stream, second.stream],
        idOf: (item) => item.id,
      ).listen(sent.add);
      first.add([(id: 'a', what: 'made')]);
      await Future<void>.delayed(Duration.zero);
      await merged.cancel();
      expect(first.hasListener, isFalse);
      expect(second.hasListener, isFalse);
    });

    test(
        'permits multiple listeners and replays the latest list to new listener',
        () async {
      final mergedStream = mergeLatestLists<_Item>(
        [first.stream, second.stream],
        idOf: (item) => item.id,
      );
      final sub1 = mergedStream.listen(sent.add);
      first.add([(id: 'a', what: 'made')]);
      second.add([(id: 'b', what: 'received')]);
      await Future<void>.delayed(Duration.zero);
      expect(sent, hasLength(1));

      // Second listener attaches after initial emission
      final secondSent = <List<_Item>>[];
      final sub2 = mergedStream.listen(secondSent.add);
      await Future<void>.delayed(Duration.zero);
      expect(secondSent, hasLength(1));
      expect(secondSent.single.map((i) => i.id).toSet(), {'a', 'b'});

      await sub1.cancel();
      await sub2.cancel();
    });
  });

  // Own group: the group above closes its controllers in tearDown, and these
  // controllers were never listened to, so closing them would never finish.
  group('mergeLatestLists restart', () {
    test('after the last listener left, only fresh lists are merged', () async {
      // Broadcast sources, as Firestore snapshot streams are, so they can be
      // listened to again after a cancel.
      final a = StreamController<List<_Item>>.broadcast();
      final b = StreamController<List<_Item>>.broadcast();
      final merged = mergeLatestLists<_Item>(
        [a.stream, b.stream],
        idOf: (item) => item.id,
      );

      final firstSent = <List<_Item>>[];
      final firstSub = merged.listen(firstSent.add);
      a.add([(id: 'a', what: 'made')]);
      b.add([(id: 'b', what: 'received')]);
      await Future<void>.delayed(Duration.zero);
      expect(firstSent, hasLength(1));
      await firstSub.cancel();

      // Nothing from before the cancel is replayed to the new listener.
      final secondSent = <List<_Item>>[];
      final secondSub = merged.listen(secondSent.add);
      await Future<void>.delayed(Duration.zero);
      expect(secondSent, isEmpty);

      // One source alone is not a merged list: the other has to send again.
      a.add([(id: 'c', what: 'made')]);
      await Future<void>.delayed(Duration.zero);
      expect(secondSent, isEmpty);

      b.add([(id: 'd', what: 'received')]);
      await Future<void>.delayed(Duration.zero);
      expect(secondSent, hasLength(1));
      expect(secondSent.single.map((i) => i.id).toSet(), {'c', 'd'});

      await secondSub.cancel();
      await a.close();
      await b.close();
    });
  });
}
