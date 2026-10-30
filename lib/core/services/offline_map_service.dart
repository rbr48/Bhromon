import 'dart:async';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../utils/app_logger.dart';

class MapProgress {
  final String districtId;
  final double progress;
  MapProgress(this.districtId, this.progress);
}

/// True offline maps built on MapLibre's native offline-region engine.
///
/// `downloadOfflineRegion` stores the style JSON, sprites, glyphs and every
/// vector tile for the region inside MapLibre's own cache database. The map
/// then renders offline with the exact same style URL used online — no
/// hand-written styles, no file:// tile hacks, no white screen.
class OfflineMapService {
  /// Styles pre-cached for offline use. Light + dark share the same
  /// carto.streets tile source, so the second pass only fetches the style,
  /// sprites and glyphs — the tiles are already in the cache.
  static const List<String> offlineStyleUrls = [
    'https://tiles.basemaps.cartocdn.com/gl/voyager-gl-style/style.json',
    'https://tiles.basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json',
  ];

  /// carto.streets vector tiles top out at z14; MapLibre overzooms beyond
  /// that natively, so z8–z14 gives full detail at every zoom level.
  static const double _minZoom = 8;
  static const double _maxZoom = 14;

  static final _progressController = StreamController<MapProgress>.broadcast();
  static Stream<MapProgress> get progressStream => _progressController.stream;

  static bool _tileLimitRaised = false;

  // Geographic bounds for popular districts/divisions in Bangladesh
  static const Map<String, Map<String, double>> districtBounds = {
    'Dhaka': {
      'minLat': 23.50,
      'minLng': 90.20,
      'maxLat': 23.95,
      'maxLng': 90.60,
    },
    'Rangamati': {
      'minLat': 22.25,
      'minLng': 92.00,
      'maxLat': 23.25,
      'maxLng': 92.50,
    },
    'Chittagong': {
      'minLat': 22.00,
      'minLng': 91.60,
      'maxLat': 22.50,
      'maxLng': 92.00,
    },
    'Sylhet': {
      'minLat': 24.50,
      'minLng': 91.60,
      'maxLat': 25.20,
      'maxLng': 92.50,
    },
    'Khulna': {
      'minLat': 22.40,
      'minLng': 89.20,
      'maxLat': 23.00,
      'maxLng': 89.80,
    },
    "Cox's Bazar": {
      'minLat': 21.00,
      'minLng': 91.80,
      'maxLat': 22.00,
      'maxLng': 92.50,
    },
    'Bandarban': {
      'minLat': 21.20,
      'minLng': 92.10,
      'maxLat': 22.30,
      'maxLng': 92.80,
    },
    'Sajek': {
      'minLat': 23.30,
      'minLng': 92.20,
      'maxLat': 23.60,
      'maxLng': 92.40,
    },
    // Fallback bounds (covering Bangladesh center generally)
    'default': {
      'minLat': 23.40,
      'minLng': 90.10,
      'maxLat': 23.90,
      'maxLng': 90.80,
    }
  };

  /// Returns the district name matching the coordinates, or null if none match.
  static String? getDistrictForPosition(double lat, double lng) {
    for (final entry in districtBounds.entries) {
      if (entry.key == 'default') continue;
      final bounds = entry.value;
      if (lat >= bounds['minLat']! &&
          lat <= bounds['maxLat']! &&
          lng >= bounds['minLng']! &&
          lng <= bounds['maxLng']!) {
        return entry.key;
      }
    }
    return null;
  }

  static LatLngBounds _boundsFor(String districtId) {
    final b = districtBounds[districtId] ?? districtBounds['default']!;
    return LatLngBounds(
      southwest: LatLng(b['minLat']!, b['minLng']!),
      northeast: LatLng(b['maxLat']!, b['maxLng']!),
    );
  }

  /// The default per-download tile limit is 6000, which large districts at
  /// z14 can exceed. Raise it once per app run.
  static Future<void> _ensureTileLimit() async {
    if (_tileLimitRaised) return;
    try {
      await setOfflineTileCountLimit(60000);
      _tileLimitRaised = true;
    } catch (e, st) {
      logWarning('[OfflineMapService] Could not raise tile count limit', e, st);
    }
  }

  /// Downloads the offline region (style + sprites + glyphs + tiles) for
  /// [districtId] in both light and dark styles. Returns true on success.
  static Future<bool> downloadRegion(
    String districtId, {
    void Function(double)? onProgress,
  }) async {
    await _ensureTileLimit();
    final bounds = _boundsFor(districtId);

    try {
      for (int i = 0; i < offlineStyleUrls.length; i++) {
        // Light style carries the tiles: weight it 90% of overall progress.
        final double base = i == 0 ? 0.0 : 0.9;
        final double span = i == 0 ? 0.9 : 0.1;
        final completer = Completer<void>();

        await downloadOfflineRegion(
          OfflineRegionDefinition(
            bounds: bounds,
            mapStyleUrl: offlineStyleUrls[i],
            minZoom: _minZoom,
            maxZoom: _maxZoom,
          ),
          metadata: <String, dynamic>{
            'district': districtId,
            'styleIndex': i,
          },
          onEvent: (status) {
            if (completer.isCompleted) return;
            if (status is Success) {
              completer.complete();
            } else if (status is Error) {
              completer.completeError(status.cause);
            } else if (status is InProgress) {
              final overall = base + (status.progress / 100.0) * span;
              _progressController.add(MapProgress(districtId, overall));
              onProgress?.call(overall);
            }
          },
        );

        await completer.future;
      }

      _progressController.add(MapProgress(districtId, 1.0));
      onProgress?.call(1.0);
      logInfo('[OfflineMapService] Offline region ready for $districtId');
      return true;
    } catch (e, st) {
      logError('[OfflineMapService] Failed to download region $districtId', e, st);
      return false;
    }
  }

  /// District names that have at least one fully downloaded offline region.
  static Future<List<String>> listDownloadedDistricts() async {
    try {
      final regions = await getListOfRegions();
      return regions
          .map((r) => r.metadata['district'])
          .whereType<String>()
          .toSet()
          .toList();
    } catch (e, st) {
      logWarning('[OfflineMapService] Could not list offline regions', e, st);
      return [];
    }
  }

  /// Whether [districtId] has a downloaded offline region.
  static Future<bool> hasRegion(String districtId) async {
    final districts = await listDownloadedDistricts();
    return districts.contains(districtId);
  }

  /// Deletes every offline region belonging to [districtId] and frees the
  /// tiles that no other region references.
  static Future<void> deleteRegion(String districtId) async {
    try {
      final regions = await getListOfRegions();
      for (final region in regions) {
        if (region.metadata['district'] == districtId) {
          await deleteOfflineRegion(region.id);
        }
      }
    } catch (e, st) {
      logWarning('[OfflineMapService] Failed to delete region $districtId', e, st);
    }
  }
}
