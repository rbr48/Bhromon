import 'package:workmanager/workmanager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../app/di/injection.dart';
import '../../features/offline_vault/data/datasources/sync_manager.dart';
import '../../features/notifications/geo_fence_service.dart'
    show kGeoFenceTask, checkGeoFencesBackground;

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      if (task == kGeoFenceTask) {
        // Geo-fence check — does not need full DI stack
        await checkGeoFencesBackground();
        return true;
      }

      // Default: outbox sync
      await Hive.initFlutter();
      await Firebase.initializeApp();
      configureDependencies();

      final syncManager = getIt<SyncManager>();
      await syncManager.flushOutbox();

      return Future.value(true);
    } catch (err) {
      return Future.value(false);
    }
  });
}

class SyncWorker {
  static const String _syncTask = 'com.bhromon.app.syncTask';

  /// Unique name for the periodic background sync task.
  /// Using a versioned name prevents duplicate registrations across app updates.
  static const String _periodicSyncUniqueName = 'bhromon_periodic_sync_v1';

  /// Unique name for the one-time immediate sync task.
  static const String _oneTimeSyncUniqueName = 'bhromon_one_time_sync';

  static void initialize() {
    Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );
  }

  /// Registers a periodic outbox-flush task (~hourly).
  ///
  /// Uses [ExistingWorkPolicy.keep] so that if a task with this unique name is
  /// already enqueued it is left untouched, preventing duplicate scheduled
  /// work across multiple cold starts or FCM wakeups.
  static void registerPeriodicSync() {
    Workmanager().registerPeriodicTask(
      _periodicSyncUniqueName,
      _syncTask,
      frequency: const Duration(hours: 1),
      existingWorkPolicy: ExistingWorkPolicy.keep,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  }

  /// Schedules an immediate one-off outbox flush, e.g. on connectivity
  /// restored or after the user creates content while offline.
  ///
  /// Uses [ExistingWorkPolicy.replace] so any pending one-time sync is
  /// superseded by the freshest request, avoiding stale queue runs.
  static void registerOneTimeImmediateSync() {
    Workmanager().registerOneOffTask(
      _oneTimeSyncUniqueName,
      _syncTask,
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  }
}
