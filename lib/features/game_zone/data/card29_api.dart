import 'package:cloud_functions/cloud_functions.dart';

/// Calls the server that runs the online 29 table. The server checks every
/// action, so the phone only asks; it never decides the result.
class Card29Api {
  Card29Api({FirebaseFunctions? functions}) : _functionsOverride = functions;

  final FirebaseFunctions? _functionsOverride;

  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  /// Deals a waiting table. Only the host may start it. Empty seats get bots.
  Future<void> start({required String tourId, required String gameId}) async {
    await _call('card29Start', {'tourId': tourId, 'gameId': gameId});
  }

  /// A seated player's action, such as a bid, a card or a reveal. [expectedStep]
  /// is the table step the player was looking at. The server refuses the action
  /// if the table has moved on since.
  Future<void> act({
    required String tourId,
    required String gameId,
    required Map<String, dynamic> action,
    required int expectedStep,
  }) async {
    await _call('card29Act', {
      'tourId': tourId,
      'gameId': gameId,
      'action': action,
      'expectedStep': expectedStep,
    });
  }

  /// One step for a bot, a finished trick, or a player who ran out of time.
  /// Returns the server's status: advanced, resolve, bot, auto, noop or stale.
  Future<String> advance({
    required String tourId,
    required String gameId,
    required int expectedStep,
  }) async {
    final data = await _call('card29Advance', {
      'tourId': tourId,
      'gameId': gameId,
      'expectedStep': expectedStep,
    });
    return data is Map ? (data['status'] as String?) ?? 'noop' : 'noop';
  }

  /// Leaves the table. In play, the seat is handed to a bot.
  Future<void> leave({required String tourId, required String gameId}) async {
    await _call('card29Leave', {'tourId': tourId, 'gameId': gameId});
  }

  Future<dynamic> _call(String name, Map<String, dynamic> payload) async {
    final result = await _functions.httpsCallable(name).call<dynamic>(payload);
    return result.data;
  }
}
