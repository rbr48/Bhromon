import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/core/utils/geohash_utils.dart';
import 'package:bhromon/core/value_objects/geo_coordinate.dart';

void main() {
  group('GeoHashUtils.encode', () {
    test('matches the published reference hash', () {
      // Reference point from the geohash specification.
      expect(
        GeoHashUtils.encode(57.64911, 10.40744, precision: 11),
        'u4pruydqqvj',
      );
    });

    test('defaults to nine characters', () {
      expect(GeoHashUtils.encode(23.8103, 90.4125).length, 9);
    });

    test('nearby points share a prefix; distant ones do not', () {
      final dhaka = GeoHashUtils.encode(23.8103, 90.4125, precision: 6);
      final nearby = GeoHashUtils.encode(23.8110, 90.4130, precision: 6);
      final coxsBazar = GeoHashUtils.encode(21.4272, 92.0058, precision: 6);

      expect(nearby, dhaka);
      expect(coxsBazar, isNot(dhaka));
    });
  });

  group('GeoHashUtils.decode', () {
    test('decodes the reference hash back to its point', () {
      final point = GeoHashUtils.decode('u4pruydqqvj');

      expect(point.latitude, closeTo(57.64911, 0.0001));
      expect(point.longitude, closeTo(10.40744, 0.0001));
    });

    test('round-trips a point within its cell', () {
      final hash = GeoHashUtils.encode(23.8103, 90.4125);
      final point = GeoHashUtils.decode(hash);

      expect(point.latitude, closeTo(23.8103, 0.0001));
      expect(point.longitude, closeTo(90.4125, 0.0001));
    });

    test('rejects a character outside the geohash alphabet', () {
      // 'a', 'i', 'l' and 'o' are not in the geohash base-32 alphabet.
      expect(() => GeoHashUtils.decode('wh0a'), throwsArgumentError);
    });
  });

  group('GeoHashUtils.getNeighbourCells', () {
    test('returns the centre cell and its neighbours, without duplicates', () {
      const centre = GeoCoordinate(latitude: 23.8103, longitude: 90.4125);
      final cells = GeoHashUtils.getNeighbourCells(centre, 5, precision: 6);

      expect(
          cells, contains(GeoHashUtils.encode(23.8103, 90.4125, precision: 6)));
      expect(cells.length, inInclusiveRange(1, 9));
      expect(cells.toSet().length, cells.length);
    });

    test('a wider radius covers at least as many cells', () {
      const centre = GeoCoordinate(latitude: 23.8103, longitude: 90.4125);
      final narrow = GeoHashUtils.getNeighbourCells(centre, 0.5, precision: 6);
      final wide = GeoHashUtils.getNeighbourCells(centre, 200, precision: 6);

      expect(wide.length, greaterThanOrEqualTo(narrow.length));
    });
  });
}
