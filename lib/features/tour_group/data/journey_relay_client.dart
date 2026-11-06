import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/utils/app_logger.dart';
import '../domain/services/live_journey_tracker.dart';
import 'live_journey_session.dart';

/// Where the group's live relay runs (roadmap section 4, LJ-4.4). The token is
/// sent as the first message, never in the URL, so it stays out of the logs.
final Uri kJourneyRelayUri = Uri.parse('wss://bhromon.fun/api/live/ws');

/// One other member's position, as the relay sends it. Positions are shown on
/// screen only. They are never stored on the device or on the server (roadmap
/// section 4).
class RelayPosition {
  const RelayPosition({
    required this.uid,
    required this.lat,
    required this.lng,
    required this.at,
    this.accuracyM,
  });

  final String uid;
  final double lat;
  final double lng;
  final DateTime at;
  final double? accuracyM;
}

/// The socket the relay talks through. The app wraps `web_socket_channel`, and
/// the tests use a fake.
abstract class JourneyRelaySocket {
  Stream<Object?> get messages;
  void send(String text);
  Future<void> close();
}

/// Opens a socket to [uri] and waits until it is connected.
typedef JourneyRelayOpener = Future<JourneyRelaySocket> Function(Uri uri);

/// Sends this member's position to the group and receives the others' (roadmap
/// LJ-4.5).
///
/// The client sends at most one position per [interval], because the server
/// allows one per five seconds. It reconnects with backoff while [connect] has
/// been called and [close] has not. Sign-in failures and a refused membership
/// stop it for good.
class JourneyRelayClient implements JourneyRelayPort {
  JourneyRelayClient({
    required this.open,
    required this.authToken,
    Uri? uri,
    this.interval = const Duration(seconds: 15),
    this.heartbeatEvery = const Duration(seconds: 60),
    this.maxBackoff = const Duration(seconds: 60),
    DateTime Function()? now,
  })  : _uri = uri ?? kJourneyRelayUri,
        _now = now ?? DateTime.now;

  /// Opens the socket.
  final JourneyRelayOpener open;

  /// The signed-in member's ID token, or null when there is none.
  final Future<String?> Function() authToken;

  /// The shortest time between two positions this client sends.
  final Duration interval;

  /// How often a heartbeat keeps the member fresh on the server, when the
  /// phone has no new reading to send (the server drops a member silent for two
  /// minutes).
  final Duration heartbeatEvery;

  /// The longest wait between two connection attempts.
  final Duration maxBackoff;

  final Uri _uri;
  final DateTime Function() _now;

  final StreamController<RelayPosition> _positions =
      StreamController<RelayPosition>.broadcast();

  /// The other members' positions, as they arrive.
  Stream<RelayPosition> get positions => _positions.stream;

  String? _tourId;
  JourneyRelaySocket? _socket;
  StreamSubscription<Object?>? _subscription;
  Timer? _retry;
  Timer? _heartbeat;
  int _attempt = 0;
  DateTime? _lastSentAt;
  bool _wanted = false;
  bool _ready = false;

  /// Whether the relay has accepted this member and can send.
  bool get isReady => _ready;

  /// Connects for [tourId], and keeps connecting until [close].
  @override
  Future<void> connect(String tourId) async {
    if (_wanted && _tourId == tourId) return;
    await close();
    _tourId = tourId;
    _wanted = true;
    _attempt = 0;
    await _open();
  }

  /// Sends [fix] when the relay is ready and the interval has passed. Other
  /// readings are dropped: the group needs the latest position, not every one.
  @override
  void offer(JourneyFix fix) {
    final socket = _socket;
    if (socket == null || !_ready) return;
    final now = _now();
    final last = _lastSentAt;
    if (last != null && now.difference(last) < interval) return;
    _lastSentAt = now;
    socket.send(jsonEncode({
      't': 'pos',
      'lat': fix.lat,
      'lng': fix.lng,
      'acc': fix.accuracyM,
      'spd': fix.speedMps,
      'ts': fix.time.millisecondsSinceEpoch,
    }));
  }

