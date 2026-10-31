import 'package:bhromon/features/tour_group/domain/models/family_task_models.dart';
import 'package:bhromon/features/tour_group/domain/services/family_task_rules.dart';
import 'package:flutter_test/flutter_test.dart';

FamilyTask _task(String id, String title,
        {FamilyTaskKind kind = FamilyTaskKind.shopping, bool done = false}) =>
    FamilyTask(id: id, title: title, kind: kind, done: done);

void main() {
  group('familyTaskSections', () {
    test('open shopping, then open to-dos, then what is done', () {
      final sections = familyTaskSections([
        _task('1', 'Mop', kind: FamilyTaskKind.todo),
        _task('2', 'Rice'),
        _task('3', 'Soap', done: true),
        _task('4', 'Call the plumber', kind: FamilyTaskKind.todo),
      ]);
      expect(sections.map((s) => s.section).toList(), [
        FamilyTaskSection.shopping,
        FamilyTaskSection.todo,
        FamilyTaskSection.done,
      ]);
      expect(sections[1].items.map((t) => t.title).toList(),
          ['Call the plumber', 'Mop']);
      expect(sections[2].items.map((t) => t.id).toList(), ['3']);
    });

    test('items sort by text, ignoring case', () {
      final sections = familyTaskSections([
        _task('1', 'pulses'),
        _task('2', 'Atta'),
        _task('3', 'Milk'),
      ]);
      expect(sections.single.items.map((t) => t.title).toList(),
          ['Atta', 'Milk', 'pulses']);
    });

    test('empty sections are left out, and an empty list has none', () {
      expect(familyTaskSections(const []), isEmpty);
      final onlyDone = familyTaskSections([_task('1', 'Milk', done: true)]);
      expect(onlyDone.map((s) => s.section).toList(), [FamilyTaskSection.done]);
    });
  });

  group('FamilyTask', () {
    test('reads a stored item, and a blank title is left out', () {
      final task = FamilyTask.fromMap('t1', {
        'title': '  Rice  ',
        'kind': 'shopping',
        'done': true,
        'assigneeEmail': 'asha@x.com',
        'doneByEmail': 'babu@x.com',
        'createdByEmail': 'asha@x.com',
      });
      expect(task, isNotNull);
      expect(task!.title, 'Rice');
      expect(task.done, isTrue);
      expect(task.assigneeEmail, 'asha@x.com');
      expect(task.doneByEmail, 'babu@x.com');
      expect(FamilyTask.fromMap('t2', {'title': '   '}), isNull);
    });

    test('an unknown kind is something to buy, and empty names read as none',
        () {
      final task = FamilyTask.fromMap('t3', {
        'title': 'Something',
        'kind': 'errand',
        'assigneeEmail': '',
        'doneByEmail': '',
      })!;
      expect(task.kind, FamilyTaskKind.shopping);
      expect(task.assigneeEmail, isNull);
      expect(task.doneByEmail, isNull);
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
}
