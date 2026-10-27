import 'package:bhromon/features/game_zone/domain/models/online_game_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OnlinePlayer', () {
    test('serialization and deserialization', () {
      final player = OnlinePlayer(
        email: 'traveler@bhromon.fun',
        displayName: 'Mountain Hiker',
        photoUrl: 'https://bhromon.fun/avatar.png',
        seatIndex: 2,
        isReady: true,
        isHost: false,
        isBot: false,
      );

      final map = player.toMap();
      final reconstructed = OnlinePlayer.fromMap(map);

      expect(reconstructed.email, 'traveler@bhromon.fun');
      expect(reconstructed.displayName, 'Mountain Hiker');
      expect(reconstructed.photoUrl, 'https://bhromon.fun/avatar.png');
      expect(reconstructed.seatIndex, 2);
      expect(reconstructed.isReady, isTrue);
      expect(reconstructed.isHost, isFalse);
      expect(reconstructed.isBot, isFalse);
    });

    test('copyWith updates properties properly', () {
      const player = OnlinePlayer(
        email: 'user@bhromon.fun',
        displayName: 'User',
        seatIndex: 0,
      );

      final updated = player.copyWith(
        displayName: 'VIP Explorer',
        isReady: true,
        isHost: true,
      );

      expect(updated.displayName, 'VIP Explorer');
      expect(updated.isReady, isTrue);
      expect(updated.isHost, isTrue);
      expect(updated.email, 'user@bhromon.fun');
    });
  });

  group('OnlineGameSession', () {
    test('session serialization and turn checking', () {
      final now = DateTime(2026, 10, 27, 10, 0);
      final p1 = OnlinePlayer(
        email: 'lead@bhromon.fun',
        displayName: 'Lead',
        seatIndex: 0,
        isHost: true,
        isReady: true,
      );
      final p2 = OnlinePlayer(
        email: 'companion@bhromon.fun',
        displayName: 'Companion',
        seatIndex: 1,
        isHost: false,
        isReady: true,
      );

      final session = OnlineGameSession(
        id: 'session_sajek_1',
        tourId: 'tour_sajek_2026',
        gameType: OnlineGameType.ludo,
        tableName: 'Sajek Cloud Ludo',
        status: GameSessionStatus.waiting,
        hostEmail: 'lead@bhromon.fun',
        players: [p1, p2],
        maxPlayers: 4,
        currentTurn: 0,
        createdAt: now,
        updatedAt: now,
        version: 1,
      );

      expect(session.canStart, isTrue);
      expect(session.isFull, isFalse);
      expect(session.isMyTurn('lead@bhromon.fun'), isTrue);
      expect(session.isMyTurn('companion@bhromon.fun'), isFalse);
      expect(session.playerAt(0)?.email, 'lead@bhromon.fun');
      expect(session.playerAt(1)?.email, 'companion@bhromon.fun');
      expect(session.playerAt(2), isNull);

      final map = session.toMap();
      final reconstructed = OnlineGameSession.fromMap('session_sajek_1', map);

      expect(reconstructed.id, 'session_sajek_1');
      expect(reconstructed.tourId, 'tour_sajek_2026');
      expect(reconstructed.gameType, OnlineGameType.ludo);
      expect(reconstructed.tableName, 'Sajek Cloud Ludo');
      expect(reconstructed.status, GameSessionStatus.waiting);
      expect(reconstructed.players.length, 2);
    });

    test('game types correctly parse from strings', () {
      expect(OnlineGameType.fromString('chess'), OnlineGameType.chess);
      expect(OnlineGameType.fromString('ludo'), OnlineGameType.ludo);
      expect(OnlineGameType.fromString('card29'), OnlineGameType.card29);
      expect(OnlineGameType.fromString('card_29'), OnlineGameType.card29);
      expect(OnlineGameType.fromString('teen_patti'), OnlineGameType.teenPatti);
      expect(OnlineGameType.fromString('carrom'), OnlineGameType.carrom);
      expect(OnlineGameType.fromString('unknown'), OnlineGameType.ludo);
    });
  });
}
