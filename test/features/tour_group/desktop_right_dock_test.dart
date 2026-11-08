import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/desktop_right_dock.dart';

class _FakeTourRepo extends TourGroupRepository {
  final List<TourGroup> _groups;

  _FakeTourRepo(this._groups);

  @override
  Stream<List<TourGroup>> watchMyGroups() => Stream.value(_groups);

  @override
  String get currentUid => 'test-uid';
}

void main() {
  testWidgets('DesktopRightDock renders group panel and direct chats panel',
      (tester) async {
    final now = DateTime.now();
    final groups = <TourGroup>[
      TourGroup(
        id: 'group-1',
        name: 'Cox Trip 2026',
        description: 'Trip group',
        destination: "Cox's Bazar",
        startDate: now,
        endDate: now.add(const Duration(days: 3)),
        tourType: TourType.beach,
        originCity: 'Dhaka',
        ownerEmail: 'owner@test.com',
        inviteCode: 'CODE1234',
        createdAt: now,
      ),
      TourGroup(
        id: 'group-2',
        name: 'Bachelor Mess',
        description: 'Mess group',
        destination: '',
        startDate: now,
        endDate: now,
        tourType: TourType.nature,
        preset: 'mess',
        ownerEmail: 'owner@test.com',
        inviteCode: 'MESS1234',
        createdAt: now,
      ),
    ];

    final fakeRepo = _FakeTourRepo(groups);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('en', ''),
          Locale('bn', ''),
        ],
        home: Scaffold(
          body: DesktopRightDock(
            activeTourId: 'group-1',
            repository: fakeRepo,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(DesktopGroupListPanel), findsOneWidget);
    expect(find.byType(DesktopDirectChatsPanel), findsOneWidget);
    expect(find.text('Cox Trip 2026'), findsOneWidget);
    expect(find.text('Bachelor Mess'), findsOneWidget);
  });
}
