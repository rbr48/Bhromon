import 'media_rules.dart';

/// Frame rate of a reel encoded in the browser. Faster sources drop frames to it.
const int kWebVideoFrameRate = 30;

/// Audio bitrate of a reel encoded in the browser. AAC audio is copied as it is
/// when the source has it, so this only applies to other audio codecs.
const int kWebVideoAudioBitrate = 128000;

/// What the browser reads from a video before it shrinks it.
class WebVideoInfo {
  const WebVideoInfo({
    required this.durationSeconds,
    required this.width,
    required this.height,
    required this.rotation,
    required this.videoCodec,
    this.audioCodec,
  });

  factory WebVideoInfo.fromJson(Map<String, dynamic> json) {
    return WebVideoInfo(
      durationSeconds: (json['durationSeconds'] as num).toDouble(),
      width: (json['width'] as num).toInt(),
      height: (json['height'] as num).toInt(),
      rotation: (json['rotation'] as num).toInt(),
      videoCodec: json['videoCodec'] as String,
      audioCodec: json['audioCodec'] as String?,
    );
  }

  final double durationSeconds;

  /// Display size after rotation.
  final int width;
  final int height;

  /// Clockwise rotation the file asks for: 0, 90, 180 or 270.
  final int rotation;
  final String videoCodec;
  final String? audioCodec;
}

/// One attempt at shrinking a video in the browser: the largest frame it may
/// produce, and the bitrates it aims for.
class WebVideoPass {
  const WebVideoPass({
    required this.maxShortSide,
    required this.maxLongSide,
    required this.videoBitrate,
    this.audioBitrate = kWebVideoAudioBitrate,
    this.frameRate = kWebVideoFrameRate,
  });

  final int maxShortSide;
  final int maxLongSide;
  final int videoBitrate;
  final int audioBitrate;
  final int frameRate;

  /// The options the browser transcoder reads.
  Map<String, Object> toJson() => {
        'maxShortSide': maxShortSide,
        'maxLongSide': maxLongSide,
        'videoBitrate': videoBitrate,
        'audioBitrate': audioBitrate,
        'frameRate': frameRate,
        'videoCodec': 'avc1.42001f',
      };
}

/// The attempts that bring a video under [targetMaxBytes], in order. The first
/// is 720p and the second 480p, like the medium and low passes on Android. Both
/// share the bits the duration allows, with a tenth kept back for the container.
List<WebVideoPass> webVideoPasses({
  required double durationSeconds,
  required int targetMaxBytes,
}) {
  final seconds =
      durationSeconds > 0 ? durationSeconds : kMaxReelSeconds.toDouble();
  final bitsPerSecond = (targetMaxBytes * 8 * 0.9 / seconds).floor();
  final videoBudget = bitsPerSecond - kWebVideoAudioBitrate;
  return [
    WebVideoPass(
      maxShortSide: 720,
      maxLongSide: 1280,
      videoBitrate: _clamp(videoBudget, 300000, 2500000),
    ),
    WebVideoPass(
      maxShortSide: 480,
      maxLongSide: 854,
      videoBitrate: _clamp(videoBudget, 200000, 1000000),
    ),
  ];
}

int _clamp(int value, int low, int high) {
  if (value < low) return low;
  if (value > high) return high;
  return value;
}
