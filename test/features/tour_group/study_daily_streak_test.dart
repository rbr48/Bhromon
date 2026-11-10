import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/domain/models/study_streak_models.dart';
import 'package:bhromon/features/tour_group/domain/services/study_daily_streak_rules.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/study/branch_study_hall_sheet.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/study/study_daily_streak_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildTestApp(
    Widget child, {
    Locale locale = const Locale('en'),
    ThemeData? theme,
  }) {
    return MaterialApp(
      locale: locale,
      theme: theme ?? ThemeData.light(),
      supportedLocales: const [Locale('en'), Locale('bn')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    );
  }

  group('StudyDailyStreakCard Widget Tests', () {
    testWidgets(
        'renders streak counter, flame icon, tier, and 7-day indicators',
        (tester) async {
      const streak = StudyDailyStreak(
        currentStreak: 5,
        bestStreak: 12,
        isActiveToday: true,
        hasUsedFreeze: false,
        weekDaysActive: [true, true, true, true, true, false, false],
        tier: StudyStreakTier.flame,
      );

      await tester.pumpWidget(
        buildTestApp(
          const StudyDailyStreakCard(streak: streak),
        ),
      );
      await tester.pumpAndSettle();

      // Verify streak days & flame icon
      expect(find.text('5 Day Streak'), findsOneWidget);
      expect(find.text('Best: 12 days'), findsOneWidget);
      expect(find.text('🔥'), findsWidgets);
      expect(find.text('Active Today!'), findsOneWidget);
      expect(find.text('Steady Flame'), findsOneWidget);
      expect(find.text('Branch Study Hall'), findsOneWidget);
    });

    testWidgets('action required status shown when not active today',
        (tester) async {
      const streak = StudyDailyStreak(
        currentStreak: 3,
        bestStreak: 7,
        isActiveToday: false,
        hasUsedFreeze: false,
        weekDaysActive: [true, true, false, false, false, false, false],
        tier: StudyStreakTier.flame,
      );

      await tester.pumpWidget(
        buildTestApp(
          const StudyDailyStreakCard(streak: streak),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Study today to keep streak!'), findsOneWidget);
    });

    testWidgets('tapping branch study hall triggers callback or sheet',
        (tester) async {
      var tapped = false;
      const streak = StudyDailyStreak(
        currentStreak: 4,
        bestStreak: 4,
        isActiveToday: true,
      );

      await tester.pumpWidget(
        buildTestApp(
          StudyDailyStreakCard(
            streak: streak,
            onOpenBranchHall: () => tapped = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final button = find.text('Branch Study Hall');
      expect(button, findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });
  });

  group('BranchStudyHallSheet Widget Tests', () {
    testWidgets(
        'renders leaderboard, bank filter chips, and cheering colleague',
        (tester) async {
      final peers = StudyDailyStreakRules.fallbackStandings(
        myEmail: 'me@sonali.org',
        myName: 'Izhaan',
        myStreak: 12,
        myChapters: 6,
        myExams: 3,
      );

      await tester.pumpWidget(
        buildTestApp(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => BranchStudyHallSheet.show(
                context,
                standings: peers,
              ),
              child: const Text('Open Hall'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open sheet
      await tester.tap(find.text('Open Hall'));
      await tester.pumpAndSettle();

      // Header and summary metrics
      expect(find.text('Branch Study Hall'), findsOneWidget);
      expect(find.text('Colleague accountability & rankings'), findsOneWidget);
      expect(find.text('All Banks'), findsWidgets);

      // Verify current user details
      expect(find.text('Izhaan'), findsOneWidget);
      expect(find.text('YOU'), findsOneWidget);

      // Verify colleagues
      expect(find.text('Tahmina Akhter'), findsOneWidget);
      expect(find.text('Mahmudul Hasan'), findsOneWidget);

      // Tap Cheer button on a colleague
      final cheerButton = find.text('Cheer').first;
      await tester.tap(cheerButton);
      await tester.pump(); // Start snackbar animation
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SnackBar), findsOneWidget);
    });
  });
}
