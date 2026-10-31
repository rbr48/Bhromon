import 'package:bhromon/features/tour_group/domain/services/notice_speech.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('noticeSpeechText', () {
    test('reads the title, the text, the time and the place in order', () {
      expect(
        noticeSpeechText(
          title: 'Bus departure',
          content: 'Be at the bus early',
          timeSentence: 'At Sat, 3 Nov, 6:00 AM',
          placeSentence: 'Place: Lobby',
          bengali: false,
        ),
        'Bus departure. Be at the bus early. At Sat, 3 Nov, 6:00 AM. Place: Lobby.',
      );
    });

    test('a Bengali notice ends its sentences with a daari', () {
      expect(
        noticeSpeechText(
          title: 'বাস ছাড়ার সময়',
          content: 'সময়মতো আসুন',
          timeSentence: 'সময় ৩ নভেম্বর, ৬:০০ AM',
          bengali: true,
        ),
        'বাস ছাড়ার সময়। সময়মতো আসুন। সময় ৩ নভেম্বর, ৬:০০ AM।',
      );
    });

    test('a part that already ends a sentence gets no second full stop', () {
      expect(
        noticeSpeechText(
          title: 'Lost and found?',
          content: 'Tell the leader!',
          bengali: false,
        ),
        'Lost and found? Tell the leader!',
      );
    });

    test('empty and blank parts are skipped', () {
      expect(
        noticeSpeechText(
          title: '  Quiet hours ',
          content: '   ',
          timeSentence: null,
          placeSentence: '',
          bengali: false,
        ),
        'Quiet hours.',
      );
    });

    test('nothing to say gives an empty text, so nothing is read', () {
      expect(
        noticeSpeechText(title: '', content: '', bengali: true),
        isEmpty,
      );
    });
  });
}
