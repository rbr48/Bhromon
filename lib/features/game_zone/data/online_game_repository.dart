import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/models/online_game_session.dart';

class OnlineGameRepository {
  OnlineGameRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestoreInstance = firestore,
        _authInstance = auth;

  final FirebaseFirestore? _firestoreInstance;
  final FirebaseAuth? _authInstance;

  FirebaseFirestore get _firestore =>
      _firestoreInstance ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _authInstance ?? FirebaseAuth.instance;

  String get currentEmail =>
      _auth.currentUser?.email?.trim().toLowerCase() ?? '';
  String get currentDisplayName =>
      _auth.currentUser?.displayName?.trim() ?? 'Explorer';
  String? get currentPhotoUrl => _auth.currentUser?.photoURL;
  String get currentUid => _auth.currentUser?.uid ?? '';

  CollectionReference<Map<String, dynamic>> _gamesRef(String tourId) =>
      _firestore.collection('tours').doc(tourId).collection('games');

  /// Streams active game sessions in the tour group.
  Stream<List<OnlineGameSession>> watchActiveGames(String tourId) {
    if (tourId.isEmpty) return Stream.value(const []);
    return _gamesRef(tourId)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => OnlineGameSession.fromMap(doc.id, doc.data()))
          .toList();
    });
  }

  /// Streams a single live game session.
  Stream<OnlineGameSession?> watchGame(String tourId, String gameId) {
    if (tourId.isEmpty || gameId.isEmpty) return Stream.value(null);
    return _gamesRef(tourId).doc(gameId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return OnlineGameSession.fromMap(doc.id, doc.data()!);
    });
  }

  /// Creates a new game table.
  Future<String> createGameSession({
    required String tourId,
    required OnlineGameType gameType,
    required String tableName,
    int? customMaxPlayers,
  }) async {
    final host = OnlinePlayer(
      email: currentEmail,
      displayName: currentDisplayName,
      photoUrl: currentPhotoUrl,
      seatIndex: 0,
      isReady: true,
      isHost: true,
      isBot: false,
    );

    final maxPlayers = customMaxPlayers ?? gameType.maxPlayers;
    final now = DateTime.now();
    final docRef = _gamesRef(tourId).doc();

    final session = OnlineGameSession(
      id: docRef.id,
      tourId: tourId,
      gameType: gameType,
      tableName: tableName.trim().isEmpty ? '${gameType.label} Table' : tableName.trim(),
      status: GameSessionStatus.waiting,
      hostEmail: currentEmail,
      players: [host],
      maxPlayers: maxPlayers,
      currentTurn: 0,
      state: const {},
      createdAt: now,
      updatedAt: now,
      version: 1,
    );

    await docRef.set(session.toMap());
    return docRef.id;
  }

  /// Joins an existing game table.
  Future<void> joinGameSession({
    required String tourId,
    required String gameId,
  }) async {
    final docRef = _gamesRef(tourId).doc(gameId);
    final snapshot = await docRef.get();
    if (!snapshot.exists || snapshot.data() == null) {
      throw StateError('Game table not found');
    }

    final session = OnlineGameSession.fromMap(snapshot.id, snapshot.data()!);
    final me = currentEmail;

    // Check if already joined
    if (session.playerByEmail(me) != null) return;

    if (session.isFull) {
      throw StateError('This game table is already full');
    }

    // Pick lowest unoccupied seat
    final occupiedSeats = session.players.map((p) => p.seatIndex).toSet();
    int targetSeat = 0;
    for (int i = 0; i < session.maxPlayers; i++) {
      if (!occupiedSeats.contains(i)) {
        targetSeat = i;
        break;
      }
    }

    final newPlayer = OnlinePlayer(
      email: me,
      displayName: currentDisplayName,
      photoUrl: currentPhotoUrl,
      seatIndex: targetSeat,
      isReady: true,
      isHost: false,
      isBot: false,
    );

    final updatedPlayers = [...session.players, newPlayer];

    await docRef.update({
      'players': updatedPlayers.map((p) => p.toMap()).toList(),
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  /// Fills unoccupied seats with bots so the host can start without waiting.
  Future<void> fillRemainingSeatsWithBots({
    required String tourId,
    required String gameId,
  }) async {
    final docRef = _gamesRef(tourId).doc(gameId);
    final snapshot = await docRef.get();
    if (!snapshot.exists || snapshot.data() == null) return;

    final session = OnlineGameSession.fromMap(snapshot.id, snapshot.data()!);
    final occupied = session.players.map((p) => p.seatIndex).toSet();
    final updated = [...session.players];

    final botNames = ['Tour Guide Bot', 'Highway Ace Bot', 'Dhaka Champ Bot'];
    int botNameIdx = 0;

    for (int i = 0; i < session.maxPlayers; i++) {
      if (!occupied.contains(i)) {
        final name = botNames[botNameIdx % botNames.length];
        botNameIdx++;
        updated.add(OnlinePlayer(
          email: 'bot_seat_$i@bhromon.fun',
          displayName: name,
          seatIndex: i,
          isReady: true,
          isHost: false,
          isBot: true,
        ));
      }
    }

    await docRef.update({
      'players': updated.map((p) => p.toMap()).toList(),
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  /// Leaves a game session. If host leaves while in lobby, table is closed or host re-assigned.
  Future<void> leaveGameSession({
    required String tourId,
    required String gameId,
  }) async {
    final docRef = _gamesRef(tourId).doc(gameId);
    final snapshot = await docRef.get();
    if (!snapshot.exists || snapshot.data() == null) return;

    final session = OnlineGameSession.fromMap(snapshot.id, snapshot.data()!);
    final me = currentEmail;

    final remaining = session.players.where((p) => p.email != me).toList();

    if (remaining.isEmpty || (session.hostEmail == me && session.status == GameSessionStatus.waiting)) {
      await docRef.delete();
      return;
    }

    // Reassign host if needed
    String newHost = session.hostEmail;
    if (session.hostEmail == me) {
      newHost = remaining.first.email;
      remaining[0] = remaining[0].copyWith(isHost: true);
    }

    await docRef.update({
      'hostEmail': newHost,
      'players': remaining.map((p) => p.toMap()).toList(),
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  /// Starts the game with an initial state payload.
  Future<void> startGameSession({
    required String tourId,
    required String gameId,
    required Map<String, dynamic> initialState,
    int initialTurn = 0,
  }) async {
    final docRef = _gamesRef(tourId).doc(gameId);
    await docRef.update({
      'status': GameSessionStatus.inProgress.name,
      'state': initialState,
      'currentTurn': initialTurn,
      'updatedAt': DateTime.now().toIso8601String(),
      'version': FieldValue.increment(1),
    });
  }

  /// Commits a player move or game event action.
  Future<void> commitAction({
    required String tourId,
    required String gameId,
    required Map<String, dynamic> action,
    required Map<String, dynamic> newState,
    int? nextTurn,
    int? winnerSeat,
    bool isFinished = false,
  }) async {
    final docRef = _gamesRef(tourId).doc(gameId);
    final updates = <String, dynamic>{
      'lastAction': action,
      'state': newState,
      'updatedAt': DateTime.now().toIso8601String(),
      'version': FieldValue.increment(1),
    };

    if (nextTurn != null) {
      updates['currentTurn'] = nextTurn;
    }
    if (winnerSeat != null) {
      updates['winnerSeat'] = winnerSeat;
    }
    if (isFinished) {
      updates['status'] = GameSessionStatus.finished.name;
    }

    await docRef.update(updates);
  }

  /// Deletes a finished or cancelled game table.
  Future<void> deleteGameSession({
    required String tourId,
    required String gameId,
  }) async {
    await _gamesRef(tourId).doc(gameId).delete();
  }
}
