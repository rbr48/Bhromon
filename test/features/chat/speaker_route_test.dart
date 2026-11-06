import 'package:bhromon/features/chat/domain/speaker_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reading the loudspeaker route', () {
    test('no snapshot means there is nothing to check', () {
      expect(readSpeakerRoute(null), SpeakerRoute.unknown);
    });

    test(
        'a communication device on the speaker, agreed by the plugin, is the loudspeaker',
        () {
      expect(
        readSpeakerRoute({
          'communicationDevice': 'speaker',
          'speakerphoneOn': true,
          'pluginDevice': 'Speakerphone',
        }),
        SpeakerRoute.onSpeaker,
      );
    });

    test(
        'a communication device on the earpiece is not the loudspeaker, even with the flag set',
        () {
      expect(
        readSpeakerRoute({
          'communicationDevice': 'earpiece',
          'speakerphoneOn': true,
          'pluginDevice': 'Speakerphone',
        }),
        SpeakerRoute.notOnSpeaker,
      );
    });

    test('a plugin that chose another output is not the loudspeaker', () {
      expect(
        readSpeakerRoute({
          'communicationDevice': 'speaker',
          'pluginDevice': 'Earpiece',
        }),
        SpeakerRoute.notOnSpeaker,
      );
    });

    test('before Android 12 the speakerphone flag stands for the route', () {
      expect(
        readSpeakerRoute({'communicationDevice': null, 'speakerphoneOn': true}),
        SpeakerRoute.onSpeaker,
      );
      expect(
        readSpeakerRoute(
            {'communicationDevice': null, 'speakerphoneOn': false}),
        SpeakerRoute.notOnSpeaker,
      );
    });

    test(
        'a plugin that has not chosen a device does not count against the route',
        () {
      expect(
        readSpeakerRoute(
            {'communicationDevice': 'speaker', 'pluginDevice': null}),
        SpeakerRoute.onSpeaker,
      );
    });
  });

  group('describing the route', () {
    test('names types and volumes in one short line', () {
      final line = describeSpeakerRoute({
        'communicationDevice': 'earpiece',
        'speakerphoneOn': false,
        'pluginDevice': 'Speakerphone',
        'mode': 3,
        'voiceCallVolume': 2,
        'voiceCallMax': 7,
        'outputs': ['earpiece', 'speaker', 'bluetooth'],
      });
      expect(
        line,
        'comm=earpiece flag=false plugin=Speakerphone mode=3 vol=2/7 '
        'out=earpiece+speaker+bluetooth',
      );
      expect(line.length, lessThanOrEqualTo(100));
    });

    test('a line longer than a Crashlytics value is cut to fit', () {
      final line =
          describeSpeakerRoute({'outputs': List.filled(40, 'bluetooth')});
      expect(line.length, 100);
    });
  });
}
