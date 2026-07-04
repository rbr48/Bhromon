import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/core/entities/trip_log.dart';
import 'package:bhromon/core/entities/trip_block.dart';
import 'package:bhromon/core/value_objects/trust_tier.dart';
import 'package:bhromon/core/value_objects/sync_status.dart';

void main() {
  test('Test Firestore Trip Log Write', () async {
    // We cannot run live Firebase calls in a standard offline unit test without initializing it.
    // Let's see if we can print the JSON structure of a TripLog to check for anomalies.
    final log = TripLog(
      tripId: 'test_log_id',
      authorId: 'test_author_uid',
      title: 'Beautiful Sajek Valley Trip',
      blocks: [
        const TripBlock.text(
          id: 'blk_1',
          content: 'We had an amazing time at Sajek.',
          isBold: false,
        ),
        const TripBlock.image(
          id: 'blk_2',
          storageUrl:
              'https://images.unsplash.com/photo-1507525428034-b723cf961d3e',
          caption: 'Sunset at Sajek',
        )
      ],
      routePoints: const [],
      costItems: const [],
      locationPinId: 'sajek_pin',
      trustScore: 50,
      helpfulVotes: 0,
      lastConfirmed: DateTime.now(),
      division: 'Chittagong',
      district: 'Rangamati',
      hidden: false,
      tier: TrustTier.unverified,
      syncStatus: SyncStatus.synced,
      isPremiumGuide: false,
    );

    debugPrint('Serialized JSON:');
    debugPrint(log.toJson().toString());
  });
}
