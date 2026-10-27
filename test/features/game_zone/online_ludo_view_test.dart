import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/game_zone/data/online_game_repository.dart';
import 'package:bhromon/features/game_zone/domain/models/online_game_session.dart';
import 'package:bhromon/features/game_zone/ludo/ludo_board_painters.dart';
import 'package:bhromon/features/game_zone/online/online_ludo_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeOnlineGameRepo extends OnlineGameRepository {
  _FakeOnlineGameRepo() : super(firestore: null, auth: null);

  @override
  String get currentEmail => 'player1@bhromon.fun';

  @override
  String get currentDisplayName => 'Player 1';

  @override
  String? get currentPhotoUrl => null;

  @override
  String get currentUid => 'uid_1';

  @override
  Future<void> commitAction({
    required String tourId,
    required String gameId,
    required Map<String, dynamic> action,
    required Map<String, dynamic> newState,
    int? nextTurn,
    int? winnerSeat,
    bool isFinished = false,
  }) async {}
}

Widget _wrapLudo(Widget child) {
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
  testWidgets('OnlineLudoView renders board, 2x2 yards, center, and 3D dice',
      (tester) async {
    final now = DateTime(2026, 10, 27, 12, 0);
    final session = OnlineGameSession(
      id: 'ludo_session_1',
      tourId: 'tour_1',
      gameType: OnlineGameType.ludo,
      tableName: 'Evening Ludo',
      status: GameSessionStatus.inProgress,
      hostEmail: 'player1@bhromon.fun',
      players: const [
        OnlinePlayer(
          email: 'player1@bhromon.fun',
          displayName: 'Player Red',
          seatIndex: 0,
          isReady: true,
          isHost: true,
        ),
        OnlinePlayer(
          email: 'player2@bhromon.fun',
          displayName: 'Player Green',
          seatIndex: 1,
          isReady: true,
        ),
      ],
      maxPlayers: 4,
      currentTurn: 0,
      state: const {},
      createdAt: now,
      updatedAt: now,
      version: 1,
    );

    final repo = _FakeOnlineGameRepo();

    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      _wrapLudo(
        OnlineLudoView(
          session: session,
          repository: repo,
          myEmail: 'player1@bhromon.fun',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Board painters are present
    expect(
      find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is LudoPathwayGridPainter),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is LudoCenterHomePainter),
      findsOneWidget,
    );

    // 2. Player labels appear on their yards
    expect(find.textContaining('Player Red'), findsWidgets);
    expect(find.textContaining('Player Green'), findsWidgets);

    // 3. Dice button is rendered for active turn
    expect(find.byIcon(Icons.casino_rounded), findsOneWidget);

    // 4. Tap the dice button to roll and display 3D Dice Face
    await tester.tap(find.byIcon(Icons.casino_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));

    expect(
      find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is LudoDiceFacePainter),
      findsWidgets,
    );
  });
}
