import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/core/entities/location_pin.dart';
import 'package:bhromon/core/value_objects/trust_tier.dart';
import 'package:bhromon/core/services/discovery_score_service.dart';

void main() {
  group('DiscoveryScoreService', () {
    test('computes highest discovery score for unvisited remote pin with no photos', () {
      final pin = LocationPin(
        pinId: 'hidden_spot',
        name: 'Secret Waterfall',
        geoHash: 'w3',
        lat: 23.38,
        lng: 92.29,
        trustTier: TrustTier.unverified,
        lastConfirmed: DateTime.now(),
        linkedTripIds: const [],
        linkedTipIds: const [],
        division: 'Chittagong',
        district: 'Bandarban',
        createdByUid: 'user_1',
        category: 'nature',
        visitCount: 0,
        photos: const [],
        imageUrl: null,
        description: '',
      );

      final score = DiscoveryScoreService.compute(pin);
      expect(score, greaterThanOrEqualTo(80));
      expect(DiscoveryScoreService.isHiddenGem(pin), isTrue);
      expect(DiscoveryScoreService.label(score), contains('Undiscovered'));
    });

    test('computes lower discovery score for well-known verified pin with many visits and trips', () {
      final pin = LocationPin(
        pinId: 'popular_spot',
        name: 'Cox Beach',
        geoHash: 'w3',
        lat: 21.42,
        lng: 91.97,
        trustTier: TrustTier.verified,
        lastConfirmed: DateTime.now(),
        linkedTripIds: const ['trip_1', 'trip_2', 'trip_3', 'trip_4', 'trip_5', 'trip_6', 'trip_7', 'trip_8', 'trip_9', 'trip_10', 'trip_11'],
        linkedTipIds: const [],
        division: 'Chittagong',
        district: 'Coxs Bazar',
        createdByUid: 'admin',
        category: 'beach',
        visitCount: 200,
        photos: const ['p1.jpg', 'p2.jpg'],
        imageUrl: 'https://example.com/img.jpg',
        description: 'World famous unbroken natural sea beach.',
      );

      final score = DiscoveryScoreService.compute(pin);
      expect(score, lessThan(30));
      expect(DiscoveryScoreService.isHiddenGem(pin), isFalse);
    });
  });
}
