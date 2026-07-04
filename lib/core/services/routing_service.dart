import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:bhromon/app/di/injection.dart';
import 'package:bhromon/core/network/secure_network_client.dart';

class RoutingService {
  /// Fetches the road route coordinates between a list of pins using OSRM.
  static Future<List<LatLng>> getRoute(List<LatLng> points) async {
    if (points.length < 2) return [];

    try {
      final coordinatesStr =
          points.map((p) => '${p.longitude},${p.latitude}').join(';');
      final url =
          'https://router.project-osrm.org/route/v1/driving/$coordinatesStr?overview=full&geometries=geojson';

      debugPrint('[RoutingService] Fetching road route: $url');
      final secureClient = getIt<SecureNetworkClient>();
      final response = await secureClient.dio
          .get<dynamic>(url)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = response.data is Map<String, dynamic>
            ? response.data
            : json.decode(response.data.toString());
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final geometry = routes[0]['geometry'] as Map<String, dynamic>?;
          if (geometry != null && geometry['coordinates'] != null) {
            final List<dynamic> coords =
                geometry['coordinates'] as List<dynamic>;
            return coords
                .map<LatLng>((c) => LatLng(c[1] as double, c[0] as double))
                .toList();
          }
        }
      }
    } catch (e) {
      debugPrint(
          '[RoutingService] Failed to fetch road route: $e. Falling back to straight-line path.');
      return points;
    }
    debugPrint(
        '[RoutingService] Route fetching returned empty. Falling back to straight-line path.');
    return points;
  }
}
