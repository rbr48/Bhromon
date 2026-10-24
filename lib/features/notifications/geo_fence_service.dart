import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:workmanager/workmanager.dart';
import 'package:bhromon/core/security/hive_encryption_service.dart';
import 'package:bhromon/features/map/data/datasources/nearby_pins_query.dart';
import 'package:bhromon/features/map/presentation/widgets/pin_detail_sheet.dart';
import 'package:bhromon/core/entities/location_pin.dart';
import 'package:bhromon/core/theme/colors.dart';

/// Background task name for geo-fence checking
const String kGeoFenceTask = 'bhromon_geofence_check';

/// Register geo-fence background work with workmanager
Future<void> registerGeoFenceWork() async {
  await Workmanager().registerPeriodicTask(
    kGeoFenceTask,
    kGeoFenceTask,
    frequency: const Duration(minutes: 30),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingWorkPolicy.replace,
  );
}

/// Pins within this distance raise a geo-fence trigger.
const double kGeoFenceRadiusMeters = 5000;

/// The same pin triggers at most once per this period on a device.
const Duration kGeoFenceRepeatAfter = Duration(hours: 24);

/// A candidate pin for the geo-fence check.
class GeoFenceCandidate {
  final String pinId;
  final String name;
  final double lat;
  final double lng;
  final bool hidden;

  const GeoFenceCandidate({
    required this.pinId,
    required this.name,
    required this.lat,
    required this.lng,
    this.hidden = false,
  });
}

/// The nearest visible candidate within [radiusMeters] of ([lat], [lng]) that
/// hasn't triggered since [now] - [kGeoFenceRepeatAfter], with its distance.
({GeoFenceCandidate pin, double meters})? nearestUntriggeredPin({
  required double lat,
  required double lng,
  required Iterable<GeoFenceCandidate> candidates,
  required Map<String, DateTime> lastTriggered,
  required DateTime now,
  double radiusMeters = kGeoFenceRadiusMeters,
  double Function(double, double, double, double) distance =
      Geolocator.distanceBetween,
}) {
  ({GeoFenceCandidate pin, double meters})? best;
  for (final pin in candidates) {
    if (pin.hidden) continue;
    final last = lastTriggered[pin.pinId];
    if (last != null && now.difference(last) < kGeoFenceRepeatAfter) continue;
    final meters = distance(lat, lng, pin.lat, pin.lng);
    if (meters >= radiusMeters) continue;
    if (best == null || meters < best.meters) best = (pin: pin, meters: meters);
  }
  return best;
}

Future<void> _checkGeoFences() async {
  try {
    final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium);

    // Geohash ranges around the device instead of the first N pins anywhere.
    final docs = await queryPinsNear(FirebaseFirestore.instance, pos.latitude,
        pos.longitude, kGeoFenceRadiusMeters);

    final candidates = <GeoFenceCandidate>[];
    for (final doc in docs) {
      final data = doc.data();
      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      candidates.add(GeoFenceCandidate(
        pinId: doc.id,
        name: (data['name'] ?? 'Unknown').toString(),
        lat: lat,
        lng: lng,
        hidden: data['hidden'] == true,
      ));
    }

    final box = await _openTriggerHistory();
    final lastTriggered = <String, DateTime>{
      if (box != null)
        for (final key in box.keys)
          if (box.get(key) is int)
            key.toString():
                DateTime.fromMillisecondsSinceEpoch(box.get(key) as int),
    };

    final now = DateTime.now();
    final hit = nearestUntriggeredPin(
      lat: pos.latitude,
      lng: pos.longitude,
      candidates: candidates,
      lastTriggered: lastTriggered,
      now: now,
    );
    if (hit == null) return;

    // The notification itself is sent by a Cloud Function.
    await FirebaseFirestore.instance.collection('geo_fence_triggers').add({
      'pinId': hit.pin.pinId,
      'pinName': hit.pin.name,
      'distanceM': hit.meters.toInt(),
      'triggeredAt': FieldValue.serverTimestamp(),
    });
    await box?.put(hit.pin.pinId, now.millisecondsSinceEpoch);
  } catch (_) {}
}

/// Pin id -> last trigger time (epoch ms) on this device.
Future<Box<dynamic>?> _openTriggerHistory() async {
  try {
    await Hive.initFlutter();
    return await HiveEncryptionService()
        .openEncryptedBox<dynamic>('geofence_triggers');
  } catch (_) {
    return null;
  }
}

/// Public entry point called by [SyncWorker.callbackDispatcher] when the
/// Workmanager task name matches [kGeoFenceTask].
Future<void> checkGeoFencesBackground() => _checkGeoFences();

/// In-app geo-fence notification banner
class GeoFenceNotificationBanner extends StatefulWidget {
  final String pinName;
  final String district;
  final LocationPin pin;
  final Position? currentPosition;

  const GeoFenceNotificationBanner({
    super.key,
    required this.pinName,
    required this.district,
    required this.pin,
    this.currentPosition,
  });

  @override
  State<GeoFenceNotificationBanner> createState() =>
      _GeoFenceNotificationBannerState();
}

class _GeoFenceNotificationBannerState extends State<GeoFenceNotificationBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _slide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slide,
      child: GestureDetector(
        onTap: () {
          PinDetailSheet.show(context, widget.pin,
              currentPosition: widget.currentPosition);
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1B4332), Color(0xFF2D6A4F)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: AppColors.mintGreen.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.mintGreen.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.location_on,
                    color: AppColors.mintGreen, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '📍 You\'re near ${widget.pinName}!',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                    ),
                    Text(
                      'Tap to explore  •  ${widget.district}',
                      style:
                          const TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: AppColors.mintGreen, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