  /// Stops the relay for good: no reconnects, and the socket is closed.
  @override
  Future<void> close() async {
    _wanted = false;
    _tourId = null;
    _retry?.cancel();
    _retry = null;
    _lastSentAt = null;
    _drop();
  }

  Future<void> _open() async {
    if (!_wanted) return;
    final tourId = _tourId;
    if (tourId == null) return;
    try {
      final socket =
          await open(_uri.replace(queryParameters: {'tour': tourId}));
      if (!_wanted) {
        await socket.close();
        return;
      }
      _socket = socket;
      _ready = false;
      _subscription = socket.messages.listen(
        _onMessage,
        onError: (Object error, StackTrace stackTrace) {
          logSkipped(error, stackTrace);
          _lost();
        },
        onDone: _lost,
        cancelOnError: true,
      );
      final token = await authToken();
      if (token == null) {
        // Without a signed-in member the relay cannot start, and retrying will not help.
        await close();
        return;
      }
      if (_socket == socket) {
        socket.send(jsonEncode({'t': 'auth', 'token': token}));
      }
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
      _lost();
    }
  }

  void _onMessage(Object? raw) {
    if (raw is! String) return;
    final Object? data;
    try {
      data = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (data is! Map) return;
    switch (data['t']) {
      case 'ready':
        _ready = true;
        _attempt = 0;
        _startHeartbeat();
        break;
      case 'pos':
        final position = _positionFrom(data);
        if (position != null) _positions.add(position);
        break;
      case 'err':
        // A refused membership or sign-in will not succeed on retry.
        final code = data['code'];
        if (code == 'auth' || code == 'forbidden') {
          unawaited(close());
        }
        break;
    }
  }

  RelayPosition? _positionFrom(Map<dynamic, dynamic> data) {
    final uid = data['uid'];
    final lat = data['lat'];
    final lng = data['lng'];
    final ts = data['ts'];
    if (uid is! String || lat is! num || lng is! num || ts is! num) return null;
    final acc = data['acc'];
    return RelayPosition(
      uid: uid,
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      at: DateTime.fromMillisecondsSinceEpoch(ts.toInt(), isUtc: true),
      accuracyM: acc is num ? acc.toDouble() : null,
    );
  }

  /// The connection was lost. Retry after a growing wait, while still wanted.
  void _lost() {
    _drop();
    if (!_wanted) return;
    final wait = _backoff(_attempt);
    _attempt++;
    _retry?.cancel();
    _retry = Timer(wait, () => unawaited(_open()));
  }

  Duration _backoff(int attempt) {
    final seconds = 2 * math.pow(2, math.min(attempt, 5)).toInt();
    return Duration(seconds: math.min(seconds, maxBackoff.inSeconds));
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(heartbeatEvery, (_) {
      final socket = _socket;
      if (socket != null && _ready) socket.send(jsonEncode({'t': 'hb'}));
    });
  }

  void _drop() {
    _heartbeat?.cancel();
    _heartbeat = null;
    _ready = false;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    final socket = _socket;
    _socket = null;
    if (socket != null) unawaited(socket.close());
  }
}

/// The real socket, on `web_socket_channel`.
class WebSocketJourneyRelaySocket implements JourneyRelaySocket {
  WebSocketJourneyRelaySocket(this._channel);

  final WebSocketChannel _channel;

  @override
  Stream<Object?> get messages => _channel.stream;

  @override
  void send(String text) => _channel.sink.add(text);

  @override
  Future<void> close() => _channel.sink.close();
}

/// Opens the relay over a real WebSocket.
Future<JourneyRelaySocket> openJourneyRelaySocket(Uri uri) async {
  final channel = WebSocketChannel.connect(uri);
  await channel.ready;
  return WebSocketJourneyRelaySocket(channel);
}
