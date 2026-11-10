import 'package:bhromon/app/di/injection.dart';
import 'package:bhromon/core/security/hive_encryption_service.dart';
import 'package:bhromon/core/utils/app_logger.dart';
import 'package:hive/hive.dart';

import '../domain/models/study_offline_vault_models.dart';

/// Manages local offline packages of banking exam books and examiner-grade solutions.
/// Allows candidate bank officers to prepare for exams without network connectivity,
/// zero data usage during transit, and immediate response times.
class StudyOfflineVault {
  StudyOfflineVault({HiveEncryptionService? encryption})
      : _encryption = encryption;

  static final StudyOfflineVault instance = StudyOfflineVault();

  static const String boxName = 'study_offline_vault';

  final HiveEncryptionService? _encryption;

  Future<Box<dynamic>?> _box() async {
    try {
      final encryption = _encryption ??
          (getIt.isRegistered<HiveEncryptionService>()
              ? getIt<HiveEncryptionService>()
              : null);
      if (encryption != null) {
        return await encryption.openEncryptedBox<dynamic>(boxName);
      }
      if (Hive.isBoxOpen(boxName)) return Hive.box<dynamic>(boxName);
      return null;
    } catch (e, st) {
      logWarning('[StudyOfflineVault] Could not open Hive box: $e', e, st);
      return null;
    }
  }

  static String _key(String tourId, String bookId) => '${tourId}__$bookId';

  /// Whether a subject book has an active offline package stored locally.
  Future<bool> isCached(String tourId, String bookId) async {
    try {
      final box = await _box();
      if (box == null) return false;
      return box.containsKey(_key(tourId, bookId));
    } catch (_) {
      // Safe fallback when disk access fails or database is locked.
      return false;
    }
  }

  /// Retrieves an offline package for a book, or null if not cached.
  Future<StudyOfflinePackage?> getPackage(String tourId, String bookId) async {
    try {
      final box = await _box();
      if (box == null) return null;
      final raw = box.get(_key(tourId, bookId));
      if (raw is! Map) return null;
      return StudyOfflinePackage.fromJson(raw);
    } catch (error, stack) {
      logWarning('[StudyOfflineVault] Failed to read package', error, stack);
      return null;
    }
  }

  /// Saves or updates an offline package for a book.
  Future<void> savePackage(StudyOfflinePackage package) async {
    try {
      final box = await _box();
      if (box == null) return;
      await box.put(_key(package.tourId, package.bookId), package.toJson());
    } catch (error, stack) {
      logWarning('[StudyOfflineVault] Failed to save package', error, stack);
    }
  }

  /// Removes an offline package for a book.
  Future<void> removePackage(String tourId, String bookId) async {
    try {
      final box = await _box();
      if (box == null) return;
      await box.delete(_key(tourId, bookId));
    } catch (error, stack) {
      logWarning('[StudyOfflineVault] Failed to remove package', error, stack);
    }
  }

  /// Lists all offline packages cached for a particular tour group.
  Future<List<StudyOfflinePackage>> listPackages(String tourId) async {
    try {
      final box = await _box();
      if (box == null) return [];
      final packages = <StudyOfflinePackage>[];
      final prefix = '${tourId}__';
      for (final key in box.keys) {
        if (key is String && key.startsWith(prefix)) {
          final raw = box.get(key);
          if (raw is Map) {
            final pkg = StudyOfflinePackage.fromJson(raw);
            if (pkg != null) packages.add(pkg);
          }
        }
      }
      packages.sort((a, b) => b.cachedAt.compareTo(a.cachedAt));
      return packages;
    } catch (error, stack) {
      logWarning('[StudyOfflineVault] Failed to list packages', error, stack);
      return [];
    }
  }

  /// Computes the aggregate cached bytes across all offline packages in a tour.
  Future<int> totalCachedBytes(String tourId) async {
    final packages = await listPackages(tourId);
    var total = 0;
    for (final p in packages) {
      total += p.totalSizeBytes;
    }
    return total;
  }

  /// Clears all cached offline packages for a tour.
  Future<void> clearAll(String tourId) async {
    try {
      final box = await _box();
      if (box == null) return;
      final prefix = '${tourId}__';
      final keysToDelete =
          box.keys.where((k) => k is String && k.startsWith(prefix)).toList();
      for (final k in keysToDelete) {
        await box.delete(k);
      }
    } catch (error, stack) {
      logWarning('[StudyOfflineVault] Failed to clear packages', error, stack);
    }
  }
}
