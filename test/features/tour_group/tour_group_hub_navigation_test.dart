import 'dart:async';
import 'dart:io';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/pages/tour_group_hub_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

class _FakeTourGroupRepository extends TourGroupRepository {
  _FakeTourGroupRepository({required this.groupsStream});

  final Stream<List<TourGroup>> groupsStream;

  @override
  String get currentEmail => 'tester@bhromon.fun';

  @override
  Stream<List<TourGroup>> watchMyGroups() => groupsStream;

  @override
  Stream<TourGroup?> watchGroup(String tourId) => Stream.value(null);

  @override
  Stream<List<TourMember>> watchMembers(String tourId) =>
      Stream.value(<TourMember>[
        TourMember(
          tourId: tourId,
          email: currentEmail,
          displayName: 'Lead Organizer',
          role: TourRole.owner,
          status: TourMemberStatus.active,
          joinedAt: DateTime(2026, 10, 1),
          familyCount: 2,
        ),
      ]);
}

void main() {
  setUpAll(() {
    // The hub remembers the last tour in a Hive box, so give Hive a directory.
    Hive.init(Directory.systemTemp.createTempSync('bhromon_hub').path);
  });

  testWidgets('TourGroupHubScreen renders Tour OS branding and navigation bar',
      (tester) async {
    final repo = _FakeTourGroupRepository(
      groupsStream: Stream.value(<TourGroup>[]),
    );

    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en'), Locale('bn')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          DefaultMaterialLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        home: TourGroupHubScreen(repository: repo),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Brand title & Tour OS subtitle
    expect(find.text('Bhromon'), findsOneWidget);
    expect(find.text('Family & tour groups'), findsOneWidget);

    // Verify Action Bar buttons (Join with code, Create tour)
    expect(find.byIcon(Icons.backup_rounded), findsNothing);
    expect(find.byIcon(Icons.group_add_outlined), findsOneWidget);
    expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);

    // Verify Tour OS Bottom Navigation Bar with 5 tabs
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Tours'), findsOneWidget);
    expect(find.text('Channels'), findsOneWidget);
    expect(find.text('Moments'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);

    // Empty state should be visible since 0 groups were emitted
    expect(find.text('No active tour groups'), findsOneWidget);
    expect(find.text('Create tour'), findsOneWidget);
    expect(find.text('Enter code'), findsOneWidget);
  });

  testWidgets(
      'TourGroupHubScreen renders active tour card with Open Tour action and responsive grid',
      (tester) async {
    final testTour = TourGroup(
      id: 'tour_sajek_2026',
      name: "Sajek Cloud Trek Batch '26",
      ownerEmail: 'tester@bhromon.fun',
      inviteCode: 'SJ8K2026',
      destination: 'Sajek',
      originCity: 'Dhaka',
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 4),
      tourType: TourType.hill,
      modules: const TourModules(),
      createdAt: DateTime(2026, 10, 1),
    );

    final repo = _FakeTourGroupRepository(
      groupsStream: Stream.value([testTour]),
    );

    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en'), Locale('bn')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          DefaultMaterialLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        home: TourGroupHubScreen(repository: repo),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Active Tour Card Details
    expect(find.text("Sajek Cloud Trek Batch '26"), findsOneWidget);
    expect(find.text('Open Tour Experience'), findsOneWidget);
    expect(find.textContaining('SJ8K2026'), findsOneWidget);

    // Verify Tour Modules Grid
    expect(find.text('Tour modules & operations'), findsOneWidget);
    expect(find.text('Tour InstaFeed 📸'), findsOneWidget);
    expect(find.text('Shared fund & ledger'), findsOneWidget);
    expect(find.text('Highway roadmap 🛣️'), findsOneWidget);
    expect(find.text('Safety hub & SOS 🚨'), findsOneWidget);
    expect(find.text('Holiday calendar 📅'), findsOneWidget);

    // Verify Navigation bar tabs
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
