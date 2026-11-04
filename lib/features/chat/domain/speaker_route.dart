/// Whether the phone's audio route is the loudspeaker, read from the snapshot that
/// `CallAudioSession.routeSnapshot` returns. Pure, so the rule is tested without a phone.
enum SpeakerRoute {
  /// The communication route and the WebRTC plugin both say loudspeaker.
  onSpeaker,

  /// One of them says otherwise: the route did not take, or it moved afterwards.
  notOnSpeaker,

  /// There is nothing to read: the platform has no route to check, or the phone
  /// did not answer.
  unknown,
}

/// Reads [snapshot]. From Android 12 the communication device is the route, and before
/// it the speakerphone flag is. When the plugin reports a device of its own, that device
/// must be the loudspeaker too.
SpeakerRoute readSpeakerRoute(Map<String, Object?>? snapshot) {
  if (snapshot == null) return SpeakerRoute.unknown;
  final communication = snapshot['communicationDevice'];
  final onLoudspeaker = communication is String
      ? communication == 'speaker'
      : snapshot['speakerphoneOn'] == true;
  final plugin = snapshot['pluginDevice'];
  final pluginAgrees = plugin == null || plugin == 'Speakerphone';
  return onLoudspeaker && pluginAgrees
      ? SpeakerRoute.onSpeaker
      : SpeakerRoute.notOnSpeaker;
}

/// The snapshot as one short line for a Crashlytics value. Crashlytics keeps values up
/// to 100 characters, so the line is cut to fit. It names types and volumes only.
String describeSpeakerRoute(Map<String, Object?> snapshot) {
  final outputs = snapshot['outputs'];
  final line = 'comm=${snapshot['communicationDevice'] ?? 'none'} '
      'flag=${snapshot['speakerphoneOn']} '
      'plugin=${snapshot['pluginDevice'] ?? 'none'} '
      'mode=${snapshot['mode']} '
      'vol=${snapshot['voiceCallVolume']}/${snapshot['voiceCallMax']} '
      'out=${outputs is List ? outputs.join('+') : '-'}';
  return line.length <= 100 ? line : line.substring(0, 100);
}
