import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:bhromon/features/tour_group/domain/services/map_cache_manager.dart';
import 'package:bhromon/features/tour_group/domain/services/offline_map_regions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('bhromon_map_cache_test');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('MapCacheManager Tests', () {
    late MapCacheManager manager;

    setUp(() {
      manager = MapCacheManager.instance;
    });

    test('initializes with default sajek_valley region', () async {
      final ids = await manager.init();
      expect(ids.contains('sajek_valley'), isTrue);
      expect(manager.isDownloaded('sajek_valley'), isTrue);
    });

    test('downloads a region pack and updates reactive notifier', () async {
      final tanguar =
          kCuratedOfflineRegions.firstWhere((r) => r.id == 'tanguar_haor');

      double lastProgress = 0.0;
      final success = await manager.downloadRegion(
        tanguar,
        onProgress: (p) => lastProgress = p,
      );

      expect(success, isTrue);
      expect(lastProgress, equals(1.0));
      expect(manager.isDownloaded('tanguar_haor'), isTrue);
      expect(manager.downloadedRegionIdsNotifier.value.contains('tanguar_haor'),
          isTrue);
    });

    test('removes a region pack and updates reactive notifier', () async {
      final tanguar =
          kCuratedOfflineRegions.firstWhere((r) => r.id == 'tanguar_haor');

      await manager.removeRegion(tanguar.id);

      expect(manager.isDownloaded('tanguar_haor'), isFalse);
      expect(manager.downloadedRegionIdsNotifier.value.contains('tanguar_haor'),
          isFalse);
    });

    test('exposes default style URL pointing to open vector tiles', () {
      expect(MapCacheManager.defaultStyleUrl,
          contains('https://tiles.openfreemap.org/styles/liberty'));
    });
  });
}
