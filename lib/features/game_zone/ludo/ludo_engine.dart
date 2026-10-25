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

  /// Text/icon colour that stays readable on top of [color].
  Color get onColor => this == LudoColor.yellow ? const Color(0xFF212121) : const Color(0xFFFFFFFF);
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

  /// Sixes rolled in a row by the player whose turn it is.
  int consecutiveSixes = 0;
  final Set<LudoColor> humanPlayers = {LudoColor.red}; // Default: Red is User, others are Bots
  final Random _random;

  LudoEngine({Random? random}) : _random = random ?? Random() {
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

  /// Rolls for the current player. Returns -1 when a third six in a row
  /// forfeits the turn (the turn has already passed on).
  int rollDice() {
    currentDice = _random.nextInt(6) + 1;
    hasRolled = true;

    if (currentDice == 6) {
      consecutiveSixes++;
      if (consecutiveSixes >= 3) {
        passTurn();
        return -1;
      }
    } else {
      consecutiveSixes = 0;
    }

    return currentDice!;
  }

  /// Ends the current player's turn (no legal move, or a forfeit).
  void passTurn() => _nextTurn();

  List<LudoToken> getMovableTokens() {
    if (!hasRolled || currentDice == null) return [];
    return tokens[currentTurn]!.where((t) => canMoveToken(t, currentDice!)).toList();
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
    consecutiveSixes = 0;
    hasRolled = false;
    currentDice = null;
  }

  bool hasPlayerWon(LudoColor color) {
    return tokens[color]!.every((t) => t.state == TokenState.home);
  }

  /// True if an opponent token on the track could land on [index] with one roll.
  bool isThreatened(int index, LudoColor own) {
    if (safeIndices.contains(index)) return false;
    for (final entry in tokens.entries) {
      if (entry.key == own) continue;
      for (final opp in entry.value) {
        if (opp.state != TokenState.onTrack) continue;
        final distance = (index - opp.boardIndex + totalTrackSteps) % totalTrackSteps;
        if (distance >= 1 && distance <= 6 && opp.stepCount + distance <= stepsToHomeEntrance) {
          return true;
        }
      }
    }
    return false;
  }

  /// Picks the move with the best mix of finishing, capturing, safety and progress.
  LudoToken? getBestBotMove() {
    final movable = getMovableTokens();
    if (movable.isEmpty) return null;

    LudoToken? best;
    var bestScore = double.negativeInfinity;
    for (final t in movable) {
      final score = _scoreMove(t, currentDice!) + _random.nextDouble() * 0.5;
      if (score > bestScore) {
        bestScore = score;
        best = t;
      }
    }
    return best;
  }

  double _scoreMove(LudoToken t, int dice) {
    if (t.state == TokenState.inYard) {
      // Leaving the yard lands on the (safe) start square.
      return 420;
    }

    final target = t.stepCount + dice;
    if (target == stepsToHome) return 1000;

    final currentIndex = t.boardIndex;
    final threatenedNow = t.state == TokenState.onTrack && isThreatened(currentIndex, t.color);

    if (target > stepsToHomeEntrance) {
      // Entering or moving up the home column: nobody can touch it there.
      return 300.0 + (t.state == TokenState.onTrack ? 150 : 0) + (threatenedNow ? 250 : 0) + target;
    }

    final dest = (t.color.startIndex + target) % totalTrackSteps;
    var score = target.toDouble();

    if (!safeIndices.contains(dest)) {
      for (final entry in tokens.entries) {
        if (entry.key == t.color) continue;
        for (final opp in entry.value) {
          if (opp.state == TokenState.onTrack && opp.boardIndex == dest) {
            score += 600 + opp.stepCount * 4;
          }
        }
      }
    }

    if (threatenedNow) score += 220;
    if (safeIndices.contains(dest)) score += 120;
    if (isThreatened(dest, t.color)) score -= 260;
    return score;
  }
}
