import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/entities/location_pin.dart';
import '../../../../core/security/hive_encryption_service.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/value_objects/trust_tier.dart';
import '../../../../app/di/injection.dart';
import '../../domain/repositories/i_map_repository.dart';

@LazySingleton(as: IMapRepository)
class MapRepositoryImpl implements IMapRepository {
  final FirebaseFirestore _firestore;
  final AppDatabase _database;

  MapRepositoryImpl(this._firestore, this._database);

  @override
  Future<Either<Failure, List<LocationPin>>> getPinsInProximity(
    double lat,
    double lng,
    double radiusKm,
  ) async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.isNotEmpty &&
          connectivity.first == ConnectivityResult.none) {
        return _getCachedPins();
      }

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

      // Cache pins in the local Drift SQLite database
      for (final pin in pins) {
        try {
          await _database.savePointOfInterest(
            pin.pinId,
            pin.district,
            pin.name,
            pin.category,
            pin.lat,
            pin.lng,
            pin.description,
            jsonEncode(pin.toJson()),
          );
        } catch (dbError) {
          // Non-blocking log
          debugPrint(
              '[MapRepository] Failed to cache pin ${pin.pinId} in Drift: $dbError');
        }
      }

      return Right(pins);
    } catch (e) {
      return _getCachedPins();
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
          for (final pin in pins) {
            try {
              await _database.savePointOfInterest(
                pin.pinId,
                pin.district,
                pin.name,
                pin.category,
                pin.lat,
                pin.lng,
                pin.description,
                jsonEncode(pin.toJson()),
              );
            } catch (_) {}
          }
        } catch (e) {
          debugPrint('Failed to load predefined travel spots: $e');
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
      await _firestore
          .collection('location_pins')
          .doc(pin.pinId)
          .set(pin.toJson());
      return Right(pin);
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
      return const Right(unit);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
