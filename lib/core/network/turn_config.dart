/// ICE servers for WebRTC calls.
///
/// The TURN relay credential is not in the source. It is supplied at build
/// time, for example:
///
///   flutter build apk --release \
///     --dart-define=TURN_USERNAME=... --dart-define=TURN_CREDENTIAL=...
///
/// Without both values only the STUN servers are used. Calls then connect
/// directly, or fail on networks that need a relay.
abstract final class TurnConfig {
  static const String _url = String.fromEnvironment(
    'TURN_URL',
    defaultValue: 'turn:148.135.137.245:3478',
  );
  static const String _username = String.fromEnvironment('TURN_USERNAME');
  static const String _credential = String.fromEnvironment('TURN_CREDENTIAL');

  static bool get hasRelay => _username.isNotEmpty && _credential.isNotEmpty;

  static List<Map<String, dynamic>> get iceServers => [
        {
          'urls': [
            'stun:stun.l.google.com:19302',
            'stun:stun1.l.google.com:19302',
          ],
        },
        if (hasRelay)
          {
            'urls': [
              '$_url?transport=udp',
              '$_url?transport=tcp',
            ],
            'username': _username,
            'credential': _credential,
          },
      ];
}
