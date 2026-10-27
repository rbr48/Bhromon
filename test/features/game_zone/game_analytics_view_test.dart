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
}
