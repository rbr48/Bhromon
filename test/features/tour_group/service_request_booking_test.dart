import 'package:bhromon/features/tour_group/domain/models/service_request_models.dart';
import 'package:bhromon/features/tour_group/domain/services/fund_analytics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a booked repair is filed under a society upkeep category', () {
    expect(kSocietyExpenseCategories, contains(kRepairCostCategory));
  });

  test('a booked repair uses the Repairs category', () {
    expect(kRepairCostCategory, 'Repairs');
  });
}
