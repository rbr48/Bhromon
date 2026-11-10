import 'package:bhromon/features/tour_group/domain/models/study_assignment_models.dart';
import 'package:bhromon/features/tour_group/domain/services/study_assignment_rules.dart';
import 'package:flutter_test/flutter_test.dart';

// The assignments a study group keeps: who sees which, who may change one, the order to work through them, and how
// near a due day is. The rules that the database enforces are tested on the emulator.

StudyAssignment _item(
  String id, {
  DateTime? dueAt,
  DateTime? createdAt,
  bool shown = true,
  String by = 'me@x.com',
}) =>
    StudyAssignment(
      id: id,
      title: 'Assignment $id',
      dueAt: dueAt,
      createdAt: createdAt,
      shown: shown,
      createdByEmail: by,
    );

void main() {
  group('who sees an assignment', () {
    test('every member sees a shown one', () {
      final shown = _item('a');
      expect(
        canSeeAssignment(
            assignment: shown, viewerEmail: 'other@x.com', isAdmin: false),
        isTrue,
      );
    });

    test(
        'a waiting one is seen by its author and by an admin, and by no other member',
        () {
      final waiting = _item('w', shown: false, by: 'me@x.com');
      expect(
          canSeeAssignment(
              assignment: waiting, viewerEmail: 'me@x.com', isAdmin: false),
          isTrue);
      expect(
          canSeeAssignment(
              assignment: waiting, viewerEmail: 'other@x.com', isAdmin: true),
          isTrue);
      expect(
          canSeeAssignment(
              assignment: waiting, viewerEmail: 'other@x.com', isAdmin: false),
          isFalse);
    });

    test(
        'the visible list keeps the given order, without the waiting ones of others',
        () {
      final list = [
        _item('shown'),
        _item('theirs', shown: false, by: 'other@x.com'),
        _item('mine', shown: false),
      ];
      final visible = visibleStudyAssignments(
        assignments: list,
        viewerEmail: 'me@x.com',
        isAdmin: false,
      );
      expect(visible.map((a) => a.id), ['shown', 'mine']);
    });
  });

  group('who may change an assignment', () {
    test('its author and an admin may; another member may not', () {
      expect(
          canEditAssignment(
              createdByEmail: 'me@x.com',
              viewerEmail: 'me@x.com',
              isAdmin: false),
          isTrue);
      expect(
          canEditAssignment(
              createdByEmail: 'me@x.com',
              viewerEmail: 'other@x.com',
              isAdmin: true),
          isTrue);
      expect(
          canEditAssignment(
              createdByEmail: 'me@x.com',
              viewerEmail: 'other@x.com',
              isAdmin: false),
          isFalse);
    });

    test('an assignment with no author is only for an admin', () {
      expect(
          canEditAssignment(
              createdByEmail: '', viewerEmail: '', isAdmin: false),
          isFalse);
      expect(
          canEditAssignment(createdByEmail: '', viewerEmail: '', isAdmin: true),
          isTrue);
    });
  });

  group('the order to work through them', () {
    test(
        'the ones not yet finished come first, then the nearest due day, undated ones last',
        () {
      final list = [
        _item('undated', createdAt: DateTime(2026, 11, 2)),
        _item('later', dueAt: DateTime(2026, 11, 20)),
        _item('soon', dueAt: DateTime(2026, 11, 12)),
        _item('done-soon', dueAt: DateTime(2026, 11, 11)),
      ];
      final sorted = sortStudyAssignments(list, finished: {'done-soon'});
      expect(
          sorted.map((a) => a.id), ['soon', 'later', 'undated', 'done-soon']);
    });

    test('among the undated, a just-written one comes first, then the newest',
        () {
      final list = [
        _item('older', createdAt: DateTime(2026, 11, 1)),
        _item('newer', createdAt: DateTime(2026, 11, 5)),
        _item('just-written'),
      ];
      expect(sortStudyAssignments(list).map((a) => a.id),
          ['just-written', 'newer', 'older']);
    });

    test('sorting leaves the list it was given as it was', () {
      final list = [
        _item('b', dueAt: DateTime(2026, 11, 20)),
        _item('a', dueAt: DateTime(2026, 11, 12))
      ];
      sortStudyAssignments(list);
      expect(list.map((a) => a.id), ['b', 'a']);
    });
  });

  test('how many of the shown ones are finished', () {
    final list = [_item('a'), _item('b'), _item('c')];
    expect(
        finishedAssignmentCount(
            assignments: list, finished: {'a', 'c', 'gone'}),
        2);
    expect(finishedAssignmentCount(assignments: list, finished: const {}), 0);
  });

  group('how near a due day is', () {
    test(
        'a day due today is 0, a day that has passed is negative, and time of day does not count',
        () {
      expect(
          daysUntilAssignmentDue(
              dueAt: DateTime(2026, 11, 10),
              now: DateTime(2026, 11, 10, 23, 59)),
          0);
      expect(
          daysUntilAssignmentDue(
              dueAt: DateTime(2026, 11, 10, 23, 59),
              now: DateTime(2026, 11, 10, 0, 1)),
          0);
      expect(
          daysUntilAssignmentDue(
              dueAt: DateTime(2026, 11, 9), now: DateTime(2026, 11, 10)),
          -1);
    });

    test(
        'no due day has no state; overdue, due today, due soon in the three days before, and upcoming after',
        () {
      final now = DateTime(2026, 11, 10, 9);
      expect(assignmentDueState(dueAt: null, now: now), AssignmentDue.none);
      expect(assignmentDueState(dueAt: DateTime(2026, 11, 9), now: now),
          AssignmentDue.overdue);
      expect(assignmentDueState(dueAt: DateTime(2026, 11, 10), now: now),
          AssignmentDue.dueToday);
      expect(assignmentDueState(dueAt: DateTime(2026, 11, 11), now: now),
          AssignmentDue.dueSoon);
      expect(assignmentDueState(dueAt: DateTime(2026, 11, 13), now: now),
          AssignmentDue.dueSoon);
      expect(assignmentDueState(dueAt: DateTime(2026, 11, 14), now: now),
          AssignmentDue.upcoming);
    });
  });

  group('reading an assignment from the store', () {
    test('a stored assignment with no title is not read', () {
      expect(StudyAssignment.fromMap('x', {'title': '   ', 'shown': true}),
          isNull);
    });

    test(
        'an assignment is shown unless it says otherwise, and blank text reads as empty',
        () {
      final read = StudyAssignment.fromMap('x', {
        'title': 'Lab 4',
        'details': '  ',
        'url': ' https://x.org/lab4 ',
        'createdByEmail': 'me@x.com',
      });
      expect(read, isNotNull);
      expect(read!.shown, isTrue);
      expect(read.details, '');
      expect(read.url, 'https://x.org/lab4');
      expect(read.dueAt, isNull);
    });

    test('a due day that is not a date is not read', () {
      final read = StudyAssignment.fromMap(
          'x', {'title': 'Lab 4', 'dueAt': 'soon', 'shown': false});
      expect(read!.dueAt, isNull);
      expect(read.shown, isFalse);
    });
  });
}
