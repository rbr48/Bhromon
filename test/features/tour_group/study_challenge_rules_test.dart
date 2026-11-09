import 'package:bhromon/features/tour_group/domain/models/study_challenge_models.dart';
import 'package:bhromon/features/tour_group/domain/services/study_challenge_rules.dart';
import 'package:flutter_test/flutter_test.dart';

// A weekly challenge: one small task a week that members choose to join. A week runs from its Monday at local
// midnight to the next Monday. 2026-11-09 is a Monday.

void main() {
  group('the week a challenge belongs to', () {
    test('a day belongs to the Monday that starts its week', () {
      expect(challengeWeekStart(DateTime(2026, 11, 9)), DateTime(2026, 11, 9));
      expect(challengeWeekStart(DateTime(2026, 11, 9, 23, 59)),
          DateTime(2026, 11, 9));
      expect(challengeWeekStart(DateTime(2026, 11, 14)), DateTime(2026, 11, 9));
      expect(challengeWeekStart(DateTime(2026, 11, 15, 10)),
          DateTime(2026, 11, 9));
    });

    test('the id of a week is its Monday as yyyy-MM-dd, and reads back', () {
      final monday = DateTime(2026, 11, 9);
      expect(challengeWeekKey(monday), '2026-11-09');
      expect(challengeWeekStartOf('2026-11-09'), monday);
    });

    test('an id that is not a real date does not read as a week', () {
      expect(challengeWeekStartOf('bogus'), isNull);
      expect(challengeWeekStartOf('2026-1-9'), isNull);
      expect(challengeWeekStartOf('2026-02-30'), isNull);
    });

    test('a week ends on the next Monday, and a day in the week is inside it',
        () {
      final monday = DateTime(2026, 11, 9);
      expect(challengeWeekEnd(monday), DateTime(2026, 11, 16));
      expect(inChallengeWeek(monday, DateTime(2026, 11, 9)), isTrue);
      expect(inChallengeWeek(monday, DateTime(2026, 11, 15, 23, 59)), isTrue);
      expect(inChallengeWeek(monday, DateTime(2026, 11, 16)), isFalse);
      expect(inChallengeWeek(monday, DateTime(2026, 11, 8, 23, 59)), isFalse);
      expect(inChallengeWeek(monday, null), isFalse);
    });

    test('work is counted only within its week', () {
      final monday = DateTime(2026, 11, 9);
      expect(
        countInChallengeWeek([
          DateTime(2026, 11, 9, 8),
          DateTime(2026, 11, 16, 8),
          null,
          DateTime(2026, 11, 12),
          DateTime(2026, 11, 8, 20),
        ], monday),
        2,
      );
    });
  });

  group('when a challenge is open', () {
    final monday = DateTime(2026, 11, 9);

    test('members may join and leave while the week runs', () {
      expect(challengeIsOpen(weekStart: monday, now: DateTime(2026, 11, 9, 7)),
          isTrue);
      expect(
          challengeIsOpen(weekStart: monday, now: DateTime(2026, 11, 15, 23)),
          isTrue);
    });

    test('it is closed before its week and after it', () {
      expect(challengeIsOpen(weekStart: monday, now: DateTime(2026, 11, 8, 23)),
          isFalse);
      expect(challengeIsOpen(weekStart: monday, now: DateTime(2026, 11, 16)),
          isFalse);
    });
  });

  group('progress', () {
    test('tasks done are capped at the target and never below none', () {
      expect(challengeDone(7, 5), 5);
      expect(challengeDone(3, 5), 3);
      expect(challengeDone(0, 5), 0);
      expect(challengeDone(-2, 5), 0);
    });

    test('the target is met when the tasks done reach it', () {
      expect(challengeMet(5, 5), isTrue);
      expect(challengeMet(6, 5), isTrue);
      expect(challengeMet(4, 5), isFalse);
    });
  });

  group('the challenge a week stores', () {
    test('its kind is read by name, and an unknown kind is not', () {
      expect(ChallengeKind.fromName('cards'), ChallengeKind.cards);
      expect(ChallengeKind.fromName('quizzes'), isNull);
      expect(ChallengeKind.fromName(null), isNull);
    });

    test('a valid challenge is read, and a target outside the limits is not',
        () {
      final read = StudyChallenge.fromMap('2026-11-09', {
        'kind': 'problems',
        'target': 5,
        'setByEmail': '  admin@x.com ',
      });
      expect(read?.kind, ChallengeKind.problems);
      expect(read?.target, 5);
      expect(read?.setByEmail, 'admin@x.com');
      expect(read?.weekKey, '2026-11-09');

      expect(
        StudyChallenge.fromMap('2026-11-09', {'kind': 'problems', 'target': 0}),
        isNull,
      );
      expect(
        StudyChallenge.fromMap('2026-11-09', {
          'kind': 'problems',
          'target': StudyChallengeLimits.targetMax + 1,
        }),
        isNull,
      );
      expect(
        StudyChallenge.fromMap('2026-11-09', {'kind': 'quizzes', 'target': 3}),
        isNull,
      );
    });

    test('a whole-number target stored as a decimal still reads', () {
      final read = StudyChallenge.fromMap(
          '2026-11-09', {'kind': 'findings', 'target': 3.0});
      expect(read?.target, 3);
    });

    test('an admin writes only the kind and the target', () {
      const challenge = StudyChallenge(
        weekKey: '2026-11-09',
        kind: ChallengeKind.cards,
        target: 10,
      );
      expect(challenge.toFields(), {'kind': 'cards', 'target': 10});
    });
  });
}
