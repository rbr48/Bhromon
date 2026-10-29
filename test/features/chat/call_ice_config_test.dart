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
      expect(CallIceConfig.parse({'iceServers': []}), isNull);
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

      await ice.current();
      expect(fetches, 2);
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
  });
}
