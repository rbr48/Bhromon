import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../../../core/services/offline_map_service.dart';
import '../../../../core/services/routing_service.dart';
import '../../../../core/utils/app_logger.dart';
import '../widgets/sos_hub_dialog.dart';
import '../widgets/pin_detail_sheet.dart';
import '../../../../core/theme/colors.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../../../../core/entities/location_pin.dart';
import '../utils/map_math.dart';
import '../bloc/map_bloc.dart';
import '../bloc/map_event.dart';
import '../bloc/map_state.dart';
import '../../../../core/value_objects/trust_tier.dart';
import '../../../../core/utils/logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Map style presets
// ─────────────────────────────────────────────────────────────────────────────
enum _MapStyle { light, dark, satellite }

extension _MapStyleExt on _MapStyle {
  String get url {
    switch (this) {
      case _MapStyle.light:
        return 'https://tiles.basemaps.cartocdn.com/gl/voyager-gl-style/style.json';
      case _MapStyle.dark:
        return 'https://tiles.basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json';
      case _MapStyle.satellite:
        // Inline raster style — keyless Esri World Imagery (the previous
        // MapTiler URL used the docs demo key and never loaded).
        return '''
{
  "version": 8,
  "name": "Satellite",
  "sources": {
    "esri-imagery": {
      "type": "raster",
      "tiles": ["https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"],
      "tileSize": 256,
      "maxzoom": 18,
      "attribution": "Esri, Maxar, Earthstar Geographics"
    }
  },
  "layers": [{"id": "esri-imagery", "type": "raster", "source": "esri-imagery"}]
}''';
    }
  }

  IconData get icon {
    switch (this) {
      case _MapStyle.light:
        return Icons.light_mode_outlined;
      case _MapStyle.dark:
        return Icons.dark_mode_outlined;
      case _MapStyle.satellite:
        return Icons.satellite_alt_outlined;
    }
  }

  _MapStyle get next {
    const values = _MapStyle.values;
    return values[(index + 1) % values.length];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MapScreen
// ─────────────────────────────────────────────────────────────────────────────

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MapLibreMapController? _mapController;
  Position? _currentPosition;
  bool _loadingLocation = true;
  List<LocationPin> _pins = [];
  _MapStyle _currentStyle = _MapStyle.light;
  String _mapStyleUrl = _MapStyle.light.url;
  final TextEditingController _searchController = TextEditingController();
  List<LocationPin> _searchSuggestions = [];
  bool _routePlanningMode = false;
  final List<LocationPin> _routePins = [];
  final Map<String, List<LocationPin>> _clusterIdToPins = {};
  final List<String> _suggestedOfflineDistricts = [];
  String _activeFilter = 'All';
  List<String> _downloadedOfflineDistricts = [];
  bool _loadingRoute = false;
  bool _justTappedCircle = false;
  // Only the compass needs the bearing; a notifier rebuilds just that icon
  // instead of the whole screen on every camera frame during rotation.
  final ValueNotifier<double> _mapBearing = ValueNotifier<double>(0.0);
  Timer? _searchDebounce;
  bool _isOffline = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // Skip redundant circle re-renders on camera idle
  double? _lastCirclesZoom;
  int? _lastCirclesHash;

  MapTrackingMode _currentTrackingMode = MapTrackingMode.moving;
  StreamSubscription<Position>? _positionStreamSubscription;
  final ValueNotifier<Position?> _positionNotifier =
      ValueNotifier<Position?>(null);

  // For resolving proximity tap correctly when multiple circles overlap
  final Map<String, LocationPin> _circleIdToPin = {};

  @override
  void initState() {
    super.initState();
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    _currentStyle =
        brightness == Brightness.dark ? _MapStyle.dark : _MapStyle.light;
    _mapStyleUrl = _currentStyle.url;
    _determinePosition();
    _watchConnectivity();
    _loadOfflineDistricts();
  }

  @override
  void dispose() {
    _mapController?.removeListener(_onMapCameraChanged);
    _positionStreamSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _searchController.dispose();
    _positionNotifier.dispose();
    _mapBearing.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onMapCameraChanged() {
    if (_mapController != null && mounted) {
      final bearing = _mapController!.cameraPosition?.bearing;
      if (bearing != null) _mapBearing.value = bearing;
    }
  }

  // ── Position & Style Setup ─────────────────────────────────────────────────

  void _initPositionStream() {
    try {
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3,
        ),
      ).listen((pos) {
        if (mounted) {
          _currentPosition = pos;
          _positionNotifier.value = pos;
          _adaptLocationTrackingSettings(pos);
        }
      });
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
    }
  }

