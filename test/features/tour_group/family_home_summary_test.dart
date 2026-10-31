import 'package:bhromon/features/tour_group/domain/models/family_date_models.dart';
import 'package:bhromon/features/tour_group/domain/models/family_task_models.dart';
import 'package:bhromon/features/tour_group/domain/models/safety_alert_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_activity_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/family_home_summary.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 31, 9);

TourMember _member(String email) => TourMember(
      tourId: 'f',
      email: email,
      displayName: email.split('@').first,
      role: TourRole.member,
      status: TourMemberStatus.active,
      joinedAt: DateTime(2026),
    );

FamilyDate _date(String id,
        {String startOn = '2000-10-31',
        FamilyRecurrence recurrence = FamilyRecurrence.yearly}) =>
    FamilyDate(
      id: id,
      title: 'Date $id',
      kind: FamilyDateKind.birthday,
      recurrence: recurrence,
      startOn: startOn,
      nextOn: startOn,
      remindDays: 1,
    );

TourNotice _notice(String id,
        {bool requireAck = false,
        List<String> ackBy = const [],
        DateTime? createdAt}) =>
    TourNotice(
      id: id,
      title: 'Notice $id',
      content: '',
      author: 'Asha',
      createdAt: createdAt ?? DateTime(2026, 10, 30),
      kind: NoticeKind.announcement,
      requireAck: requireAck,
      ackBy: ackBy,
    );

void main() {
  group('summarizeFamilyHome', () {
    test('lists up to three dates in the next thirty days, soonest first', () {
      final summary = summarizeFamilyHome(
        dates: [
          _date('far', startOn: '2000-12-25'),
          _date('today', startOn: '2000-10-31'),
          _date('soon', startOn: '2000-11-02'),
          _date('within', startOn: '2000-11-20'),
          _date('fourth', startOn: '2000-11-25'),
          _date('past',
              startOn: '2026-10-01', recurrence: FamilyRecurrence.once),
        ],
        tasks: const [],
        notices: const [],
        telemetry: const [],
        members: const [],
        me: 'asha@x.com',
        now: _now,
      );
      // Three of the dates in the next thirty days; the far and past ones are left out.
      expect(summary.nextDates.map((d) => d.id).toList(),
          ['today', 'soon', 'within']);
    });

    test('counts open items to buy and to do, and leaves out ticked ones', () {
      final summary = summarizeFamilyHome(
        dates: const [],
        tasks: const [
          FamilyTask(id: 'a', title: 'Rice', kind: FamilyTaskKind.shopping),
          FamilyTask(
              id: 'b',
              title: 'Milk',
              kind: FamilyTaskKind.shopping,
              done: true),
          FamilyTask(id: 'c', title: 'Plumber', kind: FamilyTaskKind.todo),
        ],
        notices: const [],
        telemetry: const [],
        members: const [],
        me: 'asha@x.com',
        now: _now,
      );
      expect(summary.toBuy, 1);
      expect(summary.toDo, 1);
    });

    test('counts check-ins made today by active members only', () {
      final members = [
        _member('asha@x.com'),
        _member('babu@x.com'),
        _member('chitra@x.com')
      ];
      final summary = summarizeFamilyHome(
        dates: const [],
        tasks: const [],
        notices: const [],
        telemetry: [
          BatteryTelemetry(
              email: 'asha@x.com',
              name: 'Asha',
              safeAt: DateTime(2026, 10, 31, 7)),
          BatteryTelemetry(
              email: 'babu@x.com',
              name: 'Babu',
              safeAt: DateTime(2026, 10, 30, 22)),
          BatteryTelemetry(
              email: 'gone@x.com',
              name: 'Gone',
              safeAt: DateTime(2026, 10, 31, 8)),
        ],
        members: members,
        me: 'asha@x.com',
        now: _now,
      );
      expect(summary.checkedInToday, 1,
          reason: 'yesterday and a former member do not count');
      expect(summary.activeMembers, 3);
    });

    test(
        'counts notices that need this member, and shows the first on the board',
        () {
      final summary = summarizeFamilyHome(
        dates: const [],
        tasks: const [],
        notices: [
          _notice('ask', requireAck: true),
          _notice('answered', requireAck: true, ackBy: ['asha@x.com']),
          _notice('plain'),
        ],
        telemetry: const [],
        members: const [],
        me: 'asha@x.com',
        now: _now,
      );
      expect(summary.needMyReply, 1);
      expect(summary.latestNotice, isNotNull);
    });

    test('an empty family has nothing to show, and no notice', () {
      final summary = summarizeFamilyHome(
        dates: const [],
        tasks: const [],
        notices: const [],
        telemetry: const [],
        members: const [],
        me: 'asha@x.com',
        now: _now,
      );
      expect(summary.nextDates, isEmpty);
      expect(summary.toBuy, 0);
      expect(summary.toDo, 0);
      expect(summary.checkedInToday, 0);
      expect(summary.needMyReply, 0);
      expect(summary.latestNotice, isNull);
    });
  });
}
