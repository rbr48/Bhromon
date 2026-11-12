import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/notifications/data/notification_center_repository.dart';
import 'package:bhromon/features/notifications/presentation/widgets/notification_bell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// The bell answers from a fixed set of entries and a fixed last-visit time.

final _seen = DateTime(2026, 11, 11, 9);
final _arrived = DateTime(2026, 11, 12, 10);

AppNotification _entry(String id, {bool read = false, DateTime? at}) =>
    AppNotification(
      id: id,
      title: id,
      body: '',
      action: null,
      uid: null,
      itemId: null,
      tourId: null,
      imageUrl: null,
      timestamp: at ?? _arrived,
      read: read,
    );

class _FakeRepository extends NotificationCenterRepository {
  _FakeRepository(this.entries);

  final List<AppNotification> entries;

  @override
  Stream<List<AppNotification>> watch(String uid) => Stream.value(entries);

  @override
  Future<DateTime> seenAt(String uid) async => _seen;
}

Future<void> _pump(WidgetTester tester, NotificationCenterRepository repo,
    {String? uid = 'u1'}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(
          appBar: AppBar(
            actions: [NotificationBell(uid: uid, repository: repo)],
          ),
          body: const SizedBox(),
        ),
      ),
      GoRoute(
        path: '/notifications',
        builder: (_, __) => const Text('the list'),
      ),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    routerConfig: router,
  ));
  await tester.pumpAndSettle();
}

bool _badgeShown(WidgetTester tester) =>
    tester.widget<Badge>(find.byType(Badge)).isLabelVisible;

void main() {
  testWidgets(
      'the badge counts the unread entries that arrived since the last visit',
      (tester) async {
    final repo = _FakeRepository([
      _entry('new'),
      _entry('newRead', read: true),
      _entry('old', at: DateTime(2026, 11, 1), read: false),
    ]);
    await _pump(tester, repo);

    expect(_badgeShown(tester), isTrue);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('the badge is hidden when nothing new is unread', (tester) async {
    final repo = _FakeRepository([_entry('a', read: true)]);
    await _pump(tester, repo);

    expect(_badgeShown(tester), isFalse);
  });

  testWidgets('tapping the bell opens the notification list', (tester) async {
    final repo = _FakeRepository([_entry('a')]);
    await _pump(tester, repo);

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(find.text('the list'), findsOneWidget);
  });

  testWidgets('the bell is still visible when signed out (uid is null)',
      (tester) async {
    final repo = _FakeRepository([]);
    await _pump(tester, repo, uid: null);

    expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
    expect(_badgeShown(tester), isFalse);

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(find.text('the list'), findsOneWidget);
  });
}
