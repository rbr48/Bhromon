import 'package:bhromon/features/tour_group/domain/models/family_task_models.dart';
import 'package:bhromon/features/tour_group/domain/services/family_task_rules.dart';
import 'package:flutter_test/flutter_test.dart';

FamilyTask _task(
  String id,
  String title, {
  FamilyTaskKind kind = FamilyTaskKind.shopping,
  bool done = false,
  DateTime? createdAt,
  DateTime? doneAt,
}) =>
    FamilyTask(
      id: id,
      title: title,
      kind: kind,
      done: done,
      createdAt: createdAt,
      doneAt: doneAt,
    );

void main() {
  group('familyTaskPage: open items', () {
    test(
        'show oldest first, and items saved before the time was kept come first',
        () {
      final page = familyTaskPage([
        _task('new', 'Bread', createdAt: DateTime.utc(2026, 11, 3)),
        _task('legacy_b', 'Soap'),
        _task('old', 'Rice', createdAt: DateTime.utc(2026, 11, 1)),
        _task('legacy_a', 'Atta'),
      ], FamilyTaskKind.shopping);

      expect(page.single.section, FamilyTaskSection.shopping);
      expect(
        page.single.items.map((t) => t.title).toList(),
        ['Atta', 'Soap', 'Rice', 'Bread'],
      );
    });

    test('added at the same moment sort by text, ignoring case, then by id',
        () {
      final at = DateTime.utc(2026, 11, 4);
      final page = familyTaskPage([
        _task('2', 'Milk', createdAt: at),
        _task('1', 'atta', createdAt: at),
        _task('3', 'Milk', createdAt: at),
      ], FamilyTaskKind.shopping);

      expect(page.single.items.map((t) => t.id).toList(), ['1', '2', '3']);
    });
  });

  group('familyTaskPage: ticked items', () {
    test(
        'show the latest tick first, and ticks kept before the time was recorded come last',
        () {
      final page = familyTaskPage([
        _task('a', 'Milk', done: true, doneAt: DateTime.utc(2026, 11, 2)),
        _task('b', 'Eggs', done: true, doneAt: DateTime.utc(2026, 11, 5)),
        _task('c', 'Dal', done: true),
      ], FamilyTaskKind.shopping);

      expect(page.single.section, FamilyTaskSection.done);
      expect(
        page.single.items.map((t) => t.title).toList(),
        ['Eggs', 'Milk', 'Dal'],
      );
    });
  });

  test('each page holds only its kind: open items first, then its ticked ones',
      () {
    final tasks = [
      _task('1', 'Rice', createdAt: DateTime.utc(2026, 11, 1)),
      _task(
        '2',
        'Mop',
        kind: FamilyTaskKind.todo,
        createdAt: DateTime.utc(2026, 11, 1),
      ),
      _task('3', 'Soap', done: true, doneAt: DateTime.utc(2026, 11, 2)),
      _task('4', 'Bread', done: true, doneAt: DateTime.utc(2026, 11, 3)),
      _task(
        '5',
        'Sweep',
        kind: FamilyTaskKind.todo,
        done: true,
        doneAt: DateTime.utc(2026, 11, 4),
      ),
    ];

    final shopping = familyTaskPage(tasks, FamilyTaskKind.shopping);
    expect(
      shopping.map((s) => s.section).toList(),
      [FamilyTaskSection.shopping, FamilyTaskSection.done],
    );
    expect(shopping.last.items.map((t) => t.title).toList(), ['Bread', 'Soap']);

    final todo = familyTaskPage(tasks, FamilyTaskKind.todo);
    expect(
      todo.map((s) => s.section).toList(),
      [FamilyTaskSection.todo, FamilyTaskSection.done],
    );
    expect(todo.last.items.map((t) => t.title).toList(), ['Sweep']);
  });

  test('an empty kind has no sections', () {
    expect(familyTaskPage([_task('1', 'Rice')], FamilyTaskKind.todo), isEmpty);
    expect(
        familyTaskPage(const <FamilyTask>[], FamilyTaskKind.shopping), isEmpty);
  });

  group('FamilyTask', () {
    test('a stored item reads with its trimmed text, its people and its times',
        () {
      final task = FamilyTask.fromMap('t1', {
        'title': '  Rice  ',
        'kind': 'shopping',
        'done': true,
        'assigneeEmail': 'asha@x.com',
        'doneByEmail': 'babu@x.com',
        'createdByEmail': 'asha@x.com',
        'createdAt': DateTime.utc(2026, 11, 1),
        'doneAt': DateTime.utc(2026, 11, 2),
      });

      expect(task.title, 'Rice');
      expect(task.isUntitled, isFalse);
      expect(task.done, isTrue);
      expect(task.assigneeEmail, 'asha@x.com');
      expect(task.doneByEmail, 'babu@x.com');
      expect(task.createdByEmail, 'asha@x.com');
      expect(task.createdAt, DateTime.utc(2026, 11, 1));
      expect(task.doneAt, DateTime.utc(2026, 11, 2));
    });

    test('a blank item still reads, as untitled, so it can be removed', () {
      final blank = FamilyTask.fromMap('t2', {
        'title': '   ',
        'createdByEmail': 'asha@x.com',
      });

      expect(blank.isUntitled, isTrue);
      expect(blank.createdByEmail, 'asha@x.com');
    });

    test('a damaged item reads with its odd fields left out', () {
      final damaged = FamilyTask.fromMap('t3', {
        'title': 42,
        'kind': 'errand',
        'assigneeEmail': 7,
        'doneByEmail': '',
        'createdAt': 'yesterday',
        'doneAt': 5,
        'createdByEmail': null,
      });

      expect(damaged.isUntitled, isTrue);
      expect(damaged.kind, FamilyTaskKind.shopping);
      expect(damaged.assigneeEmail, isNull);
      expect(damaged.doneByEmail, isNull);
      expect(damaged.createdAt, isNull);
      expect(damaged.doneAt, isNull);
      expect(damaged.createdByEmail, '');
    });

    test('writes the fields the rules check', () {
      const task = FamilyTask(
        id: 't4',
        title: 'Milk',
        kind: FamilyTaskKind.todo,
        createdByEmail: 'asha@x.com',
      );

      expect(task.toFields().keys.toSet(), {
        'title',
        'kind',
        'done',
        'assigneeEmail',
        'doneByEmail',
        'createdByEmail',
      });
      expect(task.toFields()['kind'], 'todo');
    });
  });

  group('the Dhaka day and the daily limit', () {
    test('the day turns over at 18:00 UTC, which is midnight in Dhaka', () {
      expect(
          familyTaskDayKey(DateTime.utc(2026, 11, 10, 17, 59, 59)), 20261110);
      expect(familyTaskDayKey(DateTime.utc(2026, 11, 10, 18)), 20261111);
      expect(familyTaskDayKey(DateTime.utc(2026, 12, 31, 18)), 20270101);
    });

    test('the counter is kept under the email and the day', () {
      expect(
        familyTaskCounterId('asha@x.com', DateTime.utc(2026, 11, 10, 18)),
        'asha@x.com__20261111',
      );
    });

    test('a day is full at the limit, and a list is long above 500 items', () {
      expect(familyTaskDayFull(familyTaskDailyLimit - 1), isFalse);
      expect(familyTaskDayFull(familyTaskDailyLimit), isTrue);
      expect(familyTaskListIsLong(familyTaskLongListAt), isFalse);
      expect(familyTaskListIsLong(familyTaskLongListAt + 1), isTrue);
    });
  });
}
