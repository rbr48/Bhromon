import 'dart:convert';
import 'package:flutter/services.dart';

import '../../../../core/utils/app_logger.dart';
import '../domain/models/predefined_spot.dart';

/// Repository that loads and indexes predefined Bangladesh tourist spots
/// from `assets/bd_predefined_spots.json`.
class PredefinedSpotsRepository {
  PredefinedSpotsRepository({AssetBundle? bundle}) : _bundle = bundle;

  final AssetBundle? _bundle;
  static List<PredefinedSpot>? _cachedSpots;

  static const String kAssetPath = 'assets/bd_predefined_spots.json';

  /// Loads all verified spots from the asset bundle. Results are cached in memory.
  Future<List<PredefinedSpot>> loadSpots() async {
    if (_cachedSpots != null) return _cachedSpots!;
    try {
      final bundle = _bundle ?? rootBundle;
      final raw = await bundle.loadString(kAssetPath);
      final jsonList = jsonDecode(raw) as List<dynamic>;
      _cachedSpots = jsonList
          .map((item) => PredefinedSpot.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
      return _cachedSpots!;
    } catch (e, st) {
      logWarning('PredefinedSpotsRepository: failed to load spots', e, st);
      return const [];
    }
  }

  /// Filters spots by optional query, division, and category.
  Future<List<PredefinedSpot>> filterSpots({
    String? query,
    String? division,
    String? category,
  }) async {
    final all = await loadSpots();
    final q = query?.trim().toLowerCase() ?? '';
    final div = division?.trim().toLowerCase() ?? '';
    final cat = category?.trim().toLowerCase() ?? '';

    return all.where((s) {
      if (div.isNotEmpty && div != 'all' && s.division.toLowerCase() != div) {
        return false;
      }
      if (cat.isNotEmpty && cat != 'all' && s.category.toLowerCase() != cat) {
        return false;
      }
      if (q.isNotEmpty && !s.matches(q)) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  /// Returns distinct divisions represented across verified spots.
  Future<List<String>> getDivisions() async {
    final all = await loadSpots();
    final set = <String>{};
    for (final s in all) {
      if (s.division.isNotEmpty) set.add(s.division);
    }
    final sorted = set.toList()..sort();
    return sorted;
  }

  /// Clears in-memory cache (primarily for unit tests).
  static void clearCacheForTest() {
    _cachedSpots = null;
  }
}
