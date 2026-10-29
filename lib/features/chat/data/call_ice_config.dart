import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// The ICE servers (STUN and the VPS TURN relay) for a call or a voice room.
///
/// The chat server mints the TURN credential for the signed-in user, and it
/// expires after an hour. Nothing secret ships in the app. The config is kept
/// until shortly before it expires. If the server cannot give one, the call
/// still gets STUN, which works on most networks.
class CallIceConfig {
  CallIceConfig({
    Future<Map<String, dynamic>?> Function()? fetch,
    DateTime Function()? clock,
  })  : _fetch = fetch ?? _fetchFromServer,
        _clock = clock ?? DateTime.now;

  /// One config shared by every call and voice room in the app.
  static final CallIceConfig shared = CallIceConfig();

  static const String endpoint = 'https://bhromon.fun/api/chat/ice_servers';

  /// Renew this long before the server's expiry, so a call never starts on a
  /// credential that is about to lapse.
  static const Duration refreshBeforeExpiry = Duration(minutes: 10);

  /// Used when no TURN credential is available.
  static const Map<String, dynamic> stunOnly = {
    'iceServers': [
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
          'stun:stun.cloudflare.com:3478',
        ],
      },
    ],
    'sdpSemantics': 'unified-plan',
  };

  final Future<Map<String, dynamic>?> Function() _fetch;
  final DateTime Function() _clock;

  Map<String, dynamic>? _cached;
  DateTime? _refreshAt;
  Future<Map<String, dynamic>>? _inFlight;

  /// The ICE configuration to use now. Callers that arrive together share one request.
  Future<Map<String, dynamic>> current() {
    final cached = _cached;
    final refreshAt = _refreshAt;
    if (cached != null && refreshAt != null && _clock().isBefore(refreshAt)) {
      return Future.value(cached);
    }
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  Future<Map<String, dynamic>> _load() async {
    final body = await _fetch();
    final config = parse(body);
    if (config == null) {
      // Not cached, so the next call asks the server again.
      _cached = null;
      _refreshAt = null;
      return stunOnly;
    }
    _cached = config;
    final expiresAt = _expiryOf(body!);
    _refreshAt = expiresAt == null
        ? _clock().add(const Duration(minutes: 5))
        : expiresAt.subtract(refreshBeforeExpiry);
    return config;
  }

  /// The ICE servers from a server response, or null when the response is not usable.
  static Map<String, dynamic>? parse(Map<String, dynamic>? body) {
    final servers = body?['iceServers'];
    if (servers is! List || servers.isEmpty) return null;
    return {
      'iceServers': servers,
      'sdpSemantics': body?['sdpSemantics'] ?? 'unified-plan',
    };
  }

  static DateTime? _expiryOf(Map<String, dynamic> body) {
    final seconds = body['expiresAt'];
    if (seconds is! num) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000);
  }

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );

  static Future<Map<String, dynamic>?> _fetchFromServer() async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) return null;
      final response = await _dio.get<Map<String, dynamic>>(
        endpoint,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response.data;
    } catch (e) {
      // The token is never logged.
      debugPrint('[CallIceConfig] TURN unavailable, using STUN only: $e');
      return null;
    }
  }
}
