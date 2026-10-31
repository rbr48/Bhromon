import '../models/family_date_models.dart';
import '../models/family_task_models.dart';
import '../models/safety_alert_models.dart';
import '../models/tour_activity_models.dart';
import '../models/tour_group.dart';
import 'family_date_rules.dart';
import 'notice_engine.dart';

/// What a family circle needs to see at a glance: what is coming up, what is still
/// open on the shared list, who has checked in today, and what is on the board.
class FamilyHomeSummary {
  const FamilyHomeSummary({
    required this.nextDates,
    required this.toBuy,
    required this.toDo,
    required this.checkedInToday,
    required this.activeMembers,
    required this.needMyReply,
    this.latestNotice,
  });

  /// Up to three dates that are today or coming up soon, soonest first.
  final List<FamilyDate> nextDates;

  /// Open items to buy, and open items to do.
  final int toBuy;
  final int toDo;

  /// How many active members checked in today, out of [activeMembers].
  final int checkedInToday;
  final int activeMembers;

  /// Notices that still need this member's answer.
  final int needMyReply;

  /// The first notice on the board, or null when the board is empty.
  final TourNotice? latestNotice;
}

/// Builds the family's home summary. Inputs are the live lists, so the summary is
/// the same as the screens it links to. Pure, so it is tested with fixed times.
FamilyHomeSummary summarizeFamilyHome({
  required List<FamilyDate> dates,
  required List<FamilyTask> tasks,
  required List<TourNotice> notices,
  required List<BatteryTelemetry> telemetry,
  required List<TourMember> members,
  required String me,
  required DateTime now,
}) {
  final today = FamilyDateRules.dateOnly(now);
  final nextDates = [
    for (final section in FamilyDateRules.sections(dates, today))
      if (section.timing == FamilyDateTiming.today ||
          section.timing == FamilyDateTiming.soon)
        ...section.items,
  ].take(3).toList();

  var toBuy = 0;
  var toDo = 0;
  for (final task in tasks) {
    if (task.done) continue;
    if (task.kind == FamilyTaskKind.shopping) {
      toBuy++;
    } else {
      toDo++;
    }
  }

  final activeEmails = {for (final m in members) m.email};
  final todayKey = FamilyDateRules.dayKey(now);
  final checkedIn = {
    for (final t in telemetry)
      if (t.safeAt != null &&
          activeEmails.contains(t.email) &&
          FamilyDateRules.dayKey(t.safeAt!) == todayKey)
        t.email,
  };

  final board =
      NoticeEngine.filter(notices, NoticeFilter.all, me: me, now: now);
  return FamilyHomeSummary(
    nextDates: nextDates,
    toBuy: toBuy,
    toDo: toDo,
    checkedInToday: checkedIn.length,
    activeMembers: members.length,
    needMyReply:
        NoticeEngine.filter(notices, NoticeFilter.needsMe, me: me, now: now)
            .length,
    latestNotice: board.firstOrNull,
  );
}
