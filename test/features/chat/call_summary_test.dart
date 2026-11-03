import 'package:bhromon/features/chat/domain/call_quality.dart';
import 'package:bhromon/features/chat/domain/call_summary.dart';
import 'package:bhromon/features/chat/domain/sdp_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _pair({
  required String localId,
  bool nominated = true,
  String state = 'succeeded',
}) =>
    {
      'id': 'pair-$localId',
      'type': 'candidate-pair',
      'localCandidateId': localId,
      'nominated': nominated,
      'state': state,
    };

Map<String, dynamic> _candidate(String id, String type) =>
    {'id': id, 'type': 'local-candidate', 'candidateType': type};

void main() {
  group('callEndReasonFor', () {
    test('maps the call document status to a reason', () {
      expect(callEndReasonFor('declined'), CallEndReason.declined);
      expect(callEndReasonFor('missed'), CallEndReason.missed);
      expect(callEndReasonFor('cancelled'), CallEndReason.cancelled);
      expect(callEndReasonFor('failed'), CallEndReason.failed);
      expect(callEndReasonFor('ended'), CallEndReason.ended);
      expect(callEndReasonFor(null), CallEndReason.ended);
    });
  });

  group('pathTypeFromStats', () {
    test('reads the type of the selected pair\'s local candidate', () {
      final path = pathTypeFromStats([
        _candidate('L1', 'host'),
        _candidate('L2', 'srflx'),
        _pair(localId: 'L2'),
      ]);
      expect(path, 'srflx');
    });

    test('reports a TURN relay', () {
      expect(
        pathTypeFromStats([_candidate('L3', 'relay'), _pair(localId: 'L3')]),
        'relay',
      );
    });

    test('is null while no pair is selected', () {
      expect(
        pathTypeFromStats([
          _candidate('L1', 'host'),
          _pair(localId: 'L1', nominated: false, state: 'in-progress'),
        ]),
        isNull,
      );
    });

    test('is null when the local candidate is missing from the report', () {
      expect(pathTypeFromStats([_pair(localId: 'gone')]), isNull);
    });
  });

  group('CallSummaryRecorder', () {
    final start = DateTime(2026, 1, 2, 9, 30);

    test('a connected call reports its time to connect and its length', () {
      final recorder = CallSummaryRecorder()
        ..start(start)
        ..connected(start.add(const Duration(milliseconds: 2400)))
        ..path('srflx');
      final summary = recorder.finish(
        callId: 'call-1',
        isCaller: true,
        isVideo: false,
        reason: CallEndReason.ended,
        at: start.add(const Duration(seconds: 62)),
        networkType: 'wifi',
      );

      expect(summary.timeToConnectedMs, 2400);
      // 2.4 s to connect, then 59.6 s until the end: 59 whole seconds.
      expect(summary.connectedSeconds, 59);
      expect(summary.pathType, 'srflx');
      expect(summary.networkType, 'wifi');
      expect(summary.isCaller, isTrue);
      expect(summary.isVideo, isFalse);
    });

    test('a call that never connected reports no path and no time', () {
      final recorder = CallSummaryRecorder()..start(start);
      final summary = recorder.finish(
        callId: 'call-2',
        isCaller: false,
        isVideo: true,
        reason: CallEndReason.missed,
        at: start.add(const Duration(seconds: 30)),
      );

      expect(summary.connectedSeconds, 0);
      expect(summary.timeToConnectedMs, isNull);
      expect(summary.pathType, isNull);
      expect(summary.endReason, CallEndReason.missed);
      expect(summary.isVideo, isTrue);
    });

    test('a connected call with no selected path says so, not nothing', () {
      final recorder = CallSummaryRecorder()
        ..start(start)
        ..connected(start.add(const Duration(seconds: 1)));
      final summary = recorder.finish(
        callId: 'call-3',
        isCaller: true,
        isVideo: false,
        reason: CallEndReason.ended,
        at: start.add(const Duration(seconds: 10)),
      );

      expect(summary.pathType, 'unknown');
    });

    test('counts reconnects and keeps the latest loss and jitter', () {
      final recorder = CallSummaryRecorder()
        ..start(start)
        ..connected(start)
        ..reconnect()
        ..reconnect()
        ..link(const CallLinkSample(lossRatio: 0.05, jitterMs: 12.4))
        ..link(const CallLinkSample(lossRatio: 0.021, jitterMs: 18.6));
      final summary = recorder.finish(
        callId: 'call-4',
        isCaller: true,
        isVideo: false,
        reason: CallEndReason.ended,
        at: start.add(const Duration(seconds: 5)),
      );

      expect(summary.reconnects, 2);
      expect(summary.lossPercent, 2.1);
      expect(summary.jitterMs, 19);
    });

    test('reset clears the figures from the call before', () {
      final recorder = CallSummaryRecorder()
        ..start(start)
        ..connected(start)
        ..reconnect();
      recorder.reset();
      final summary = recorder.finish(
        callId: 'call-5',
        isCaller: false,
        isVideo: false,
        reason: CallEndReason.ended,
        at: start.add(const Duration(seconds: 9)),
      );

      expect(summary.reconnects, 0);
      expect(summary.connectedSeconds, 0);
    });
  });

  group('CallSummary.toKeys', () {
    test('holds short values and no personal data', () {
      final keys = const CallSummary(
        callId: 'call-6',
        isCaller: true,
        isVideo: true,
        endReason: CallEndReason.ended,
        connectedSeconds: 120,
        reconnects: 1,
        timeToConnectedMs: 2100,
        pathType: 'relay',
        lossPercent: 3.25,
        jitterMs: 22,
        networkType: 'cellular',
      ).toKeys();

      expect(keys['call_role'], 'caller');
      expect(keys['call_kind'], 'video');
      expect(keys['call_end'], 'ended');
      expect(keys['call_path'], 'relay');
      expect(keys['call_loss_pct'], '3.3');
      expect(keys['call_network'], 'cellular');
      expect(keys.keys.any((k) => k.contains('email') || k.contains('name')),
          isFalse);
      for (final value in keys.values) {
        expect(value.length, lessThanOrEqualTo(100));
      }
      expect(keys.length, lessThanOrEqualTo(64));
    });

    test('leaves out the optional figures that were never measured', () {
      final keys = const CallSummary(
        callId: 'call-7',
        isCaller: false,
        isVideo: false,
        endReason: CallEndReason.declined,
        connectedSeconds: 0,
        reconnects: 0,
      ).toKeys();

      expect(keys.containsKey('call_ttc_ms'), isFalse);
      expect(keys.containsKey('call_path'), isFalse);
      expect(keys.containsKey('call_loss_pct'), isFalse);
      expect(keys['call_role'], 'callee');
    });
  });

  group('opusFmtpLines', () {
    test('returns the fmtp line of the Opus payload', () {
      const sdp = 'v=0\r\n'
          'm=audio 9 UDP/TLS/RTP/SAVPF 111 0\r\n'
          'a=rtpmap:111 opus/48000/2\r\n'
          'a=rtpmap:0 PCMU/8000\r\n'
          'a=fmtp:111 minptime=10;useinbandfec=1\r\n'
          'a=fmtp:0 some=other\r\n';

      expect(opusFmtpLines(sdp), ['a=fmtp:111 minptime=10;useinbandfec=1']);
    });

    test('says so when the description has no Opus line', () {
      expect(
        opusFmtpLines('v=0\nm=video 9 RTP/AVP 96\na=rtpmap:96 VP8/90000\n'),
        ['no Opus fmtp line'],
      );
    });
  });
}
