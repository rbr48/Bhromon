import '../models/tour_activity_models.dart';
import '../models/tour_group.dart';

/// How the board is filtered.
enum NoticeFilter { all, pinned, upcoming, needsMe, archive }

/// Where a timed notice stands against the clock.
enum NoticeTiming { none, upcoming, now, past }

/// A ready-made notice a tour leader posts in two taps. Its title and text
/// are translation keys: `notice_tpl_<id>_title` and `notice_tpl_<id>_body`.
class NoticeTemplate {
  const NoticeTemplate(this.id, this.kind,
      {this.leadMinutes, this.requireAck = false, this.urgent = false});

  final String id;
  final NoticeKind kind;

  /// How far ahead the event usually is when the notice goes out.
  final int? leadMinutes;
  final bool requireAck;
  final bool urgent;
}

const List<NoticeTemplate> kNoticeTemplates = [
  NoticeTemplate('bus_departure', NoticeKind.schedule,
      leadMinutes: 60, requireAck: true),
  NoticeTemplate('breakfast', NoticeKind.schedule, leadMinutes: 30),
  NoticeTemplate('checkout', NoticeKind.reminder, leadMinutes: 90),
  NoticeTemplate('lobby_meet', NoticeKind.meetup, leadMinutes: 30),
  NoticeTemplate('ship_boarding', NoticeKind.schedule,
      leadMinutes: 90, requireAck: true),
  NoticeTemplate('jeep', NoticeKind.schedule,
      leadMinutes: 60, requireAck: true),
  NoticeTemplate('headcount', NoticeKind.rollcall, leadMinutes: 5),
  NoticeTemplate('weather', NoticeKind.emergency,
      requireAck: true, urgent: true),
  NoticeTemplate('beach_safety', NoticeKind.rule, requireAck: true),
  NoticeTemplate('quiet_hours', NoticeKind.rule),
  NoticeTemplate('payment_due', NoticeKind.reminder),
  NoticeTemplate('lost_found', NoticeKind.announcement),
];

/// The ready-made notices for a family circle: home life, not trip logistics.
const List<NoticeTemplate> kFamilyNoticeTemplates = [
  NoticeTemplate('family_dinner', NoticeKind.meetup, leadMinutes: 30),
  NoticeTemplate('family_meeting', NoticeKind.meetup,
      leadMinutes: 60, requireAck: true),
  NoticeTemplate('school_pickup', NoticeKind.reminder, leadMinutes: 30),
  NoticeTemplate('medicine_time', NoticeKind.reminder,
      leadMinutes: 0, requireAck: true),
  NoticeTemplate('bills_due', NoticeKind.reminder),
  NoticeTemplate('shopping_list', NoticeKind.announcement),
  NoticeTemplate('home_check', NoticeKind.rollcall, leadMinutes: 60),
  NoticeTemplate('safety_check', NoticeKind.emergency,
      requireAck: true, urgent: true),
];

/// The templates offered for a circle: family or trip.
List<NoticeTemplate> noticeTemplatesFor({required bool family}) =>
    family ? kFamilyNoticeTemplates : kNoticeTemplates;

/// Who answered a notice, among the tour's members.
class NoticeAnswers {
  const NoticeAnswers(this.answered, this.waiting);

  final List<TourMember> answered;
  final List<TourMember> waiting;

  int get total => answered.length + waiting.length;
  double get ratio => total == 0 ? 0 : answered.length / total;
}

class NoticeEngine {
  NoticeEngine._();

  /// A timed notice counts as happening "now" this long either side.
  static const Duration nowWindow = Duration(minutes: 15);

  /// When a notice leaves the board if the admin does not say: a few hours
  /// after a timed one happens. Plain notices stay.
  static DateTime? defaultExpiry(NoticeKind kind, DateTime? eventAt) {
    if (eventAt == null || !kind.isTimed) return null;
    return eventAt.add(switch (kind) {
      NoticeKind.reminder => const Duration(hours: 1),
      NoticeKind.rollcall => const Duration(hours: 2),
      _ => const Duration(hours: 3),
    });
  }

  static bool isArchived(TourNotice n, DateTime now) =>
      n.expiresAt != null && now.isAfter(n.expiresAt!);

  static NoticeTiming timing(TourNotice n, DateTime now) {
    final at = n.eventAt;
    if (at == null) return NoticeTiming.none;
    final diff = at.difference(now);
    if (diff.abs() <= nowWindow) return NoticeTiming.now;
    return diff.isNegative ? NoticeTiming.past : NoticeTiming.upcoming;
  }

