import 'package:bhromon/core/database/app_database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('AppDatabase unsynced changes queries', () {
    test('returns 0 when outbox and trip logs are empty', () async {
      expect(await db.getPendingOutboxCount(), equals(0));
      expect(await db.getDraftTripLogsCount(), equals(0));
      expect(await db.getTotalUnsyncedChangesCount(), equals(0));
    });

    test('counts pending, processing, and failed outbox entries', () async {
      await db.enqueueOutbox('e1', 1000, '{"action":"post"}', status: 'pending');
      await db.enqueueOutbox('e2', 2000, '{"action":"comment"}', status: 'failed');
      await db.enqueueOutbox('e3', 3000, '{"action":"notice"}', status: 'processing');
      // Completed / synced items should not be counted
      await db.enqueueOutbox('e4', 4000, '{"action":"ledger"}', status: 'completed');

      expect(await db.getPendingOutboxCount(), equals(3));
    });

    test('counts draft trip logs (isDraft == 1)', () async {
      await db.into(db.tripLogsTable).insert(
            TripLogsTableCompanion.insert(
              tripId: 'trip_1',
              locationPinId: 'pin_1',
              isDraft: const Value(1),
              jsonData: '{"title":"draft trip"}',
            ),
          );
      await db.into(db.tripLogsTable).insert(
            TripLogsTableCompanion.insert(
              tripId: 'trip_2',
              locationPinId: 'pin_2',
              isDraft: const Value(0), // Published
              jsonData: '{"title":"published trip"}',
            ),
          );

      expect(await db.getDraftTripLogsCount(), equals(1));
    });

    test('computes total unsynced changes accurately', () async {
      await db.enqueueOutbox('e1', 1000, '{"action":"post"}', status: 'pending');
      await db.enqueueOutbox('e2', 2000, '{"action":"comment"}', status: 'pending');

      await db.into(db.tripLogsTable).insert(
            TripLogsTableCompanion.insert(
              tripId: 'draft_1',
              locationPinId: 'pin_1',
              isDraft: const Value(1),
              jsonData: '{"title":"draft 1"}',
            ),
          );

      expect(await db.getTotalUnsyncedChangesCount(), equals(3));
    });
  });
}