  void _adaptLocationTrackingSettings(Position pos) {
    final newMode = nextTrackingMode(_currentTrackingMode, pos.speed);

    if (newMode != _currentTrackingMode) {
      _currentTrackingMode = newMode;
      _positionStreamSubscription?.cancel();

      LocationSettings settings;
      if (newMode == MapTrackingMode.stationary) {
        settings = const LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: 20,
        );
      } else if (newMode == MapTrackingMode.moving) {
        settings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3,
        );
      } else {
        settings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 15,
        );
      }

      try {
        _positionStreamSubscription = Geolocator.getPositionStream(
          locationSettings: settings,
        ).listen((newPos) {
          if (mounted) {
            _currentPosition = newPos;
            _positionNotifier.value = newPos;
            _adaptLocationTrackingSettings(newPos);
          }
        });
      } catch (error, stackTrace) {
        logSkipped(error, stackTrace);
      }
    }
  }

  Future<void> _loadOfflineDistricts() async {
    final downloaded = await OfflineMapService.listDownloadedDistricts();
    if (mounted) setState(() => _downloadedOfflineDistricts = downloaded);
    _drawOfflineShadedZones();
  }

  /// Offline rendering is transparent: MapLibre serves downloaded regions
  /// from its own cache using the normal style URL. This only tracks
  /// connectivity so the UI can show an offline banner instead of a blank map.
  Future<void> _watchConnectivity() async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      _applyConnectivity(connectivity);
      _connectivitySubscription =
          Connectivity().onConnectivityChanged.listen(_applyConnectivity);
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
    }
  }

  void _applyConnectivity(List<ConnectivityResult> results) {
    final offline =
        results.isNotEmpty && results.first == ConnectivityResult.none;
    if (offline != _isOffline && mounted) {
      setState(() => _isOffline = offline);
    }
  }

  Future<void> _determinePosition() async {
    setState(() => _loadingLocation = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _useDefaultLocation();
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _useDefaultLocation();
        return;
      }

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Please enable location services (GPS) for maps navigation.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
      }

      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 7));
      if (mounted) {
        setState(() {
          _currentPosition = pos;
          _loadingLocation = false;
        });
        _positionNotifier.value = pos;
        _checkAndSuggestOfflineDownload(pos);
        _mapController?.animateCamera(CameraUpdate.newCameraPosition(
          CameraPosition(
              target: LatLng(pos.latitude, pos.longitude), zoom: 11.0),
        ));
        context
            .read<MapBloc>()
            .add(LoadPinsEvent(lat: pos.latitude, lng: pos.longitude));

        // Initialize location tracking stream now that we have permission
        _initPositionStream();
      }
    } catch (_) {
      _useDefaultLocation();
    }
  }

  void _useDefaultLocation() {
    if (!mounted) return;
    setState(() {
      _currentPosition = Position(
        latitude: 23.6850,
        longitude: 90.3563,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
      _loadingLocation = false;
    });
    _positionNotifier.value = _currentPosition;
    context
        .read<MapBloc>()
        .add(const LoadPinsEvent(lat: 23.6850, lng: 90.3563));
  }

  // ── Map Helpers ────────────────────────────────────────────────────────────

  // Recomputed only when the pins or the filter change, not per access.
  List<LocationPin>? _filteredCache;
  List<LocationPin>? _filteredCacheSource;
  String? _filteredCacheFilter;

  List<LocationPin> get _filteredPins {
    if (_filteredCache != null &&
        identical(_filteredCacheSource, _pins) &&
        _filteredCacheFilter == _activeFilter) {
      return _filteredCache!;
    }
    _filteredCacheSource = _pins;
    _filteredCacheFilter = _activeFilter;
    return _filteredCache = _computeFilteredPins();
  }

  List<LocationPin> _computeFilteredPins() {
    switch (_activeFilter) {
      case 'Verified Safety':
        return _pins.where((p) => p.trustTier.isVerifiedOrAbove).toList();
      case 'Verified Business':
        return _pins
            .where((p) =>
                p.businessProfileId != null && p.businessProfileId!.isNotEmpty)
            .toList();
      case 'Active Hubs':
        return _pins.where((p) => p.linkedTripIds.isNotEmpty).toList();
      default:
        return _pins;
    }
  }

  Future<void> _drawOfflineShadedZones() async {
    if (_mapController == null) return;
    try {
      await _mapController!.clearFills();
      final List<FillOptions> optionsList = [];
      for (final district in _downloadedOfflineDistricts) {
        final bounds = OfflineMapService.districtBounds[district];
        if (bounds == null) continue;
        optionsList.add(FillOptions(
          geometry: [
            [
              LatLng(bounds['minLat']!, bounds['minLng']!),
              LatLng(bounds['maxLat']!, bounds['minLng']!),
              LatLng(bounds['maxLat']!, bounds['maxLng']!),
              LatLng(bounds['minLat']!, bounds['maxLng']!),
              LatLng(bounds['minLat']!, bounds['minLng']!),
            ]
          ],
          fillColor: '#52B788',
          fillOpacity: 0.12,
          fillOutlineColor: '#52B788',
        ));
      }
      if (optionsList.isNotEmpty) {
        await _mapController!.addFills(optionsList);
      }
    } catch (e) {
      logError('Error drawing offline fills: $e');
    }
  }

  /// The visible map area plus a margin, or null if it can't be read.
  Future<GeoBounds?> _paddedVisibleBounds() async {
    try {
      final region = await _mapController!.getVisibleRegion();
      return GeoBounds(
        south: region.southwest.latitude,
        west: region.southwest.longitude,
        north: region.northeast.latitude,
        east: region.northeast.longitude,
      ).expandedBy(0.5);
    } catch (_) {
      return null;
    }
  }

  static String _tierHex(LocationPin pin) {
    final Color color = AppColors.forTier(pin.trustTier);
    return '#${color.toARGB32().toRadixString(16).substring(2).padLeft(6, '0')}';
  }

  // Redraws are async (visible region, clear, add); camera idles can fire
  // while one is running, so they're serialised and only the latest request
  // runs after it.
  bool _circlesUpdating = false;
  ({List<LocationPin> pins, bool force})? _pendingCircles;

  /// Re-draw map circles for the given pin list using smarter clustering.
  Future<void> _updateMapCircles(List<LocationPin> pins,
      {bool force = false}) async {
    if (_circlesUpdating) {
      _pendingCircles = (
        pins: pins,
        force: force || (_pendingCircles?.force ?? false),
      );
      return;
    }
    _circlesUpdating = true;
    try {
      await _redrawMapCircles(pins, force: force);
    } finally {
      _circlesUpdating = false;
    }
    final next = _pendingCircles;
    _pendingCircles = null;
    if (next != null && mounted) {
      await _updateMapCircles(next.pins, force: next.force);
    }
  }

  Future<void> _redrawMapCircles(List<LocationPin> pins,
      {bool force = false}) async {
    if (_mapController == null) return;
    try {
      final double zoom = _mapController!.cameraPosition?.zoom ?? 7.0;
      final bool highZoom = zoom > 10.0;

      // Zoomed in, only pins near the viewport are sent to the native map;
      // zoomed out, clustering already keeps the marker count down.
      final drawn =
          highZoom ? pinsInBounds(pins, await _paddedVisibleBounds()) : pins;
      if (_mapController == null) return;

      // Camera idle fires constantly while panning; skip the full
      // clear-and-redraw when neither the drawn pins nor the zoom regime
      // changed. The padded bounds mean small pans keep the same set.
      final int pinsHash = Object.hashAll(drawn.map((p) => p.pinId));
      final bool sameZoomRegime = _lastCirclesZoom != null &&
          ((zoom > 10.0 && _lastCirclesZoom! > 10.0) ||
              (zoom <= 10.0 &&
                  _lastCirclesZoom! <= 10.0 &&
                  (zoom - _lastCirclesZoom!).abs() < 0.3));
      if (!force && pinsHash == _lastCirclesHash && sameZoomRegime) return;
      _lastCirclesZoom = zoom;
      _lastCirclesHash = pinsHash;

      await _mapController!.clearCircles();
      _circleIdToPin.clear();
      _clusterIdToPins.clear();

      if (highZoom) {
        final optionsList = [
          for (final pin in drawn)
            CircleOptions(
              geometry: LatLng(pin.lat, pin.lng),
              circleColor: _tierHex(pin),
              circleRadius: 11.0,
              circleStrokeColor: '#ffffff',
              circleStrokeWidth: 2.0,
              circleOpacity: 0.95,
            ),
        ];
        if (optionsList.isEmpty) return;
        final circles = await _mapController!.addCircles(optionsList);
        for (int i = 0; i < circles.length; i++) {
          _circleIdToPin[circles[i].id] = drawn[i];
        }
        return;
      }

      final clusters = clusterPins(drawn, zoom);
      final List<CircleOptions> optionsList = [];
      for (final cluster in clusters) {
        if (cluster.pins.length == 1) {
          final pin = cluster.pins.first;
          optionsList.add(CircleOptions(
            geometry: LatLng(pin.lat, pin.lng),
            circleColor: _tierHex(pin),
            circleRadius: 11.0,
            circleStrokeColor: '#ffffff',
            circleStrokeWidth: 2.0,
            circleOpacity: 0.95,
          ));
        } else {
          final count = cluster.pins.length;
          optionsList.add(CircleOptions(
            geometry: LatLng(cluster.lat, cluster.lng),
            circleColor: '#FF9F1C',
            circleRadius: 14.0 + (count > 9 ? 4.0 : count.toDouble()),
            circleStrokeColor: '#ffffff',
            circleStrokeWidth: 2.0,
            circleOpacity: 0.92,
          ));
        }
      }

      if (optionsList.isNotEmpty) {
        final circles = await _mapController!.addCircles(optionsList);
        for (int i = 0; i < circles.length; i++) {
          final cluster = clusters[i];
          if (cluster.pins.length == 1) {
            _circleIdToPin[circles[i].id] = cluster.pins.first;
          } else {
            _clusterIdToPins[circles[i].id] = cluster.pins;
          }
        }
      }
    } catch (e) {
      logError('Error updating circles: $e');
    }
  }

  void _onCircleTapped(Circle circle) {
    _justTappedCircle = true;

    // Check if we have a direct pin mapping
    final pin = _circleIdToPin[circle.id];
    if (pin != null) {
      if (_routePlanningMode) {
        setState(() {
          if (_routePins.contains(pin)) {
            _routePins.remove(pin);
          } else {
            _routePins.add(pin);
          }
        });
        _updateRouteLines();
      } else {
        _openPinDetail(pin);
      }
      return;
    }

    // It's a cluster circle — show list of pins in the cluster
    final clusterPins = _clusterIdToPins[circle.id];
    if (clusterPins != null && clusterPins.isNotEmpty) {
      _showClusterPinsList(clusterPins);
    } else {
      _mapController?.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(
          target: circle.options.geometry!,
          zoom: (_mapController!.cameraPosition?.zoom ?? 7.0) + 2.5,
        ),
      ));
    }
  }

  void _openPinDetail(LocationPin pin) {
    if (!mounted) return;
    // First fly to pin
    _mapController?.animateCamera(CameraUpdate.newCameraPosition(
      CameraPosition(
        target: LatLng(pin.lat, pin.lng),
        zoom: (_mapController!.cameraPosition?.zoom ?? 12).clamp(12.0, 16.0),
      ),
    ));

    // Then show detail sheet
    PinDetailSheet.show(context, pin, currentPosition: _currentPosition);
  }

  /// Proximity fallback when map base is tapped (not a circle)
  LocationPin? _findProximityPin(LatLng latlng) {
    if (_pins.isEmpty) return null;
    final double zoom = _mapController?.cameraPosition?.zoom ?? 7.0;
    // Tighter threshold at higher zoom
    final double threshold = 0.01 / (zoom > 12 ? 2 : 1);
    LocationPin? closest;
    double minDist = double.infinity;
    for (final p in _filteredPins) {
      final latD = (p.lat - latlng.latitude).abs();
      final lngD = (p.lng - latlng.longitude).abs();
      if (latD < threshold && lngD < threshold) {
        final d = latD * latD + lngD * lngD;
        if (d < minDist) {
          minDist = d;
          closest = p;
        }
      }
    }
    return closest;
  }

  Future<void> _updateRouteLines() async {
    if (_mapController == null) return;
    try {
      await _mapController!.clearLines();
      if (_routePins.length < 2) return;
      setState(() => _loadingRoute = true);

      final points = _routePins.map((p) => LatLng(p.lat, p.lng)).toList();
      final road = await RoutingService.getRoute(points);
      final geometry = road.isNotEmpty ? road : points;

      await _mapController!.addLine(LineOptions(
        geometry: geometry,
        lineColor: '#52B788',
        lineWidth: 4.5,
        lineOpacity: 0.85,
      ));
    } catch (e) {
      logError('Route error: $e');
    } finally {
      if (mounted) setState(() => _loadingRoute = false);
    }
  }

  String _headingLabel(double h) {
    if (h >= 337.5 || h < 22.5) return 'N';
    if (h < 67.5) return 'NE';
    if (h < 112.5) return 'E';
    if (h < 157.5) return 'SE';
    if (h < 202.5) return 'S';
    if (h < 247.5) return 'SW';
    if (h < 292.5) return 'W';
    return 'NW';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthCubit>().state;
    final explorerName = authState is Authenticated
        ? authState.profile.displayName
        : 'Guest Explorer';
    final explorerScore =
        authState is Authenticated ? authState.profile.explorerScore.value : 0;
    final explorerTier = authState is Authenticated
        ? authState.profile.tier
        : TrustTier.unverified;

    return PopScope(
      canPop: context.canPop(),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go('/group-hub');
      },
      child: Scaffold(
        body: BlocListener<MapBloc, MapState>(
          listener: (ctx, state) {
            if (state is MapPinsLoaded) {
              setState(() => _pins = state.pins);
              _updateMapCircles(_filteredPins);
            }
          },
          child: Stack(
            children: [
              // ── 1. MapLibre Map ─────────────────────────────────────────
              _loadingLocation
                  ? const Center(
                      child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.mintGreen)))
                  : RepaintBoundary(
                      child: MapLibreMap(
                        key: ValueKey(_mapStyleUrl),
                        initialCameraPosition: CameraPosition(
                          target: LatLng(
                            _currentPosition?.latitude ?? 23.6850,
                            _currentPosition?.longitude ?? 90.3563,
                          ),
                          zoom: 8.0,
                        ),
                        styleString: _mapStyleUrl,
                        myLocationEnabled: true,
                        myLocationTrackingMode: MyLocationTrackingMode.tracking,
                        trackCameraPosition: true,
                        onMapCreated: (controller) {
                          _mapController = controller;
                          // New platform view (e.g. after style switch): the
                          // previous circles are gone, so reset the guard.
                          _lastCirclesHash = null;
                          _lastCirclesZoom = null;
                          _mapController!.onCircleTapped.add(_onCircleTapped);
                          _mapController!.addListener(_onMapCameraChanged);
                          if (_currentPosition != null) {
                            _mapController!.animateCamera(
                              CameraUpdate.newCameraPosition(CameraPosition(
                                target: LatLng(_currentPosition!.latitude,
                                    _currentPosition!.longitude),
                                zoom: 11.0,
                              )),
                            );
                          }
                        },
                        onStyleLoadedCallback: () {
                          _updateMapCircles(_filteredPins, force: true);
                          _drawOfflineShadedZones();
                        },
                        onCameraIdle: () {
                          // Re-cluster circles when camera stops moving
                          _updateMapCircles(_filteredPins);
                        },
                        onMapClick: (point, latlng) {
                          if (_justTappedCircle) {
                            _justTappedCircle = false;
                            return;
                          }
                          final proximityPin = _findProximityPin(latlng);
                          if (proximityPin != null) {
                            _openPinDetail(proximityPin);
                          }
                        },
                        onMapLongClick: (point, latlng) {
                          _showAddPinDialog(latlng);
                        },
                      ),
                    ),

              // ── 1b. Offline banner ──────────────────────────────────────
              if (_isOffline)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 78,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.mintGreen.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.cloud_off_rounded,
                            color: AppColors.mintGreen, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _downloadedOfflineDistricts.isNotEmpty
                                ? 'Offline mode — showing downloaded maps (${_downloadedOfflineDistricts.join(', ')})'
                                : 'You are offline. Download maps from the Offline Vault to explore without internet.',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          ),
                        ),
                        if (_downloadedOfflineDistricts.isEmpty)
                          TextButton(
                            onPressed: () => context.push('/vault'),
                            child: const Text('VAULT',
                                style: TextStyle(
                                    color: AppColors.mintGreen,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                  ),
                ),

              // ── 2. Top Explorer Hub Bar ─────────────────────────────────
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 16,
                right: 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                        width: 1.5,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 11),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: AppColors.forTier(explorerTier),
                          child: const Icon(Icons.person,
                              color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                explorerName,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15),
                              ),
                              Text(
                                '${explorerTier.displayName} • $explorerScore pts',
                                style: TextStyle(
                                    color: AppColors.mintGreen
                                        .withValues(alpha: 0.9),
                                    fontWeight: FontWeight.w500,
                                    fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        // SOS
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.redAccent.withValues(alpha: 0.4),
                              width: 1,
                            ),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.warning_amber_rounded,
                                color: Colors.redAccent),
                            iconSize: 22,
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (_) => SosHubDialog(
                                  currentPosition: _currentPosition),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── 3. Search Bar ───────────────────────────────────────────
              Positioned(
                top: MediaQuery.of(context).padding.top + 82,
                left: 16,
                right: 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(23),
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(23),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                        width: 1.5,
                      ),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) {
                        // Parse once typing pauses, not per keystroke.
                        _searchDebounce?.cancel();
                        if (val.trim().isEmpty) {
                          setState(() => _searchSuggestions = []);
                          return;
                        }
                        _searchDebounce =
                            Timer(const Duration(milliseconds: 250), () {
                          if (!mounted) return;
                          setState(
                              () => _searchSuggestions = _parseNlpQuery(val));
                        });
                      },
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search — Sajek, Cox\'s Bazar, waterfall…',
                        hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12),
                        prefixIcon: const Icon(Icons.search,
                            color: AppColors.mintGreen, size: 20),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear,
                                    color: Colors.white70, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchSuggestions = []);
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 13),
                      ),
                    ),
                  ),
                ),
              ),

              // ── 4. Filter Chips ─────────────────────────────────────────
              Positioned(
                top: MediaQuery.of(context).padding.top + 134,
                left: 0,
                right: 0,
                child: SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      'All',
                      'Verified Safety',
                      'Verified Business',
                      'Active Hubs'
                    ].map((filter) {
                      final sel = _activeFilter == filter;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _activeFilter = filter);
                            WidgetsBinding.instance.addPostFrameCallback(
                                (_) => _updateMapCircles(_filteredPins));
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: sel
                                    ? AppColors.mintGreen.withValues(alpha: 0.9)
                                    : Colors.black.withValues(alpha: 0.72),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: sel
                                      ? AppColors.mintGreen
                                      : Colors.white.withValues(alpha: 0.15),
                                  width: 1.5,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  filter,
                                  style: TextStyle(
                                    color: sel ? Colors.black87 : Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

              // ── 5. Search Suggestions Dropdown ──────────────────────────
              if (_searchSuggestions.isNotEmpty)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 80 + 52,
                  left: 16,
                  right: 16,
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 230),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 12,
                            offset: const Offset(0, 4)),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _searchSuggestions.length,
                        itemBuilder: (_, i) {
                          final pin = _searchSuggestions[i];
                          final cs = Theme.of(context).colorScheme;
                          return ListTile(
                            leading: const Icon(Icons.location_on_outlined,
                                color: AppColors.midGreen, size: 20),
                            title: Text(pin.name,
                                style: TextStyle(
                                    color: cs.onSurface,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                            subtitle: Text('${pin.district}, ${pin.division}',
                                style: TextStyle(
                                    color: cs.onSurfaceVariant, fontSize: 11)),
                            onTap: () {
                              FocusScope.of(context).unfocus();
                              _searchController.text = pin.name;
                              setState(() => _searchSuggestions = []);
                              // Fly + open detail
                              _mapController?.animateCamera(
                                  CameraUpdate.newCameraPosition(
                                CameraPosition(
                                    target: LatLng(pin.lat, pin.lng),
                                    zoom: 14.0),
                              ));
                              Future.delayed(
                                const Duration(milliseconds: 600),
                                () => _openPinDetail(pin),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),

              // ── 6. Live GPS HUD ─────────────────────────────────────────
              Positioned(
                left: 16,
                top: MediaQuery.of(context).padding.top + 182,
                child: ValueListenableBuilder<Position?>(
                  valueListenable: _positionNotifier,
                  builder: (context, pos, child) {
                    final speed = pos != null ? pos.speed * 3.6 : 0.0;
                    final altitude = pos != null ? pos.altitude : 0.0;
                    final heading = pos != null ? pos.heading : 0.0;

                    return ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 112,
                        color: Colors.black.withValues(alpha: 0.86),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _hudRow(Icons.speed,
                                '${speed.toStringAsFixed(1)} km/h'),
                            const SizedBox(height: 6),
                            _hudRow(Icons.terrain_rounded,
                                '${altitude.toStringAsFixed(0)} m'),
                            const SizedBox(height: 6),
                            _hudRow(Icons.explore_outlined,
                                '${_headingLabel(heading)} ${heading.toStringAsFixed(0)}°'),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // ── 7. Map Controls (right side) ────────────────────────────
              Positioned(
                right: 16,
                top: MediaQuery.of(context).padding.top + 182,
                child: Column(
                  children: [
                    // Compass
                    _compassFab(),
                    const SizedBox(height: 8),

                    // Recenter
                    _mapFab('recenter', Icons.my_location, AppColors.mintGreen,
                        () {
                      if (_currentPosition != null) {
                        _mapController?.animateCamera(
                            CameraUpdate.newCameraPosition(CameraPosition(
                          target: LatLng(_currentPosition!.latitude,
                              _currentPosition!.longitude),
                          zoom: 13.0,
                        )));
                      } else {
                        _determinePosition();
                      }
                    }),
                    const SizedBox(height: 8),

                    // Map style cycle (Light → Dark → Satellite)
                    _mapFab('styleToggle', _currentStyle.next.icon,
                        AppColors.mintGreen, () {
                      final next = _currentStyle.next;
                      setState(() {
                        _currentStyle = next;
                        _mapStyleUrl = next.url;
                      });
                    }),
                    const SizedBox(height: 8),

                    // Offline maps status — rendering is automatic: MapLibre
                    // serves downloaded regions from cache when offline.
                    _mapFab(
                      'offline',
                      Icons.cloud_off_rounded,
                      _downloadedOfflineDistricts.isNotEmpty
                          ? Colors.black
                          : AppColors.mintGreen,
                      () {
                        if (_downloadedOfflineDistricts.isEmpty) {
                          _showSnack(
                              'No offline maps yet. Download districts from the Offline Vault.');
                          context.push('/vault');
                        } else {
                          _showSnack(
                              'Offline maps ready: ${_downloadedOfflineDistricts.join(', ')}. '
                              'The map keeps working here without internet.');
                        }
                      },
                      bgColor: _downloadedOfflineDistricts.isNotEmpty
                          ? AppColors.mintGreen
                          : Colors.black.withValues(alpha: 0.85),
                    ),
                    const SizedBox(height: 8),

                    // Route planner
                    _mapFab(
                      'route',
                      Icons.alt_route,
                      _routePlanningMode ? Colors.black : AppColors.mintGreen,
                      () {
                        setState(() {
                          _routePlanningMode = !_routePlanningMode;
                          if (!_routePlanningMode) _routePins.clear();
                        });
                        _updateRouteLines();
                      },
                      bgColor: _routePlanningMode
                          ? AppColors.mintGreen
                          : Colors.black.withValues(alpha: 0.85),
                    ),
                  ],
                ),
              ),

              // ── 8. Quick Action FABs ────────────────────────────────────
              Positioned(
                right: 16,
                bottom: 36 + MediaQuery.of(context).padding.bottom,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _extFab(Icons.edit_note, 'Log Trip', AppColors.midGreen,
                        () => context.push('/editor')),
                    const SizedBox(height: 10),
                    _extFab(
                        Icons.explore_outlined,
                        'AR Compass',
                        const Color(0xFF8A2BE2),
                        () => context.push('/ar', extra: {
                              'nearbyPins': _filteredPins,
                              'currentPosition': _currentPosition
                            })),
                    const SizedBox(height: 10),
                    _extFab(Icons.cloud_download_outlined, 'Offline Vault',
                        AppColors.leafGreen, () => context.push('/vault')),
                    const SizedBox(height: 10),
                    _extFab(Icons.verified_user_outlined, 'Trust Hub',
                        AppColors.gold, () => context.push('/trust')),
                    const SizedBox(height: 10),
                    FloatingActionButton(
                      heroTag: 'addPin',
                      backgroundColor: AppColors.mintGreen,
                      onPressed: _showAddPinDialog,
                      child: const Icon(Icons.add_location_alt_outlined,
                          color: AppColors.darkGreen),
                    ),
                  ],
                ),
              ),

              // ── 9. Route Planner Summary ────────────────────────────────
              if (_routePlanningMode && _routePins.isNotEmpty)
                _buildRoutePlannerSummary(),

              // ── 10. Route planner hint when mode active but no pins ─────
              if (_routePlanningMode && _routePins.isEmpty)
                Positioned(
                  bottom: 100 + MediaQuery.of(context).padding.bottom,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.touch_app,
                              color: AppColors.mintGreen, size: 16),
                          SizedBox(width: 8),
                          Text('Tap pins to build your route',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Widget Builders ────────────────────────────────────────────────────────

  Widget _hudRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: AppColors.mintGreen, size: 13),
        const SizedBox(width: 6),
        Flexible(
          child: Text(text,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget _mapFab(String tag, IconData icon, Color iconColor, VoidCallback onTap,
      {Color? bgColor}) {
    return FloatingActionButton(
      mini: true,
      heroTag: tag,
      backgroundColor: bgColor ?? Colors.black.withValues(alpha: 0.85),
      onPressed: onTap,
      child: Icon(icon, color: iconColor, size: 20),
    );
  }

  Widget _compassFab() {
    return FloatingActionButton(
      mini: true,
      heroTag: 'map_compass_fab',
      backgroundColor: Colors.black.withValues(alpha: 0.85),
      onPressed: () {
        _mapController?.animateCamera(
          CameraUpdate.bearingTo(0.0),
        );
      },
      child: ValueListenableBuilder<double>(
        valueListenable: _mapBearing,
        builder: (context, bearing, icon) =>
            Transform.rotate(angle: -bearing * pi / 180, child: icon),
        child: const Icon(
          Icons.explore,
          color: AppColors.mintGreen,
          size: 22,
        ),
      ),
    );
  }

  Widget _extFab(IconData icon, String label, Color color, VoidCallback onTap) {
    return FloatingActionButton.extended(
      heroTag: label,
      onPressed: onTap,
      icon: Icon(icon, color: Colors.white, size: 18),
      label: Text(label,
          style: const TextStyle(color: Colors.white, fontSize: 12)),
      backgroundColor: color,
    );
  }

  Widget _buildRoutePlannerSummary() {
    final bp = MediaQuery.of(context).padding.bottom;
    double totalDist = 0;
    for (int i = 0; i < _routePins.length - 1; i++) {
      totalDist += Geolocator.distanceBetween(_routePins[i].lat,
              _routePins[i].lng, _routePins[i + 1].lat, _routePins[i + 1].lng) /
          1000;
    }
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + bp),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 10)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_loadingRoute)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: LinearProgressIndicator(
                    color: AppColors.mintGreen,
                    backgroundColor: Colors.white10),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('ITINERARY BUILDER',
                    style: TextStyle(
                        color: AppColors.mintGreen,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1)),
                IconButton(
                  icon:
                      const Icon(Icons.close, color: Colors.white60, size: 18),
                  onPressed: () {
                    setState(() {
                      _routePins.clear();
                      _routePlanningMode = false;
                    });
                    _updateRouteLines();
                  },
                ),
              ],
            ),
            Text(
              _routePins.map((p) => p.name).join(' ➔ '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_routePins.length} stops  •  ${totalDist.toStringAsFixed(1)} km  •  ⏱️ ~${(totalDist * 2).toStringAsFixed(0)} mins',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '🚌 Bus ~৳${(totalDist * 2.5).toStringAsFixed(0)}  '
                      '🛺 CNG ~৳${(totalDist * 6).toStringAsFixed(0)}  '
                      '🏍️ Bike ~৳${(totalDist * 4).toStringAsFixed(0)}',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 10),
                    ),
                  ],
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.mintGreen,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () {
                    _showSnack('Itinerary saved: ${_routePins.length} stops!');
                    setState(() {
                      _routePlanningMode = false;
                      _routePins.clear();
                    });
                    _updateRouteLines();
                  },
                  child: const Text('Save Itinerary',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Add Pin Dialog ─────────────────────────────────────────────────────────

  void _showAddPinDialog([LatLng? customCenter]) {
    if (_mapController == null) return;
    final center = customCenter ?? _mapController!.cameraPosition?.target;
    if (center == null) return;

    final nameCtrl = TextEditingController();
    final districtCtrl = TextEditingController();
    final divisionCtrl = TextEditingController();
    String selectedCategory = 'place';

    final categories = [
      'place',
      'waterfall',
      'beach',
      'temple',
      'mosque',
      'forest',
      'market',
      'heritage',
      'hill',
      'lake',
      'river',
      'park',
      'mountain',
    ];

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final cs = Theme.of(ctx).colorScheme;
          return AlertDialog(
            backgroundColor: cs.surface,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Add Location Pin',
                style: TextStyle(
                    color: cs.onSurface, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dialogField(nameCtrl, 'Place Name *', Icons.place),
                  const SizedBox(height: 12),
                  _dialogField(districtCtrl, 'District *', Icons.location_city),
                  const SizedBox(height: 12),
                  _dialogField(divisionCtrl, 'Division *', Icons.map_outlined),
                  const SizedBox(height: 16),
                  // Category picker
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Category',
                        style: TextStyle(
                            color: cs.onSurfaceVariant, fontSize: 12)),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: categories.map((cat) {
                      final sel = cat == selectedCategory;
                      return GestureDetector(
                        onTap: () =>
                            setDialogState(() => selectedCategory = cat),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: sel
                                ? AppColors.mintGreen
                                : cs.surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: sel
                                    ? AppColors.mintGreen
                                    : cs.outlineVariant.withValues(alpha: 0.4)),
                          ),
                          child: Text(cat,
                              style: TextStyle(
                                  color: sel
                                      ? AppColors.darkGreen
                                      : cs.onSurfaceVariant,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '📍 ${center.latitude.toStringAsFixed(5)}, ${center.longitude.toStringAsFixed(5)}',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel',
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.midGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  final district = districtCtrl.text.trim();
                  final division = divisionCtrl.text.trim();
                  if (name.isEmpty || district.isEmpty || division.isEmpty) {
                    _showSnack('Please fill in all required fields');
                    return;
                  }
                  final newPin = LocationPin(
                    pinId: 'pin_${DateTime.now().millisecondsSinceEpoch}',
                    name: name,
                    geoHash: 'w3',
                    lat: center.latitude,
                    lng: center.longitude,
                    trustTier: TrustTier.unverified,
                    lastConfirmed: DateTime.now(),
                    linkedTripIds: const [],
                    linkedTipIds: const [],
                    division: division,
                    district: district,
                    createdByUid:
                        (context.read<AuthCubit>().state is Authenticated)
                            ? (context.read<AuthCubit>().state as Authenticated)
                                .profile
                                .uid
                            : 'guest',
                    category: selectedCategory,
                  );
                  context.read<MapBloc>().add(AddPinEvent(newPin));
                  Navigator.pop(ctx);
                  _showSnack('📍 Pin "$name" added!');
                },
                child: const Text('Create',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _dialogField(TextEditingController ctrl, String hint, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: ctrl,
      style: TextStyle(color: cs.onSurface),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
        prefixIcon: Icon(icon, color: AppColors.mintGreen, size: 18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.mintGreen),
        ),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      ),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  List<LocationPin> _parseNlpQuery(String query) {
    final q = query.toLowerCase().trim();
    // Extract location keywords
    final districts = [
      'sylhet',
      'chittagong',
      'dhaka',
      'rajshahi',
      'khulna',
      'barisal',
      'mymensingh',
      'rangamati',
      'bandarban',
      'cox\'s bazar',
      'coxsbazar',
      'sunamganj'
    ];
    final categories = [
      'waterfall',
      'beach',
      'temple',
      'mosque',
      'forest',
      'market',
      'heritage',
      'hill',
      'lake',
      'river',
      'park',
      'mountain',
      'hotel',
      'restaurant'
    ];

    String? districtFilter;
    String? categoryFilter;

    for (final d in districts) {
      if (q.contains(d)) {
        districtFilter = d;
        break;
      }
    }
    for (final c in categories) {
      if (q.contains(c)) {
        categoryFilter = c;
        break;
      }
    }

    // Remove location/category words to get name query
    var nameQuery = q;
    if (districtFilter != null) {
      nameQuery = nameQuery.replaceAll(districtFilter, '');
    }
    if (categoryFilter != null) {
      nameQuery = nameQuery.replaceAll(categoryFilter, '');
    }
    // Remove common filler words
    for (final word in [
      'near',
      'in',
      'at',
      'around',
      'best',
      'cheap',
      'good'
    ]) {
      nameQuery = nameQuery.replaceAll(word, '');
    }
    nameQuery = nameQuery.trim();

    return _filteredPins
        .where((p) {
          bool matchesName =
              nameQuery.isEmpty || p.name.toLowerCase().contains(nameQuery);
          bool matchesDistrict = districtFilter == null ||
              p.district.toLowerCase().contains(districtFilter);
          bool matchesCategory = categoryFilter == null ||
              p.category.toLowerCase() == categoryFilter;
          return matchesName && matchesDistrict && matchesCategory;
        })
        .take(8)
        .toList();
  }

  void _showClusterPinsList(List<LocationPin> pins) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return Container(
          height: MediaQuery.of(context).size.height * 0.5,
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
                top: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.3),
                    width: 0.5)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(Icons.maps_home_work_outlined,
                        color: AppColors.mintGreen, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Pins in this Area (${pins.length})',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 8,
                    bottom: MediaQuery.of(context).padding.bottom + 16,
                  ),
                  itemCount: pins.length,
                  itemBuilder: (context, index) {
                    final pin = pins[index];
                    final Color tierColor = AppColors.forTier(pin.trustTier);
                    return Card(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                            color: cs.outlineVariant.withValues(alpha: 0.4),
                            width: 0.5),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 8,
                          height: 24,
                          decoration: BoxDecoration(
                            color: tierColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        title: Text(
                          pin.name,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '${pin.category} • ${pin.district}',
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 11),
                        ),
                        trailing: Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: cs.onSurfaceVariant,
                          size: 14,
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _openPinDetail(pin);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _checkAndSuggestOfflineDownload(Position pos) {
    String? currentDistrict;
    for (final entry in OfflineMapService.districtBounds.entries) {
      if (entry.key == 'default') continue;
      final bounds = entry.value;
      if (pos.latitude >= bounds['minLat']! &&
          pos.latitude <= bounds['maxLat']! &&
          pos.longitude >= bounds['minLng']! &&
          pos.longitude <= bounds['maxLng']!) {
        currentDistrict = entry.key;
        break;
      }
    }

    if (currentDistrict != null &&
        !_downloadedOfflineDistricts.contains(currentDistrict)) {
      final district = currentDistrict;
      if (_suggestedOfflineDistricts.contains(district)) return;
      _suggestedOfflineDistricts.add(district);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '📍 You are in $district. Download offline map to save data?'),
            duration: const Duration(seconds: 7),
            action: SnackBarAction(
              label: 'DOWNLOAD',
              textColor: AppColors.mintGreen,
              onPressed: () {
                context.push('/vault');
              },
            ),
          ),
        );
      });
    }
  }
}
