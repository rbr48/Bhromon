import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../domain/models/card29_table.dart';
import '../domain/models/online_game_session.dart';
import '../domain/models/teen_patti_table.dart';
import 'card29_api.dart';
import 'carrom_api.dart';
import 'teen_patti_api.dart';

class OnlineGameRepository {
  OnlineGameRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    Card29Api? card29,
    TeenPattiApi? teenPatti,
    CarromApi? carrom,
  })  : _firestoreInstance = firestore,
        _authInstance = auth,
        _card29 = card29 ?? Card29Api(),
        _teenPatti = teenPatti ?? TeenPattiApi(),
        _carrom = carrom ?? CarromApi();

  final FirebaseFirestore? _firestoreInstance;
  final FirebaseAuth? _authInstance;
  final Card29Api _card29;
  final TeenPattiApi _teenPatti;
  final CarromApi _carrom;

  FirebaseFirestore get _firestore =>
      _firestoreInstance ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _authInstance ?? FirebaseAuth.instance;

  String get currentEmail =>
      _auth.currentUser?.email?.trim().toLowerCase() ?? '';
  String get currentDisplayName {
    final cached = _cachedExplorerProfile();
    if (cached != null && cached['displayName'] is String) {
      final name = (cached['displayName'] as String).trim();
      if (name.isNotEmpty) return name;
    }
    try {
      return _auth.currentUser?.displayName?.trim() ?? 'Explorer';
    } catch (_) {
      return 'Explorer';
    }
  }

  String? get currentPhotoUrl {
    final cached = _cachedExplorerProfile();
    if (cached != null && cached['avatarUrl'] is String) {
      final url = cached['avatarUrl'] as String;
      if (url.isNotEmpty) return url;
    }
    try {
      return _auth.currentUser?.photoURL;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _cachedExplorerProfile() {
    try {
      if (!Hive.isBoxOpen('auth_box')) return null;
      final raw = Hive.box<dynamic>('auth_box').get('profile');
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (_) {}
    return null;
  }
  String get currentUid => _auth.currentUser?.uid ?? '';

  CollectionReference<Map<String, dynamic>> _gamesRef(String tourId) =>
      _firestore.collection('tours').doc(tourId).collection('games');

  /// Streams active game sessions in the tour group.
  Stream<List<OnlineGameSession>> watchActiveGames(String tourId) {
    if (tourId.isEmpty) return const Stream<List<OnlineGameSession>>.empty();
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
    if (tourId.isEmpty || gameId.isEmpty) {
      return const Stream<OnlineGameSession?>.empty();
    }
    return _gamesRef(tourId).doc(gameId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return OnlineGameSession.fromMap(doc.id, doc.data()!);
    });
  }

  /// Streams the cards held by [seat] in a 29 table. Only that seat's owner
  /// can read them; other members get a permission error, which the caller
  /// shows as "no cards".
  Stream<Card29PrivateHand?> watchCard29Seat(
    String tourId,
    String gameId,
    int seat,
  ) {
    return _gamesRef(tourId)
        .doc(gameId)
        .collection('private')
        .doc('seat$seat')
        .snapshots()
        .map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return Card29PrivateHand.fromMap(doc.data()!);
    });
  }

  /// Streams the cards dealt to [seat] in a Teen Patti table. Only that seat's
  /// owner can read them, as with [watchCard29Seat].
  Stream<TeenPattiPrivateHand?> watchTeenPattiSeat(
    String tourId,
    String gameId,
    int seat,
  ) {
    return _gamesRef(tourId)
        .doc(gameId)
        .collection('private')
        .doc('seat$seat')
        .snapshots()
        .map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return TeenPattiPrivateHand.fromMap(doc.data()!);
    });
  }

  /// Creates a new game table.
  Future<String> createGameSession({
    required String tourId,
    required OnlineGameType gameType,
    required String tableName,
    int? customMaxPlayers,
    bool isTournament = false,
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
      tableName: tableName.trim().isEmpty
          ? '${gameType.label} Table'
          : tableName.trim(),
      status: GameSessionStatus.waiting,
      hostEmail: currentEmail,
      players: [host],
      maxPlayers: maxPlayers,
      currentTurn: 0,
      state: const {},
      createdAt: now,
      updatedAt: now,
      version: 1,
      isTournament: isTournament,
    );

    await docRef.set(session.toMap());
    return docRef.id;
  }

  /// Joins an existing game table. The read and the write happen in one
  /// transaction, so two people joining at once cannot take the same seat.
  Future<void> joinGameSession({
    required String tourId,
    required String gameId,
  }) async {
    final docRef = _gamesRef(tourId).doc(gameId);
    final me = currentEmail;
    final name = currentDisplayName;
    final photo = currentPhotoUrl;

    await _firestore.runTransaction((tx) async {
      final snapshot = await tx.get(docRef);
      if (!snapshot.exists || snapshot.data() == null) {
        throw StateError('Game table not found');
      }

      final session = OnlineGameSession.fromMap(snapshot.id, snapshot.data()!);

      // Already joined.
      if (session.playerByEmail(me) != null) return;

      if (session.isFull) {
        throw StateError('This game table is already full');
      }

      // Pick lowest unoccupied seat.
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
        displayName: name,
        photoUrl: photo,
        seatIndex: targetSeat,
        isReady: true,
        isHost: false,
        isBot: false,
      );

      final updatedPlayers = [...session.players, newPlayer];

      tx.update(docRef, {
        'players': updatedPlayers.map((p) => p.toMap()).toList(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
    });
  }

  /// Fills unoccupied seats with bots so the host can start without waiting.
  Future<void> fillRemainingSeatsWithBots({
    required String tourId,
    required String gameId,
  }) async {
    final docRef = _gamesRef(tourId).doc(gameId);

    await _firestore.runTransaction((tx) async {
      final snapshot = await tx.get(docRef);
      if (!snapshot.exists || snapshot.data() == null) return;

      final session = OnlineGameSession.fromMap(snapshot.id, snapshot.data()!);
      final occupied = session.players.map((p) => p.seatIndex).toSet();
      final updated = [...session.players];

      const botNames = ['Tour Guide Bot', 'Highway Ace Bot', 'Dhaka Champ Bot'];
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

      tx.update(docRef, {
        'players': updated.map((p) => p.toMap()).toList(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
    });
  }

  /// Leaves a game session. If host leaves while in lobby, table is closed or host re-assigned.
  /// A 29 table is left through the server, which hands a seat in play to a bot.
  Future<void> leaveGameSession({
    required String tourId,
    required String gameId,
  }) async {
    final docRef = _gamesRef(tourId).doc(gameId);
    final current = await docRef.get();
    if (current.data()?['gameType'] == OnlineGameType.card29.codeName) {
      await _card29.leave(tourId: tourId, gameId: gameId);
      return;
    }
    if (current.data()?['gameType'] == OnlineGameType.teenPatti.codeName) {
      await _teenPatti.leave(tourId: tourId, gameId: gameId);
      return;
    }
    if (current.data()?['gameType'] == OnlineGameType.carrom.codeName) {
      await _carrom.leave(tourId: tourId, gameId: gameId);
      return;
    }

    final me = currentEmail;
    await _firestore.runTransaction((tx) async {
      final snapshot = await tx.get(docRef);
      if (!snapshot.exists || snapshot.data() == null) return;

      final session = OnlineGameSession.fromMap(snapshot.id, snapshot.data()!);
      final remaining = session.players.where((p) => p.email != me).toList();

      if (remaining.isEmpty ||
          (session.hostEmail == me &&
              session.status == GameSessionStatus.waiting)) {
        tx.delete(docRef);
        return;
      }

      // Reassign host if needed
      String newHost = session.hostEmail;
      if (session.hostEmail == me) {
        newHost = remaining.first.email;
        remaining[0] = remaining[0].copyWith(isHost: true);
      }

      tx.update(docRef, {
        'hostEmail': newHost,
        'players': remaining.map((p) => p.toMap()).toList(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
    });
  }

  /// Starts the game with an initial state payload. 29 tables are dealt by the
  /// server with [start29Table] instead.
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

  /// Deals a waiting 29 table. The server fills empty seats with bots.
  Future<void> start29Table({
    required String tourId,
    required String gameId,
  }) {
    return _card29.start(tourId: tourId, gameId: gameId);
  }

  /// Deals a waiting Teen Patti table. The server fills empty seats with bots.
  Future<void> startTeenPattiTable({
    required String tourId,
    required String gameId,
  }) {
    return _teenPatti.start(tourId: tourId, gameId: gameId);
  }

  /// The 29 table's action service, for the table screen.
  Card29Api get card29 => _card29;

  /// The Teen Patti table's action service, for the table screen.
  TeenPattiApi get teenPatti => _teenPatti;

  /// Lays out a waiting carrom board. The server fills an empty seat with a bot.
  Future<void> startCarromTable({
    required String tourId,
    required String gameId,
  }) {
    return _carrom.start(tourId: tourId, gameId: gameId);
  }

  /// The carrom board's action service, for the board screen.
  CarromApi get carrom => _carrom;

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
