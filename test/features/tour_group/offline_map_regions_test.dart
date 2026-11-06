import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/features/tour_group/domain/services/offline_map_regions.dart';

void main() {
  group('OfflineMapRegion Bounding and Waypoint Coverage', () {
    test('contains verified remote Bangladesh destinations', () {
      expect(kCuratedOfflineRegions.length, greaterThanOrEqualTo(6));

      final sajek =
          kCuratedOfflineRegions.firstWhere((r) => r.id == 'sajek_valley');
      expect(sajek.division, 'Chattogram');
      expect(sajek.estimatedMb, inInclusiveRange(10, 50));
      expect(sajek.waypoints.isNotEmpty, isTrue);
      expect(sajek.contacts.isNotEmpty, isTrue);

      // Verify coordinate containment
      expect(sajek.contains(23.3833, 92.2833), isTrue); // Center
      expect(sajek.contains(24.0, 90.0), isFalse); // Dhaka is outside Sajek
    });

    test('validates emergency helplines for Tanguar Haor and Bandarban', () {
      final tanguar =
          kCuratedOfflineRegions.firstWhere((r) => r.id == 'tanguar_haor');
      expect(tanguar.division, 'Sylhet');
      expect(tanguar.contacts.any((c) => c.phone.startsWith('01')), isTrue);

      final bandarban = kCuratedOfflineRegions
          .firstWhere((r) => r.id == 'bandarban_highlands');
      expect(bandarban.waypoints.any((w) => w.nameBn.contains('কেওক্রাডং')),
          isTrue);
    });

    test('ensures all regions have positive bounds and zoom levels', () {
      for (final r in kCuratedOfflineRegions) {
        expect(r.minLat, lessThan(r.maxLat));
        expect(r.minLng, lessThan(r.maxLng));
        expect(r.minZoom, lessThan(r.maxZoom));
        expect(r.estimatedMb, greaterThan(0));
      }
    });

    test('matches tour destinations to curated offline regions accurately', () {
      expect(regionForDestination('Sajek Cloud Trek')?.id, 'sajek_valley');
      expect(regionForDestination('সাজেক ভ্যালি')?.id, 'sajek_valley');
      expect(regionForDestination('Tanguar Haor Camping')?.id, 'tanguar_haor');
      expect(regionForDestination('টাঙ্গুয়ার হাওর')?.id, 'tanguar_haor');
      expect(regionForDestination('Bandarban Keokradong Peak')?.id,
          'bandarban_highlands');
      expect(regionForDestination('Sundarbans Safari')?.id,
          'sundarbans_riverways');
      expect(regionForDestination("Saint Martin's Island Coral Trek")?.id,
          'saint_martins');
      expect(regionForDestination('শ্রীমঙ্গল')?.id, 'sreemangal_lawachara');
      expect(regionForDestination('London Heathrow'), isNull);
      expect(regionForDestination(null), isNull);
    });

    test('looks up region by unique id', () {
      expect(regionById('sajek_valley')?.nameEn, contains('Sajek'));
      expect(regionById('non_existent'), isNull);
    });

    test('validates waypoint categories and emoji getters', () {
      final sajek =
          kCuratedOfflineRegions.firstWhere((r) => r.id == 'sajek_valley');
      final peak = sajek.waypoints.firstWhere((w) => w.category == 'viewpoint');
      expect(peak.categoryEmoji, '🌄');
      expect(peak.categoryName(false), 'Viewpoint');
      expect(peak.categoryName(true), 'ভিউ পয়েন্ট');
    });
  });
}
