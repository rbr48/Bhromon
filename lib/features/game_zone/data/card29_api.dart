import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/utils/app_logger.dart';

/// Calls the server that runs the online 29 table. The server checks every
/// action, so the phone only asks; it never decides the result.
///
/// Dispatches requests first to the Bhromon VPS games microservice
/// (`https://bhromon.fun/api/games`), bypassing Firebase Cloud Functions and
/// keeping the app 100% free on the Firebase Spark plan. Automatically falls
/// back to Firebase Cloud Functions if the VPS is unreachable.
class Card29Api {
  Card29Api({
    FirebaseFunctions? functions,
    Dio? dio,
    String? baseUrl,
    FirebaseAuth? auth,
  })  : _functionsOverride = functions,
        _dioOverride = dio,
        _baseUrlOverride = baseUrl,
        _authOverride = auth;

  final FirebaseFunctions? _functionsOverride;
  final Dio? _dioOverride;
  final String? _baseUrlOverride;
  final FirebaseAuth? _authOverride;

  static const String defaultBaseUrl = 'https://bhromon.fun/api/games';

  Dio get _dio =>
      _dioOverride ??
      Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  FirebaseAuth? get _auth => _authOverride;

  Future<String?> _getIdToken() async {
    try {
      final user = _auth?.currentUser ?? FirebaseAuth.instance.currentUser;
      return await user?.getIdToken();
    } catch (_) {
      return null;
    }
  }

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
    if (_functionsOverride != null &&
        _dioOverride == null &&
        _baseUrlOverride == null) {
      final result =
          await _functions.httpsCallable(name).call<dynamic>(payload);
      return result.data;
    }

    final token = await _getIdToken();
    final baseUrl = _baseUrlOverride ?? defaultBaseUrl;
    final hasCustomClient = _dioOverride != null || _baseUrlOverride != null;

    if (token != null || hasCustomClient) {
      try {
        final authToken = token ?? '';
        final response = await _dio.post<dynamic>(
          '$baseUrl/$name',
          data: payload,
          options: Options(
            headers: {
              if (authToken.isNotEmpty) 'Authorization': 'Bearer $authToken',
              'Content-Type': 'application/json',
            },
          ),
        );
        final data = response.data;
        if (data is Map && data.containsKey('result')) {
          return data['result'];
        }
        return data;
      } on DioException catch (e) {
        if (e.response != null && e.response?.data is Map) {
          final body = e.response!.data as Map;
          final error = body['error'];
          if (error is Map) {
            final message =
                (error['message'] as String?) ?? 'Action rejected by server.';
            final code = ((error['status'] as String?) ?? 'unknown')
                .toLowerCase()
                .replaceAll('_', '-');
            throw FirebaseFunctionsException(
              message: message,
              code: code,
            );
          }
        }
        logWarning(
          '[Card29Api] VPS call $name failed (${e.message}). Falling back to Functions.', e);
      } catch (e, st) {
        if (e is FirebaseFunctionsException) rethrow;
        logWarning(
          '[Card29Api] VPS call $name error. Falling back to Functions.', e, st);
      }
    }

    final result = await _functions.httpsCallable(name).call<dynamic>(payload);
    return result.data;
  }
}
