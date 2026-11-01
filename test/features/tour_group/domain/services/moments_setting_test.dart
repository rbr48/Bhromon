import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _circle({String? preset, bool? moments}) => {
      'name': 'Sales team',
      'ownerEmail': 'boss@example.com',
      'inviteCode': 'ABCDEFGH',
      'kind': 'family',
      if (preset != null) 'preset': preset,
      if (moments != null) 'momentsEnabled': moments,
    };

void main() {
  group('moments setting', () {
    test(
        'Moments is on by default, and a circle that does not store it reads as on',
        () {
      final office = TourGroup.fromMap('o1', _circle(preset: 'office'));

      expect(office.momentsEnabled, isTrue);
      expect(office.momentsOpen, isTrue);
      expect(office.toMap().containsKey('momentsEnabled'), isFalse);
    });

    test(
        'an office or campus that turns Moments off is closed; a family circle is not',
        () {
      final office =
          TourGroup.fromMap('o1', _circle(preset: 'office', moments: false));
      final campus =
          TourGroup.fromMap('c1', _circle(preset: 'campus', moments: false));
      final family = TourGroup.fromMap('f1', _circle(moments: false));

      expect(office.momentsOpen, isFalse);
      expect(campus.momentsOpen, isFalse);
      expect(family.momentsEnabled, isFalse);
      expect(family.momentsOpen, isTrue);
    });

    test('the setting is written only when Moments is off', () {
      final off =
          TourGroup.fromMap('o1', _circle(preset: 'office', moments: false));

      expect(off.toMap()['momentsEnabled'], isFalse);
    });

    test('a copy keeps the preset and the Moments setting', () {
      final office =
          TourGroup.fromMap('o1', _circle(preset: 'office', moments: false));
      final copy = office.copyWith(name: 'Renamed team');

      expect(copy.preset, 'office');
      expect(copy.momentsEnabled, isFalse);
      expect(copy.name, 'Renamed team');
    });
  });
}
