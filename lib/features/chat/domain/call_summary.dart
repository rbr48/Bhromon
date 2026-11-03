import 'call_quality.dart';

/// How a call ended, as the summary reports it.
enum CallEndReason { ended, declined, missed, cancelled, failed }

/// Maps the status written to the call document (or the UI state) to a reason.
CallEndReason callEndReasonFor(String? documentStatus) {
  switch (documentStatus) {
    case 'declined':
      return CallEndReason.declined;
    case 'missed':
      return CallEndReason.missed;
    case 'cancelled':
      return CallEndReason.cancelled;
    case 'failed':
      return CallEndReason.failed;
    default:
      return CallEndReason.ended;
  }
}

/// The path the media takes, from the selected candidate pair in the stats:
/// `host`, `srflx`, `prflx` or `relay` (TURN). Null when no pair is selected yet.
String? pathTypeFromStats(Iterable<Map<String, dynamic>> reports) {
  final list = reports.toList();
  Map<String, dynamic>? pair;
  for (final report in list) {
    if (report['type'] != 'candidate-pair') {
      continue;
    }
    final selected = report['selected'] == true || report['nominated'] == true;
    if (!selected) continue;
    // Prefer the pair that is actually succeeding, if there are several.
    if (pair == null || report['state'] == 'succeeded') pair = report;
  }
  if (pair == null) return null;
  final localId = pair['localCandidateId']?.toString();
  if (localId == null) return null;
  for (final report in list) {
    if (report['id']?.toString() != localId) continue;
    final type = report['candidateType']?.toString();
    return type == null || type.isEmpty ? null : type;
  }
  return null;
}

/// What one side of a call reports when the call ends. It holds only the call
/// id, numbers and short labels. It holds no names, emails or message text.
class CallSummary {
  const CallSummary({
    required this.callId,
    required this.isCaller,
    required this.isVideo,
    required this.endReason,
    required this.connectedSeconds,
    required this.reconnects,
    this.timeToConnectedMs,
    this.pathType,
    this.lossPercent,
    this.jitterMs,
    this.networkType,
  });

  final String callId;
  final bool isCaller;
  final bool isVideo;
  final CallEndReason endReason;
  final int connectedSeconds;
  final int reconnects;

  /// From the first ring to the first connected media, or null if it never connected.
  final int? timeToConnectedMs;
  final String? pathType;
  final double? lossPercent;
  final int? jitterMs;
  final String? networkType;

  /// The summary as Crashlytics custom keys. Crashlytics keeps at most 64 keys
  /// and values up to 100 characters, so every value here is short.
  Map<String, String> toKeys() {
    final keys = <String, String>{
      'call_callId': callId,
      'call_role': isCaller ? 'caller' : 'callee',
      'call_kind': isVideo ? 'video' : 'voice',
      'call_end': endReason.name,
      'call_connected_s': '$connectedSeconds',
      'call_reconnects': '$reconnects',
    };
    if (timeToConnectedMs != null) {
      keys['call_ttc_ms'] = '$timeToConnectedMs';
    }
    if (pathType != null) keys['call_path'] = pathType!;
    if (lossPercent != null) {
      keys['call_loss_pct'] = lossPercent!.toStringAsFixed(1);
    }
    if (jitterMs != null) keys['call_jitter_ms'] = '$jitterMs';
    if (networkType != null) keys['call_network'] = networkType!;
    return keys;
  }
}

/// Collects the figures for one call while it runs, and turns them into a
/// [CallSummary] when it ends.
class CallSummaryRecorder {
  DateTime? _startedAt;
  DateTime? _connectedAt;
  String? _pathType;
  double? _lossPercent;
  int? _jitterMs;
  int _reconnects = 0;

  /// Clears the figures for a new call.
  void reset() {
    _startedAt = null;
    _connectedAt = null;
    _pathType = null;
    _lossPercent = null;
    _jitterMs = null;
    _reconnects = 0;
  }

  /// The first call to start counts. A later one is ignored.
  void start(DateTime at) => _startedAt ??= at;

  /// The first connected media counts.
  void connected(DateTime at) => _connectedAt ??= at;

  void path(String? type) {
    if (type != null) _pathType = type;
  }

  void reconnect() => _reconnects++;

  /// Keeps the latest loss and jitter. Loss is the last interval, as the call
  /// quality code measures it.
  void link(CallLinkSample sample) {
    final loss = sample.lossRatio;
    if (loss != null) {
      _lossPercent =
          double.parse((loss * 100).clamp(0, 100).toStringAsFixed(1));
    }
    final jitter = sample.jitterMs;
    if (jitter != null) _jitterMs = jitter.round();
  }

  CallSummary finish({
    required String callId,
    required bool isCaller,
    required bool isVideo,
    required CallEndReason reason,
    required DateTime at,
    String? networkType,
  }) {
    final connectedAt = _connectedAt;
    final startedAt = _startedAt;
    return CallSummary(
      callId: callId,
      isCaller: isCaller,
      isVideo: isVideo,
      endReason: reason,
      connectedSeconds: connectedAt == null
          ? 0
          : at.difference(connectedAt).inSeconds.clamp(0, 1 << 31),
      reconnects: _reconnects,
      timeToConnectedMs: connectedAt == null || startedAt == null
          ? null
          : connectedAt.difference(startedAt).inMilliseconds,
      pathType: connectedAt == null ? null : _pathType ?? 'unknown',
      lossPercent: _lossPercent,
      jitterMs: _jitterMs,
      networkType: networkType,
    );
  }
}
