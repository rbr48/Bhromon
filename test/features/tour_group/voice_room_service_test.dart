import 'package:bhromon/features/chat/domain/call_quality.dart';
import 'package:bhromon/features/tour_group/data/voice_room_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VoiceRoomService speaking indicator & quality telemetry', () {
    test(
        'initializes with default good network quality and empty speaking emails',
        () {
      final service = VoiceRoomService();
      expect(service.speakingEmails, isEmpty);
      expect(service.isSpeaking('alice@example.com'), isFalse);
      expect(service.networkQuality.value, CallNetworkQuality.good);
      expect(service.linkSample.value, isNull);
    });

    test(
        'classifyCallLink classifies quality according to loss and delay thresholds',
        () {
      const goodSample = CallLinkSample(
        roundTripMs: 80,
        jitterMs: 15,
        lossRatio: 0.01,
        packetsLost: 2,
        packetsReceived: 200,
      );
      expect(classifyCallLink(goodSample), CallNetworkQuality.good);

      const fairSample = CallLinkSample(
        roundTripMs: 350,
        jitterMs: 50,
        lossRatio: 0.06,
        packetsLost: 12,
        packetsReceived: 200,
      );
      expect(classifyCallLink(fairSample), CallNetworkQuality.fair);

      const poorSample = CallLinkSample(
        roundTripMs: 950,
        jitterMs: 150,
        lossRatio: 0.20,
        packetsLost: 50,
        packetsReceived: 200,
      );
      expect(classifyCallLink(poorSample), CallNetworkQuality.poor);
    });
  });
}
