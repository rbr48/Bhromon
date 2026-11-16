import 'dart:async';

import 'package:bhromon/features/chat/data/call_ice_config.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> serverBody({required int expiresAtSeconds}) => {
      'iceServers': [
        {
          'urls': ['stun:stun.example:3478'],
        },
        {
          'urls': ['turn:turn.example:3478'],
          'username': '1:uid',
          'credential': 'secret',
        },
      ],
      'sdpSemantics': 'unified-plan',
      'expiresAt': expiresAtSeconds,
    };

int secondsFrom(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;

void main() {
  group('CallIceConfig.parse', () {
    test('keeps the servers the chat server sends', () {
      final config = CallIceConfig.parse(serverBody(expiresAtSeconds: 1));

      expect(config, isNotNull);
      expect((config!['iceServers'] as List).length, 2);
      expect(config['sdpSemantics'], 'unified-plan');
    });

    test('rejects a response with no servers', () {
      expect(CallIceConfig.parse(null), isNull);
      expect(CallIceConfig.parse({'iceServers': <Object>[]}), isNull);
      expect(CallIceConfig.parse({'other': 1}), isNull);
    });
  });

  group('CallIceConfig.current', () {
    test('asks once, and renews shortly before the credential expires',
        () async {
      var now = DateTime.fromMillisecondsSinceEpoch(0);
      var fetches = 0;
      final expiresAt = secondsFrom(now.add(const Duration(hours: 1)));
      final ice = CallIceConfig(
        fetch: () async {
          fetches++;
          return serverBody(expiresAtSeconds: expiresAt);
        },
        clock: () => now,
      );

      await ice.current();
      await ice.current();
      expect(fetches, 1);

      // Renewal starts ten minutes before expiry, which is at fifty minutes.
      now = now.add(const Duration(minutes: 49));
      await ice.current();
      expect(fetches, 1);

      now = now.add(const Duration(minutes: 2));
      await ice.current();
      expect(fetches, 2);
    });

    test('falls back to STUN without credentials, and asks again next time',
        () async {
      var fetches = 0;
      final ice = CallIceConfig(
        fetch: () async {
          fetches++;
          return null;
        },
        clock: () => DateTime(2026),
      );

      final first = await ice.current();
      expect(first, CallIceConfig.stunOnly);
      expect(first.toString(), isNot(contains('username')));

      // Each attempt asks twice before giving up on TURN.
      expect(fetches, 2);
      await ice.current();
      expect(fetches, 4);
    });

    test('keeps the last credential while it still works if a refresh fails',
        () async {
      var now = DateTime.fromMillisecondsSinceEpoch(0);
      var serverUp = true;
      final expiresAt = secondsFrom(now.add(const Duration(hours: 1)));
      final ice = CallIceConfig(
        fetch: () async =>
            serverUp ? serverBody(expiresAtSeconds: expiresAt) : null,
        clock: () => now,
      );

      final first = await ice.current();
      serverUp = false;

      // In the refresh window, but before expiry: the old credential is kept.
      now = now.add(const Duration(minutes: 55));
      expect(await ice.current(), first);

      // After expiry it is no use any more.
      now = now.add(const Duration(minutes: 10));
      expect(await ice.current(), CallIceConfig.stunOnly);
    });

    test('callers that arrive together share one request', () async {
      var fetches = 0;
      final gate = Completer<Map<String, dynamic>?>();
      final ice = CallIceConfig(
        fetch: () {
          fetches++;
          return gate.future;
        },
        clock: () => DateTime(2026),
      );

      final first = ice.current();
      final second = ice.current();
      gate.complete(serverBody(
        expiresAtSeconds:
            secondsFrom(DateTime(2026).add(const Duration(hours: 1))),
      ));
      await Future.wait([first, second]);

      expect(fetches, 1);
    });

    test('the fallback never carries a shared TURN credential', () {
      final text = CallIceConfig.stunOnly.toString();

      expect(text, isNot(contains('openrelay')));
      expect(text, isNot(contains('credential')));
    });

    test('refresh forces a new fetch while keeping valid cache on outage',
        () async {
      var fetches = 0;
      var now = DateTime.fromMillisecondsSinceEpoch(0);
      final expiresAt = secondsFrom(now.add(const Duration(hours: 1)));
      var serverUp = true;
      final ice = CallIceConfig(
        fetch: () async {
          fetches++;
          return serverUp ? serverBody(expiresAtSeconds: expiresAt) : null;
        },
        clock: () => now,
      );

      final first = await ice.current();
      expect(fetches, 1);

      // Regular current() hits cache.
      await ice.current();
      expect(fetches, 1);

      // refresh() fetches again when server is healthy.
      await ice.refresh();
      expect(fetches, 2);

      // If refresh() fails before expiry, cached TURN config is still kept.
      serverUp = false;
      expect(await ice.refresh(), first);

      // invalidate() drops the cache completely.
      ice.invalidate();
      expect(await ice.current(), CallIceConfig.stunOnly);
    });

    test(
        'short-TTL credentials schedule refresh before expiry and reject expired',
        () async {
      var fetches = 0;
      var now = DateTime(2026);
      final ice = CallIceConfig(
        fetch: () async {
          fetches++;
          if (fetches == 1) {
            // 4-minute TTL (shorter than 10-minute refreshBeforeExpiry).
            return serverBody(
                expiresAtSeconds:
                    secondsFrom(now.add(const Duration(minutes: 4))));
          }
          // Expired timestamp must not be cached.
          return serverBody(
              expiresAtSeconds:
                  secondsFrom(now.subtract(const Duration(minutes: 1))));
        },
        clock: () => now,
      );

      await ice.current();
      expect(fetches, 1);

      // 1 minute later (before 2m halfway point): still cached.
      now = now.add(const Duration(minutes: 1));
      await ice.current();
      expect(fetches, 1);

      // 2.5 minutes later (past 2m halfway refresh, before 4m expiry): refreshes,
      // receives expired payload -> falls back to STUN only.
      now = now.add(const Duration(minutes: 2));
      expect(await ice.current(), CallIceConfig.stunOnly);
    });
  });
}
