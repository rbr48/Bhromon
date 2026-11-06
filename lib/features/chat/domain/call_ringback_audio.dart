import 'package:audioplayers/audioplayers.dart';

/// Builds the [AudioContext] for the outgoing call ringback tone.
///
/// On Android:
/// When placing an outgoing call, Android Telecom enters the dialing state and
/// the device audio manager is set to [AndroidAudioMode.inCommunication].
/// Playing audio with default media settings ([AndroidUsageType.media],
/// [AndroidAudioFocus.gain]) causes Android OS to deny media audio focus or duck
/// the audio stream to silence.
///
/// By specifying [AndroidUsageType.voiceCommunication], [AndroidAudioMode.inCommunication],
/// and [AndroidAudioFocus.none], the ringback tone is routed over the telephony /
/// voice call communication stream ([isSpeaker] selecting between speakerphone
/// and earpiece) alongside WebRTC, bypassing media ducking and focus rejection.
AudioContext buildRingbackAudioContext({required bool isSpeaker}) {
  return AudioContext(
    android: AudioContextAndroid(
      isSpeakerphoneOn: isSpeaker,
      stayAwake: true,
      contentType: AndroidContentType.speech,
      usageType: AndroidUsageType.voiceCommunication,
      audioFocus: AndroidAudioFocus.none,
      audioMode: AndroidAudioMode.inCommunication,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playAndRecord,
      options: {
        if (isSpeaker) AVAudioSessionOptions.defaultToSpeaker,
        AVAudioSessionOptions.mixWithOthers,
      },
    ),
  );
}

/// Builds the [AudioContext] for incoming call ringtones.
///
/// Uses [AndroidUsageType.notificationRingtone] and [AndroidContentType.sonification]
/// so the in-app ringtone plays through the ringtone volume stream and respects
/// device silent / DND settings.
AudioContext buildIncomingRingtoneAudioContext() {
  return AudioContext(
    android: const AudioContextAndroid(
      isSpeakerphoneOn: true,
      stayAwake: true,
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.notificationRingtone,
      audioFocus: AndroidAudioFocus.gainTransientMayDuck,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.ambient,
    ),
  );
}
