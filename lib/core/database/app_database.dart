import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'connection/connection.dart' as conn;

part 'app_database.g.dart';

class AuthProfilesTable extends Table {
  TextColumn get uid => text()();
  TextColumn get jsonData => text()(); // Serialized ExplorerProfile

  @override
  Set<Column> get primaryKey => {uid};
}

class TripLogsTable extends Table {
  TextColumn get tripId => text()();
  TextColumn get locationPinId => text()();
  IntColumn get isDraft =>
      integer().withDefault(const Constant(0))(); // 1 = Draft, 0 = Published
  TextColumn get jsonData => text()(); // Serialized TripLog

  @override
  Set<Column> get primaryKey => {tripId};
}

class SyncOutboxTable extends Table {
  TextColumn get id => text()();
  IntColumn get enqueuedAt => integer()(); // Epoch milliseconds
  TextColumn get status => text().withDefault(
      const Constant('pending'))(); // pending, processing, failed, conflict
  TextColumn get jsonData => text()(); // Serialized OutboxEntry

  @override
  Set<Column> get primaryKey => {id};
}

class PointsOfInterestTable extends Table {
  TextColumn get id => text()();
  TextColumn get districtId => text()();
  TextColumn get title => text()();
  TextColumn get category => text()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  TextColumn get description => text().nullable()();
  TextColumn get jsonData => text().nullable()(); // Full serialized JSON

  @override
  Set<Column> get primaryKey => {id};
}

class SyncConflictsTable extends Table {
  TextColumn get id => text()();
  IntColumn get enqueuedAt => integer()(); // Epoch milliseconds
  TextColumn get jsonData => text()(); // Serialized OutboxEntry

  @override
  Set<Column> get primaryKey => {id};
}

