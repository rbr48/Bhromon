import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/family_task_models.dart';
import 'package:bhromon/features/tour_group/domain/services/family_task_rules.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_firestore.dart';

const _tour = 't1';
const _me = 'asha@x.com';
const _items = 'tours/$_tour/family_tasks';
const _counters = 'tours/$_tour/family_task_daily';

/// The repository signed in as [_me], over the in-memory store.
class _Repo extends TourGroupRepository {
  _Repo(FakeFirestore store) : super(firestore: store);

  @override
  String get currentEmail => _me;
}

void main() {
  late FakeFirestore store;
  late _Repo repo;

  setUp(() {
    store = FakeFirestore();
    repo = _Repo(store);
  });

  group('adding an item', () {
    test(
        'writes the item with its creator and a server time, and moves the day count in the same batch',
        () async {
      final synced = await repo.addFamilyTask(
        _tour,
        title: '  Milk  ',
        kind: FamilyTaskKind.shopping,
        assigneeEmail: 'Babu@X.com',
      );

      expect(synced, isTrue);
      final items = store.docsIn(_items).values.toList();
      expect(items, hasLength(1));
      final item = items.single;
      expect(item['title'], 'Milk');
      expect(item['kind'], 'shopping');
      expect(item['done'], isFalse);
      expect(item['doneByEmail'], isNull);
      expect(item['createdByEmail'], _me);
      expect(item['assigneeEmail'], 'babu@x.com');
      expect(item['createdAt'], isA<FieldValue>());

      final counter =
          store.read('$_counters/${familyTaskCounterId(_me, DateTime.now())}');
      expect(counter, isNotNull);
      expect(counter!['email'], _me);
      expect(counter['count'], isA<FieldValue>());
      expect(store.committedBatchSizes, [2]);
    });

    test('a member at the day limit is refused before anything is written',
        () async {
      store.seed(_counters, familyTaskCounterId(_me, DateTime.now()), {
        'count': familyTaskDailyLimit,
        'email': _me,
      });

      await expectLater(
        repo.addFamilyTask(_tour, title: 'Salt', kind: FamilyTaskKind.shopping),
        throwsA(isA<FamilyTaskDailyLimitException>()),
      );
      expect(store.docsIn(_items), isEmpty);
      expect(store.committedBatchSizes, isEmpty);
    });

    test('the last item of the day is still allowed', () async {
      store.seed(_counters, familyTaskCounterId(_me, DateTime.now()), {
        'count': familyTaskDailyLimit - 1,
        'email': _me,
      });

      expect(
        await repo.addFamilyTask(_tour,
            title: 'Salt', kind: FamilyTaskKind.shopping),
        isTrue,
      );
      expect(store.docsIn(_items), hasLength(1));
      expect(store.committedBatchSizes, [2]);
    });
  });

  group('ticking', () {
    test(
        'a tick is recorded under the member’s name with the server time, and an untick clears both',
        () async {
      store.seed(_items, 'x1', {
        'title': 'Rice',
        'kind': 'shopping',
        'done': false,
        'createdByEmail': 'babu@x.com',
      });

      expect(await repo.setFamilyTaskDone(_tour, 'x1', true), isTrue);
      var item = store.read('$_items/x1')!;
      expect(item['done'], isTrue);
      expect(item['doneByEmail'], _me);
      expect(item['doneAt'], isA<FieldValue>());

      expect(await repo.setFamilyTaskDone(_tour, 'x1', false), isTrue);
      item = store.read('$_items/x1')!;
      expect(item['done'], isFalse);
      expect(item['doneByEmail'], isNull);
      expect(item['doneAt'], isNull);
    });
  });

  group('changing an item', () {
    test('a rename, a new assignee and a new kind each write their own field',
        () async {
      store.seed(_items, 'x2', {
        'title': 'Rice',
        'kind': 'shopping',
        'done': false,
        'createdByEmail': _me,
        'assigneeEmail': null,
      });

      expect(
          await repo.renameFamilyTask(_tour, 'x2', '  Basmati rice  '), isTrue);
      expect(await repo.reassignFamilyTask(_tour, 'x2', 'Babu@X.com'), isTrue);
      expect(await repo.setFamilyTaskKind(_tour, 'x2', FamilyTaskKind.todo),
          isTrue);

      final item = store.read('$_items/x2')!;
      expect(item['title'], 'Basmati rice');
      expect(item['assigneeEmail'], 'babu@x.com');
      expect(item['kind'], 'todo');
      expect(item['done'], isFalse);
      expect(item['createdByEmail'], _me);

      await repo.reassignFamilyTask(_tour, 'x2', null);
      expect(store.read('$_items/x2')!['assigneeEmail'], isNull);
    });

    test('a delete removes the item', () async {
      store.seed(
          _items, 'x3', {'title': 'Salt', 'kind': 'shopping', 'done': false});

      expect(await repo.deleteFamilyTask(_tour, 'x3'), isTrue);
      expect(store.read('$_items/x3'), isNull);
    });

    test('clearing finished items writes them in batches of at most 400',
        () async {
      final ids = [for (var i = 0; i < 401; i++) 'x$i'];
      for (final id in ids) {
        store.seed(_items, id, {
          'title': 'Item $id',
          'kind': 'shopping',
          'done': true,
          'createdByEmail': _me,
        });
      }

      expect(await repo.clearFamilyTasks(_tour, ids), isTrue);
      expect(store.committedBatchSizes, [400, 1]);
      expect(store.docsIn(_items), isEmpty);
    });

    test('an empty clear writes nothing', () async {
      expect(await repo.clearFamilyTasks(_tour, const []), isTrue);
      expect(store.committedBatchSizes, isEmpty);
    });
  });
}
