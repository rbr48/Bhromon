import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/game_zone/domain/models/game_analytics_models.dart';
import 'package:bhromon/features/game_zone/presentation/widgets/game_analytics_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: child,
    ),
  );
}

void main() {
  testWidgets(
      'GameAnalyticsView renders overview card and game breakdown cards',
      (tester) async {
    const analytics = PlayerGameAnalytics(
      gameStats: {
        OnlineGameType.ludo: GameStatItem(
          gameType: OnlineGameType.ludo,
          matchesPlayed: 15,
          matchesWon: 12,
          currentStreak: 4,
          bestStreak: 6,
          highestScore: 120,
        ),
        OnlineGameType.chess: GameStatItem(
          gameType: OnlineGameType.chess,
          matchesPlayed: 10,
          matchesWon: 6,
          currentStreak: 0,
          bestStreak: 3,
        ),
      },
    );

    await tester.pumpWidget(
      _wrap(
        const GameAnalyticsView(analytics: analytics),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 1. Title and Overview are rendered
    expect(find.textContaining('খেলা ভিত্তিক পরিসংখ্যান'), findsOneWidget);
    expect(find.textContaining('Ludo Express'), findsWidgets);
    expect(find.textContaining('Chess'), findsWidgets);

    // 2. Win rate & streaks are calculated and shown
    expect(find.textContaining('72%'), findsOneWidget); // 18 / 25
    expect(find.textContaining('Master'), findsWidgets);
  });

  testWidgets('GameAnalyticsView switches to Match History tab and displays records',
      (tester) async {
    final analytics = PlayerGameAnalytics(
      gameStats: const {},
      recentMatches: [
        GameMatchRecord(
          id: '1',
          gameType: OnlineGameType.card29,
          won: true,
          score: 28,
          timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
          mode: 'Online Table',
          details: 'High Bid 24 Made',
        ),
        GameMatchRecord(
          id: '2',
          gameType: OnlineGameType.carrom,
          won: false,
          score: 15,
          timestamp: DateTime.now().subtract(const Duration(hours: 2)),
          mode: 'Pass & Play',
        ),
      ],
    );

    await tester.pumpWidget(
      _wrap(
        GameAnalyticsView(analytics: analytics),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to History tab
    await tester.tap(find.textContaining('ম্যাচ হিস্টোরি'));
    await tester.pumpAndSettle();

    expect(find.text('WON'), findsOneWidget);
    expect(find.text('LOST'), findsOneWidget);
    expect(find.text('High Bid 24 Made'), findsOneWidget);
    expect(find.text('28 pts'), findsOneWidget);
  });

  testWidgets('GameAnalyticsView switches to Tour Leaderboard tab and handles empty tour state',
      (tester) async {
    const analytics = PlayerGameAnalytics(gameStats: {});

    await tester.pumpWidget(
      _wrap(
        const GameAnalyticsView(analytics: analytics, activeTourId: null),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to Tour Leaderboard tab
    await tester.tap(find.textContaining('ট্যুর লিডারবোর্ড'));
    await tester.pumpAndSettle();

    expect(find.textContaining('ট্যুর লিডারবোর্ড সক্রিয় নয়'), findsOneWidget);
  });
}
