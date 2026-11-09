import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/features/tour_group/domain/services/local_fare_guide.dart';

void main() {
  const guide = LocalFareGuide();

  group('LocalFareGuide Catalog & Search', () {
    test('catalog contains verified destinations across multiple divisions',
        () {
      expect(LocalFareGuide.catalog, isNotEmpty);
      final destinations =
          LocalFareGuide.catalog.map((r) => r.destination).toSet();
      expect(destinations.contains('Sajek Valley'), isTrue);
      expect(destinations.contains('Tanguar Haor'), isTrue);
      expect(destinations.contains('Sreemangal'), isTrue);
      expect(destinations.contains('Bandarban'), isTrue);
      expect(destinations.contains('Sundarbans'), isTrue);
      expect(destinations.contains('Kuakata'), isTrue);
    });

    test('search filters by query string', () {
      final sajekRoutes = guide.search(query: 'sajek');
      expect(sajekRoutes, isNotEmpty);
      for (final r in sajekRoutes) {
        expect(
          r.destination.toLowerCase().contains('sajek') ||
              r.destinationBn.contains('সাজেক'),
          isTrue,
        );
      }
    });

    test('search filters by division', () {
      final sylhetRoutes = guide.search(division: 'Sylhet');
      expect(sylhetRoutes, isNotEmpty);
      for (final r in sylhetRoutes) {
        expect(r.division, 'Sylhet');
      }
    });
  });

  group('LocalFareGuide Fare Calculation', () {
    test('calculates vehicle reservation for single and multiple vehicles', () {
      final sajekRoute = LocalFareGuide.catalog
          .firstWhere((r) => r.id == 'sajek_chander_gari_rt');

      // 10 passengers (capacity 13) -> 1 vehicle
      final res1 = guide.calculate(route: sajekRoute, passengerCount: 10);
      expect(res1.vehiclesNeeded, 1);
      expect(res1.totalMinFare, 8500);
      expect(res1.totalMaxFare, 11000);
      expect(res1.perPersonMinFare, (8500 / 10).ceil());
      expect(res1.perPersonMaxFare, (11000 / 10).ceil());

      // 15 passengers (capacity 13) -> 2 vehicles
      final res2 = guide.calculate(route: sajekRoute, passengerCount: 15);
      expect(res2.vehiclesNeeded, 2);
      expect(res2.totalMinFare, 8500 * 2);
      expect(res2.totalMaxFare, 11000 * 2);
      expect(res2.perPersonMinFare, (17000 / 15).ceil());
      expect(res2.perPersonMaxFare, (22000 / 15).ceil());
    });

    test('calculates per-person ticket routes accurately', () {
      final shipRoute = LocalFareGuide.catalog
          .firstWhere((r) => r.id == 'saint_martin_ship_ticket');
      expect(shipRoute.isPerPerson, isTrue);

      final res = guide.calculate(route: shipRoute, passengerCount: 5);
      expect(res.vehiclesNeeded, 5);
      expect(res.totalMinFare, 950 * 5);
      expect(res.totalMaxFare, 2500 * 5);
      expect(res.perPersonMinFare, 950);
      expect(res.perPersonMaxFare, 2500);
    });

    test('handles zero or negative passenger count safely', () {
      final sajekRoute = LocalFareGuide.catalog
          .firstWhere((r) => r.id == 'sajek_chander_gari_rt');

      final res = guide.calculate(route: sajekRoute, passengerCount: 0);
      expect(res.passengerCount, 1);
      expect(res.vehiclesNeeded, 1);
      expect(res.totalMinFare, 8500);
    });

    test('formatSummary returns readable non-empty text with Bengali figures',
        () {
      final sajekRoute = LocalFareGuide.catalog
          .firstWhere((r) => r.id == 'sajek_chander_gari_rt');
      final res = guide.calculate(route: sajekRoute, passengerCount: 12);
      final text = res.formatSummary();
      expect(text.contains('সাজেক ভ্যালি'), isTrue);
      expect(text.contains('চাঁদের গাড়ি'), isTrue);
      expect(text.contains('৳'), isTrue);
      expect(text.contains('টিপস ও সতর্কতা'), isTrue);
    });
  });

  group('LocalFareGuide Sourced Audit (Task 9.2)', () {
    test('every catalog route carries a verified source and audit date', () {
      for (final r in LocalFareGuide.catalog) {
        expect(r.source, isNotEmpty);
        expect(r.asOf, isNotEmpty);
      }
    });
  });
}