  /// Whether [me] still owes this notice an answer.
  static bool needsMe(TourNotice n, String me, DateTime now) =>
      n.asksAnswer && !isArchived(n, now) && !n.ackedBy(me);

  /// The board's order: pinned, then emergencies and urgent notices, then
  /// what is coming up soonest, then the rest newest first. The archive
  /// goes last, newest first.
  static List<TourNotice> sorted(List<TourNotice> notices, DateTime now) {
    int rank(TourNotice n) {
      if (isArchived(n, now)) return 5;
      if (n.pinned) return 0;
      if (n.kind == NoticeKind.emergency || n.urgent) return 1;
      final t = timing(n, now);
      if (t == NoticeTiming.now || t == NoticeTiming.upcoming) return 2;
      return 3;
    }

    return [...notices]..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        if (r != 0) return r;
        if (rank(a) == 2) return a.eventAt!.compareTo(b.eventAt!);
        return b.createdAt.compareTo(a.createdAt);
      });
  }

  static List<TourNotice> filter(
    List<TourNotice> notices,
    NoticeFilter filter, {
    required String me,
    required DateTime now,
  }) {
    final list = sorted(notices, now);
    return switch (filter) {
      NoticeFilter.all => list.where((n) => !isArchived(n, now)).toList(),
      NoticeFilter.pinned =>
        list.where((n) => n.pinned && !isArchived(n, now)).toList(),
      NoticeFilter.upcoming => list
          .where((n) =>
              !isArchived(n, now) &&
              (timing(n, now) == NoticeTiming.upcoming ||
                  timing(n, now) == NoticeTiming.now))
          .toList(),
      NoticeFilter.needsMe => list.where((n) => needsMe(n, me, now)).toList(),
      NoticeFilter.archive => list.where((n) => isArchived(n, now)).toList(),
    };
  }

  /// The next thing that happens, for the countdown at the top.
  static TourNotice? nextUp(List<TourNotice> notices, DateTime now) {
    final timed = notices
        .where((n) =>
            !isArchived(n, now) &&
            (timing(n, now) == NoticeTiming.upcoming ||
                timing(n, now) == NoticeTiming.now))
        .toList()
      ..sort((a, b) => a.eventAt!.compareTo(b.eventAt!));
    return timed.firstOrNull;
  }

  /// Timed notices on [day], in order: the day's schedule.
  static List<TourNotice> scheduleOn(List<TourNotice> notices, DateTime day) {
    bool same(DateTime d) =>
        d.year == day.year && d.month == day.month && d.day == day.day;
    return notices.where((n) => n.eventAt != null && same(n.eventAt!)).toList()
      ..sort((a, b) => a.eventAt!.compareTo(b.eventAt!));
  }

  /// Splits the active members into those who answered and those who have
  /// not. Answers from people who have left are not counted.
  static NoticeAnswers answers(TourNotice n, List<TourMember> members) {
    final answered = <TourMember>[];
    final waiting = <TourMember>[];
    for (final m in members) {
      (n.ackedBy(m.email) ? answered : waiting).add(m);
    }
    return NoticeAnswers(answered, waiting);
  }

  /// A Google Calendar link that adds the event, for members who want a
  /// phone reminder.
  static Uri? calendarUri(TourNotice n, {String? tourName}) {
    final start = n.eventAt;
    if (start == null) return null;
    final end = n.expiresAt != null && n.expiresAt!.isAfter(start)
        ? n.expiresAt!
        : start.add(const Duration(hours: 1));
    String stamp(DateTime d) {
      final u = d.toUtc();
      String two(int v) => v.toString().padLeft(2, '0');
      return '${u.year}${two(u.month)}${two(u.day)}T'
          '${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
    }

    return Uri.https('calendar.google.com', '/calendar/render', {
      'action': 'TEMPLATE',
      'text': tourName == null ? n.title : '${n.title} · $tourName',
      'dates': '${stamp(start)}/${stamp(end)}',
      if (n.content.isNotEmpty) 'details': n.content,
      if (n.place != null) 'location': n.place!,
    });
  }

  /// A map search for the notice's place when no link was given.
  static Uri? mapUri(TourNotice n) {
    final url = n.mapUrl;
    if (url != null && url.startsWith('https://')) return Uri.tryParse(url);
    final place = n.place;
    if (place == null) return null;
    return Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': place,
    });
  }
}
