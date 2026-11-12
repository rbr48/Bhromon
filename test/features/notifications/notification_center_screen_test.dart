import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/notifications/data/notification_center_repository.dart';
import 'package:bhromon/features/notifications/presentation/pages/notification_center_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// The list answers from a fixed set of entries and records each change. The routes it opens are
// stand-in pages, so a test can see where a tap went.

const _uid = 'u1';
final _at = DateTime(2026, 11, 12, 10);

AppNotification _entry(
  String id,
  String title, {
  bool read = false,
  String? action,
  String? tourId,
}) =>
    AppNotification(
      id: id,
      title: title,
      body: 'About $title',
      action: action,
      uid: null,
      itemId: null,
      tourId: tourId,
      imageUrl: null,
      timestamp: _at,
      read: read,
    );

class _FakeRepository extends NotificationCenterRepository {
  _FakeRepository(this.entries);

  final List<AppNotification> entries;
  final List<String> calls = [];

  @override
  Stream<List<AppNotification>> watch(String uid) => Stream.value(entries);

  @override
  Future<void> markSeen(String uid) async {}

  @override
  Future<void> markRead(String uid, String id) async => calls.add('read:$id');

  @override
  Future<void> markUnread(String uid, String id) async =>
      calls.add('unread:$id');

  @override
  Future<void> markAllRead(String uid, Iterable<AppNotification> items) async {
    calls.add('all');
  }

  @override
  Future<void> clearRead(String uid, Iterable<AppNotification> items) async {
    calls.add('clear:${readIds(items).join(',')}');
  }

  @override
  Future<void> deleteMany(String uid, Iterable<String> ids) async {
    calls.add('delete:${ids.join(',')}');
  }
}

Future<void> _pump(WidgetTester tester, _FakeRepository repo) async {
  final router = GoRouter(
    initialLocation: '/notifications',
    routes: [
      GoRoute(
        path: '/notifications',
        builder: (_, __) =>
            NotificationCenterScreen(repository: repo, uid: _uid),
      ),
      GoRoute(
        path: '/group/:tourId/meals',
        builder: (_, state) => Text('meals ${state.pathParameters['tourId']}'),
      ),
      GoRoute(
        path: '/group/:tourId/study-reading',
        builder: (_, state) =>
            Text('reading ${state.pathParameters['tourId']}'),
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

void main() {
  testWidgets('unread entries are marked, and the filter keeps only them',
      (tester) async {
    final repo = _FakeRepository([
      _entry('a', 'Alpha'),
      _entry('b', 'Beta', read: true),
    ]);
    await _pump(tester, repo);

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.byKey(const Key('notif_unread_a')), findsOneWidget);
    expect(find.byKey(const Key('notif_unread_b')), findsNothing);

    await tester.tap(find.text('Unread'));
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);
  });

  testWidgets('a tap marks the entry read and opens the group\'s meals page',
      (tester) async {
    final repo = _FakeRepository([
      _entry('a', 'Duty', action: 'bazar_duty', tourId: 't1'),
    ]);
    await _pump(tester, repo);

    await tester.tap(find.text('Duty'));
    await tester.pumpAndSettle();

    expect(repo.calls, ['read:a']);
    expect(find.text('meals t1'), findsOneWidget);
  });

  testWidgets('a study session entry opens the reading plan', (tester) async {
    final repo = _FakeRepository([
      _entry('s', 'Session', action: 'session', tourId: 't2'),
    ]);
    await _pump(tester, repo);

    await tester.tap(find.text('Session'));
    await tester.pumpAndSettle();

    expect(find.text('reading t2'), findsOneWidget);
  });

  testWidgets('an unread entry can be marked read from its menu',
      (tester) async {
    final repo = _FakeRepository([_entry('a', 'Alpha')]);
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('notif_menu_a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as read'));
    await tester.pumpAndSettle();

    expect(repo.calls, ['read:a']);
  });

  testWidgets('a read entry can be marked unread from its menu',
      (tester) async {
    final repo = _FakeRepository([_entry('b', 'Beta', read: true)]);
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('notif_menu_b')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as unread'));
    await tester.pumpAndSettle();

    expect(repo.calls, ['unread:b']);
  });

  testWidgets('mark all as read marks the whole list', (tester) async {
    final repo = _FakeRepository([_entry('a', 'Alpha')]);
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('notif_list_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark all as read'));
    await tester.pumpAndSettle();

    expect(repo.calls, ['all']);
  });

  testWidgets('clear read removes only the read entries, after a confirmation',
      (tester) async {
    final repo = _FakeRepository([
      _entry('a', 'Alpha'),
      _entry('b', 'Beta', read: true),
    ]);
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('notif_list_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear read'));
    await tester.pumpAndSettle();

    expect(find.text('Read notifications leave your list. Unread ones stay.'),
        findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Clear read'));
    await tester.pumpAndSettle();

    expect(repo.calls, ['clear:b']);
  });

  testWidgets('cancelling clear read removes nothing', (tester) async {
    final repo = _FakeRepository([_entry('b', 'Beta', read: true)]);
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('notif_list_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear read'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repo.calls, isEmpty);
  });

  testWidgets('clear read says so when nothing is read', (tester) async {
    final repo = _FakeRepository([_entry('a', 'Alpha')]);
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('notif_list_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear read'));
    await tester.pumpAndSettle();

    expect(find.text('No read notifications to clear'), findsOneWidget);
    expect(repo.calls, isEmpty);
  });

  testWidgets('swiping an entry deletes it', (tester) async {
    final repo = _FakeRepository([_entry('a', 'Alpha')]);
    await _pump(tester, repo);

    await tester.drag(find.byKey(const ValueKey('a')), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(repo.calls, ['delete:a']);
  });

  testWidgets('an empty list says there are no notifications', (tester) async {
    final repo = _FakeRepository(const []);
    await _pump(tester, repo);

    expect(find.text('No notifications yet'), findsOneWidget);
  });
}
