import 'dart:math';
import 'package:flutter/material.dart';

enum LudoColor {
  red('Red', Color(0xFFE53935), 0, 50),
  green('Green', Color(0xFF43A047), 13, 11),
  yellow('Yellow', Color(0xFFFDD835), 26, 24),
  blue('Blue', Color(0xFF1E88E5), 39, 37);

  final String name;
  final Color color;
  final int startIndex;
  final int homeEntranceIndex;

  const LudoColor(this.name, this.color, this.startIndex, this.homeEntranceIndex);
}

enum TokenState { inYard, onTrack, inHomeStretch, home }

class LudoToken {
  final int id;
  final LudoColor color;
  TokenState state;
  int stepCount; // 0 to 56: 0=start, 50=home entrance, 51-55=stretch, 56=home

  LudoToken({
    required this.id,
    required this.color,
    this.state = TokenState.inYard,
    this.stepCount = 0,
  });

  int get boardIndex {
    if (state != TokenState.onTrack) return -1;
    return (color.startIndex + stepCount) % 52;
  }
}

class LudoEngine {
  static const int totalTrackSteps = 52;
  static const int stepsToHomeEntrance = 50;
  static const int stepsToHome = 56;
  static const List<int> safeIndices = [0, 8, 13, 21, 26, 34, 39, 47];

  final Map<LudoColor, List<LudoToken>> tokens = {};
  LudoColor currentTurn = LudoColor.red;
  int? currentDice;
  bool hasRolled = false;
  int consecutiveSixes = 0;
  final Set<LudoColor> humanPlayers = {LudoColor.red}; // Default: Red is User, others are Bots
  final Random _random = Random();

  LudoEngine() {
    reset();
  }

  void reset() {
    tokens.clear();
    for (final color in LudoColor.values) {
      tokens[color] = List.generate(
        4,
        (i) => LudoToken(id: i, color: color),
      );
    }
    currentTurn = LudoColor.red;
    currentDice = null;
    hasRolled = false;
    consecutiveSixes = 0;
  }

  bool isCurrentTurnHuman() => humanPlayers.contains(currentTurn);

  int rollDice() {
    currentDice = _random.nextInt(6) + 1;
    hasRolled = true;

    if (currentDice == 6) {
      consecutiveSixes++;
      if (consecutiveSixes >= 3) {
        // Triple sixes penalty: forfeit turn!
        consecutiveSixes = 0;
        hasRolled = false;
        currentDice = null;
        _nextTurn();
        return -1; // Special indicator for triple sixes penalty
      }
    } else {
      consecutiveSixes = 0;
    }

    return currentDice!;
  }

  List<LudoToken> getMovableTokens() {
    if (!hasRolled || currentDice == null) return [];

    final playerTokens = tokens[currentTurn]!;
    final movable = <LudoToken>[];

    for (final t in playerTokens) {
      if (canMoveToken(t, currentDice!)) {
        movable.add(t);
      }
    }
    return movable;
  }

  bool canMoveToken(LudoToken token, int dice) {
    if (token.state == TokenState.home) return false;

    if (token.state == TokenState.inYard) {
      return dice == 6;
    }

    // On track or in home stretch
    final targetStep = token.stepCount + dice;
    return targetStep <= stepsToHome;
  }

  /// Moves the token and returns true if an extra turn is awarded (rolled 6 or captured piece or reached home).
  bool moveToken(LudoToken token) {
    if (currentDice == null || !canMoveToken(token, currentDice!)) return false;

    final dice = currentDice!;
    bool extraTurn = (dice == 6);

    if (token.state == TokenState.inYard) {
      token.state = TokenState.onTrack;
      token.stepCount = 0;
    } else {
      token.stepCount += dice;
      if (token.stepCount == stepsToHome) {
        token.state = TokenState.home;
        extraTurn = true; // Bonus roll for reaching home!
      } else if (token.stepCount > stepsToHomeEntrance) {
        token.state = TokenState.inHomeStretch;
      }
    }

    // Check for capture if on track
    if (token.state == TokenState.onTrack) {
      final landingIndex = token.boardIndex;
      if (!safeIndices.contains(landingIndex)) {
        for (final entry in tokens.entries) {
          if (entry.key == token.color) continue;
          for (final oppToken in entry.value) {
            if (oppToken.state == TokenState.onTrack && oppToken.boardIndex == landingIndex) {
              // Captured! Send back to yard
              oppToken.state = TokenState.inYard;
              oppToken.stepCount = 0;
              extraTurn = true; // Bonus roll for capture!
            }
          }
        }
      }
    }

    hasRolled = false;
    currentDice = null;

    if (!extraTurn) {
      _nextTurn();
    }

    return extraTurn;
  }

  void _nextTurn() {
    final nextIdx = (currentTurn.index + 1) % LudoColor.values.length;
    currentTurn = LudoColor.values[nextIdx];
  }

  bool hasPlayerWon(LudoColor color) {
    return tokens[color]!.every((t) => t.state == TokenState.home);
  }

  LudoToken? getBestBotMove() {
    final movable = getMovableTokens();
    if (movable.isEmpty) return null;

    // Prioritize: 1) Reaching home, 2) Capturing opponent, 3) Leaving yard, 4) Furthest token
    for (final t in movable) {
      if (t.stepCount + currentDice! == stepsToHome) return t;
    }

    for (final t in movable) {
      if (t.state == TokenState.onTrack) {
        final destIndex = (t.color.startIndex + t.stepCount + currentDice!) % 52;
        if (!safeIndices.contains(destIndex)) {
          for (final entry in tokens.entries) {
            if (entry.key == t.color) continue;
            if (entry.value.any((opp) => opp.state == TokenState.onTrack && opp.boardIndex == destIndex)) {
              return t;
            }
          }
        }
      }
    }

    for (final t in movable) {
      if (t.state == TokenState.inYard && currentDice == 6) return t;
    }

    movable.sort((a, b) => b.stepCount.compareTo(a.stepCount));
    return movable.first;
  }
}
