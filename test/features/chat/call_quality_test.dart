import 'package:bhromon/features/chat/domain/call_quality.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classifyCallLink', () {
    test('a clean link is good', () {
      const sample = CallLinkSample(
        roundTripMs: 90,
        jitterMs: 8,
        lossRatio: 0.01,
      );

      expect(classifyCallLink(sample), CallNetworkQuality.good);
    });

    test('a slow round trip alone makes the link fair, not weak', () {
      const sample = CallLinkSample(roundTripMs: 350, lossRatio: 0);

      expect(classifyCallLink(sample), CallNetworkQuality.fair);
    });

    test('jitter above 40 ms is fair and above 120 ms is weak', () {
      expect(
        classifyCallLink(const CallLinkSample(jitterMs: 50)),
        CallNetworkQuality.fair,
      );
      expect(
        classifyCallLink(const CallLinkSample(jitterMs: 130)),
        CallNetworkQuality.poor,
      );
    });

    test('loss decides first: over 5 % is fair and over 15 % is weak', () {
      expect(
        classifyCallLink(const CallLinkSample(lossRatio: 0.06)),
        CallNetworkQuality.fair,
      );
      expect(
        classifyCallLink(const CallLinkSample(lossRatio: 0.2, roundTripMs: 40)),
        CallNetworkQuality.poor,
      );
    });

    test('a round trip beyond 800 ms is weak whatever the loss', () {
      expect(
        classifyCallLink(const CallLinkSample(roundTripMs: 900, lossRatio: 0)),
        CallNetworkQuality.poor,
      );
    });

    test('a sample with no figures rates as good, and reports no media', () {
      const sample = CallLinkSample();

      expect(classifyCallLink(sample), CallNetworkQuality.good);
      expect(sample.hasIncomingMedia, isFalse);
    });
  });

  group('videoBitrateCapFor', () {
    test('the cap falls as the link gets weaker', () {
      final good = videoBitrateCapFor(CallNetworkQuality.good);
      final fair = videoBitrateCapFor(CallNetworkQuality.fair);
      final poor = videoBitrateCapFor(CallNetworkQuality.poor);

      expect(good, greaterThan(fair));
      expect(fair, greaterThan(poor));
      expect(poor, greaterThan(0));
    });
  });

  group('callConnectedSeconds', () {
    final connectedAt = DateTime(2026, 10, 31, 10);

    test('is zero before the media connects', () {
      expect(
        callConnectedSeconds(connectedAt: null, now: connectedAt),
        0,
      );
    });

    test('a call that connected counts at least one second', () {
      expect(
        callConnectedSeconds(connectedAt: connectedAt, now: connectedAt),
        1,
      );
    });

    test('counts whole seconds since the media connected', () {
      expect(
        callConnectedSeconds(
          connectedAt: connectedAt,
          now: connectedAt.add(const Duration(seconds: 75, milliseconds: 900)),
        ),
        75,
      );
    });
  });

  group('callLinkSampleFromStats', () {
    test('reads the round trip from the pair in use, in milliseconds', () {
      final sample = callLinkSampleFromStats([
        {
          'type': 'candidate-pair',
          'nominated': false,
          'currentRoundTripTime': 0.9,
        },
        {
          'type': 'candidate-pair',
          'nominated': true,
          'currentRoundTripTime': 0.12,
        },
      ]);

      expect(sample.roundTripMs, closeTo(120, 1e-9));
    });

    test('sums packets across incoming streams and takes the worst jitter', () {
      final sample = callLinkSampleFromStats([
        {
          'type': 'inbound-rtp',
          'packetsLost': 4,
          'packetsReceived': 96,
          'jitter': 0.01,
        },
        {
          'type': 'inbound-rtp',
          'packetsLost': 0,
          'packetsReceived': 100,
          'jitter': 0.05,
        },
      ]);

      expect(sample.lossRatio, closeTo(4 / 200, 1e-9));
      expect(sample.jitterMs, closeTo(50, 1e-9));
      expect(sample.hasIncomingMedia, isTrue);
    });

    test('adds up the bytes sent on every outgoing stream', () {
      final sample = callLinkSampleFromStats([
        {'type': 'outbound-rtp', 'bytesSent': 1000},
        {'type': 'outbound-rtp', 'bytesSent': 2500},
      ]);

      expect(sample.sentBytes, 3500);
      expect(sample.hasIncomingMedia, isFalse);
    });

    test('an empty poll says nothing about the link', () {
      final sample = callLinkSampleFromStats(const []);

      expect(sample.hasIncomingMedia, isFalse);
      expect(sample.sentBytes, isNull);
    });
  });

  group('OutboundBitrateMeter', () {
    test('the first reading has no rate yet', () {
      final meter = OutboundBitrateMeter();

      expect(meter.kbpsAt(10000, DateTime(2026)), isNull);
    });

    test('gives the kilobits per second since the previous reading', () {
      final meter = OutboundBitrateMeter();
      final start = DateTime(2026);
      meter.kbpsAt(0, start);

      // 125,000 bytes in one second is 1,000 kbps.
      expect(
        meter.kbpsAt(125000, start.add(const Duration(seconds: 1))),
        closeTo(1000, 1e-9),
      );
    });

    test('a count that went down starts again rather than going negative', () {
      final meter = OutboundBitrateMeter();
      final start = DateTime(2026);
      meter.kbpsAt(500000, start);

      expect(
        meter.kbpsAt(1000, start.add(const Duration(seconds: 2))),
        isNull,
      );
    });
  });

  group('CallReconnectPolicy', () {
    test('allows the configured number of rebuilds and no more', () {
      final policy = CallReconnectPolicy(maxAttempts: 2);

      expect(policy.startAttempt(), isTrue);
      expect(policy.startAttempt(), isTrue);
      expect(policy.startAttempt(), isFalse);
      expect(policy.attempts, 2);
    });
  });
}
