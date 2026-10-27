/// Supported multiplayer games for tour groups.
enum OnlineGameType {
  chess('Chess', 'Classic 2-player strategic duel', 2),
  ludo('Ludo Express', '4-token race to the home triangle', 4),
  card29('Card 29', 'Trick-taking partnership card battle', 4),
  teenPatti('Teen Patti', '3-card poker, chaal & sideshow', 4),
  carrom('Carrom', 'Pocket the queen and coins in real-time', 2);

  final String label;
  final String description;
  final int maxPlayers;

  const OnlineGameType(this.label, this.description, this.maxPlayers);

  static OnlineGameType fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'chess':
        return OnlineGameType.chess;
      case 'ludo':
        return OnlineGameType.ludo;
      case 'card29':
      case 'card_29':
        return OnlineGameType.card29;
      case 'teenpatti':
      case 'teen_patti':
        return OnlineGameType.teenPatti;
      case 'carrom':
        return OnlineGameType.carrom;
      default:
        return OnlineGameType.ludo;
    }
  }

  String get codeName {
    switch (this) {
      case OnlineGameType.chess:
        return 'chess';
      case OnlineGameType.ludo:
        return 'ludo';
      case OnlineGameType.card29:
        return 'card29';
      case OnlineGameType.teenPatti:
        return 'teen_patti';
      case OnlineGameType.carrom:
        return 'carrom';
    }
  }
}

/// Lifecycle status of an online game table.
enum GameSessionStatus {
  waiting,
  inProgress,
  finished;

  static GameSessionStatus fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'inprogress':
      case 'in_progress':
      case 'playing':
        return GameSessionStatus.inProgress;
      case 'finished':
      case 'gameover':
      case 'game_over':
        return GameSessionStatus.finished;
      default:
        return GameSessionStatus.waiting;
    }
  }
}

/// A participant seated at an online game table.
class OnlinePlayer {
  final String email;
  final String displayName;
  final String? photoUrl;
  final int seatIndex;
  final bool isReady;
  final bool isHost;
  final bool isBot;

  const OnlinePlayer({
    required this.email,
    required this.displayName,
    this.photoUrl,
    required this.seatIndex,
    this.isReady = false,
    this.isHost = false,
    this.isBot = false,
  });

  factory OnlinePlayer.fromMap(Map<String, dynamic> map) {
    return OnlinePlayer(
      email: (map['email'] as String? ?? '').trim().toLowerCase(),
      displayName: (map['displayName'] as String?)?.trim() ?? 'Explorer',
      photoUrl: map['photoUrl'] as String?,
      seatIndex: (map['seatIndex'] as num?)?.toInt() ?? 0,
      isReady: map['isReady'] == true,
      isHost: map['isHost'] == true,
      isBot: map['isBot'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email.trim().toLowerCase(),
      'displayName': displayName,
      if (photoUrl != null && photoUrl!.isNotEmpty) 'photoUrl': photoUrl,
      'seatIndex': seatIndex,
      'isReady': isReady,
      'isHost': isHost,
      'isBot': isBot,
    };
  }

  OnlinePlayer copyWith({
    String? email,
    String? displayName,
    String? photoUrl,
    int? seatIndex,
    bool? isReady,
    bool? isHost,
    bool? isBot,
  }) {
    return OnlinePlayer(
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      seatIndex: seatIndex ?? this.seatIndex,
      isReady: isReady ?? this.isReady,
      isHost: isHost ?? this.isHost,
      isBot: isBot ?? this.isBot,
    );
  }
}

/// Synchronized session for a multiplayer game in a tour group.
class OnlineGameSession {
  final String id;
  final String tourId;
  final OnlineGameType gameType;
  final String tableName;
  final GameSessionStatus status;
  final String hostEmail;
  final List<OnlinePlayer> players;
  final int maxPlayers;
  final int currentTurn;
  final Map<String, dynamic> state;
  final Map<String, dynamic>? lastAction;
  final int? winnerSeat;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;

  const OnlineGameSession({
    required this.id,
    required this.tourId,
    required this.gameType,
    required this.tableName,
    required this.status,
    required this.hostEmail,
    required this.players,
    required this.maxPlayers,
    this.currentTurn = 0,
    this.state = const {},
    this.lastAction,
    this.winnerSeat,
    required this.createdAt,
    required this.updatedAt,
    this.version = 0,
  });

  factory OnlineGameSession.fromMap(String id, Map<String, dynamic> map) {
    final rawPlayers = map['players'] as List<dynamic>? ?? [];
    final players = rawPlayers
        .whereType<Map<String, dynamic>>()
        .map((m) => OnlinePlayer.fromMap(m))
        .toList();

    DateTime parseTime(dynamic val) {
      if (val is DateTime) return val;
      if (val is String && val.isNotEmpty) {
        return DateTime.tryParse(val) ?? DateTime.now();
      }
      return DateTime.now();
    }

    final type = OnlineGameType.fromString(map['gameType'] as String?);

    return OnlineGameSession(
      id: id,
      tourId: map['tourId'] as String? ?? '',
      gameType: type,
      tableName: (map['tableName'] as String?)?.trim() ?? '${type.label} Table',
      status: GameSessionStatus.fromString(map['status'] as String?),
      hostEmail: (map['hostEmail'] as String? ?? '').trim().toLowerCase(),
      players: players,
      maxPlayers: (map['maxPlayers'] as num?)?.toInt() ?? type.maxPlayers,
      currentTurn: (map['currentTurn'] as num?)?.toInt() ?? 0,
      state: (map['state'] as Map<String, dynamic>?) ?? const {},
      lastAction: map['lastAction'] as Map<String, dynamic>?,
      winnerSeat: (map['winnerSeat'] as num?)?.toInt(),
      createdAt: parseTime(map['createdAt']),
      updatedAt: parseTime(map['updatedAt']),
      version: (map['version'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'tourId': tourId,
      'gameType': gameType.codeName,
      'tableName': tableName,
      'status': status.name,
      'hostEmail': hostEmail.trim().toLowerCase(),
      'players': players.map((p) => p.toMap()).toList(),
      'maxPlayers': maxPlayers,
      'currentTurn': currentTurn,
      'state': state,
      if (lastAction != null) 'lastAction': lastAction,
      if (winnerSeat != null) 'winnerSeat': winnerSeat,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'version': version,
    };
  }

  OnlinePlayer? playerAt(int seat) {
    try {
      return players.firstWhere((p) => p.seatIndex == seat);
    } catch (_) {
      return null;
    }
  }

  OnlinePlayer? playerByEmail(String email) {
    final norm = email.trim().toLowerCase();
    try {
      return players.firstWhere((p) => p.email == norm);
    } catch (_) {
      return null;
    }
  }

  bool isMyTurn(String email) {
    final me = playerByEmail(email);
    if (me == null) return false;
    return me.seatIndex == currentTurn;
  }

  bool get isFull => players.length >= maxPlayers;

  bool get canStart {
    if (status != GameSessionStatus.waiting) return false;
    if (players.length < 2) return false;
    // Host can start once at least 2 players are seated
    return true;
  }
}
