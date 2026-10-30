import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../../../core/utils/app_logger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' show Value;
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/entities/location_pin.dart';
import '../../../../core/geo/geohash.dart';
import '../../../../core/network/connectivity_check.dart';
import '../../../../core/security/hive_encryption_service.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/value_objects/trust_tier.dart';
import '../../../../app/di/injection.dart';
import '../../domain/repositories/i_map_repository.dart';

/// How long a fetched pin set is reused before the next network read.
const Duration kPinCacheTtl = Duration(minutes: 10);

@LazySingleton(as: IMapRepository)
class MapRepositoryImpl implements IMapRepository {
  final FirebaseFirestore _firestore;
  final AppDatabase _database;
  final OnlineCheck _isOnline;
  final DateTime Function() _now;

  MapRepositoryImpl(this._firestore, this._database)
      : _isOnline = deviceIsOnline,
        _now = DateTime.now;

  @visibleForTesting
  MapRepositoryImpl.withDependencies(
      this._firestore, this._database, this._isOnline, this._now);

  // The feed, the map and Discover all ask for pins as they open. One
  // network read serves them all until the cache expires or a pin changes.
  List<LocationPin>? _cachedPins;
  DateTime? _cachedAt;
  Future<Either<Failure, List<LocationPin>>>? _inFlight;

  /// Drops the cached pin set so the next request reads Firestore again.
  void invalidatePinCache() {
    _cachedPins = null;
    _cachedAt = null;
  }

  @override
  Future<Either<Failure, List<LocationPin>>> getPinsInProximity(
    double lat,
    double lng,
    double radiusKm,
  ) {
    // The whole pin set is returned (the map shows the entire country);
    // a radius-bounded server query needs geohashes stored on every pin.
    final cached = _cachedPins;
    final cachedAt = _cachedAt;
    if (cached != null &&
        cachedAt != null &&
        _now().difference(cachedAt) < kPinCacheTtl) {
      return Future.value(Right(cached));
    }
    return _inFlight ??= _fetchPins().whenComplete(() => _inFlight = null);
  }

  Future<Either<Failure, List<LocationPin>>> _fetchPins() async {
    try {
      if (!await _isOnline()) return await _getCachedPins();

      final snapshot = await _firestore.collection('location_pins').get();

      final pins = snapshot.docs.map((doc) {
        final data = doc.data();
        data['pinId'] = doc.id;

        // Sanitize lastConfirmed field
        if (data['lastConfirmed'] is Timestamp) {
          data['lastConfirmed'] =
              (data['lastConfirmed'] as Timestamp).toDate().toIso8601String();
        } else if (data['lastConfirmed'] == null) {
          data['lastConfirmed'] = DateTime.now().toIso8601String();
        }

        return LocationPin.fromJson(data);
      }).toList();

      await _cachePinsLocally(pins);

      _cachedPins = pins;
      _cachedAt = _now();
      return Right(pins);
    } catch (e) {
      return _getCachedPins();
    }
  }

  /// Writes [pins] to Drift in one batched transaction.
  Future<void> _cachePinsLocally(List<LocationPin> pins) async {
    try {
      await _database.savePointsOfInterest([
        for (final pin in pins)
          PointsOfInterestTableCompanion.insert(
            id: pin.pinId,
            districtId: pin.district,
            title: pin.name,
            category: pin.category,
            latitude: pin.lat,
            longitude: pin.lng,
            description: Value(pin.description),
            jsonData: Value(jsonEncode(pin.toJson())),
          ),
      ]);
    } catch (dbError, st) {
      // Non-blocking: the network result is still returned.
      logWarning('[MapRepository] Failed to cache pins in Drift', dbError, st);
    }
  }

  Future<Either<Failure, List<LocationPin>>> _getCachedPins() async {
    try {
      // First try to load from the Drift SQLite database
      final localPois = await _database.getAllPointsOfInterest();
      final pins = <LocationPin>[];

      if (localPois.isNotEmpty) {
        for (final row in localPois) {
          if (row.jsonData != null) {
            try {
              pins.add(LocationPin.fromJson(
                  jsonDecode(row.jsonData!) as Map<String, dynamic>));
            } catch (_) {
              // Row schema fallback
              pins.add(LocationPin(
                pinId: row.id,
                name: row.title,
                geoHash: '',
                lat: row.latitude,
                lng: row.longitude,
                trustTier: TrustTier.verified,
                lastConfirmed: DateTime.now(),
                linkedTripIds: [],
                linkedTipIds: [],
                division: '',
                district: row.districtId,
                createdByUid: '',
                category: row.category,
                description: row.description,
              ));
            }
          } else {
            pins.add(LocationPin(
              pinId: row.id,
              name: row.title,
              geoHash: '',
              lat: row.latitude,
              lng: row.longitude,
              trustTier: TrustTier.verified,
              lastConfirmed: DateTime.now(),
              linkedTripIds: [],
              linkedTipIds: [],
              division: '',
              district: row.districtId,
              createdByUid: '',
              category: row.category,
              description: row.description,
            ));
          }
        }
      }

      if (pins.isEmpty) {
        // Old Hive fallback
        final encryptionService = getIt<HiveEncryptionService>();
        final box = await encryptionService
            .openEncryptedBox<dynamic>('offline_bundles');
        for (final val in box.values) {
          final bundleJson = Map<String, dynamic>.from(val as Map);
          if (bundleJson['pins'] is List) {
            final pinsList = bundleJson['pins'] as List;
            for (final pinJson in pinsList) {
              pins.add(LocationPin.fromJson(
                  Map<String, dynamic>.from(pinJson as Map)));
            }
          }
        }
      }

      // If we still have no pins, load the predefined offline travel spots from assets
      if (pins.isEmpty) {
        try {
          final jsonStr =
              await rootBundle.loadString('assets/bd_predefined_spots.json');
          final List<dynamic> jsonList = jsonDecode(jsonStr) as List;
          for (final item in jsonList) {
            pins.add(LocationPin.fromJson(item as Map<String, dynamic>));
          }
          // Save them to the local SQLite database so they are cached inside Drift
          await _cachePinsLocally(pins);
        } catch (e, st) {
          logWarning('Failed to load predefined travel spots', e, st);
        }
      }

      return Right(pins);
    } catch (cacheError) {
      return Left(CacheFailure(cacheError.toString()));
    }
  }

  @override
  Future<Either<Failure, LocationPin>> addPin(LocationPin pin) async {
    try {
      // A real geohash, so the pin can be found by nearby-pin queries (the
      // map's add-pin dialog used to send a placeholder).
      final toSave = pin.copyWith(geoHash: encodeGeohash(pin.lat, pin.lng));
      await _firestore
          .collection('location_pins')
          .doc(toSave.pinId)
          .set(toSave.toJson());
      invalidatePinCache();
      return Right(toSave);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> confirmPin(String pinId) async {
    try {
      await _firestore
          .collection('location_pins')
          .doc(pinId)
          .update({'lastConfirmed': FieldValue.serverTimestamp()});
      invalidatePinCache();
      return const Right(unit);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
