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
import 'package:bhromon/features/tour_group/domain/services/tour_record_plan.dart';
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

TourGroup _tripGroup() => TourGroup(
      id: 't1',
      name: 'Trip',
      ownerEmail: 'owner@example.com',
      inviteCode: 'CODE1234',
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 3),
      createdAt: DateTime(2026, 10, 1),
    );

TourGroup _householdGroup() => TourGroup(
      id: 'h1',
      name: 'Home',
      ownerEmail: 'owner@example.com',
      inviteCode: 'HOME1234',
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 1),
      createdAt: DateTime(2026, 10, 1),
      kind: GroupKind.family,
    );

TourMember _member(String email, String name) => TourMember(
      tourId: 't1',
      tourName: 'Trip',
      email: email,
      displayName: name,
      role: TourRole.member,
      status: TourMemberStatus.active,
      joinedAt: DateTime(2026, 10, 1),
    );

/// Reads that work: the people, the money, two posts (one archived) and two stories (one
/// older than a day). Every other read still fails, as it does in [MockTourGroupRepository].
class _WorkingRepository extends MockTourGroupRepository {
  _WorkingRepository(this.now);

  final DateTime now;

  @override
  Stream<List<TourMember>> watchMembers(String? tourId) => Stream.value([
        _member('a@example.com', 'Asha'),
        _member('b@example.com', 'Bina'),
      ]);

  @override
  Stream<List<TourNotice>> watchNotices(String? tourId) =>
      Stream.value(const []);

  @override
  Stream<List<ExpenseItem>> watchExpenses(String? tourId) =>
      Stream.value(const []);

  @override
  Stream<List<DepositItem>> watchDeposits(String? tourId) =>
      Stream.value(const []);

  @override
  Stream<List<TransferItem>> watchTransfers(String? tourId) =>
      Stream.value(const []);

  @override
  Stream<List<SettlementRecord>> watchSettlements(String? tourId) =>
      Stream.value(const []);

  @override
  Stream<List<TourStoryItem>> watchStories(String? tourId) => Stream.value([
        TourStoryItem(
          id: 'fresh',
          authorEmail: 'a@example.com',
          authorName: 'Asha',
          mediaUrl: 'https://bhromon.fun/media/fresh.jpg',
          createdAt: now.subtract(const Duration(hours: 2)),
        ),
        TourStoryItem(
          id: 'old',
          authorEmail: 'a@example.com',
          authorName: 'Asha',
          mediaUrl: 'https://bhromon.fun/media/old.jpg',
          createdAt: now.subtract(const Duration(hours: 30)),
        ),
      ]);

  @override
  Future<List<TourPostItem>> fetchAllPostsForExport(String? tourId) async => [
        TourPostItem(
          id: 'live',
          tourId: 't1',
          authorEmail: 'a@example.com',
          authorName: 'Asha',
          caption: 'live',
          images: const [],
          createdAt: now,
        ),
        TourPostItem(
          id: 'archived',
          tourId: 't1',
          authorEmail: 'a@example.com',
          authorName: 'Asha',
          caption: 'archived',
          images: const [],
          createdAt: now,
          isArchived: true,
        ),
      ];

  @override
  Future<List<TourCommentItem>> fetchCommentsForExport(
    String? tourId,
    String? postId,
  ) async =>
      const [];
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

  test('a failed read is named as an incomplete part, not shown as empty',
      () async {
    final data = await TourExportCollector(MockTourGroupRepository())
        .collect(_tripGroup());

    expect(
      data.incomplete,
      containsAll(<TourRecordSection>[
        TourRecordSection.members,
        TourRecordSection.notices,
        TourRecordSection.money,
        TourRecordSection.feed,
        TourRecordSection.journey,
        TourRecordSection.checklist,
      ]),
    );
    expect(data.incomplete, isNot(contains(TourRecordSection.overview)));
  });

  test('a household reads only the parts its record holds', () async {
    final data = await TourExportCollector(MockTourGroupRepository())
        .collect(_householdGroup());

    expect(
      data.incomplete,
      containsAll(<TourRecordSection>[
        TourRecordSection.familyDates,
        TourRecordSection.dependents,
        TourRecordSection.sharedList,
      ]),
    );
    for (final tripOnly in [
      TourRecordSection.journey,
      TourRecordSection.checklist,
      TourRecordSection.transport,
      TourRecordSection.rooms,
    ]) {
      expect(data.incomplete, isNot(contains(tripOnly)), reason: tripOnly.name);
    }
  });

  test(
      'a read that works keeps the balances, the live posts and the stories of the last day',
      () async {
    final now = DateTime.now();
    final data = await TourExportCollector(_WorkingRepository(now))
        .collect(_tripGroup());

    expect(data.incomplete, isNot(contains(TourRecordSection.money)));
    expect(data.incomplete, isNot(contains(TourRecordSection.members)));
    expect(data.ledger, isNotNull);
    expect(
      data.ledger!.rows.map((row) => row.name),
      containsAll(['Asha', 'Bina']),
    );
    expect(data.posts.map((post) => post.id), ['live']);
    expect(data.stories.map((story) => story.id), ['fresh']);
  });

  test('downloadWebFile stub throws UnsupportedError on non-web platforms',
      () async {
    expect(
      () => downloadWebFile(Uint8List(0), 'test.pdf'),
      throwsA(isA<UnsupportedError>()),
    );
  });
}
