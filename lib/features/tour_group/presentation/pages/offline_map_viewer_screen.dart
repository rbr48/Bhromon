import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../widgets/group_back_button.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/services/map_cache_manager.dart';
import '../../domain/services/offline_map_regions.dart';
import '../../domain/models/tour_activity_models.dart';
import '../../domain/services/route_engine.dart';

/// Fullscreen offline vector map and waypoint explorer for remote Bangladesh travel zones.
class OfflineMapViewerScreen extends StatefulWidget {
  final OfflineMapRegion region;
  final Position? initialPosition;
  final List<RouteCheckpoint> checkpoints;
  final RoutePlan? routePlan;

  const OfflineMapViewerScreen({
    super.key,
    required this.region,
    this.initialPosition,
    this.checkpoints = const [],
    this.routePlan,
  });

  @override
  State<OfflineMapViewerScreen> createState() => _OfflineMapViewerScreenState();
}

class _OfflineMapViewerScreenState extends State<OfflineMapViewerScreen> {
  maplibre.MapLibreMapController? _mapController;
  Position? _currentPosition;
  OfflineWaypoint? _selectedWaypoint;
  bool _isRadarMode = false;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    _currentPosition = widget.initialPosition;
    if (_currentPosition == null) {
      unawaited(_fetchGps());
    }
  }

  Future<void> _fetchGps() async {
    setState(() => _isLocating = true);
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        final req = await Geolocator.requestPermission();
        if (req == LocationPermission.denied ||
            req == LocationPermission.deniedForever) {
          if (mounted) setState(() => _isLocating = false);
          return;
        }
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) return;
      setState(() {
        _currentPosition = pos;
        _isLocating = false;
      });

      _checkIfInsideRegion(pos);
    } catch (e, st) {
      logWarning('[MapViewer] could not read the current location', e, st);
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _checkIfInsideRegion(Position pos) {
    if (!widget.region.contains(pos.latitude, pos.longitude)) {
      final distKm = _calculateDistanceKm(
        pos.latitude,
        pos.longitude,
        widget.region.centerLat,
        widget.region.centerLng,
      );
      final isBn = context.l10n.locale.languageCode == 'bn';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isBn
                ? 'আপনি এই অঞ্চলের বাইরে আছেন (~${distKm.toStringAsFixed(1)} কিমি দূরে)'
                : 'You are outside this region (~${distKm.toStringAsFixed(1)} km away)',
          ),
          duration: const Duration(seconds: 3),
          backgroundColor: context.forest.surfaceFor(const Color(0xFF1B4332)),
        ),
      );
    }
  }

  void _onMapCreated(maplibre.MapLibreMapController controller) {
    _mapController = controller;
  }

  static final Uint8List _kTransparentPixel = Uint8List.fromList(const [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1F,
    0x15,
    0xC4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0A,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x63,
    0x00,
    0x01,
    0x00,
    0x00,
    0x05,
    0x00,
    0x01,
    0x0D,
    0x0A,
    0x2D,
    0xB4,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);

  void _onStyleLoaded() {
    _registerFallbackIcons();
    _addWaypointMarkers();
    _addCheckpointAndRouteOverlays();
  }

  void _registerFallbackIcons() {
    final controller = _mapController;
    if (controller == null) return;
    for (final icon in const ['ferry_terminal', 'swimming_pool']) {
      controller.addImage(icon, _kTransparentPixel);
    }
  }

  void _addWaypointMarkers() {
    final controller = _mapController;
    if (controller == null) return;

    for (final wp in widget.region.waypoints) {
      controller.addCircle(
        maplibre.CircleOptions(
          geometry: maplibre.LatLng(wp.lat, wp.lng),
          circleRadius: 9.0,
          circleColor: '#52B788',
          circleStrokeWidth: 2.0,
          circleStrokeColor: '#FFFFFF',
          circleBlur: 0.0,
          circleOpacity: 1.0,
          circleStrokeOpacity: 1.0,
        ),
      );
    }
  }

  void _addCheckpointAndRouteOverlays() {
    final controller = _mapController;
    if (controller == null) return;

    // 1. Draw route line between consecutive points if available
    final plan = widget.routePlan;
    if (plan != null) {
      final linePoints = <maplibre.LatLng>[];
      for (final leg in plan.legs) {
        if (leg.from.hasLocation) {
          linePoints.add(maplibre.LatLng(leg.from.lat!, leg.from.lng!));
        }
        if (leg.to.hasLocation) {
          linePoints.add(maplibre.LatLng(leg.to.lat!, leg.to.lng!));
        }
      }
      if (linePoints.length >= 2) {
        controller.addLine(
          maplibre.LineOptions(
            geometry: linePoints,
            lineColor: '#2E6F5E',
            lineWidth: 3.5,
            lineOpacity: 0.85,
          ),
        );
      }
    }

    // 2. Add checkpoint markers with sequential numbering
    for (int i = 0; i < widget.checkpoints.length; i++) {
      final cp = widget.checkpoints[i];
      if (cp.hasLocation) {
        final pos = maplibre.LatLng(cp.lat!, cp.lng!);
        controller.addCircle(
          maplibre.CircleOptions(
            geometry: pos,
            circleRadius: 10.0,
            circleColor: '#FFB703',
            circleStrokeWidth: 2.0,
            circleStrokeColor: '#142428',
            circleOpacity: 1.0,
            circleStrokeOpacity: 1.0,
          ),
        );
        controller.addSymbol(
          maplibre.SymbolOptions(
            geometry: pos,
            textField: '${i + 1}',
            textSize: 11.0,
            textColor: '#142428',
            textHaloColor: '#FFFFFF',
            textHaloWidth: 0.5,
          ),
        );
      }
    }
  }

  void _focusWaypoint(OfflineWaypoint wp) {
    setState(() => _selectedWaypoint = wp);
    final controller = _mapController;
    if (controller != null && !_isRadarMode) {
      controller.animateCamera(
        maplibre.CameraUpdate.newLatLngZoom(
          maplibre.LatLng(wp.lat, wp.lng),
          14.5,
        ),
      );
    }
  }

  void _fitRegionBounds() {
    setState(() => _selectedWaypoint = null);
    final controller = _mapController;
    if (controller != null && !_isRadarMode) {
      controller.animateCamera(
        maplibre.CameraUpdate.newLatLngBounds(
          maplibre.LatLngBounds(
            southwest:
                maplibre.LatLng(widget.region.minLat, widget.region.minLng),
            northeast:
                maplibre.LatLng(widget.region.maxLat, widget.region.maxLng),
          ),
          top: 40,
          bottom: 120,
          left: 40,
          right: 40,
        ),
      );
    }
  }

  void _recenterOnUser() {
    final pos = _currentPosition;
    if (pos == null) {
      unawaited(_fetchGps());
      return;
    }

    final controller = _mapController;
    if (controller != null && !_isRadarMode) {
      controller.animateCamera(
        maplibre.CameraUpdate.newLatLngZoom(
          maplibre.LatLng(pos.latitude, pos.longitude),
          14.0,
        ),
      );
    }
  }

  Future<void> _openExternalDirections(OfflineWaypoint wp) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${wp.lat},${wp.lng}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showEmergencySheet() {
    final isBn = context.l10n.locale.languageCode == 'bn';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: context.forest.surfaceFor(const Color(0xFF14241F)),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: context.forest.text24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                const Icon(Icons.phone_in_talk_rounded,
                    color: AppColors.mintGreen, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isBn
                        ? 'জরুরি হেল্পলাইন নম্বর (${widget.region.nameBn})'
                        : 'Emergency Helplines (${widget.region.nameEn})',
                    style: TextStyle(
                      color: context.forest.text,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final contact in widget.region.contacts)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: AppColors.mintGreen.withValues(alpha: 0.2),
                  child: const Icon(Icons.call_rounded,
                      color: AppColors.mintGreen, size: 20),
                ),
                title: Text(
                  isBn ? contact.titleBn : contact.titleEn,
                  style: TextStyle(
                      color: context.forest.text, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  contact.phone,
                  style: TextStyle(color: context.forest.text70),
                ),
                trailing: FilledButton.tonal(
                  onPressed: () => launchUrl(Uri.parse('tel:${contact.phone}')),
                  child: Text(isBn ? 'কল করুন' : 'Call'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  double _calculateDistanceKm(
      double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295; // Math.PI / 180
    final a = 0.5 -
        math.cos((lat2 - lat1) * p) / 2 +
        math.cos(lat1 * p) *
            math.cos(lat2 * p) *
            (1 - math.cos((lon2 - lon1) * p)) /
            2;
    return 12742 * math.asin(math.sqrt(a)); // 2 * R; R = 6371 km
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isBn = l10n.locale.languageCode == 'bn';
    final regionTitle = isBn ? widget.region.nameBn : widget.region.nameEn;

    return GroupPopScope(
      tourId: '',
      child: Scaffold(
        backgroundColor: context.forest.surfaceFor(const Color(0xFF0D1A12)),
        appBar: AppBar(
          leading: const GroupBackButton(tourId: ''),
          backgroundColor: context.forest.surfaceFor(const Color(0xFF14241F)),
          foregroundColor: context.forest.text,
          elevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                regionTitle,
                style: TextStyle(
                    color: context.forest.text,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
              Text(
                '${widget.region.division} · ~${widget.region.estimatedMb} MB · ${isBn ? "অফলাইন ম্যাপ" : "Offline Map"}',
                style: TextStyle(fontSize: 11, color: context.forest.text54),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: isBn ? 'জরুরি হেল্পলাইন' : 'Emergency Contacts',
              icon: const Icon(Icons.phone_in_talk_rounded,
                  color: AppColors.mintGreen),
              onPressed: _showEmergencySheet,
            ),
            IconButton(
              tooltip: _isRadarMode
                  ? (isBn ? 'ম্যাপ ভিউ' : 'Map View')
                  : (isBn ? 'রাডার ভিউ' : 'Radar View'),
              icon: Icon(
                _isRadarMode ? Icons.map_rounded : Icons.radar_rounded,
                color: AppColors.mintGreen,
              ),
              onPressed: () => setState(() => _isRadarMode = !_isRadarMode),
            ),
            IconButton(
              tooltip: isBn ? 'সম্পূর্ণ অঞ্চল' : 'Fit Region',
              icon: const Icon(Icons.crop_free_rounded),
              onPressed: _fitRegionBounds,
            ),
          ],
        ),
        body: Stack(
          children: [
            // 1. Map Canvas or Waypoint Radar
            Positioned.fill(
              child: _isRadarMode
                  ? _buildRadarView()
                  : _buildMapWithRadarFallback(),
            ),

            // 2. Offline Status Banner / Chip
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: context.forest
                      .surfaceFor(const Color(0xFF14241F))
                      .withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.mintGreen.withValues(alpha: 0.4),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.offline_pin_rounded,
                        color: AppColors.mintGreen, size: 14),
                    const SizedBox(width: 5),
                    Text(
                      isBn ? 'অফলাইন প্যাক সক্রিয়' : 'Offline Pack Active',
                      style: TextStyle(
                        color: context.forest.text,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 3. Floating GPS Locator Button
            Positioned(
              right: 14,
              bottom: _selectedWaypoint != null ? 220 : 120,
              child: FloatingActionButton.small(
                heroTag: 'offline_map_gps_fab',
                backgroundColor:
                    context.forest.surfaceFor(const Color(0xFF1E3326)),
                foregroundColor:
                    _isLocating ? Colors.orangeAccent : AppColors.mintGreen,
                onPressed: _recenterOnUser,
                tooltip: isBn ? 'আমার অবস্থান' : 'My Location',
                child: _isLocating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.mintGreen,
                        ),
                      )
                    : const Icon(Icons.my_location_rounded),
              ),
            ),

            // 4. Horizontal Waypoints Carousel (bottom docked)
            Positioned(
              left: 0,
              right: 0,
              bottom: _selectedWaypoint != null ? 140 : 16,
              child: SizedBox(
                height: 44,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.region.waypoints.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final wp = widget.region.waypoints[index];
                    final isSelected = _selectedWaypoint == wp;
                    return ActionChip(
                      avatar: Text(wp.categoryEmoji,
                          style: const TextStyle(fontSize: 13)),
                      label: Text(
                        isBn ? wp.nameBn : wp.nameEn,
                        style: TextStyle(
                          fontSize: 12,
                          color: isSelected
                              ? AppColors.darkGreen
                              : context.forest.text,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                      backgroundColor: isSelected
                          ? AppColors.mintGreen
                          : context.forest
                              .surfaceFor(const Color(0xFF14241F))
                              .withValues(alpha: 0.9),
                      side: BorderSide(
                        color: isSelected
                            ? AppColors.mintGreen
                            : context.forest.text24,
                      ),
                      onPressed: () => _focusWaypoint(wp),
                    );
                  },
                ),
              ),
            ),

            // 5. Selected Waypoint Details Card
            if (_selectedWaypoint != null)
              Positioned(
                left: 14,
                right: 14,
                bottom: 16,
                child: _buildWaypointCard(_selectedWaypoint!, isBn),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapWithRadarFallback() {
    try {
      return maplibre.MapLibreMap(
        initialCameraPosition: maplibre.CameraPosition(
          target:
              maplibre.LatLng(widget.region.centerLat, widget.region.centerLng),
          zoom: 12.0,
        ),
        styleString: MapCacheManager.defaultStyleUrl,
        minMaxZoomPreference: maplibre.MinMaxZoomPreference(
          widget.region.minZoom.toDouble(),
          widget.region.maxZoom.toDouble(),
        ),
        cameraTargetBounds: maplibre.CameraTargetBounds(
          maplibre.LatLngBounds(
            southwest:
                maplibre.LatLng(widget.region.minLat, widget.region.minLng),
            northeast:
                maplibre.LatLng(widget.region.maxLat, widget.region.maxLng),
          ),
        ),
        onMapCreated: _onMapCreated,
        onStyleLoadedCallback: _onStyleLoaded,
        myLocationEnabled: false,
        trackCameraPosition: true,
      );
    } catch (_) {
      // In headless test or unsupported WebGL environments, fall back to Vector Waypoint Radar
      return _buildRadarView();
    }
  }

  Widget _buildRadarView() {
    return Container(
      color: context.forest.surfaceFor(const Color(0xFF0D1A12)),
      child: CustomPaint(
        painter: _OfflineWaypointPainter(
          region: widget.region,
          userPosition: _currentPosition,
          selectedWaypoint: _selectedWaypoint,
          palette: context.forest,
        ),
        child: GestureDetector(
          onTapUp: (details) {
            // Find closest waypoint on canvas
            final size = context.size ?? const Size(400, 600);
            for (final wp in widget.region.waypoints) {
              final normX = (wp.lng - widget.region.minLng) /
                  (widget.region.maxLng - widget.region.minLng);
              final normY = 1.0 -
                  ((wp.lat - widget.region.minLat) /
                      (widget.region.maxLat - widget.region.minLat));
              final pt = Offset(
                normX * (size.width - 80) + 40,
                normY * (size.height - 180) + 60,
              );
              if ((details.localPosition - pt).distance < 28) {
                _focusWaypoint(wp);
                return;
              }
            }
          },
        ),
      ),
    );
  }

  Widget _buildWaypointCard(OfflineWaypoint wp, bool isBn) {
    double? distKm;
    final pos = _currentPosition;
    if (pos != null) {
      distKm =
          _calculateDistanceKm(pos.latitude, pos.longitude, wp.lat, wp.lng);
    }

    return Container(
      decoration: BoxDecoration(
        color: context.forest
            .surfaceFor(const Color(0xFF14241F))
            .withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.mintGreen.withValues(alpha: 0.5)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(wp.categoryEmoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isBn ? wp.nameBn : wp.nameEn,
                      style: TextStyle(
                        color: context.forest.text,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      wp.categoryName(isBn),
                      style: const TextStyle(
                        color: AppColors.mintGreen,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                color: context.forest.text70,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => setState(() => _selectedWaypoint = null),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: context.forest.text24.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${wp.lat.toStringAsFixed(4)}° N, ${wp.lng.toStringAsFixed(4)}° E',
                  style: TextStyle(
                    color: context.forest.text70,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (distKm != null)
                Text(
                  isBn
                      ? '${distKm.toStringAsFixed(1)} কিমি দূরে'
                      : '${distKm.toStringAsFixed(1)} km away',
                  style: TextStyle(
                    color: context.forest.accentText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: () => _openExternalDirections(wp),
                icon: const Icon(Icons.directions_rounded, size: 16),
                label: Text(
                  isBn ? 'ডিরেকশন' : 'Directions',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Canvas painter that renders a vector coordinate grid, radar concentric circles,
/// and waypoint pins when MapLibre vector tiles are loading or in battery-saving radar mode.
class _OfflineWaypointPainter extends CustomPainter {
  final OfflineMapRegion region;
  final Position? userPosition;
  final OfflineWaypoint? selectedWaypoint;
  final ForestPalette palette;

  _OfflineWaypointPainter({
    required this.region,
    required this.userPosition,
    required this.selectedWaypoint,
    required this.palette,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = palette.text24.withValues(alpha: 0.12)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final radarPaint = Paint()
      ..color = AppColors.mintGreen.withValues(alpha: 0.15)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2 - 20);

    // 1. Draw Radar Range Rings
    for (final radius in [60.0, 120.0, 180.0]) {
      canvas.drawCircle(center, radius, radarPaint);
    }

    // 2. Draw Crosshairs & Coordinate Grid
    canvas.drawLine(
        Offset(center.dx, 40), Offset(center.dx, size.height - 100), gridPaint);
    canvas.drawLine(
        Offset(20, center.dy), Offset(size.width - 20, center.dy), gridPaint);

    // Cardinal directions
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    void drawLabel(String text, Offset pos) {
      textPainter.text = TextSpan(
        text: text,
        style: TextStyle(
          color: palette.text54,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(
          canvas, pos - Offset(textPainter.width / 2, textPainter.height / 2));
    }

    drawLabel('N', Offset(center.dx, 28));
    drawLabel('S', Offset(center.dx, size.height - 85));
    drawLabel('W', Offset(12, center.dy));
    drawLabel('E', Offset(size.width - 12, center.dy));

    // 3. Render Waypoints
    for (final wp in region.waypoints) {
      final normX = (wp.lng - region.minLng) / (region.maxLng - region.minLng);
      final normY =
          1.0 - ((wp.lat - region.minLat) / (region.maxLat - region.minLat));
      final pt = Offset(
        normX * (size.width - 80) + 40,
        normY * (size.height - 180) + 60,
      );

      final isSelected = selectedWaypoint == wp;

      // Pin halo
      final pinPaint = Paint()
        ..color = isSelected ? AppColors.mintGreen : const Color(0xFF2D6A4F)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(pt, isSelected ? 12.0 : 8.0, pinPaint);
      canvas.drawCircle(
        pt,
        isSelected ? 12.0 : 8.0,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke,
      );

      // Label below pin
      textPainter.text = TextSpan(
        text: '${wp.categoryEmoji} ${wp.nameBn}',
        style: TextStyle(
          color: isSelected ? AppColors.mintGreen : palette.text,
          fontSize: isSelected ? 11 : 9.5,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        ),
      );
      textPainter.layout();
      textPainter.paint(
          canvas, Offset(pt.dx - textPainter.width / 2, pt.dy + 12));
    }

    // 4. Render User Location if available
    final user = userPosition;
    if (user != null && region.contains(user.latitude, user.longitude)) {
      final normX =
          (user.longitude - region.minLng) / (region.maxLng - region.minLng);
      final normY = 1.0 -
          ((user.latitude - region.minLat) / (region.maxLat - region.minLat));
      final userPt = Offset(
        normX * (size.width - 80) + 40,
        normY * (size.height - 180) + 60,
      );

      canvas.drawCircle(
        userPt,
        14.0,
        Paint()
          ..color = Colors.blueAccent.withValues(alpha: 0.25)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        userPt,
        7.0,
        Paint()
          ..color = Colors.blueAccent
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        userPt,
        7.0,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OfflineWaypointPainter oldDelegate) {
    return oldDelegate.region != region ||
        oldDelegate.userPosition != userPosition ||
        oldDelegate.selectedWaypoint != selectedWaypoint;
  }
}
