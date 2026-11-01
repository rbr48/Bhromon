import 'dart:async';
import 'dart:typed_data';

import 'package:bhromon/features/tour_group/data/tour_export_collector.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/expense_models.dart';
import 'package:bhromon/features/tour_group/domain/models/logistics_models.dart';
import 'package:bhromon/features/tour_group/domain/models/safety_alert_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_activity_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_post_models.dart';
import 'package:bhromon/features/tour_group/domain/models/vehicle_models.dart';
import 'package:bhromon/features/tour_group/presentation/tour_pdf_download.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

class MockTourGroupRepository extends Mock implements TourGroupRepository {
  @override
  Future<TourGroup?> getGroup(String? tourId) async => null;

  @override
  Stream<List<TourMember>> watchMembers(String? tourId) =>
      Stream.error(Exception('network error'));

  @override
  Stream<List<TourNotice>> watchNotices(String? tourId) =>
      Stream.error(Exception('permission denied'));

  @override
  Stream<List<RouteCheckpoint>> watchCheckpoints(String? tourId) =>
      Stream.error(Exception('timed out'));

  @override
  Stream<List<ChecklistItem>> watchChecklist(String? tourId) =>
      Stream.error(Exception('failed'));

  @override
  Stream<List<ExpenseItem>> watchExpenses(String? tourId) =>
      Stream.error(Exception('failed'));

  @override
  Stream<List<DepositItem>> watchDeposits(String? tourId) =>
      Stream.error(Exception('failed'));

  @override
  Stream<List<TransferItem>> watchTransfers(String? tourId) =>
      Stream.error(Exception('failed'));

  @override
  Stream<List<TourVehicle>> watchVehicles(String? tourId) =>
      Stream.error(Exception('failed'));

  @override
  Stream<List<BusSeat>> watchCoachSeats(String? tourId) =>
      Stream.error(Exception('failed'));

  @override
  Stream<List<HotelRoom>> watchHotelRooms(String? tourId) =>
      Stream.error(Exception('failed'));

  @override
  Stream<List<SafetyAlert>> watchSafetyAlerts(String? tourId,
          {int limit = 30}) =>
      Stream.error(Exception('failed'));

  @override
  Stream<List<TourStoryItem>> watchStories(String? tourId) =>
      Stream.error(Exception('failed'));

  @override
  Stream<List<TourStoryHighlight>> watchHighlights(String? tourId) =>
      Stream.error(Exception('failed'));

  @override
  Future<List<TourPostItem>> fetchAllPostsForExport(String? tourId) async {
    throw Exception('failed posts query');
  }
}

void main() {
  test('TourExportCollector is resilient against failing subcollections',
      () async {
    final repo = MockTourGroupRepository();
    final group = TourGroup(
      id: 'tour_123',
      name: 'Rangpur to Coxs Bazar',
      ownerEmail: 'test@example.com',
      inviteCode: 'INV12345',
      destination: 'Coxs Bazar',
      originCity: 'Rangpur',
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 5),
      createdAt: DateTime(2026, 10, 1),
    );

    final collector = TourExportCollector(repo);
    final data = await collector.collect(group);

    expect(data.group.id, 'tour_123');
    expect(data.members, isEmpty);
    expect(data.notices, isEmpty);
    expect(data.checkpoints, isEmpty);
    expect(data.posts, isEmpty);
    expect(data.expenses, isEmpty);
  });

  test('downloadWebFile stub throws UnsupportedError on non-web platforms',
      () async {
    expect(
      () => downloadWebFile(Uint8List(0), 'test.pdf'),
      throwsA(isA<UnsupportedError>()),
    );
  });
}
