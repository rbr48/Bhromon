import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:bhromon/app/di/injection.dart';
import 'package:bhromon/core/network/secure_network_client.dart';
import 'package:path_provider/path_provider.dart';

class MapProgress {
  final String districtId;
  final double progress;
  MapProgress(this.districtId, this.progress);
}

class TileDownloader {
  static const String _tileUrlPattern = 'https://basemaps.cartocdn.com/vectortiles/voyager-gl/v1/{z}/{x}/{y}.mvt';

  static final _progressController = StreamController<MapProgress>.broadcast();
  static Stream<MapProgress> get progressStream => _progressController.stream;

  static final Set<String> _canceledDownloads = {};

  /// Aborts an active download for a specific district.
  static void cancelDownload(String districtId) {
    _canceledDownloads.add(districtId);
  }

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

  /// Translates longitude to Slippy Map tile X coordinate.
  static int _lng2tilex(double lng, int zoom) {
    return ((lng + 180.0) / 360.0 * pow(2.0, zoom)).floor();
  }

  /// Translates latitude to Slippy Map tile Y coordinate.
  static int _lat2tiley(double lat, int zoom) {
    return ((1.0 - log(tan(lat * pi / 180.0) + 1.0 / cos(lat * pi / 180.0)) / pi) / 2.0 * pow(2.0, zoom)).floor();
  }

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

  /// Downloads map tiles for the selected [districtId] and returns the local style file URI.
  static Future<String?> downloadMapTiles(
    String districtId, {
    void Function(double)? onProgress,
  }) async {
    final secureClient = getIt<SecureNetworkClient>();
    _canceledDownloads.remove(districtId);

    try {
      final bounds = districtBounds[districtId] ?? districtBounds['default']!;
      final minLat = bounds['minLat']!;
      final minLng = bounds['minLng']!;
      final maxLat = bounds['maxLat']!;
      final maxLng = bounds['maxLng']!;

      final appDir = await getApplicationDocumentsDirectory();
      final mapsDir = Directory('${appDir.path}/offline_maps/$districtId');
      if (!mapsDir.existsSync()) {
        mapsDir.createSync(recursive: true);
      }

      // Download zoom levels 10, 11, and 12 for high fidelity offline details
      final zooms = [10, 11, 12];
      final List<Map<String, int>> tilesToDownload = [];

      for (final z in zooms) {
        final xMin = _lng2tilex(minLng, z);
        final xMax = _lng2tilex(maxLng, z);
        final yMin = _lat2tiley(maxLat, z); // Y goes north-to-south
        final yMax = _lat2tiley(minLat, z);

        for (int x = xMin; x <= xMax; x++) {
          for (int y = yMin; y <= yMax; y++) {
            tilesToDownload.add({'z': z, 'x': x, 'y': y});
          }
        }
      }

      final totalTiles = tilesToDownload.length;
      if (totalTiles == 0) return null;

      debugPrint('[TileDownloader] Queued $totalTiles tiles for $districtId');
      int downloadedCount = 0;

      // Download in chunks of 5 parallel requests
      const chunkSize = 5;
      for (int i = 0; i < tilesToDownload.length; i += chunkSize) {
        if (_canceledDownloads.contains(districtId)) {
          debugPrint('[TileDownloader] Download canceled for $districtId');
          _canceledDownloads.remove(districtId);
          return null;
        }

        final chunk = tilesToDownload.sublist(
          i,
          i + chunkSize > tilesToDownload.length ? tilesToDownload.length : i + chunkSize,
        );

        await Future.wait(chunk.map((tile) async {
          final z = tile['z']!;
          final x = tile['x']!;
          final y = tile['y']!;

          final tileUrl = _tileUrlPattern
              .replaceAll('{z}', z.toString())
              .replaceAll('{x}', x.toString())
              .replaceAll('{y}', y.toString());

          final tileFile = File('${mapsDir.path}/$z/$x/$y.mvt');

          // Download only if file doesn't exist or is empty (corrupted)
          if (!tileFile.existsSync() || tileFile.lengthSync() == 0) {
            try {
              final res = await secureClient.dio.get<List<int>>(
                tileUrl,
                options: Options(
                  responseType: ResponseType.bytes,
                  sendTimeout: const Duration(seconds: 5),
                  receiveTimeout: const Duration(seconds: 5),
                ),
              );
              if (res.statusCode == 200 && res.data != null) {
                if (!tileFile.parent.existsSync()) {
                  tileFile.parent.createSync(recursive: true);
                }
                await tileFile.writeAsBytes(res.data!);
              }
            } catch (e) {
              debugPrint('[TileDownloader] Error downloading tile $z/$x/$y: $e');
              // Ensure we clean up any incomplete/corrupted file
              if (tileFile.existsSync()) {
                try {
                  tileFile.deleteSync();
                } catch (_) {}
              }
            }
          }
        }));

        downloadedCount += chunk.length;
        final progressVal = downloadedCount / totalTiles;
        _progressController.add(MapProgress(districtId, progressVal));
        if (onProgress != null) {
          onProgress(progressVal);
        }
      }

      // Write a local MapLibre-compatible style JSON pointing to the offline folder path
      final styleFile = File('${mapsDir.path}/style.json');
      final tilesPathPattern = 'file://${mapsDir.path}/{z}/{x}/{y}.mvt';

      final styleJson = '''
      {
        "version": 8,
        "sources": {
          "offline-vector-tiles": {
            "type": "vector",
            "tiles": [
              "$tilesPathPattern"
            ],
            "minzoom": 10,
            "maxzoom": 14
          }
        },
        "layers": [
          {
            "id": "background",
            "type": "background",
            "paint": {
              "background-color": "#eef3f7"
            }
          },
          {
            "id": "landuse",
            "type": "fill",
            "source": "offline-vector-tiles",
            "source-layer": "landuse",
            "paint": {
              "fill-color": "#e2ebd5"
            }
          },
          {
            "id": "water",
            "type": "fill",
            "source": "offline-vector-tiles",
            "source-layer": "water",
            "paint": {
              "fill-color": "#c4dbf6"
            }
          },
          {
            "id": "roads",
            "type": "line",
            "source": "offline-vector-tiles",
            "source-layer": "roads",
            "paint": {
              "line-color": "#ffffff",
              "line-width": 1.5
            }
          },
          {
            "id": "buildings",
            "type": "fill",
            "source": "offline-vector-tiles",
            "source-layer": "buildings",
            "paint": {
              "fill-color": "#d9d0c9",
              "fill-opacity": 0.8
            }
          }
        ]
      }
      ''';

      await styleFile.writeAsString(styleJson);
      debugPrint('[TileDownloader] Saved style.json to ${styleFile.path}');
      return styleFile.path;
    } catch (e) {
      debugPrint('[TileDownloader] Failed to download tiles for $districtId: $e');
      return null;
    }
  }

  /// Checks if offline map tiles exist for the [districtId] and returns the style path.
  static Future<String?> getOfflineStylePath(String districtId) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final styleFile = File('${appDir.path}/offline_maps/$districtId/style.json');
      if (styleFile.existsSync() && styleFile.lengthSync() > 0) {
        return styleFile.path;
      }
    } catch (_) {}
    return null;
  }
}
