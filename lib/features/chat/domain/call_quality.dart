/// Rules for a live call that do not need WebRTC: how good the link is, how much
/// video to send, how long the call has been connected, and how many times it
/// may try to rebuild a dropped link. The call service feeds them numbers from
/// the peer connection's stats.
library;

/// How good a call's link is. The call screen shows this as HD, Fair or Weak.
enum CallNetworkQuality {
  good,
  fair,
  poor,
}

/// The figures one stats poll gives for the link. A null field was not reported.
class CallLinkSample {
  const CallLinkSample({
    this.roundTripMs,
    this.jitterMs,
    this.lossRatio,
    this.sentBytes,
    this.outboundKbps,
  });

  /// Round trip to the other side, in milliseconds.
  final double? roundTripMs;

  /// The worst jitter across the incoming streams, in milliseconds.
  final double? jitterMs;

  /// Share of incoming packets that never arrived, from 0 to 1.
  final double? lossRatio;

  /// Bytes sent so far on all outgoing streams. A running total.
  final int? sentBytes;

  /// Sending rate since the previous poll, in kilobits per second.
  final double? outboundKbps;

  /// True when the poll had incoming media to judge the link by.
  bool get hasIncomingMedia =>
      roundTripMs != null || jitterMs != null || lossRatio != null;

  CallLinkSample withOutboundKbps(double? kbps) => CallLinkSample(
        roundTripMs: roundTripMs,
        jitterMs: jitterMs,
        lossRatio: lossRatio,
        sentBytes: sentBytes,
        outboundKbps: kbps,
      );
}

/// Rates a link. Loss decides first, then round trip and jitter, so a clean
/// but slow link is still rated by its delay.
CallNetworkQuality classifyCallLink(CallLinkSample sample) {
  final loss = sample.lossRatio ?? 0;
  final roundTrip = sample.roundTripMs ?? 0;
  final jitter = sample.jitterMs ?? 0;
  if (loss > 0.15 || roundTrip > 800 || jitter > 120) {
    return CallNetworkQuality.poor;
  }
  if (loss > 0.05 || roundTrip > 300 || jitter > 40) {
    return CallNetworkQuality.fair;
  }
  return CallNetworkQuality.good;
}

/// The most video this device may send, in bits per second, at each quality.
/// A weak link gets a smaller picture rather than a stalled one.
int videoBitrateCapFor(CallNetworkQuality quality) => switch (quality) {
      CallNetworkQuality.good => 1500000,
      CallNetworkQuality.fair => 700000,
      CallNetworkQuality.poor => 250000,
    };

/// Whole seconds the call has been connected. Zero before media connects. A
/// call that connected counts at least one second.
int callConnectedSeconds(
    {required DateTime? connectedAt, required DateTime now}) {
  if (connectedAt == null) return 0;
  final elapsed = now.difference(connectedAt).inSeconds;
  return elapsed < 1 ? 1 : elapsed;
}

/// Reads one stats poll. Each report is the values of one WebRTC stats entry,
/// with its `type` included.
CallLinkSample callLinkSampleFromStats(Iterable<Map<String, dynamic>> reports) {
  double? roundTripSeconds;
  double? jitterSeconds;
  var lost = 0;
  var received = 0;
  int? sentBytes;

  for (final report in reports) {
    switch (report['type']) {
      case 'candidate-pair':
        // Only the pair in use counts. Other pairs have no RTT worth showing.
        if (report['nominated'] == true) {
          roundTripSeconds =
              _asDouble(report['currentRoundTripTime']) ?? roundTripSeconds;
        }
      case 'inbound-rtp':
        lost += _asInt(report['packetsLost']) ?? 0;
        received += _asInt(report['packetsReceived']) ?? 0;
        final jitter = _asDouble(report['jitter']);
        if (jitter != null &&
            (jitterSeconds == null || jitter > jitterSeconds)) {
          jitterSeconds = jitter;
        }
      case 'outbound-rtp':
        sentBytes = (sentBytes ?? 0) + (_asInt(report['bytesSent']) ?? 0);
    }
  }

  final total = lost + received;
  return CallLinkSample(
    roundTripMs: roundTripSeconds == null ? null : roundTripSeconds * 1000,
    jitterMs: jitterSeconds == null ? null : jitterSeconds * 1000,
    lossRatio: total == 0 ? null : lost / total,
    sentBytes: sentBytes,
  );
}

/// Turns a running byte count into a sending rate, one reading at a time.
class OutboundBitrateMeter {
  int? _lastBytes;
  DateTime? _lastAt;

  /// Kilobits per second since the last reading. Null for the first reading,
  /// when no time has passed, or when the count went down (a restarted stream).
  double? kbpsAt(int bytes, DateTime at) {
    final previousBytes = _lastBytes;
    final previousAt = _lastAt;
    _lastBytes = bytes;
    _lastAt = at;
    if (previousBytes == null || previousAt == null) return null;
    final seconds = at.difference(previousAt).inMilliseconds / 1000;
    if (seconds <= 0 || bytes < previousBytes) return null;
    return (bytes - previousBytes) * 8 / 1000 / seconds;
  }
}

/// How many times a call may rebuild a dropped link before it gives up.
class CallReconnectPolicy {
  CallReconnectPolicy({this.maxAttempts = 3});

  final int maxAttempts;
  int _attempts = 0;

  int get attempts => _attempts;

  /// Counts one attempt that is starting. Returns false when none are left.
  bool startAttempt() {
    if (_attempts >= maxAttempts) return false;
    _attempts++;
    return true;
  }
}

double? _asDouble(Object? value) => value is num ? value.toDouble() : null;

int? _asInt(Object? value) => value is num ? value.toInt() : null;