@lazySingleton
@DriftDatabase(tables: [
  AuthProfilesTable,
  TripLogsTable,
  SyncOutboxTable,
  PointsOfInterestTable,
  SyncConflictsTable,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(conn.openConnection());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // Add status column to SyncOutboxTable
            await m.addColumn(syncOutboxTable, syncOutboxTable.status);
            // Add jsonData column to PointsOfInterestTable
            await m.addColumn(
                pointsOfInterestTable, pointsOfInterestTable.jsonData);
            // Create SyncConflictsTable
            await m.createTable(syncConflictsTable);
          }
          if (from < 3) {
            await customStatement(
                'CREATE INDEX IF NOT EXISTS trip_logs_pin_idx ON trip_logs_table (location_pin_id);');
            await customStatement(
                'CREATE INDEX IF NOT EXISTS poi_district_idx ON points_of_interest_table (district_id);');
          }
        },
      );

  // Auth Profile Operations
  Future<void> saveProfile(String uid, String json) async {
    await into(authProfilesTable).insertOnConflictUpdate(
      AuthProfilesTableCompanion(
        uid: Value(uid),
        jsonData: Value(json),
      ),
    );
  }

  Future<String?> getProfile(String uid) async {
    final query = select(authProfilesTable)..where((t) => t.uid.equals(uid));
    final row = await query.getSingleOrNull();
    return row?.jsonData;
  }

  Future<void> deleteProfile(String uid) async {
    await (delete(authProfilesTable)..where((t) => t.uid.equals(uid))).go();
  }

  // Trip Log Operations
  Future<void> saveTripLog(
      String tripId, String pinId, bool isDraft, String json) async {
    await into(tripLogsTable).insertOnConflictUpdate(
      TripLogsTableCompanion(
        tripId: Value(tripId),
        locationPinId: Value(pinId),
        isDraft: Value(isDraft ? 1 : 0),
        jsonData: Value(json),
      ),
    );
  }

  Future<List<String>> getTripLogsForPin(String pinId, bool isDraft) async {
    final query = select(tripLogsTable)
      ..where((t) =>
          t.locationPinId.equals(pinId) & t.isDraft.equals(isDraft ? 1 : 0));
    final rows = await query.get();
    return rows.map((r) => r.jsonData).toList();
  }

  Future<String?> getTripLogById(String tripId) async {
    final query = select(tripLogsTable)..where((t) => t.tripId.equals(tripId));
    final row = await query.getSingleOrNull();
    return row?.jsonData;
  }

  Future<void> deleteTripLog(String tripId) async {
    await (delete(tripLogsTable)..where((t) => t.tripId.equals(tripId))).go();
  }

  Future<void> deleteTripLogDraft(String pinId) async {
    await (delete(tripLogsTable)
          ..where((t) => t.locationPinId.equals(pinId) & t.isDraft.equals(1)))
        .go();
  }

  // Sync Outbox Operations
  Future<void> enqueueOutbox(String id, int enqueuedAt, String json,
      {String status = 'pending'}) async {
    await into(syncOutboxTable).insertOnConflictUpdate(
      SyncOutboxTableCompanion(
        id: Value(id),
        enqueuedAt: Value(enqueuedAt),
        status: Value(status),
        jsonData: Value(json),
      ),
    );
  }

  Future<List<String>> getOutboxEntriesOrdered() async {
    final query = select(syncOutboxTable)
      ..where((t) => t.status.equals('pending') | t.status.equals('failed'))
      ..orderBy([
        (t) => OrderingTerm(expression: t.enqueuedAt, mode: OrderingMode.asc)
      ]);
    final rows = await query.get();
    return rows.map((r) => r.jsonData).toList();
  }

  Future<void> deleteOutboxEntry(String id) async {
    await (delete(syncOutboxTable)..where((t) => t.id.equals(id))).go();
  }

  // Points of Interest Operations (Fuzzy Local Search)
  Future<void> savePointOfInterest(
    String id,
    String districtId,
    String title,
    String category,
    double lat,
    double lng,
    String? desc,
    String? json,
  ) async {
    await into(pointsOfInterestTable).insertOnConflictUpdate(
      PointsOfInterestTableCompanion(
        id: Value(id),
        districtId: Value(districtId),
        title: Value(title),
        category: Value(category),
        latitude: Value(lat),
        longitude: Value(lng),
        description: Value(desc),
        jsonData: Value(json),
      ),
    );
  }

  Future<List<PointsOfInterestTableData>> getAllPointsOfInterest() async {
    return select(pointsOfInterestTable).get();
  }

  Future<List<String>> searchPointsOfInterest(
      String query, String districtId) async {
    final sqlQuery = select(pointsOfInterestTable)
      ..where((t) =>
          t.districtId.equals(districtId) &
          (t.title.like('%$query%') | t.description.like('%$query%')));
    final rows = await sqlQuery.get();
    return rows
        .map((r) => '{'
            '"id":"${r.id}",'
            '"districtId":"${r.districtId}",'
            '"title":"${r.title.replaceAll('"', '\\"')}",'
            '"category":"${r.category}",'
            '"latitude":${r.latitude},'
            '"longitude":${r.longitude},'
            '"description":"${(r.description ?? '').replaceAll('"', '\\"')}"'
            '}')
        .toList();
  }

  // Sync Conflict Operations
  Future<void> saveConflict(String id, int enqueuedAt, String json) async {
    await into(syncConflictsTable).insertOnConflictUpdate(
      SyncConflictsTableCompanion(
        id: Value(id),
        enqueuedAt: Value(enqueuedAt),
        jsonData: Value(json),
      ),
    );
  }

  Future<List<String>> getConflictsOrdered() async {
    final query = select(syncConflictsTable)
      ..orderBy([
        (t) => OrderingTerm(expression: t.enqueuedAt, mode: OrderingMode.asc)
      ]);
    final rows = await query.get();
    return rows.map((r) => r.jsonData).toList();
  }

  Future<void> deleteConflict(String id) async {
    await (delete(syncConflictsTable)..where((t) => t.id.equals(id))).go();
  }
}
