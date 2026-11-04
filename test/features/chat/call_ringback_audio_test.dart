import 'package:audioplayers/audioplayers.dart';
import 'package:bhromon/features/chat/domain/call_ringback_audio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildRingbackAudioContext', () {
    test('routes through voice communication stream on loudspeaker', () {
      final context = buildRingbackAudioContext(isSpeaker: true);

      final android = context.android;
      expect(android.isSpeakerphoneOn, isTrue);
      expect(android.stayAwake, isTrue);
      expect(android.contentType, AndroidContentType.speech);
      expect(android.usageType, AndroidUsageType.voiceCommunication);
      expect(android.audioFocus, AndroidAudioFocus.none);
      expect(android.audioMode, AndroidAudioMode.inCommunication);

      final ios = context.iOS;
      expect(ios.category, AVAudioSessionCategory.playAndRecord);
      expect(ios.options, contains(AVAudioSessionOptions.defaultToSpeaker));
      expect(ios.options, contains(AVAudioSessionOptions.mixWithOthers));
    });

    test('routes through voice communication stream on earpiece', () {
      final context = buildRingbackAudioContext(isSpeaker: false);

      final android = context.android;
      expect(android.isSpeakerphoneOn, isFalse);
      expect(android.stayAwake, isTrue);
      expect(android.contentType, AndroidContentType.speech);
      expect(android.usageType, AndroidUsageType.voiceCommunication);
      expect(android.audioFocus, AndroidAudioFocus.none);
      expect(android.audioMode, AndroidAudioMode.inCommunication);

      final ios = context.iOS;
      expect(ios.category, AVAudioSessionCategory.playAndRecord);
      expect(
          ios.options, isNot(contains(AVAudioSessionOptions.defaultToSpeaker)));
      expect(ios.options, contains(AVAudioSessionOptions.mixWithOthers));
    });
  });

  group('buildIncomingRingtoneAudioContext', () {
    test('routes incoming ringtone through notification ringtone stream', () {
      final context = buildIncomingRingtoneAudioContext();

      final android = context.android;
      expect(android.isSpeakerphoneOn, isTrue);
      expect(android.stayAwake, isTrue);
      expect(android.contentType, AndroidContentType.sonification);
      expect(android.usageType, AndroidUsageType.notificationRingtone);
      expect(android.audioFocus, AndroidAudioFocus.gainTransientMayDuck);

      final ios = context.iOS;
      expect(ios.category, AVAudioSessionCategory.ambient);
      expect(ios.options, isEmpty);
    });
  });
}
