import 'package:cloud_functions/cloud_functions.dart';

/// Calls the server that runs the online carrom board. The server plays every
/// shot and scores it, so the phone only sends where the striker sits and how
/// it is shot. It never decides the result.
class CarromApi {
  CarromApi({FirebaseFunctions? functions}) : _functionsOverride = functions;

  final FirebaseFunctions? _functionsOverride;

  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  /// Lays out a waiting board. Only the host may start it. An empty seat gets a bot.
  Future<void> start({required String tourId, required String gameId}) async {
    await _call('carromStart', {'tourId': tourId, 'gameId': gameId});
  }

  /// A seated player's shot. [x] is where the striker sits on the baseline, and
  /// [angle] (radians) and [power] (0 to 1) say how it is shot. [expectedStep]
  /// is the board step the player was looking at, so the server refuses a shot
  /// made on an old view.
  Future<void> shoot({
    required String tourId,
    required String gameId,
    required double x,
    required double angle,
    required double power,
    required int expectedStep,
  }) async {
    await _call('carromShoot', {
      'tourId': tourId,
      'gameId': gameId,
      'shot': {'x': x, 'angle': angle, 'power': power},
      'expectedStep': expectedStep,
    });
  }

  /// One step for a bot, or for a player who ran out of time. Returns the
  /// server's status: bot, auto, noop or stale.
  Future<String> advance({
    required String tourId,
    required String gameId,
    required int expectedStep,
  }) async {
    final data = await _call('carromAdvance', {
      'tourId': tourId,
      'gameId': gameId,
      'expectedStep': expectedStep,
    });
    return data is Map ? (data['status'] as String?) ?? 'noop' : 'noop';
  }

  /// Leaves the board. Once play has started, the seat is handed to a bot.
  Future<void> leave({required String tourId, required String gameId}) async {
    await _call('carromLeave', {'tourId': tourId, 'gameId': gameId});
  }

  Future<dynamic> _call(String name, Map<String, dynamic> payload) async {
    final result = await _functions.httpsCallable(name).call<dynamic>(payload);
    return result.data;
  }
}
