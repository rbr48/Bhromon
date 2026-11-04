import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/features/tour_group/domain/models/predefined_spot.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/data/predefined_spots_repository.dart';

class _MockAssetBundle extends CachingAssetBundle {
  _MockAssetBundle(this._content);
  final String _content;

  @override
  Future<String> loadString(String key, {bool cache = true}) async => _content;

  @override
  Future<ByteData> load(String key) async =>
      ByteData.view(Uint8List.fromList(utf8.encode(_content)).buffer);
}

void main() {
  const sampleJson = '''
  [
    {
      "pinId": "predefined_sajek",
      "name": "Sajek Valley",
      "lat": 23.3820,
      "lng": 92.2938,
      "description": "Queen of Hills surrounded by clouds",
      "category": "nature",
      "district": "Rangamati",
      "division": "Chattogram",
      "trustTier": "verified",
      "geoHash": "wgh5h12s"
    },
    {
      "pinId": "predefined_cox_beach",
      "name": "Cox's Bazar Beach",
      "lat": 21.4272,
      "lng": 91.9701,
      "description": "World's longest natural sea beach",
      "category": "beach",
      "district": "Cox's Bazar",
      "division": "Chattogram",
      "trustTier": "verified",
      "geoHash": "w4ycsd3d"
    },
    {
      "pinId": "predefined_jaflong",
      "name": "Jaflong",
      "lat": 25.1610,
      "lng": 92.0150,
      "description": "Stone quarry and hills",
      "category": "nature",
      "district": "Sylhet",
      "division": "Sylhet",
      "trustTier": "verified",
      "geoHash": "wgu9dfsd"
    },
    {
      "pinId": "predefined_lalbagh",
      "name": "Lalbagh Fort",
      "lat": 23.7188,
      "lng": 90.3882,
      "description": "17th century Mughal fort complex",
      "category": "historical",
      "district": "Dhaka",
      "division": "Dhaka",
      "trustTier": "verified",
      "geoHash": "wh0r0y2d"
    }
  ]
  ''';

  setUp(() {
    PredefinedSpotsRepository.clearCacheForTest();
  });

  group('PredefinedSpot model', () {
    test('parses json correctly and maps category to TourType', () {
      final spot = PredefinedSpot.fromJson({
        'pinId': 'spot_1',
        'name': 'Test Beach',
        'lat': 21.5,
        'lng': 92.0,
        'description': 'Sunny beach',
        'category': 'beach',
        'district': 'Cox',
        'division': 'Chattogram',
        'trustTier': 'verified',
        'geoHash': 'w4yc',
      });

      expect(spot.pinId, 'spot_1');
      expect(spot.name, 'Test Beach');
      expect(spot.kind, TourType.beach);
      expect(spot.lat, 21.5);
      expect(spot.lng, 92.0);
      expect(spot.district, 'Cox');
      expect(spot.division, 'Chattogram');
    });

    test('maps categories accurately', () {
      expect(
          PredefinedSpot.fromJson({'category': 'beach'}).kind, TourType.beach);
      expect(PredefinedSpot.fromJson({'category': 'hill'}).kind, TourType.hill);
      expect(PredefinedSpot.fromJson({'category': 'nature'}).kind,
          TourType.nature);
      expect(PredefinedSpot.fromJson({'category': 'historical'}).kind,
          TourType.heritage);
      expect(PredefinedSpot.fromJson({'category': 'heritage'}).kind,
          TourType.heritage);
      expect(PredefinedSpot.fromJson({'category': 'city'}).kind, TourType.city);
      expect(PredefinedSpot.fromJson({'category': 'unknown'}).kind,
          TourType.custom);
    });

    test('matches query against name, district, division and description', () {
      final spot = PredefinedSpot.fromJson({
        'name': 'Sajek Valley',
        'district': 'Rangamati',
        'division': 'Chattogram',
        'category': 'nature',
        'description': 'Queen of Hills',
      });

      expect(spot.matches('sajek'), isTrue);
      expect(spot.matches('RANGAMATI'), isTrue);
      expect(spot.matches('chattogram'), isTrue);
      expect(spot.matches('queen'), isTrue);
      expect(spot.matches('nonexistent'), isFalse);
    });
  });

  group('PredefinedSpotsRepository', () {
    test('loads spots from asset bundle and caches in memory', () async {
      final repo =
          PredefinedSpotsRepository(bundle: _MockAssetBundle(sampleJson));
      final spots = await repo.loadSpots();

      expect(spots.length, 4);
      expect(spots[0].name, 'Sajek Valley');
      expect(spots[1].name, "Cox's Bazar Beach");
      expect(spots[2].name, 'Jaflong');
      expect(spots[3].name, 'Lalbagh Fort');

      // Second load reads from cache
      final spots2 = await repo.loadSpots();
      expect(identical(spots, spots2), isTrue);
    });

    test('filters spots by division', () async {
      final repo =
          PredefinedSpotsRepository(bundle: _MockAssetBundle(sampleJson));
      final chattogramSpots = await repo.filterSpots(division: 'Chattogram');
      expect(chattogramSpots.length, 2);
      expect(chattogramSpots.every((s) => s.division == 'Chattogram'), isTrue);

      final sylhetSpots = await repo.filterSpots(division: 'Sylhet');
      expect(sylhetSpots.length, 1);
      expect(sylhetSpots.first.name, 'Jaflong');
    });

    test('filters spots by category', () async {
      final repo =
          PredefinedSpotsRepository(bundle: _MockAssetBundle(sampleJson));
      final natureSpots = await repo.filterSpots(category: 'nature');
      expect(natureSpots.length, 2);

      final beachSpots = await repo.filterSpots(category: 'beach');
      expect(beachSpots.length, 1);
      expect(beachSpots.first.name, "Cox's Bazar Beach");
    });

    test('filters spots by combined division, category, and query', () async {
      final repo =
          PredefinedSpotsRepository(bundle: _MockAssetBundle(sampleJson));
      final filtered = await repo.filterSpots(
        division: 'Chattogram',
        category: 'beach',
        query: 'cox',
      );
      expect(filtered.length, 1);
      expect(filtered.first.name, "Cox's Bazar Beach");
    });

    test('extracts distinct sorted divisions', () async {
      final repo =
          PredefinedSpotsRepository(bundle: _MockAssetBundle(sampleJson));
      final divisions = await repo.getDivisions();
      expect(divisions, ['Chattogram', 'Dhaka', 'Sylhet']);
    });
  });
}
