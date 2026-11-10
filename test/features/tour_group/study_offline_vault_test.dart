import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/domain/models/study_offline_vault_models.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/study/study_offline_vault_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildTestApp(
    Widget child, {
    Locale locale = const Locale('en'),
  }) {
    return MaterialApp(
      locale: locale,
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

  final testPackage = StudyOfflinePackage(
    tourId: 'tour_test',
    bookId: 'book_lpgb',
    bookTitle: 'Laws & Practice of General Banking',
    cachedAt: DateTime(2026, 11, 10, 15, 0),
    totalSizeBytes: 850000,
    chapters: const [],
    materials: const [],
    contents: const {'m1': 'answer 1'},
  );

  group('StudyOfflineVaultCard Widget Tests', () {
    testWidgets(
        'renders uncached state with save button and triggers onDownload',
        (tester) async {
      var downloaded = false;

      await tester.pumpWidget(
        buildTestApp(
          StudyOfflineVaultCard(
            package: null,
            onDownload: () => downloaded = true,
            onRemove: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Offline Study Vault'), findsOneWidget);
      expect(
        find.text(
            'Download full book & examiner-grade solutions for commute and zero-network banking study.'),
        findsOneWidget,
      );
      expect(find.text('Save Offline'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_download_outlined), findsOneWidget);

      await tester.tap(find.text('Save Offline'));
      expect(downloaded, isTrue);
    });

    testWidgets('renders downloading state with circular progress indicator',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          StudyOfflineVaultCard(
            package: null,
            isDownloading: true,
            onDownload: () {},
            onRemove: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Save Offline'), findsNothing);
    });

    testWidgets(
        'renders cached state with offline badge, formatted size, and menu actions',
        (tester) async {
      var removed = false;

      await tester.pumpWidget(
        buildTestApp(
          StudyOfflineVaultCard(
            package: testPackage,
            onDownload: () {},
            onRemove: () => removed = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Offline Study Vault'), findsOneWidget);
      expect(find.text('Offline Ready'), findsOneWidget);
      expect(find.byIcon(Icons.offline_pin_rounded), findsOneWidget);
      expect(
        find.text('Saved on device · 0 materials (830 KB) · 100% Native'),
        findsOneWidget,
      );

      // Open popup menu
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Update Offline Cache'), findsOneWidget);
      expect(find.text('Remove from Device'), findsOneWidget);

      await tester.tap(find.text('Remove from Device'));
      await tester.pumpAndSettle();
      expect(removed, isTrue);
    });

    testWidgets('renders in Bengali locale with proper translations',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          StudyOfflineVaultCard(
            package: null,
            onDownload: () {},
            onRemove: () {},
          ),
          locale: const Locale('bn'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('অফলাইন স্টাডি ভল্ট'), findsOneWidget);
      expect(find.text('অফলাইনে সংরক্ষণ'), findsOneWidget);
      expect(
        find.text(
            'কমিউট ও দুর্বল নেটওয়ার্কেও নিরবচ্ছিন্ন প্রস্তুতির জন্য পুরো বই ও সমাধান অফলাইনে নামিয়ে রাখুন।'),
        findsOneWidget,
      );
    });
  });
}
