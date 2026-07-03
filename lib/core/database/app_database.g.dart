// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $AuthProfilesTableTable extends AuthProfilesTable
    with TableInfo<$AuthProfilesTableTable, AuthProfilesTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AuthProfilesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _uidMeta = const VerificationMeta('uid');
  @override
  late final GeneratedColumn<String> uid = GeneratedColumn<String>(
      'uid', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _jsonDataMeta =
      const VerificationMeta('jsonData');
  @override
  late final GeneratedColumn<String> jsonData = GeneratedColumn<String>(
      'json_data', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [uid, jsonData];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'auth_profiles_table';
  @override
  VerificationContext validateIntegrity(
      Insertable<AuthProfilesTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('uid')) {
      context.handle(
          _uidMeta, uid.isAcceptableOrUnknown(data['uid']!, _uidMeta));
    } else if (isInserting) {
      context.missing(_uidMeta);
    }
    if (data.containsKey('json_data')) {
      context.handle(_jsonDataMeta,
          jsonData.isAcceptableOrUnknown(data['json_data']!, _jsonDataMeta));
    } else if (isInserting) {
      context.missing(_jsonDataMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {uid};
  @override
  AuthProfilesTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AuthProfilesTableData(
      uid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}uid'])!,
      jsonData: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}json_data'])!,
    );
  }

  @override
  $AuthProfilesTableTable createAlias(String alias) {
    return $AuthProfilesTableTable(attachedDatabase, alias);
  }
}

