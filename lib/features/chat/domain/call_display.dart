/// Small display rules for the call screens that need no Flutter.
library;

/// The first character of [name] for an avatar placeholder, upper-cased. A
/// whole code point is taken, so an emoji or other character outside the basic
/// plane is never cut in half. An empty name gives '?'.
String callInitial(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  return String.fromCharCode(trimmed.runes.first).toUpperCase();
}

/// [value] kept between [low] and [high]. When the space is smaller than the
/// range allows (a very small window), [low] wins instead of throwing.
double clampWithin(double value, double low, double high) {
  if (high < low) return low;
  return value.clamp(low, high).toDouble();
}

/// Where call audio can play.
enum AudioOutputKind { speaker, earpiece, bluetooth, headset, other }

/// The kind of an audio output from its device id and label, as the phone
/// reports them ("speaker", "earpiece", "bluetooth", "wired-headset", or a
/// headset's own name).
AudioOutputKind audioOutputKind(String deviceId, String label) {
  final text = '$deviceId $label'.toLowerCase();
  if (text.contains('bluetooth') || text.contains('bt ')) {
    return AudioOutputKind.bluetooth;
  }
  if (text.contains('headset') ||
      text.contains('headphone') ||
      text.contains('wired') ||
      text.contains('usb')) {
    return AudioOutputKind.headset;
  }
  if (text.contains('earpiece') || text.contains('receiver')) {
    return AudioOutputKind.earpiece;
  }
  if (text.contains('speaker')) return AudioOutputKind.speaker;
  return AudioOutputKind.other;
}

/// Voice calls default to the earpiece; video calls default to the speaker.
bool defaultCallSpeakerOn({required bool isVideoCall}) => isVideoCall;

/// Platform speaker/earpiece routing is only available outside the Web target.
bool shouldShowSpeakerControl({required bool isWeb}) => !isWeb;

/// Camera switching is only available on mobile when local video is active.
bool shouldShowFlipCameraControl({
  required bool isWeb,
  required bool cameraOn,
}) =>
    !isWeb && cameraOn;

/// Whether our own Android foreground service should be started/updated so
/// mic and camera keep running in the background even when accepted via CallKit.
bool shouldStartOngoingService({
  required bool systemCall,
  required bool needsMicFgs,
  required bool needsCameraFgs,
  required bool hasLocalVideo,
}) =>
    !systemCall || needsMicFgs || (hasLocalVideo && needsCameraFgs);

/// When a call reaches a terminal state (`declined`/`missed`/`ended`/`failed`),
/// CallScreen waits briefly to display the status banner before popping.
bool shouldExitImmediatelyOnCallEnded({required bool callOver}) => !callOver;
