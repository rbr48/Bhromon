import 'dart:async';
import 'dart:io';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/pages/tour_group_hub_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
        home: TourGroupHubScreen(repository: repo, groupsV2: false),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Brand title & Walk Together subtitle
    expect(find.text('Bhromon'), findsOneWidget);
    expect(find.text('Walk Together'), findsOneWidget);

    // The action bar has one labelled menu for creating and joining.
    expect(find.byIcon(Icons.backup_rounded), findsNothing);
    expect(find.byIcon(Icons.group_add_outlined), findsNothing);
    expect(find.byIcon(Icons.add_circle_outline_rounded), findsOneWidget);

    // Verify Tour OS Bottom Navigation Bar with 5 tabs
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Groups'), findsOneWidget);
    expect(find.text('Channels'), findsOneWidget);
    expect(find.text('Moments'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);

    // Empty state should be visible since 0 groups were emitted
    expect(find.text('No groups yet'), findsOneWidget);
    expect(find.text('Create group'), findsOneWidget);
    expect(find.text('Enter code'), findsOneWidget);

    // The menu lists each way to start, with its label.
    await tester.tap(find.byIcon(Icons.add_circle_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(PopupMenuItem<String>, 'Create a family circle'),
        findsOneWidget);
    expect(
        find.widgetWithText(PopupMenuItem<String>, 'Create a new tour group'),
        findsOneWidget);
    expect(find.widgetWithText(PopupMenuItem<String>, 'Join with a code'),
        findsOneWidget);
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
        home: TourGroupHubScreen(repository: repo, groupsV2: false),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Active Tour Card Details
    expect(find.text("Sajek Cloud Trek Batch '26"), findsOneWidget);
    expect(find.text('Open Tour Experience'), findsOneWidget);
    expect(find.textContaining('SJ8K2026'), findsOneWidget);

    // Verify Tour Modules Grid
    expect(find.text('Group modules & operations'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(GridView),
        matching: find.text('Moments'),
      ),
      findsOneWidget,
    );
    expect(find.text('Shared fund & ledger'), findsOneWidget);
    expect(find.text('Highway roadmap'), findsOneWidget);
    expect(find.text('Safety hub & SOS'), findsOneWidget);
    expect(find.text('Trip Milestones & Dates'), findsOneWidget);

    // On desktop widths (>= 900), bottom navigation bar is suppressed
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets(
      'empty group-hub lays out without overflow on narrow mobile, opens group-type picker, and localizes in Bangla',
      (tester) async {
    final repo = _FakeTourGroupRepository(
      groupsStream: Stream.value(<TourGroup>[]),
    );

    tester.view.physicalSize = const Size(360, 740);
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.2)),
          child: child!,
        ),
        home: TourGroupHubScreen(repository: repo, groupsV2: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('No groups yet'), findsOneWidget);
    expect(find.byKey(const Key('hub_switch_account_button')), findsOneWidget);
    expect(find.byType(ActionChip), findsNWidgets(12));

    // Enter code OutlinedButton uses dark accentText instead of washed-out mint.
    final enterCodeButton = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Enter code'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(
      enterCodeButton.style?.foregroundColor?.resolve({}),
      equals(const Color(0xFF2D6A4F)),
    );

    // Tapping "Create group" opens the group-type picker sheet instead of jumping to Trip only.
    await tester.tap(find.text('Create group'));
    await tester.pumpAndSettle();
    expect(find.text('Or start directly with a group type'), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.text('Create a family circle'),
      ),
      findsOneWidget,
    );
    final pickerList = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(
      find.text('Create a new tour group'),
      200,
      scrollable: pickerList,
    );
    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.text('Create a new tour group'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'empty group-hub localizes brand title and official feed in Bangla',
      (tester) async {
    final repo = _FakeTourGroupRepository(
      groupsStream: Stream.value(<TourGroup>[]),
    );

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('bn'),
        supportedLocales: const [Locale('en'), Locale('bn')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: TourGroupHubScreen(repository: repo, groupsV2: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('ভ্রমণ'), findsOneWidget);
    expect(find.text('ভ্রমণ অফিশিয়াল ফিড'), findsOneWidget);
    expect(find.byKey(const Key('compact_language_switch_button')),
        findsOneWidget);
  });
}
