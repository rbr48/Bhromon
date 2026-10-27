import 'package:bhromon/features/game_zone/data/online_game_repository.dart';
import 'package:bhromon/features/game_zone/domain/models/online_game_session.dart';
import 'package:bhromon/features/game_zone/online/online_table_lobby_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockOnlineGameRepository extends OnlineGameRepository {
  @override
  String get currentEmail => 'host@bhromon.fun';

  @override
  String get currentDisplayName => 'Host User';

  @override
  String? get currentPhotoUrl => null;

  @override
  String get currentUid => 'uid_host';
}

void main() {
  testWidgets('OnlineTableLobbyView renders table code and invite button',
      (tester) async {
    final session = OnlineGameSession(
      id: 'table_code_12345',
      tourId: 'tour_1',
      gameType: OnlineGameType.card29,
      tableName: 'Card 29 Battle',
      status: GameSessionStatus.waiting,
      hostEmail: 'host@bhromon.fun',
      players: [
        const OnlinePlayer(
          email: 'host@bhromon.fun',
          displayName: 'Host User',
          seatIndex: 0,
          isHost: true,
          isReady: true,
        ),
      ],
      maxPlayers: 4,
      createdAt: DateTime(2026, 10, 27),
      updatedAt: DateTime(2026, 10, 27),
    );

    final repo = _MockOnlineGameRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OnlineTableLobbyView(
            session: session,
            repository: repo,
            myEmail: 'host@bhromon.fun',
            onStartGame: () {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Table Code and Invite button
    expect(find.text('TABLE CODE'), findsOneWidget);
    expect(find.text('table_code_12345'), findsOneWidget);
    expect(find.text('Invite'), findsOneWidget);
    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
    expect(find.byIcon(Icons.share_rounded), findsOneWidget);

    // Verify Seats
    expect(find.text('TABLE SEATS'), findsOneWidget);
    expect(find.text('Host User'), findsOneWidget);
    expect(find.text('You (Seat 1)'), findsOneWidget);
    expect(find.text('Empty Seat'), findsNWidgets(3));
  });
}
