import 'package:bhromon/features/tour_group/domain/services/media_rules.dart';
import 'package:bhromon/features/tour_group/domain/services/web_video_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('webVideoPasses', () {
    test('a short reel gets the 720p first pass at its bitrate cap', () {
      final passes = webVideoPasses(
        durationSeconds: 12,
        targetMaxBytes: kMaxVideoBytes,
      );

      expect(passes, hasLength(2));
      expect(passes.first.maxShortSide, 720);
      expect(passes.first.maxLongSide, 1280);
      expect(passes.first.videoBitrate, 2500000);
    });

    test('the second pass is 480p with a lower bitrate cap', () {
      final passes = webVideoPasses(
        durationSeconds: 12,
        targetMaxBytes: kMaxVideoBytes,
      );

      expect(passes.last.maxShortSide, 480);
      expect(passes.last.maxLongSide, 854);
      expect(passes.last.videoBitrate, 1000000);
    });

    test('a three-minute reel still fits the target at the first pass', () {
      final passes = webVideoPasses(
        durationSeconds: kMaxReelSeconds.toDouble(),
        targetMaxBytes: kMaxVideoBytes,
      );
      final first = passes.first;
      final bytes =
          (first.videoBitrate + first.audioBitrate) * kMaxReelSeconds / 8;

      expect(bytes, lessThan(kMaxVideoBytes));
    });

    test('a long video scales both bitrates down to fit the target', () {
      final passes = webVideoPasses(
        durationSeconds: 1000,
        targetMaxBytes: kMaxVideoBytes,
      );
      final first = passes.first;
      final bytes = (first.videoBitrate + first.audioBitrate) * 1000 / 8;

      expect(first.videoBitrate, lessThan(2500000));
      expect(first.videoBitrate, greaterThanOrEqualTo(300000));
      expect(bytes, lessThanOrEqualTo(kMaxVideoBytes));
    });

    test('the bitrates never drop below their floors', () {
      final passes = webVideoPasses(
        durationSeconds: 100000,
        targetMaxBytes: kMaxVideoBytes,
      );

      expect(passes.first.videoBitrate, 300000);
      expect(passes.last.videoBitrate, 200000);
    });

    test('an unknown duration is planned for the longest reel', () {
      final unknown = webVideoPasses(
        durationSeconds: 0,
        targetMaxBytes: kMaxVideoBytes,
      );
      final longest = webVideoPasses(
        durationSeconds: kMaxReelSeconds.toDouble(),
        targetMaxBytes: kMaxVideoBytes,
      );

      expect(unknown.first.videoBitrate, longest.first.videoBitrate);
    });
  });

  group('WebVideoPass.toJson', () {
    test('gives the options the browser transcoder reads', () {
      const pass = WebVideoPass(
        maxShortSide: 720,
        maxLongSide: 1280,
        videoBitrate: 2500000,
      );

      expect(pass.toJson(), {
        'maxShortSide': 720,
        'maxLongSide': 1280,
        'videoBitrate': 2500000,
        'audioBitrate': kWebVideoAudioBitrate,
        'frameRate': kWebVideoFrameRate,
        'videoCodec': 'avc1.42001f',
      });
    });
  });

  group('WebVideoInfo.fromJson', () {
    test('reads the probe result, with no audio', () {
      final info = WebVideoInfo.fromJson({
        'durationSeconds': 12,
        'width': 1080,
        'height': 1920,
        'rotation': 270,
        'videoCodec': 'avc1.640028',
        'audioCodec': null,
      });

      expect(info.durationSeconds, 12.0);
      expect(info.width, 1080);
      expect(info.height, 1920);
      expect(info.rotation, 270);
      expect(info.videoCodec, 'avc1.640028');
      expect(info.audioCodec, isNull);
    });
  });
}
