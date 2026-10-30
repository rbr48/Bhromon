import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/tour_choice.dart';
import 'package:flutter_test/flutter_test.dart';

TourGroup _tour(String id) => TourGroup(
      id: id,
      name: 'Tour $id',
      ownerEmail: 'lead@bhromon.fun',
      inviteCode: 'CODE$id',
      destination: 'Sajek',
      originCity: 'Dhaka',
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 4),
      tourType: TourType.hill,
      modules: const TourModules(),
      createdAt: DateTime(2026, 10, 1),
    );

void main() {
  final first = _tour('tour_a');
  final second = _tour('tour_b');
  final groups = [first, second];

  group('pickTour', () {
    test('is null when there are no tours', () {
      expect(pickTour(const [], ['tour_a']), isNull);
    });

    test('is the first tour when no id is given', () {
      expect(pickTour(groups, const []), first);
      expect(pickTour(groups, [null]), first);
    });

    test('is the tour of the first id that is listed, in the order given', () {
      expect(pickTour(groups, ['tour_b', 'tour_a']), second);
      expect(pickTour(groups, ['tour_a', 'tour_b']), first);
    });

    test('skips null, empty and unknown ids', () {
      expect(pickTour(groups, [null, '', 'tour_gone', 'tour_b']), second);
    });

    test('is the first tour when none of the ids is listed', () {
      expect(pickTour(groups, ['tour_gone']), first);
    });
  });
}
