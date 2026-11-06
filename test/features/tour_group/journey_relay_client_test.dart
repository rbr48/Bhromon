import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/features/tour_group/data/journey_relay_client.dart';
import 'package:bhromon/features/tour_group/domain/services/live_journey_tracker.dart';

class _FakeSocket implements JourneyRelaySocket {
  final StreamController<Object?> incoming = StreamController<Object?>();
  final List<String> sent = [];
  bool closed = false;

  @override
  Stream<Object?> get messages => incoming.stream;

  @override
  void send(String text) => sent.add(text);

  @override
  Future<void> close() async {
    closed = true;
  }

  Map<String, Object?> decodeSent(int index) =>
      jsonDecode(sent[index]) as Map<String, Object?>;
}

JourneyFix _fix(DateTime time, {double lat = 23.0, double lng = 90.5}) =>
    JourneyFix(lat: lat, lng: lng, time: time, accuracyM: 5, speedMps: 10);

/// A client whose sockets are recorded in [sockets].
JourneyRelayClient _client(
  List<_FakeSocket> sockets,
  DateTime Function() now, {
  Future<String?> Function()? token,
}) {
  return JourneyRelayClient(
    open: (uri) async {
      final socket = _FakeSocket();
      sockets.add(socket);
      return socket;
    },
    authToken: token ?? () async => 'token-1',
    now: now,
  );
}