class AuthProfilesTableData extends DataClass
    implements Insertable<AuthProfilesTableData> {
  final String uid;
  final String jsonData;
  const AuthProfilesTableData({required this.uid, required this.jsonData});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['uid'] = Variable<String>(uid);
    map['json_data'] = Variable<String>(jsonData);
    return map;
  }

  AuthProfilesTableCompanion toCompanion(bool nullToAbsent) {
    return AuthProfilesTableCompanion(
      uid: Value(uid),
      jsonData: Value(jsonData),
    );
  }

  factory AuthProfilesTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AuthProfilesTableData(
      uid: serializer.fromJson<String>(json['uid']),
      jsonData: serializer.fromJson<String>(json['jsonData']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'uid': serializer.toJson<String>(uid),
      'jsonData': serializer.toJson<String>(jsonData),
    };
  }

  AuthProfilesTableData copyWith({String? uid, String? jsonData}) =>
      AuthProfilesTableData(
        uid: uid ?? this.uid,
        jsonData: jsonData ?? this.jsonData,
      );
  AuthProfilesTableData copyWithCompanion(AuthProfilesTableCompanion data) {
    return AuthProfilesTableData(
      uid: data.uid.present ? data.uid.value : this.uid,
      jsonData: data.jsonData.present ? data.jsonData.value : this.jsonData,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AuthProfilesTableData(')
          ..write('uid: $uid, ')
          ..write('jsonData: $jsonData')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(uid, jsonData);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuthProfilesTableData &&
          other.uid == this.uid &&
          other.jsonData == this.jsonData);
}

class AuthProfilesTableCompanion
    extends UpdateCompanion<AuthProfilesTableData> {
  final Value<String> uid;
  final Value<String> jsonData;
  final Value<int> rowid;
  const AuthProfilesTableCompanion({
    this.uid = const Value.absent(),
    this.jsonData = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AuthProfilesTableCompanion.insert({
    required String uid,
    required String jsonData,
    this.rowid = const Value.absent(),
  })  : uid = Value(uid),
        jsonData = Value(jsonData);
  static Insertable<AuthProfilesTableData> custom({
    Expression<String>? uid,
    Expression<String>? jsonData,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (uid != null) 'uid': uid,
      if (jsonData != null) 'json_data': jsonData,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AuthProfilesTableCompanion copyWith(
      {Value<String>? uid, Value<String>? jsonData, Value<int>? rowid}) {
    return AuthProfilesTableCompanion(
      uid: uid ?? this.uid,
      jsonData: jsonData ?? this.jsonData,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (uid.present) {
      map['uid'] = Variable<String>(uid.value);
    }
    if (jsonData.present) {
      map['json_data'] = Variable<String>(jsonData.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AuthProfilesTableCompanion(')
          ..write('uid: $uid, ')
          ..write('jsonData: $jsonData, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TripLogsTableTable extends TripLogsTable
    with TableInfo<$TripLogsTableTable, TripLogsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TripLogsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tripIdMeta = const VerificationMeta('tripId');
  @override
  late final GeneratedColumn<String> tripId = GeneratedColumn<String>(
      'trip_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _locationPinIdMeta =
      const VerificationMeta('locationPinId');
  @override
  late final GeneratedColumn<String> locationPinId = GeneratedColumn<String>(
      'location_pin_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isDraftMeta =
      const VerificationMeta('isDraft');
  @override
  late final GeneratedColumn<int> isDraft = GeneratedColumn<int>(
      'is_draft', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _jsonDataMeta =
      const VerificationMeta('jsonData');
  @override
  late final GeneratedColumn<String> jsonData = GeneratedColumn<String>(
      'json_data', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [tripId, locationPinId, isDraft, jsonData];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'trip_logs_table';
  @override
  VerificationContext validateIntegrity(Insertable<TripLogsTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('trip_id')) {
      context.handle(_tripIdMeta,
          tripId.isAcceptableOrUnknown(data['trip_id']!, _tripIdMeta));
    } else if (isInserting) {
      context.missing(_tripIdMeta);
    }
    if (data.containsKey('location_pin_id')) {
      context.handle(
          _locationPinIdMeta,
          locationPinId.isAcceptableOrUnknown(
              data['location_pin_id']!, _locationPinIdMeta));
    } else if (isInserting) {
      context.missing(_locationPinIdMeta);
    }
    if (data.containsKey('is_draft')) {
      context.handle(_isDraftMeta,
          isDraft.isAcceptableOrUnknown(data['is_draft']!, _isDraftMeta));
    }
    if (data.containsKey('json_data')) {
      context.handle(_jsonDataMeta,
          jsonData.isAcceptableOrUnknown(data['json_data']!, _jsonDataMeta));
    } else if (isInserting) {
      context.missing(_jsonDataMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tripId};
  @override
  TripLogsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TripLogsTableData(
      tripId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}trip_id'])!,
      locationPinId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}location_pin_id'])!,
      isDraft: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}is_draft'])!,
      jsonData: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}json_data'])!,
    );
  }

  @override
  $TripLogsTableTable createAlias(String alias) {
    return $TripLogsTableTable(attachedDatabase, alias);
  }
}

class TripLogsTableData extends DataClass
    implements Insertable<TripLogsTableData> {
  final String tripId;
  final String locationPinId;
  final int isDraft;
  final String jsonData;
  const TripLogsTableData(
      {required this.tripId,
      required this.locationPinId,
      required this.isDraft,
      required this.jsonData});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['trip_id'] = Variable<String>(tripId);
    map['location_pin_id'] = Variable<String>(locationPinId);
    map['is_draft'] = Variable<int>(isDraft);
    map['json_data'] = Variable<String>(jsonData);
    return map;
  }

  TripLogsTableCompanion toCompanion(bool nullToAbsent) {
    return TripLogsTableCompanion(
      tripId: Value(tripId),
      locationPinId: Value(locationPinId),
      isDraft: Value(isDraft),
      jsonData: Value(jsonData),
    );
  }

  factory TripLogsTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TripLogsTableData(
      tripId: serializer.fromJson<String>(json['tripId']),
      locationPinId: serializer.fromJson<String>(json['locationPinId']),
      isDraft: serializer.fromJson<int>(json['isDraft']),
      jsonData: serializer.fromJson<String>(json['jsonData']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tripId': serializer.toJson<String>(tripId),
      'locationPinId': serializer.toJson<String>(locationPinId),
      'isDraft': serializer.toJson<int>(isDraft),
      'jsonData': serializer.toJson<String>(jsonData),
    };
  }

  TripLogsTableData copyWith(
          {String? tripId,
          String? locationPinId,
          int? isDraft,
          String? jsonData}) =>
      TripLogsTableData(
        tripId: tripId ?? this.tripId,
        locationPinId: locationPinId ?? this.locationPinId,
        isDraft: isDraft ?? this.isDraft,
        jsonData: jsonData ?? this.jsonData,
      );
  TripLogsTableData copyWithCompanion(TripLogsTableCompanion data) {
    return TripLogsTableData(
      tripId: data.tripId.present ? data.tripId.value : this.tripId,
      locationPinId: data.locationPinId.present
          ? data.locationPinId.value
          : this.locationPinId,
      isDraft: data.isDraft.present ? data.isDraft.value : this.isDraft,
      jsonData: data.jsonData.present ? data.jsonData.value : this.jsonData,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TripLogsTableData(')
          ..write('tripId: $tripId, ')
          ..write('locationPinId: $locationPinId, ')
          ..write('isDraft: $isDraft, ')
          ..write('jsonData: $jsonData')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(tripId, locationPinId, isDraft, jsonData);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TripLogsTableData &&
          other.tripId == this.tripId &&
          other.locationPinId == this.locationPinId &&
          other.isDraft == this.isDraft &&
          other.jsonData == this.jsonData);
}

class TripLogsTableCompanion extends UpdateCompanion<TripLogsTableData> {
  final Value<String> tripId;
  final Value<String> locationPinId;
  final Value<int> isDraft;
  final Value<String> jsonData;
  final Value<int> rowid;
  const TripLogsTableCompanion({
    this.tripId = const Value.absent(),
    this.locationPinId = const Value.absent(),
    this.isDraft = const Value.absent(),
    this.jsonData = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TripLogsTableCompanion.insert({
    required String tripId,
    required String locationPinId,
    this.isDraft = const Value.absent(),
    required String jsonData,
    this.rowid = const Value.absent(),
  })  : tripId = Value(tripId),
        locationPinId = Value(locationPinId),
        jsonData = Value(jsonData);
  static Insertable<TripLogsTableData> custom({
    Expression<String>? tripId,
    Expression<String>? locationPinId,
    Expression<int>? isDraft,
    Expression<String>? jsonData,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tripId != null) 'trip_id': tripId,
      if (locationPinId != null) 'location_pin_id': locationPinId,
      if (isDraft != null) 'is_draft': isDraft,
      if (jsonData != null) 'json_data': jsonData,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TripLogsTableCompanion copyWith(
      {Value<String>? tripId,
      Value<String>? locationPinId,
      Value<int>? isDraft,
      Value<String>? jsonData,
      Value<int>? rowid}) {
    return TripLogsTableCompanion(
      tripId: tripId ?? this.tripId,
      locationPinId: locationPinId ?? this.locationPinId,
      isDraft: isDraft ?? this.isDraft,
      jsonData: jsonData ?? this.jsonData,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tripId.present) {
      map['trip_id'] = Variable<String>(tripId.value);
    }
    if (locationPinId.present) {
      map['location_pin_id'] = Variable<String>(locationPinId.value);
    }
    if (isDraft.present) {
      map['is_draft'] = Variable<int>(isDraft.value);
    }
    if (jsonData.present) {
      map['json_data'] = Variable<String>(jsonData.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TripLogsTableCompanion(')
          ..write('tripId: $tripId, ')
          ..write('locationPinId: $locationPinId, ')
          ..write('isDraft: $isDraft, ')
          ..write('jsonData: $jsonData, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncOutboxTableTable extends SyncOutboxTable
    with TableInfo<$SyncOutboxTableTable, SyncOutboxTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncOutboxTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _enqueuedAtMeta =
      const VerificationMeta('enqueuedAt');
  @override
  late final GeneratedColumn<int> enqueuedAt = GeneratedColumn<int>(
      'enqueued_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('pending'));
  static const VerificationMeta _jsonDataMeta =
      const VerificationMeta('jsonData');
  @override
  late final GeneratedColumn<String> jsonData = GeneratedColumn<String>(
      'json_data', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, enqueuedAt, status, jsonData];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_outbox_table';
  @override
  VerificationContext validateIntegrity(
      Insertable<SyncOutboxTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('enqueued_at')) {
      context.handle(
          _enqueuedAtMeta,
          enqueuedAt.isAcceptableOrUnknown(
              data['enqueued_at']!, _enqueuedAtMeta));
    } else if (isInserting) {
      context.missing(_enqueuedAtMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('json_data')) {
      context.handle(_jsonDataMeta,
          jsonData.isAcceptableOrUnknown(data['json_data']!, _jsonDataMeta));
    } else if (isInserting) {
      context.missing(_jsonDataMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncOutboxTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncOutboxTableData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      enqueuedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}enqueued_at'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      jsonData: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}json_data'])!,
    );
  }

  @override
  $SyncOutboxTableTable createAlias(String alias) {
    return $SyncOutboxTableTable(attachedDatabase, alias);
  }
}

class SyncOutboxTableData extends DataClass
    implements Insertable<SyncOutboxTableData> {
  final String id;
  final int enqueuedAt;
  final String status;
  final String jsonData;
  const SyncOutboxTableData(
      {required this.id,
      required this.enqueuedAt,
      required this.status,
      required this.jsonData});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['enqueued_at'] = Variable<int>(enqueuedAt);
    map['status'] = Variable<String>(status);
    map['json_data'] = Variable<String>(jsonData);
    return map;
  }

  SyncOutboxTableCompanion toCompanion(bool nullToAbsent) {
    return SyncOutboxTableCompanion(
      id: Value(id),
      enqueuedAt: Value(enqueuedAt),
      status: Value(status),
      jsonData: Value(jsonData),
    );
  }

  factory SyncOutboxTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncOutboxTableData(
      id: serializer.fromJson<String>(json['id']),
      enqueuedAt: serializer.fromJson<int>(json['enqueuedAt']),
      status: serializer.fromJson<String>(json['status']),
      jsonData: serializer.fromJson<String>(json['jsonData']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'enqueuedAt': serializer.toJson<int>(enqueuedAt),
      'status': serializer.toJson<String>(status),
      'jsonData': serializer.toJson<String>(jsonData),
    };
  }

  SyncOutboxTableData copyWith(
          {String? id, int? enqueuedAt, String? status, String? jsonData}) =>
      SyncOutboxTableData(
        id: id ?? this.id,
        enqueuedAt: enqueuedAt ?? this.enqueuedAt,
        status: status ?? this.status,
        jsonData: jsonData ?? this.jsonData,
      );
  SyncOutboxTableData copyWithCompanion(SyncOutboxTableCompanion data) {
    return SyncOutboxTableData(
      id: data.id.present ? data.id.value : this.id,
      enqueuedAt:
          data.enqueuedAt.present ? data.enqueuedAt.value : this.enqueuedAt,
      status: data.status.present ? data.status.value : this.status,
      jsonData: data.jsonData.present ? data.jsonData.value : this.jsonData,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncOutboxTableData(')
          ..write('id: $id, ')
          ..write('enqueuedAt: $enqueuedAt, ')
          ..write('status: $status, ')
          ..write('jsonData: $jsonData')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, enqueuedAt, status, jsonData);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncOutboxTableData &&
          other.id == this.id &&
          other.enqueuedAt == this.enqueuedAt &&
          other.status == this.status &&
          other.jsonData == this.jsonData);
}

class SyncOutboxTableCompanion extends UpdateCompanion<SyncOutboxTableData> {
  final Value<String> id;
  final Value<int> enqueuedAt;
  final Value<String> status;
  final Value<String> jsonData;
  final Value<int> rowid;
  const SyncOutboxTableCompanion({
    this.id = const Value.absent(),
    this.enqueuedAt = const Value.absent(),
    this.status = const Value.absent(),
    this.jsonData = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncOutboxTableCompanion.insert({
    required String id,
    required int enqueuedAt,
    this.status = const Value.absent(),
    required String jsonData,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        enqueuedAt = Value(enqueuedAt),
        jsonData = Value(jsonData);
  static Insertable<SyncOutboxTableData> custom({
    Expression<String>? id,
    Expression<int>? enqueuedAt,
    Expression<String>? status,
    Expression<String>? jsonData,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (enqueuedAt != null) 'enqueued_at': enqueuedAt,
      if (status != null) 'status': status,
      if (jsonData != null) 'json_data': jsonData,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncOutboxTableCompanion copyWith(
      {Value<String>? id,
      Value<int>? enqueuedAt,
      Value<String>? status,
      Value<String>? jsonData,
      Value<int>? rowid}) {
    return SyncOutboxTableCompanion(
      id: id ?? this.id,
      enqueuedAt: enqueuedAt ?? this.enqueuedAt,
      status: status ?? this.status,
      jsonData: jsonData ?? this.jsonData,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (enqueuedAt.present) {
      map['enqueued_at'] = Variable<int>(enqueuedAt.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (jsonData.present) {
      map['json_data'] = Variable<String>(jsonData.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncOutboxTableCompanion(')
          ..write('id: $id, ')
          ..write('enqueuedAt: $enqueuedAt, ')
          ..write('status: $status, ')
          ..write('jsonData: $jsonData, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PointsOfInterestTableTable extends PointsOfInterestTable
    with TableInfo<$PointsOfInterestTableTable, PointsOfInterestTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PointsOfInterestTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _districtIdMeta =
      const VerificationMeta('districtId');
  @override
  late final GeneratedColumn<String> districtId = GeneratedColumn<String>(
      'district_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _categoryMeta =
      const VerificationMeta('category');
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
      'category', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _latitudeMeta =
      const VerificationMeta('latitude');
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
      'latitude', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _longitudeMeta =
      const VerificationMeta('longitude');
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
      'longitude', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _jsonDataMeta =
      const VerificationMeta('jsonData');
  @override
  late final GeneratedColumn<String> jsonData = GeneratedColumn<String>(
      'json_data', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        districtId,
        title,
        category,
        latitude,
        longitude,
        description,
        jsonData
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'points_of_interest_table';
  @override
  VerificationContext validateIntegrity(
      Insertable<PointsOfInterestTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('district_id')) {
      context.handle(
          _districtIdMeta,
          districtId.isAcceptableOrUnknown(
              data['district_id']!, _districtIdMeta));
    } else if (isInserting) {
      context.missing(_districtIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('category')) {
      context.handle(_categoryMeta,
          category.isAcceptableOrUnknown(data['category']!, _categoryMeta));
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('latitude')) {
      context.handle(_latitudeMeta,
          latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta));
    } else if (isInserting) {
      context.missing(_latitudeMeta);
    }
    if (data.containsKey('longitude')) {
      context.handle(_longitudeMeta,
          longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta));
    } else if (isInserting) {
      context.missing(_longitudeMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('json_data')) {
      context.handle(_jsonDataMeta,
          jsonData.isAcceptableOrUnknown(data['json_data']!, _jsonDataMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PointsOfInterestTableData map(Map<String, dynamic> data,
      {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PointsOfInterestTableData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      districtId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}district_id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      category: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category'])!,
      latitude: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}latitude'])!,
      longitude: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}longitude'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description']),
      jsonData: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}json_data']),
    );
  }

  @override
  $PointsOfInterestTableTable createAlias(String alias) {
    return $PointsOfInterestTableTable(attachedDatabase, alias);
  }
}

class PointsOfInterestTableData extends DataClass
    implements Insertable<PointsOfInterestTableData> {
  final String id;
  final String districtId;
  final String title;
  final String category;
  final double latitude;
  final double longitude;
  final String? description;
  final String? jsonData;
  const PointsOfInterestTableData(
      {required this.id,
      required this.districtId,
      required this.title,
      required this.category,
      required this.latitude,
      required this.longitude,
      this.description,
      this.jsonData});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['district_id'] = Variable<String>(districtId);
    map['title'] = Variable<String>(title);
    map['category'] = Variable<String>(category);
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || jsonData != null) {
      map['json_data'] = Variable<String>(jsonData);
    }
    return map;
  }

  PointsOfInterestTableCompanion toCompanion(bool nullToAbsent) {
    return PointsOfInterestTableCompanion(
      id: Value(id),
      districtId: Value(districtId),
      title: Value(title),
      category: Value(category),
      latitude: Value(latitude),
      longitude: Value(longitude),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      jsonData: jsonData == null && nullToAbsent
          ? const Value.absent()
          : Value(jsonData),
    );
  }

  factory PointsOfInterestTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PointsOfInterestTableData(
      id: serializer.fromJson<String>(json['id']),
      districtId: serializer.fromJson<String>(json['districtId']),
      title: serializer.fromJson<String>(json['title']),
      category: serializer.fromJson<String>(json['category']),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
      description: serializer.fromJson<String?>(json['description']),
      jsonData: serializer.fromJson<String?>(json['jsonData']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'districtId': serializer.toJson<String>(districtId),
      'title': serializer.toJson<String>(title),
      'category': serializer.toJson<String>(category),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
      'description': serializer.toJson<String?>(description),
      'jsonData': serializer.toJson<String?>(jsonData),
    };
  }

  PointsOfInterestTableData copyWith(
          {String? id,
          String? districtId,
          String? title,
          String? category,
          double? latitude,
          double? longitude,
          Value<String?> description = const Value.absent(),
          Value<String?> jsonData = const Value.absent()}) =>
      PointsOfInterestTableData(
        id: id ?? this.id,
        districtId: districtId ?? this.districtId,
        title: title ?? this.title,
        category: category ?? this.category,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        description: description.present ? description.value : this.description,
        jsonData: jsonData.present ? jsonData.value : this.jsonData,
      );
  PointsOfInterestTableData copyWithCompanion(
      PointsOfInterestTableCompanion data) {
    return PointsOfInterestTableData(
      id: data.id.present ? data.id.value : this.id,
      districtId:
          data.districtId.present ? data.districtId.value : this.districtId,
      title: data.title.present ? data.title.value : this.title,
      category: data.category.present ? data.category.value : this.category,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      description:
          data.description.present ? data.description.value : this.description,
      jsonData: data.jsonData.present ? data.jsonData.value : this.jsonData,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PointsOfInterestTableData(')
          ..write('id: $id, ')
          ..write('districtId: $districtId, ')
          ..write('title: $title, ')
          ..write('category: $category, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('description: $description, ')
          ..write('jsonData: $jsonData')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, districtId, title, category, latitude,
      longitude, description, jsonData);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PointsOfInterestTableData &&
          other.id == this.id &&
          other.districtId == this.districtId &&
          other.title == this.title &&
          other.category == this.category &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.description == this.description &&
          other.jsonData == this.jsonData);
}

class PointsOfInterestTableCompanion
    extends UpdateCompanion<PointsOfInterestTableData> {
  final Value<String> id;
  final Value<String> districtId;
  final Value<String> title;
  final Value<String> category;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<String?> description;
  final Value<String?> jsonData;
  final Value<int> rowid;
  const PointsOfInterestTableCompanion({
    this.id = const Value.absent(),
    this.districtId = const Value.absent(),
    this.title = const Value.absent(),
    this.category = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.description = const Value.absent(),
    this.jsonData = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PointsOfInterestTableCompanion.insert({
    required String id,
    required String districtId,
    required String title,
    required String category,
    required double latitude,
    required double longitude,
    this.description = const Value.absent(),
    this.jsonData = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        districtId = Value(districtId),
        title = Value(title),
        category = Value(category),
        latitude = Value(latitude),
        longitude = Value(longitude);
  static Insertable<PointsOfInterestTableData> custom({
    Expression<String>? id,
    Expression<String>? districtId,
    Expression<String>? title,
    Expression<String>? category,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<String>? description,
    Expression<String>? jsonData,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (districtId != null) 'district_id': districtId,
      if (title != null) 'title': title,
      if (category != null) 'category': category,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (description != null) 'description': description,
      if (jsonData != null) 'json_data': jsonData,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PointsOfInterestTableCompanion copyWith(
      {Value<String>? id,
      Value<String>? districtId,
      Value<String>? title,
      Value<String>? category,
      Value<double>? latitude,
      Value<double>? longitude,
      Value<String?>? description,
      Value<String?>? jsonData,
      Value<int>? rowid}) {
    return PointsOfInterestTableCompanion(
      id: id ?? this.id,
      districtId: districtId ?? this.districtId,
      title: title ?? this.title,
      category: category ?? this.category,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      description: description ?? this.description,
      jsonData: jsonData ?? this.jsonData,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (districtId.present) {
      map['district_id'] = Variable<String>(districtId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (jsonData.present) {
      map['json_data'] = Variable<String>(jsonData.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PointsOfInterestTableCompanion(')
          ..write('id: $id, ')
          ..write('districtId: $districtId, ')
          ..write('title: $title, ')
          ..write('category: $category, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('description: $description, ')
          ..write('jsonData: $jsonData, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncConflictsTableTable extends SyncConflictsTable
    with TableInfo<$SyncConflictsTableTable, SyncConflictsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncConflictsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _enqueuedAtMeta =
      const VerificationMeta('enqueuedAt');
  @override
  late final GeneratedColumn<int> enqueuedAt = GeneratedColumn<int>(
      'enqueued_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _jsonDataMeta =
      const VerificationMeta('jsonData');
  @override
  late final GeneratedColumn<String> jsonData = GeneratedColumn<String>(
      'json_data', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, enqueuedAt, jsonData];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_conflicts_table';
  @override
  VerificationContext validateIntegrity(
      Insertable<SyncConflictsTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('enqueued_at')) {
      context.handle(
          _enqueuedAtMeta,
          enqueuedAt.isAcceptableOrUnknown(
              data['enqueued_at']!, _enqueuedAtMeta));
    } else if (isInserting) {
      context.missing(_enqueuedAtMeta);
    }
    if (data.containsKey('json_data')) {
      context.handle(_jsonDataMeta,
          jsonData.isAcceptableOrUnknown(data['json_data']!, _jsonDataMeta));
    } else if (isInserting) {
      context.missing(_jsonDataMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncConflictsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncConflictsTableData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      enqueuedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}enqueued_at'])!,
      jsonData: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}json_data'])!,
    );
  }

  @override
  $SyncConflictsTableTable createAlias(String alias) {
    return $SyncConflictsTableTable(attachedDatabase, alias);
  }
}

class SyncConflictsTableData extends DataClass
    implements Insertable<SyncConflictsTableData> {
  final String id;
  final int enqueuedAt;
  final String jsonData;
  const SyncConflictsTableData(
      {required this.id, required this.enqueuedAt, required this.jsonData});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['enqueued_at'] = Variable<int>(enqueuedAt);
    map['json_data'] = Variable<String>(jsonData);
    return map;
  }

  SyncConflictsTableCompanion toCompanion(bool nullToAbsent) {
    return SyncConflictsTableCompanion(
      id: Value(id),
      enqueuedAt: Value(enqueuedAt),
      jsonData: Value(jsonData),
    );
  }

  factory SyncConflictsTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncConflictsTableData(
      id: serializer.fromJson<String>(json['id']),
      enqueuedAt: serializer.fromJson<int>(json['enqueuedAt']),
      jsonData: serializer.fromJson<String>(json['jsonData']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'enqueuedAt': serializer.toJson<int>(enqueuedAt),
      'jsonData': serializer.toJson<String>(jsonData),
    };
  }

  SyncConflictsTableData copyWith(
          {String? id, int? enqueuedAt, String? jsonData}) =>
      SyncConflictsTableData(
        id: id ?? this.id,
        enqueuedAt: enqueuedAt ?? this.enqueuedAt,
        jsonData: jsonData ?? this.jsonData,
      );
  SyncConflictsTableData copyWithCompanion(SyncConflictsTableCompanion data) {
    return SyncConflictsTableData(
      id: data.id.present ? data.id.value : this.id,
      enqueuedAt:
          data.enqueuedAt.present ? data.enqueuedAt.value : this.enqueuedAt,
      jsonData: data.jsonData.present ? data.jsonData.value : this.jsonData,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncConflictsTableData(')
          ..write('id: $id, ')
          ..write('enqueuedAt: $enqueuedAt, ')
          ..write('jsonData: $jsonData')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, enqueuedAt, jsonData);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncConflictsTableData &&
          other.id == this.id &&
          other.enqueuedAt == this.enqueuedAt &&
          other.jsonData == this.jsonData);
}

class SyncConflictsTableCompanion
    extends UpdateCompanion<SyncConflictsTableData> {
  final Value<String> id;
  final Value<int> enqueuedAt;
  final Value<String> jsonData;
  final Value<int> rowid;
  const SyncConflictsTableCompanion({
    this.id = const Value.absent(),
    this.enqueuedAt = const Value.absent(),
    this.jsonData = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncConflictsTableCompanion.insert({
    required String id,
    required int enqueuedAt,
    required String jsonData,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        enqueuedAt = Value(enqueuedAt),
        jsonData = Value(jsonData);
  static Insertable<SyncConflictsTableData> custom({
    Expression<String>? id,
    Expression<int>? enqueuedAt,
    Expression<String>? jsonData,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (enqueuedAt != null) 'enqueued_at': enqueuedAt,
      if (jsonData != null) 'json_data': jsonData,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncConflictsTableCompanion copyWith(
      {Value<String>? id,
      Value<int>? enqueuedAt,
      Value<String>? jsonData,
      Value<int>? rowid}) {
    return SyncConflictsTableCompanion(
      id: id ?? this.id,
      enqueuedAt: enqueuedAt ?? this.enqueuedAt,
      jsonData: jsonData ?? this.jsonData,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (enqueuedAt.present) {
      map['enqueued_at'] = Variable<int>(enqueuedAt.value);
    }
    if (jsonData.present) {
      map['json_data'] = Variable<String>(jsonData.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncConflictsTableCompanion(')
          ..write('id: $id, ')
          ..write('enqueuedAt: $enqueuedAt, ')
          ..write('jsonData: $jsonData, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $AuthProfilesTableTable authProfilesTable =
      $AuthProfilesTableTable(this);
  late final $TripLogsTableTable tripLogsTable = $TripLogsTableTable(this);
  late final $SyncOutboxTableTable syncOutboxTable =
      $SyncOutboxTableTable(this);
  late final $PointsOfInterestTableTable pointsOfInterestTable =
      $PointsOfInterestTableTable(this);
  late final $SyncConflictsTableTable syncConflictsTable =
      $SyncConflictsTableTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        authProfilesTable,
        tripLogsTable,
        syncOutboxTable,
        pointsOfInterestTable,
        syncConflictsTable
      ];
}

typedef $$AuthProfilesTableTableCreateCompanionBuilder
    = AuthProfilesTableCompanion Function({
  required String uid,
  required String jsonData,
  Value<int> rowid,
});
typedef $$AuthProfilesTableTableUpdateCompanionBuilder
    = AuthProfilesTableCompanion Function({
  Value<String> uid,
  Value<String> jsonData,
  Value<int> rowid,
});

class $$AuthProfilesTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AuthProfilesTableTable,
    AuthProfilesTableData,
    $$AuthProfilesTableTableFilterComposer,
    $$AuthProfilesTableTableOrderingComposer,
    $$AuthProfilesTableTableCreateCompanionBuilder,
    $$AuthProfilesTableTableUpdateCompanionBuilder> {
  $$AuthProfilesTableTableTableManager(
      _$AppDatabase db, $AuthProfilesTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$AuthProfilesTableTableFilterComposer(ComposerState(db, table)),
          orderingComposer: $$AuthProfilesTableTableOrderingComposer(
              ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> uid = const Value.absent(),
            Value<String> jsonData = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AuthProfilesTableCompanion(
            uid: uid,
            jsonData: jsonData,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String uid,
            required String jsonData,
            Value<int> rowid = const Value.absent(),
          }) =>
              AuthProfilesTableCompanion.insert(
            uid: uid,
            jsonData: jsonData,
            rowid: rowid,
          ),
        ));
}

class $$AuthProfilesTableTableFilterComposer
    extends FilterComposer<_$AppDatabase, $AuthProfilesTableTable> {
  $$AuthProfilesTableTableFilterComposer(super.$state);
  ColumnFilters<String> get uid => $state.composableBuilder(
      column: $state.table.uid,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get jsonData => $state.composableBuilder(
      column: $state.table.jsonData,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));
}

class $$AuthProfilesTableTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $AuthProfilesTableTable> {
  $$AuthProfilesTableTableOrderingComposer(super.$state);
  ColumnOrderings<String> get uid => $state.composableBuilder(
      column: $state.table.uid,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get jsonData => $state.composableBuilder(
      column: $state.table.jsonData,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));
}

typedef $$TripLogsTableTableCreateCompanionBuilder = TripLogsTableCompanion
    Function({
  required String tripId,
  required String locationPinId,
  Value<int> isDraft,
  required String jsonData,
  Value<int> rowid,
});
typedef $$TripLogsTableTableUpdateCompanionBuilder = TripLogsTableCompanion
    Function({
  Value<String> tripId,
  Value<String> locationPinId,
  Value<int> isDraft,
  Value<String> jsonData,
  Value<int> rowid,
});

class $$TripLogsTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TripLogsTableTable,
    TripLogsTableData,
    $$TripLogsTableTableFilterComposer,
    $$TripLogsTableTableOrderingComposer,
    $$TripLogsTableTableCreateCompanionBuilder,
    $$TripLogsTableTableUpdateCompanionBuilder> {
  $$TripLogsTableTableTableManager(_$AppDatabase db, $TripLogsTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$TripLogsTableTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$TripLogsTableTableOrderingComposer(ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> tripId = const Value.absent(),
            Value<String> locationPinId = const Value.absent(),
            Value<int> isDraft = const Value.absent(),
            Value<String> jsonData = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TripLogsTableCompanion(
            tripId: tripId,
            locationPinId: locationPinId,
            isDraft: isDraft,
            jsonData: jsonData,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String tripId,
            required String locationPinId,
            Value<int> isDraft = const Value.absent(),
            required String jsonData,
            Value<int> rowid = const Value.absent(),
          }) =>
              TripLogsTableCompanion.insert(
            tripId: tripId,
            locationPinId: locationPinId,
            isDraft: isDraft,
            jsonData: jsonData,
            rowid: rowid,
          ),
        ));
}

class $$TripLogsTableTableFilterComposer
    extends FilterComposer<_$AppDatabase, $TripLogsTableTable> {
  $$TripLogsTableTableFilterComposer(super.$state);
  ColumnFilters<String> get tripId => $state.composableBuilder(
      column: $state.table.tripId,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get locationPinId => $state.composableBuilder(
      column: $state.table.locationPinId,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get isDraft => $state.composableBuilder(
      column: $state.table.isDraft,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get jsonData => $state.composableBuilder(
      column: $state.table.jsonData,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));
}

class $$TripLogsTableTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $TripLogsTableTable> {
  $$TripLogsTableTableOrderingComposer(super.$state);
  ColumnOrderings<String> get tripId => $state.composableBuilder(
      column: $state.table.tripId,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get locationPinId => $state.composableBuilder(
      column: $state.table.locationPinId,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get isDraft => $state.composableBuilder(
      column: $state.table.isDraft,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get jsonData => $state.composableBuilder(
      column: $state.table.jsonData,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));
}

typedef $$SyncOutboxTableTableCreateCompanionBuilder = SyncOutboxTableCompanion
    Function({
  required String id,
  required int enqueuedAt,
  Value<String> status,
  required String jsonData,
  Value<int> rowid,
});
typedef $$SyncOutboxTableTableUpdateCompanionBuilder = SyncOutboxTableCompanion
    Function({
  Value<String> id,
  Value<int> enqueuedAt,
  Value<String> status,
  Value<String> jsonData,
  Value<int> rowid,
});

class $$SyncOutboxTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SyncOutboxTableTable,
    SyncOutboxTableData,
    $$SyncOutboxTableTableFilterComposer,
    $$SyncOutboxTableTableOrderingComposer,
    $$SyncOutboxTableTableCreateCompanionBuilder,
    $$SyncOutboxTableTableUpdateCompanionBuilder> {
  $$SyncOutboxTableTableTableManager(
      _$AppDatabase db, $SyncOutboxTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$SyncOutboxTableTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$SyncOutboxTableTableOrderingComposer(ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<int> enqueuedAt = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String> jsonData = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncOutboxTableCompanion(
            id: id,
            enqueuedAt: enqueuedAt,
            status: status,
            jsonData: jsonData,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required int enqueuedAt,
            Value<String> status = const Value.absent(),
            required String jsonData,
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncOutboxTableCompanion.insert(
            id: id,
            enqueuedAt: enqueuedAt,
            status: status,
            jsonData: jsonData,
            rowid: rowid,
          ),
        ));
}

class $$SyncOutboxTableTableFilterComposer
    extends FilterComposer<_$AppDatabase, $SyncOutboxTableTable> {
  $$SyncOutboxTableTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get enqueuedAt => $state.composableBuilder(
      column: $state.table.enqueuedAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get status => $state.composableBuilder(
      column: $state.table.status,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get jsonData => $state.composableBuilder(
      column: $state.table.jsonData,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));
}

class $$SyncOutboxTableTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $SyncOutboxTableTable> {
  $$SyncOutboxTableTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get enqueuedAt => $state.composableBuilder(
      column: $state.table.enqueuedAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get status => $state.composableBuilder(
      column: $state.table.status,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get jsonData => $state.composableBuilder(
      column: $state.table.jsonData,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));
}

typedef $$PointsOfInterestTableTableCreateCompanionBuilder
    = PointsOfInterestTableCompanion Function({
  required String id,
  required String districtId,
  required String title,
  required String category,
  required double latitude,
  required double longitude,
  Value<String?> description,
  Value<String?> jsonData,
  Value<int> rowid,
});
typedef $$PointsOfInterestTableTableUpdateCompanionBuilder
    = PointsOfInterestTableCompanion Function({
  Value<String> id,
  Value<String> districtId,
  Value<String> title,
  Value<String> category,
  Value<double> latitude,
  Value<double> longitude,
  Value<String?> description,
  Value<String?> jsonData,
  Value<int> rowid,
});

class $$PointsOfInterestTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PointsOfInterestTableTable,
    PointsOfInterestTableData,
    $$PointsOfInterestTableTableFilterComposer,
    $$PointsOfInterestTableTableOrderingComposer,
    $$PointsOfInterestTableTableCreateCompanionBuilder,
    $$PointsOfInterestTableTableUpdateCompanionBuilder> {
  $$PointsOfInterestTableTableTableManager(
      _$AppDatabase db, $PointsOfInterestTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer: $$PointsOfInterestTableTableFilterComposer(
              ComposerState(db, table)),
          orderingComposer: $$PointsOfInterestTableTableOrderingComposer(
              ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> districtId = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> category = const Value.absent(),
            Value<double> latitude = const Value.absent(),
            Value<double> longitude = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<String?> jsonData = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PointsOfInterestTableCompanion(
            id: id,
            districtId: districtId,
            title: title,
            category: category,
            latitude: latitude,
            longitude: longitude,
            description: description,
            jsonData: jsonData,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String districtId,
            required String title,
            required String category,
            required double latitude,
            required double longitude,
            Value<String?> description = const Value.absent(),
            Value<String?> jsonData = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PointsOfInterestTableCompanion.insert(
            id: id,
            districtId: districtId,
            title: title,
            category: category,
            latitude: latitude,
            longitude: longitude,
            description: description,
            jsonData: jsonData,
            rowid: rowid,
          ),
        ));
}

class $$PointsOfInterestTableTableFilterComposer
    extends FilterComposer<_$AppDatabase, $PointsOfInterestTableTable> {
  $$PointsOfInterestTableTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get districtId => $state.composableBuilder(
      column: $state.table.districtId,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get title => $state.composableBuilder(
      column: $state.table.title,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get category => $state.composableBuilder(
      column: $state.table.category,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<double> get latitude => $state.composableBuilder(
      column: $state.table.latitude,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<double> get longitude => $state.composableBuilder(
      column: $state.table.longitude,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get description => $state.composableBuilder(
      column: $state.table.description,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get jsonData => $state.composableBuilder(
      column: $state.table.jsonData,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));
}

class $$PointsOfInterestTableTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $PointsOfInterestTableTable> {
  $$PointsOfInterestTableTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get districtId => $state.composableBuilder(
      column: $state.table.districtId,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get title => $state.composableBuilder(
      column: $state.table.title,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get category => $state.composableBuilder(
      column: $state.table.category,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<double> get latitude => $state.composableBuilder(
      column: $state.table.latitude,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<double> get longitude => $state.composableBuilder(
      column: $state.table.longitude,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get description => $state.composableBuilder(
      column: $state.table.description,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get jsonData => $state.composableBuilder(
      column: $state.table.jsonData,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));
}

typedef $$SyncConflictsTableTableCreateCompanionBuilder
    = SyncConflictsTableCompanion Function({
  required String id,
  required int enqueuedAt,
  required String jsonData,
  Value<int> rowid,
});
typedef $$SyncConflictsTableTableUpdateCompanionBuilder
    = SyncConflictsTableCompanion Function({
  Value<String> id,
  Value<int> enqueuedAt,
  Value<String> jsonData,
  Value<int> rowid,
});

class $$SyncConflictsTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SyncConflictsTableTable,
    SyncConflictsTableData,
    $$SyncConflictsTableTableFilterComposer,
    $$SyncConflictsTableTableOrderingComposer,
    $$SyncConflictsTableTableCreateCompanionBuilder,
    $$SyncConflictsTableTableUpdateCompanionBuilder> {
  $$SyncConflictsTableTableTableManager(
      _$AppDatabase db, $SyncConflictsTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$SyncConflictsTableTableFilterComposer(ComposerState(db, table)),
          orderingComposer: $$SyncConflictsTableTableOrderingComposer(
              ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<int> enqueuedAt = const Value.absent(),
            Value<String> jsonData = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncConflictsTableCompanion(
            id: id,
            enqueuedAt: enqueuedAt,
            jsonData: jsonData,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required int enqueuedAt,
            required String jsonData,
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncConflictsTableCompanion.insert(
            id: id,
            enqueuedAt: enqueuedAt,
            jsonData: jsonData,
            rowid: rowid,
          ),
        ));
}

class $$SyncConflictsTableTableFilterComposer
    extends FilterComposer<_$AppDatabase, $SyncConflictsTableTable> {
  $$SyncConflictsTableTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get enqueuedAt => $state.composableBuilder(
      column: $state.table.enqueuedAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get jsonData => $state.composableBuilder(
      column: $state.table.jsonData,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));
}

class $$SyncConflictsTableTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $SyncConflictsTableTable> {
  $$SyncConflictsTableTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get enqueuedAt => $state.composableBuilder(
      column: $state.table.enqueuedAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get jsonData => $state.composableBuilder(
      column: $state.table.jsonData,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));
}

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$AuthProfilesTableTableTableManager get authProfilesTable =>
      $$AuthProfilesTableTableTableManager(_db, _db.authProfilesTable);
  $$TripLogsTableTableTableManager get tripLogsTable =>
      $$TripLogsTableTableTableManager(_db, _db.tripLogsTable);
  $$SyncOutboxTableTableTableManager get syncOutboxTable =>
      $$SyncOutboxTableTableTableManager(_db, _db.syncOutboxTable);
  $$PointsOfInterestTableTableTableManager get pointsOfInterestTable =>
      $$PointsOfInterestTableTableTableManager(_db, _db.pointsOfInterestTable);
  $$SyncConflictsTableTableTableManager get syncConflictsTable =>
      $$SyncConflictsTableTableTableManager(_db, _db.syncConflictsTable);
}
