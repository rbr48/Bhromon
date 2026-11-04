import 'package:audioplayers/audioplayers.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Plays the wake-up tone while the alarm page is open. The page uses this port,
/// so its tests can replace it with a fake.
abstract class JourneyAlarmSound {
  Future<void> start();
  Future<void> stop();
}

/// The bundled tone, looping on the alarm audio stream, with the screen kept on
/// while it rings (roadmap D-10: the alarm stream, through whatever output is
/// active).
class AudioPlayersJourneyAlarmSound implements JourneyAlarmSound {
  AudioPlayersJourneyAlarmSound({AudioPlayer? player})
      : _player = player ?? AudioPlayer();

  /// The tone the app already ships for calls. A dedicated alarm tone can
  /// replace it later without changing this class.
  static const String toneAsset = 'audio/ringtone_default.mp3';

  final AudioPlayer _player;

  @override
  Future<void> start() async {
    await _player.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          usageType: AndroidUsageType.alarm,
          contentType: AndroidContentType.sonification,
          audioFocus: AndroidAudioFocus.gain,
        ),
      ),
    );
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.play(AssetSource(toneAsset));
    await WakelockPlus.enable();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await WakelockPlus.disable();
  }
}
