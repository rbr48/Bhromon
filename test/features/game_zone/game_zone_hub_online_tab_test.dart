import 'package:bhromon/features/game_zone/data/online_game_repository.dart';
import 'package:bhromon/features/game_zone/domain/models/online_game_session.dart';
import 'package:bhromon/features/game_zone/game_zone_hub_screen.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTourGroupRepository extends TourGroupRepository {
  _FakeTourGroupRepository({required this.groups});
  final List<TourGroup> groups;

  @override
  Stream<List<TourGroup>> watchMyGroups() => Stream.value(groups);

  @override
  String get currentEmail => 'lead@bhromon.fun';
}

class _FakeOnlineGameRepository extends OnlineGameRepository {
  _FakeOnlineGameRepository({required this.games});
  final List<OnlineGameSession> games;

  @override
  Stream<List<OnlineGameSession>> watchActiveGames(String tourId) =>
      Stream.value(games);

  @override
  String get currentEmail => 'lead@bhromon.fun';

  @override
  String get currentDisplayName => 'Lead Explorer';
}

void main() {
  testWidgets(
      'GameZoneHubScreen renders both tabs and switches to online tables',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tour = TourGroup(
      id: 'tour_sajek_2026',
      name: "Sajek Cloud Trek '26",
      ownerEmail: 'lead@bhromon.fun',
      inviteCode: 'SJ8K2026',
      destination: 'Sajek',
      originCity: 'Dhaka',
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 4),
      tourType: TourType.hill,
      modules: const TourModules(),
      createdAt: DateTime(2026, 10, 1),
    );

    final gameSession = OnlineGameSession(
      id: 'game_ludo_1',
      tourId: 'tour_sajek_2026',
      gameType: OnlineGameType.ludo,
      tableName: 'Evening Highway Ludo',
      status: GameSessionStatus.waiting,
      hostEmail: 'lead@bhromon.fun',
      players: [
        const OnlinePlayer(
          email: 'lead@bhromon.fun',
          displayName: 'Lead Explorer',
          seatIndex: 0,
          isHost: true,
          isReady: true,
        ),
      ],
      maxPlayers: 4,
      createdAt: DateTime(2026, 10, 27),
      updatedAt: DateTime(2026, 10, 27),
    );

    final tourRepo = _FakeTourGroupRepository(groups: [tour]);
    final gameRepo = _FakeOnlineGameRepository(games: [gameSession]);

    await tester.pumpWidget(
      MaterialApp(
        home: GameZoneHubScreen(
          tourRepository: tourRepo,
          gameRepository: gameRepo,
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify AppBar Title & TabBar
    expect(find.text('Travel GameZone'), findsOneWidget);
    expect(find.text('Offline Arcade'), findsOneWidget);
    expect(find.text('Tour Online Tables'), findsOneWidget);

    // Verify Offline Arcade Games
    expect(find.text('Card 29 (টোয়েন্টি নাইন)'), findsOneWidget);
    expect(find.text('Travel Chess AI'), findsOneWidget);
    expect(find.text('Ludo Express'), findsOneWidget);
    expect(find.text('Teen Patti (তিন পাত্তি)'), findsOneWidget);
    expect(find.text('Carrom (ক্যারম)'), findsOneWidget);

    // Switch to Online Tour Tables tab
    await tester.tap(find.text('Tour Online Tables'));
    await tester.pumpAndSettle();

    // Verify Active Tour Banner
    expect(find.text("Sajek Cloud Trek '26"), findsOneWidget);
    expect(find.text('Create New Game Table'), findsOneWidget);

    // Verify Active Table Card
    expect(find.text('Evening Highway Ludo'), findsOneWidget);
    expect(find.text('Ludo Express • 1/4 Seated'), findsOneWidget);
    expect(find.text('Enter'), findsOneWidget);
  });
}
