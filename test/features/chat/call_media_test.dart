import 'package:bhromon/features/chat/data/call_media.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('callMediaConstraints', () {
    test('asks for echo-cancelled audio and, when video, the front camera', () {
      final withVideo = callMediaConstraints(video: true);
      final audioOnly = callMediaConstraints(video: false);

      expect(withVideo['audio'], containsPair('echoCancellation', true));
      expect(withVideo['video'], containsPair('facingMode', 'user'));
      expect(audioOnly['audio'], containsPair('noiseSuppression', true));
      expect(audioOnly['video'], isFalse);
    });
  });

  group('captureCallMedia', () {
    test('an audio call asks for the microphone only', () async {
      final requests = <Map<String, dynamic>>[];

      final media = await captureCallMedia<String>(
        wantVideo: false,
        getUserMedia: (constraints) async {
          requests.add(constraints);
          return 'audio';
        },
      );

      expect(media.stream, 'audio');
      expect(media.hasVideo, isFalse);
      expect(requests, hasLength(1));
      expect(requests.single['video'], isFalse);
    });

    test('a video call keeps the camera when it opens', () async {
      final requests = <Map<String, dynamic>>[];

      final media = await captureCallMedia<String>(
        wantVideo: true,
        getUserMedia: (constraints) async {
          requests.add(constraints);
          return 'audio+video';
        },
      );

      expect(media.stream, 'audio+video');
      expect(media.hasVideo, isTrue);
      expect(requests, hasLength(1));
      expect(requests.single['video'], isA<Map<String, dynamic>>());
    });

    test('a camera that cannot be opened falls back to audio', () async {
      final requests = <Map<String, dynamic>>[];

      final media = await captureCallMedia<String>(
        wantVideo: true,
        getUserMedia: (constraints) async {
          requests.add(constraints);
          if (constraints['video'] != false) {
            throw Exception('Unable to getUserMedia: NotFoundError');
          }
          return 'audio';
        },
      );

      expect(media.stream, 'audio');
      expect(media.hasVideo, isFalse);
      expect(requests, hasLength(2));
      expect(requests.last['video'], isFalse);
      expect(requests.last['audio'], isNotNull);
    });

    test('a microphone that cannot be opened still fails the call', () async {
      await expectLater(
        captureCallMedia<String>(
          wantVideo: true,
          getUserMedia: (constraints) async {
            throw Exception('NotAllowedError');
          },
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('an audio call that fails is not retried', () async {
      final requests = <Map<String, dynamic>>[];

      await expectLater(
        captureCallMedia<String>(
          wantVideo: false,
          getUserMedia: (constraints) async {
            requests.add(constraints);
            throw Exception('NotAllowedError');
          },
        ),
        throwsA(isA<Exception>()),
      );

      expect(requests, hasLength(1));
    });
  });
}