void main() {
  group('journey relay client', () {
    test('sends the token first, then a position once the relay is ready', () {
      fakeAsync((async) {
        final clock = async.getClock(DateTime.utc(2027, 1, 13, 20));
        final sockets = <_FakeSocket>[];
        final client = _client(sockets, clock.now);

        unawaited(client.connect('tour-1'));
        async.flushMicrotasks();
        final socket = sockets.single;
        expect(socket.decodeSent(0), {'t': 'auth', 'token': 'token-1'},
            reason: 'the token is in a message, not the URL');

        socket.incoming.add(jsonEncode({'t': 'ready'}));
        async.flushMicrotasks();
        expect(client.isReady, isTrue);

        client.offer(_fix(clock.now()));
        expect(socket.sent, hasLength(2));
        expect(socket.decodeSent(1)['t'], 'pos');

        unawaited(client.close());
        async.flushMicrotasks();
        expect(socket.closed, isTrue);
      });
    });

    test('a heartbeat keeps the member fresh while no reading is sent', () {
      fakeAsync((async) {
        final clock = async.getClock(DateTime.utc(2027, 1, 13, 20));
        final sockets = <_FakeSocket>[];
        final client = _client(sockets, clock.now);
        unawaited(client.connect('tour-1'));
        async.flushMicrotasks();
        final socket = sockets.single;
        socket.incoming.add(jsonEncode({'t': 'ready'}));
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 59));
        expect(socket.sent.where((m) => m.contains('"hb"')), isEmpty);
        async.elapse(const Duration(seconds: 1));
        expect(socket.sent.where((m) => m.contains('"hb"')), hasLength(1));

        unawaited(client.close());
        async.elapse(const Duration(minutes: 5));
        expect(socket.sent.where((m) => m.contains('"hb"')), hasLength(1),
            reason: 'no heartbeat after the relay is closed');
      });
    });

    test('readings before the relay is ready are dropped', () {
      fakeAsync((async) {
        final clock = async.getClock(DateTime.utc(2027, 1, 13, 20));
        final sockets = <_FakeSocket>[];
        final client = _client(sockets, clock.now);

        unawaited(client.connect('tour-1'));
        async.flushMicrotasks();
        client.offer(_fix(clock.now()));
        expect(sockets.single.sent, hasLength(1),
            reason: 'only the auth message');
        unawaited(client.close());
      });
    });

    test('at most one position per interval is sent', () {
      fakeAsync((async) {
        final clock = async.getClock(DateTime.utc(2027, 1, 13, 20));
        final sockets = <_FakeSocket>[];
        final client = _client(sockets, clock.now);
        unawaited(client.connect('tour-1'));
        async.flushMicrotasks();
        final socket = sockets.single;
        socket.incoming.add(jsonEncode({'t': 'ready'}));
        async.flushMicrotasks();

        client.offer(_fix(clock.now()));
        client.offer(_fix(clock.now()));
        expect(socket.sent, hasLength(2),
            reason: 'the second reading is dropped');

        async.elapse(const Duration(seconds: 15));
        client.offer(_fix(clock.now()));
        expect(socket.sent, hasLength(3));
        unawaited(client.close());
      });
    });

    test('other members\' positions are delivered to listeners', () {
      fakeAsync((async) {
        final clock = async.getClock(DateTime.utc(2027, 1, 13, 20));
        final sockets = <_FakeSocket>[];
        final client = _client(sockets, clock.now);
        final received = <RelayPosition>[];
        client.positions.listen(received.add);

        unawaited(client.connect('tour-1'));
        async.flushMicrotasks();
        sockets.single.incoming.add(jsonEncode({
          't': 'pos',
          'uid': 'u2',
          'lat': 23.1,
          'lng': 90.6,
          'acc': 8,
          'ts': DateTime.utc(2027, 1, 13, 20).millisecondsSinceEpoch,
        }));
        async.flushMicrotasks();

        expect(received.single.uid, 'u2');
        expect(received.single.lat, 23.1);
        expect(received.single.accuracyM, 8);
        unawaited(client.close());
      });
    });

    test('a malformed position is ignored', () {
      fakeAsync((async) {
        final clock = async.getClock(DateTime.utc(2027, 1, 13, 20));
        final sockets = <_FakeSocket>[];
        final client = _client(sockets, clock.now);
        final received = <RelayPosition>[];
        client.positions.listen(received.add);
        unawaited(client.connect('tour-1'));
        async.flushMicrotasks();
        sockets.single.incoming
          ..add('not json')
          ..add(jsonEncode({'t': 'pos', 'uid': 'u2', 'lat': 'north'}));
        async.flushMicrotasks();
        expect(received, isEmpty);
        unawaited(client.close());
      });
    });

    test('a lost connection is retried, with a growing wait', () {
      fakeAsync((async) {
        final clock = async.getClock(DateTime.utc(2027, 1, 13, 20));
        final sockets = <_FakeSocket>[];
        final client = _client(sockets, clock.now);
        unawaited(client.connect('tour-1'));
        async.flushMicrotasks();
        expect(sockets, hasLength(1));

        // The first retry waits 2 seconds.
        unawaited(sockets.last.incoming.close());
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        expect(sockets, hasLength(1));
        async.elapse(const Duration(seconds: 1));
        expect(sockets, hasLength(2));

        // The second waits 4 seconds.
        unawaited(sockets.last.incoming.close());
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));
        expect(sockets, hasLength(2));
        async.elapse(const Duration(seconds: 1));
        expect(sockets, hasLength(3));
        unawaited(client.close());
      });
    });

    test('a refused membership stops the relay for good', () {
      fakeAsync((async) {
        final clock = async.getClock(DateTime.utc(2027, 1, 13, 20));
        final sockets = <_FakeSocket>[];
        final client = _client(sockets, clock.now);
        unawaited(client.connect('tour-1'));
        async.flushMicrotasks();
        sockets.single.incoming
            .add(jsonEncode({'t': 'err', 'code': 'forbidden'}));
        async.flushMicrotasks();
        expect(sockets.single.closed, isTrue);

        async.elapse(const Duration(minutes: 5));
        expect(sockets, hasLength(1), reason: 'no retry after a refusal');
      });
    });

    test('no signed-in member means no relay and no retries', () {
      fakeAsync((async) {
        final clock = async.getClock(DateTime.utc(2027, 1, 13, 20));
        final sockets = <_FakeSocket>[];
        final client = _client(sockets, clock.now, token: () async => null);
        unawaited(client.connect('tour-1'));
        async.flushMicrotasks();
        expect(sockets.single.closed, isTrue);

        async.elapse(const Duration(minutes: 5));
        expect(sockets, hasLength(1));
      });
    });

    test('close stops the reconnects', () {
      fakeAsync((async) {
        final clock = async.getClock(DateTime.utc(2027, 1, 13, 20));
        final sockets = <_FakeSocket>[];
        final client = _client(sockets, clock.now);
        unawaited(client.connect('tour-1'));
        async.flushMicrotasks();
        unawaited(sockets.last.incoming.close());
        async.flushMicrotasks();
        unawaited(client.close());
        async.elapse(const Duration(minutes: 5));
        expect(sockets, hasLength(1));
      });
    });
  });
}
