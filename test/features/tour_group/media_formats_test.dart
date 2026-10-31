import 'package:bhromon/features/tour_group/domain/services/media_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isSupportedVideoName', () {
    test('accepts the containers the media server stores, in any case', () {
      for (final name in [
        'clip.mp4',
        'clip.MOV',
        'clip.m4v',
        'clip.webm',
        'clip.3gp',
        'clip.mkv',
      ]) {
        expect(isSupportedVideoName(name), isTrue, reason: name);
      }
    });

    test('refuses containers the media server does not store', () {
      for (final name in [
        'clip.avi',
        'clip.mpg',
        'clip.mpeg',
        'clip.wmv',
        'clip.flv',
        'clip.ts',
      ]) {
        expect(isSupportedVideoName(name), isFalse, reason: name);
      }
    });

    test('keeps a name with no extension, which is stored as an mp4', () {
      expect(isSupportedVideoName('1000000012'), isTrue);
      expect(storedExtension('1000000012', 'mp4'), 'mp4');
    });
  });
}
