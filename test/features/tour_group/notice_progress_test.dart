import 'package:bhromon/features/tour_group/domain/models/tour_activity_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/notice_engine.dart';
import 'package:flutter_test/flutter_test.dart';

TourMember _member(String email, {String? name}) => TourMember(
      tourId: 'office_tour',
      email: email,
      displayName: name ?? email.split('@').first,
      role: TourRole.member,
      status: TourMemberStatus.active,
      joinedAt: DateTime(2026, 1, 1),
    );

void main() {
  group('NoticeEngine.answers and progress calculations', () {
    final members = [
      _member('ceo@office.com', name: 'Chief'),
      _member('dev1@office.com', name: 'Dev One'),
      _member('dev2@office.com', name: 'Dev Two'),
      _member('hr@office.com', name: 'HR Lead'),
    ];

    test('all members waiting when no one has acknowledged', () {
      final notice = TourNotice(
        id: 'n1',
        title: 'Quarterly Townhall',
        content: 'All hands meeting',
        author: 'Chief',
        createdAt: DateTime(2026, 3, 1),
        requireAck: true,
        ackBy: const [],
      );

      final answers = NoticeEngine.answers(notice, members);
      expect(answers.total, equals(4));
      expect(answers.answered, isEmpty);
      expect(answers.waiting.length, equals(4));
      expect(answers.ratio, equals(0.0));
    });

    test('partial answers calculate exact ratio and correct member lists', () {
      final notice = TourNotice(
        id: 'n2',
        title: 'Office Safety Protocol',
        content: 'Please acknowledge',
        author: 'HR Lead',
        createdAt: DateTime(2026, 3, 2),
        requireAck: true,
        ackBy: const ['dev1@office.com', 'hr@office.com'],
      );

      final answers = NoticeEngine.answers(notice, members);
      expect(answers.total, equals(4));
      expect(answers.answered.length, equals(2));
      expect(answers.waiting.length, equals(2));
      expect(answers.ratio, closeTo(0.5, 0.001));
      expect(answers.answered.map((m) => m.email),
          containsAll(['dev1@office.com', 'hr@office.com']));
      expect(answers.waiting.map((m) => m.email),
          containsAll(['ceo@office.com', 'dev2@office.com']));
    });

    test('100% completion when all members have acknowledged', () {
      final notice = TourNotice(
        id: 'n3',
        title: 'Team Outing Vote',
        content: 'Confirm headcount',
        author: 'Chief',
        createdAt: DateTime(2026, 3, 3),
        kind: NoticeKind.rollcall,
        ackBy: const [
          'ceo@office.com',
          'dev1@office.com',
          'dev2@office.com',
          'hr@office.com'
        ],
      );

      final answers = NoticeEngine.answers(notice, members);
      expect(answers.total, equals(4));
      expect(answers.answered.length, equals(4));
      expect(answers.waiting, isEmpty);
      expect(answers.ratio, equals(1.0));
    });

    test('answers from former/unlisted members are omitted', () {
      final notice = TourNotice(
        id: 'n4',
        title: 'Old Notice',
        content: 'Archive notice',
        author: 'Chief',
        createdAt: DateTime(2026, 1, 1),
        requireAck: true,
        ackBy: const ['former_employee@office.com', 'dev1@office.com'],
      );

      final answers = NoticeEngine.answers(notice, members);
      expect(answers.total, equals(4));
      expect(answers.answered.length, equals(1));
      expect(answers.answered.first.email, equals('dev1@office.com'));
      expect(answers.waiting.length, equals(3));
      expect(answers.ratio, closeTo(0.25, 0.001));
    });

    test('empty member list handles gracefully with 0 ratio', () {
      final notice = TourNotice(
        id: 'n5',
        title: 'Notice without members',
        content: 'Details',
        author: 'Chief',
        createdAt: DateTime(2026, 1, 1),
        requireAck: true,
        ackBy: const ['dev1@office.com'],
      );

      final answers = NoticeEngine.answers(notice, const []);
      expect(answers.total, equals(0));
      expect(answers.answered, isEmpty);
      expect(answers.waiting, isEmpty);
      expect(answers.ratio, equals(0.0));
    });
  });
}
