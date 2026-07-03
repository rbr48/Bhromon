import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';
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

/// Called by workmanager in the background — named distinctly to avoid
/// colliding with SyncWorker's callbackDispatcher in sync_worker.dart.
@pragma('vm:entry-point')
void geoFenceCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == kGeoFenceTask) {
      await _checkGeoFences();
    }
    return true;
  });
}

Future<void> _checkGeoFences() async {
  try {
    final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium);

    final snap = await FirebaseFirestore.instance
        .collection('location_pins')
        .where('hidden', isEqualTo: false)
        .limit(100)
        .get();

    for (final doc in snap.docs) {
      final data = doc.data();
      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      final dist = Geolocator.distanceBetween(
          pos.latitude, pos.longitude, lat, lng);

      if (dist < 5000) {
        // Within 5km — would normally send FCM notification via Cloud Function
        // Here we just log it; actual notification is sent by Cloud Function
        await FirebaseFirestore.instance
            .collection('geo_fence_triggers')
            .add({
          'pinId': doc.id,
          'pinName': data['name'] ?? 'Unknown',
          'distanceM': dist.toInt(),
          'triggeredAt': FieldValue.serverTimestamp(),
        });
        break; // Only one notification per check
      }
    }
  } catch (_) {}
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

class _GeoFenceNotificationBannerState
    extends State<GeoFenceNotificationBanner>
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
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 11),
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
