import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_activity_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/notice_engine.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/notice/notice_composer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 12, 21, 8);

TourNotice _n(
  String id, {
  NoticeKind kind = NoticeKind.announcement,
  DateTime? eventAt,
  DateTime? expiresAt,
  DateTime? createdAt,
  bool pinned = false,
  bool urgent = false,
  bool requireAck = false,
  List<String> ackBy = const [],
}) =>
    TourNotice(
      id: id,
      title: id,
      content: '',
      author: 'Lead',
      createdAt: createdAt ?? DateTime(2026, 12, 20),
      kind: kind,
      eventAt: eventAt,
      expiresAt: expiresAt ?? NoticeEngine.defaultExpiry(kind, eventAt),
      pinned: pinned,
      urgent: urgent,
      requireAck: requireAck,
      ackBy: ackBy,
    );

TourMember _m(String email) => TourMember(
      tourId: 't',
      email: email,
      displayName: email.split('@').first,
      role: TourRole.member,
      status: TourMemberStatus.active,
      joinedAt: DateTime(2026),
    );

void main() {
  group('board order and filters', () {
    final bus = _n('bus',
        kind: NoticeKind.schedule, eventAt: _now.add(const Duration(hours: 2)));
    final breakfast = _n('breakfast',
        kind: NoticeKind.schedule,
        eventAt: _now.add(const Duration(minutes: 10)));
    final yesterday = _n('yesterday',
        kind: NoticeKind.schedule,
        eventAt: _now.subtract(const Duration(hours: 20)));
    final rules = _n('rules', pinned: true);
    final storm = _n('storm', kind: NoticeKind.emergency, urgent: true);
    final old = _n('old', createdAt: DateTime(2026, 12, 1));
    final fresh = _n('fresh', createdAt: DateTime(2026, 12, 21, 7));
    final all = [old, bus, yesterday, fresh, breakfast, storm, rules];

    test('pinned, then urgent, then soonest, then newest; archive last', () {
      expect(NoticeEngine.sorted(all, _now).map((n) => n.id), [
        'rules',
        'storm',
        'breakfast',
        'bus',
        'fresh',
        'old',
        'yesterday',
      ]);
    });

    test('a timed notice expires a few hours after it happens', () {
      expect(NoticeEngine.isArchived(yesterday, _now), isTrue);
      expect(NoticeEngine.isArchived(bus, _now), isFalse);
      expect(NoticeEngine.defaultExpiry(NoticeKind.announcement, _now), isNull);
      expect(NoticeEngine.timing(breakfast, _now), NoticeTiming.now);
      expect(NoticeEngine.timing(bus, _now), NoticeTiming.upcoming);
    });

    test('filters', () {
      List<String> ids(NoticeFilter f) =>
          NoticeEngine.filter(all, f, me: 'a@x.com', now: _now)
              .map((n) => n.id)
              .toList();
      expect(ids(NoticeFilter.all), isNot(contains('yesterday')));
      expect(ids(NoticeFilter.pinned), ['rules']);
      expect(ids(NoticeFilter.upcoming), ['breakfast', 'bus']);
      expect(ids(NoticeFilter.archive), ['yesterday']);
      expect(NoticeEngine.nextUp(all, _now)?.id, 'breakfast');
    });

    test("today's schedule is the day's timed notices in order", () {
      expect(NoticeEngine.scheduleOn(all, _now).map((n) => n.id),
          ['breakfast', 'bus']);
    });
  });

  group('answers', () {
    final call = _n('call',
        kind: NoticeKind.rollcall,
        eventAt: _now,
        ackBy: ['a@x.com', 'gone@x.com']);
    final members = [_m('a@x.com'), _m('b@x.com'), _m('c@x.com')];

    test('a roll call splits members into here and missing', () {
      final a = NoticeEngine.answers(call, members);
      expect(a.answered.map((m) => m.email), ['a@x.com']);
      expect(a.waiting.map((m) => m.email), ['b@x.com', 'c@x.com']);
      expect(a.total, 3, reason: 'someone who left is not counted');
    });

    test('a roll call always asks; it needs only those who have not answered',
        () {
      expect(call.asksAnswer, isTrue);
      expect(NoticeEngine.needsMe(call, 'a@x.com', _now), isFalse);
      expect(NoticeEngine.needsMe(call, 'B@x.com', _now), isTrue);
      expect(NoticeEngine.needsMe(_n('plain'), 'b@x.com', _now), isFalse);
    });
  });

  group('links', () {
    test('the calendar link carries the time in UTC and the place', () {
      final n = TourNotice(
        id: 'n',
        title: 'Ship boarding',
        content: 'Bring your NID',
        author: 'Lead',
        createdAt: _now,
        kind: NoticeKind.schedule,
        eventAt: DateTime.utc(2026, 12, 22, 1, 30),
        place: 'Teknaf jetty',
      );
      final uri = NoticeEngine.calendarUri(n, tourName: 'Saint Martin')!;
      expect(uri.host, 'calendar.google.com');
      expect(uri.queryParameters['dates'], '20261222T013000Z/20261222T023000Z');
      expect(uri.queryParameters['text'], 'Ship boarding · Saint Martin');
      expect(uri.queryParameters['location'], 'Teknaf jetty');
      expect(NoticeEngine.mapUri(n)!.queryParameters['query'], 'Teknaf jetty');
      expect(NoticeEngine.calendarUri(_n('x')), isNull);
    });

    test('an old notice reads as an announcement with no answers', () {
      final n = TourNotice.fromMap('o', {
        'title': 'Hello',
        'urgent': true,
        'ackBy': ['A@X.com']
      });
      expect(n.kind, NoticeKind.announcement);
      expect(n.eventAt, isNull);
      expect(n.ackedBy('a@x.com'), isTrue);
      expect(n.toEditableMap().containsKey('ackBy'), isFalse);
    });
  });

  testWidgets('a template fills the composer and a roll call needs a time',
      (tester) async {
    tester.view.physicalSize = const Size(411, 891) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    TourNotice? result;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('bn')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showNoticeComposer(context,
                group: null, now: DateTime(2026, 12, 21, 8, 7)),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.textContaining('Head count'), 200,
        scrollable: find
            .byWidgetPredicate((w) =>
                w is Scrollable && w.axisDirection == AxisDirection.right)
            .first);
    await tester.ensureVisible(find.textContaining('Head count'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Head count'));
    await tester.pumpAndSettle();
    // Five minutes ahead, rounded up to the quarter hour.
    expect(find.textContaining('8:15'), findsOneWidget);

    Future<void> post() async {
      await tester.scrollUntilVisible(find.text('Post'), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.text('Post'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Post'));
      await tester.pumpAndSettle();
    }

    await tester.scrollUntilVisible(find.byTooltip('Remove the time'), -300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byTooltip('Remove the time'));
    await tester.pumpAndSettle();
    await post();
    expect(find.text('This kind of notice needs a time.'), findsOneWidget);
    expect(result, isNull);

    await tester.scrollUntilVisible(find.text('In 30 min'), -300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('In 30 min'));
    await tester.pumpAndSettle();
    await post();

    expect(result, isNotNull);
    expect(result!.kind, NoticeKind.rollcall);
    expect(result!.title, 'Head count');
    expect(result!.requireAck, isTrue);
    expect(result!.eventAt, DateTime(2026, 12, 21, 8, 45));
    expect(result!.expiresAt, DateTime(2026, 12, 21, 10, 45));
  });
}
