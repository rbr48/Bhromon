import 'package:bhromon/features/tour_group/domain/models/study_finding_models.dart';
import 'package:bhromon/features/tour_group/domain/services/study_finding_rules.dart';
import 'package:flutter_test/flutter_test.dart';

// Shared findings: a result a member reached and how it was checked. The rules are pure: no
// database. The counts on a finding come from its checks, which the repository moves in a batch.

StudyFinding _finding(
  String id, {
  int confirm = 0,
  int challenge = 0,
  bool shown = true,
  bool pinned = false,
  String by = 'a@x.com',
  DateTime? at,
}) =>
    StudyFinding(
      id: id,
      text: 'Result $id',
      method: 'Re-ran the sample',
      createdByEmail: by,
      createdAt: at,
      confirmCount: confirm,
      challengeCount: challenge,
      shown: shown,
      pinned: pinned,
    );

void main() {
  group('the standing of a finding', () {
    test('unchecked until a check is made, then by which count is higher', () {
      expect(findingStanding(_finding('f')), FindingStanding.unchecked);
      expect(
        findingStanding(_finding('f', confirm: 2, challenge: 1)),
        FindingStanding.confirmed,
      );
      expect(
        findingStanding(_finding('f', confirm: 1, challenge: 2)),
        FindingStanding.challenged,
      );
      expect(
        findingStanding(_finding('f', confirm: 1, challenge: 1)),
        FindingStanding.contested,
      );
    });
  });

  group('who may check a finding', () {
    test('a member checks a shown finding of someone else, once', () {
      expect(
        canCheckFinding(
          finding: _finding('f'),
          viewerEmail: 'b@x.com',
          hasOwnCheck: false,
        ),
        isTrue,
      );
      expect(
        canCheckFinding(
          finding: _finding('f'),
          viewerEmail: 'b@x.com',
          hasOwnCheck: true,
        ),
        isFalse,
      );
    });

    test('nobody checks their own finding, or one an admin has not shown', () {
      expect(
        canCheckFinding(
          finding: _finding('f'),
          viewerEmail: 'a@x.com',
          hasOwnCheck: false,
        ),
        isFalse,
      );
      expect(
        canCheckFinding(
          finding: _finding('f', shown: false),
          viewerEmail: 'b@x.com',
          hasOwnCheck: false,
        ),
        isFalse,
      );
    });
  });

  group('what a viewer sees', () {
    test(
        'a finding waiting for an admin is seen by its author and an admin only',
        () {
      final waiting = _finding('w', shown: false, by: 'a@x.com');
      List<StudyFinding> seen(String who, {bool admin = false}) =>
          visibleStudyFindings(
            findings: [waiting],
            viewerEmail: who,
            isAdmin: admin,
          );
      expect(seen('a@x.com'), hasLength(1));
      expect(seen('b@x.com'), isEmpty);
      expect(seen('b@x.com', admin: true), hasLength(1));
    });
  });

  group('reading order', () {
    test('pinned first, then the most checked, then the newest', () {
      final old = DateTime(2026, 10, 1);
      final recent = DateTime(2026, 11, 1);
      final sorted = sortStudyFindings([
        _finding('quiet', at: recent),
        _finding('old-checked', confirm: 3, at: old),
        _finding('pinned', pinned: true, at: old),
        _finding('new-checked', confirm: 3, at: recent),
      ]);
      expect(
        sorted.map((f) => f.id),
        ['pinned', 'new-checked', 'old-checked', 'quiet'],
      );
    });
  });

  group('a stored finding', () {
    test('needs a result and a method, and its counts never read below zero',
        () {
      expect(
        StudyFinding.fromMap('f', {'text': 'Done', 'method': ''}),
        isNull,
      );
      expect(
        StudyFinding.fromMap('f', {'text': '  ', 'method': 'Checked'}),
        isNull,
      );
      final read = StudyFinding.fromMap('f', {
        'text': 'Done',
        'method': 'Checked',
        'confirmCount': -2,
        'challengeCount': 1,
      });
      expect(read?.confirmCount, 0);
      expect(read?.challengeCount, 1);
      expect(read?.checkCount, 1);
      expect(read?.shown, isTrue);
      expect(read?.pinned, isFalse);
    });
  });

  group('a stored check', () {
    test('reads its verdict, and drops one the app does not know', () {
      expect(
        StudyFindingCheck.fromMap('b@x.com', {'verdict': 'confirm'})?.verdict,
        FindingVerdict.confirm,
      );
      expect(
        StudyFindingCheck.fromMap(
            'b@x.com', {'verdict': 'challenge', 'note': ' Old key '})?.note,
        'Old key',
      );
      expect(
          StudyFindingCheck.fromMap('b@x.com', {'verdict': 'maybe'}), isNull);
    });
  });
}
