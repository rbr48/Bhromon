import 'dart:async';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/official_feed/data/official_feed_repository.dart';
import 'package:bhromon/features/official_feed/domain/official_feed_choice.dart';
import 'package:bhromon/features/official_feed/domain/official_reel.dart';
import 'package:bhromon/features/official_feed/presentation/official_feed_entry_card.dart';
import 'package:bhromon/features/official_feed/presentation/official_feed_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _reel = OfficialReel(
  id: 'p1',
  videoUrl: 'https://bhromon.fun/media/official/reels/p1.mp4',
  caption: 'Welcome to Bhromon',
);

/// Reads nothing from Firestore. [onWatch] gives the stream for each read, numbered from 1.
class _FakeFeed extends OfficialFeedRepository {
  _FakeFeed(this.onWatch);

  final Stream<List<OfficialReel>> Function(int call) onWatch;
  int watchCalls = 0;
  final List<bool> followCalls = <bool>[];

  @override
  Stream<List<OfficialReel>> watchReels({int limit = 50}) {
    watchCalls++;
    return onWatch(watchCalls);
  }

  @override
  Future<void> setFollowing(bool follow) async {
    followCalls.add(follow);
  }
}

/// The feed with its answer kept in memory, so no Hive box is opened in a test.
OfficialFeedScreen _screen(OfficialFeedRepository repository) =>
    OfficialFeedScreen(
      repository: repository,
      loadChoice: () async => OfficialFeedChoice.unanswered,
      saveChoice: (_) async {},
    );

/// Shows [home] in English. The localizations load after the first frame, so this pumps
/// twice. There is no settle: the spinner keeps animating.
Future<void> _pump(WidgetTester tester, Widget home) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      DefaultMaterialLocalizations.delegate,
      DefaultWidgetsLocalizations.delegate,
    ],
    home: home,
  ));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('shows a spinner while the feed loads', (tester) async {
    final never = StreamController<List<OfficialReel>>();
    addTearDown(never.close);

    await _pump(tester, _screen(_FakeFeed((_) => never.stream)));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('says the feed is empty when it has no posts', (tester) async {
    await _pump(
      tester,
      _screen(_FakeFeed((_) => Stream.value(const <OfficialReel>[]))),
    );

    expect(
      find.text(
          'No posts yet. New posts from the Bhromon team will appear here.'),
      findsOneWidget,
    );
  });

  testWidgets('a failed load says so, and Try again listens once more',
      (tester) async {
    final fake = _FakeFeed((call) => call == 1
        ? Stream.error(Exception('offline'))
        : Stream.value(const [_reel]));
    await _pump(tester, _screen(fake));

    expect(
      find.text(
          'The feed could not be loaded. Check your connection and try again.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();

    expect(fake.watchCalls, 2);
    expect(find.text('Welcome to Bhromon'), findsOneWidget);
  });

  testWidgets('a reel shows its caption and the Official badge',
      (tester) async {
    await _pump(
      tester,
      _screen(_FakeFeed((_) => Stream.value(const [_reel]))),
    );

    expect(find.text('Welcome to Bhromon'), findsOneWidget);
    expect(find.text('Official'), findsOneWidget);
  });

  testWidgets(
      'an image post renders its image with BoxFit.contain so photos are not cropped',
      (tester) async {
    const imageReel = OfficialReel(
      id: 'img1',
      imageUrl: 'https://bhromon.fun/media/official/images/img1.webp',
      caption: 'Landscape Photo',
    );
    await _pump(
      tester,
      _screen(_FakeFeed((_) => Stream.value(const [imageReel]))),
    );

    expect(find.text('Landscape Photo'), findsOneWidget);
    final cachedImage =
        tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(cachedImage.fit, BoxFit.contain);
  });

  testWidgets('the bell turns new-post notifications on and off',
      (tester) async {
    final fake = _FakeFeed((_) => Stream.value(const [_reel]));
    await _pump(tester, _screen(fake));

    await tester.tap(find.byTooltip('Notifications off. Tap to follow.'));
    await tester.pump();
    expect(fake.followCalls, [true]);
    expect(
      find.byTooltip('Notifications on. Tap to turn them off.'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Notifications on. Tap to turn them off.'));
    await tester.pump();
    expect(fake.followCalls, [true, false]);
  });

  testWidgets('the entry card opens the official feed', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const Scaffold(body: OfficialFeedEntryCard()),
      ),
      GoRoute(
        path: '/official-feed',
        builder: (context, state) => const Scaffold(body: Text('feed page')),
      ),
    ]);
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router,
      locale: const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('bn')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
    ));
    await tester.pumpAndSettle();

    expect(
      find.text(
          'Reels and updates from the Bhromon team. Anyone signed in can read them.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Official feed'));
    await tester.pumpAndSettle();
    expect(find.text('feed page'), findsOneWidget);
  });
}
