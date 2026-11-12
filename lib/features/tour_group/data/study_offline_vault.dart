import 'package:bhromon/app/di/injection.dart';
import 'package:bhromon/core/security/hive_encryption_service.dart';
import 'package:bhromon/core/utils/app_logger.dart';
import 'package:hive/hive.dart';

import '../domain/models/study_offline_vault_models.dart';

/// Manages local offline packages of banking exam books and examiner-grade solutions.
/// Allows candidate bank officers to prepare for exams without network connectivity,
/// zero data usage during transit, and immediate response times.
///
/// A package is stored in two boxes. Each package, with every solution in its book, is one value
/// in [boxName]. Its summary is one small value in [indexBoxName]. Screens that only show whether a
/// book is saved, and how big it is, read the index, so opening a book never decodes its solutions.
/// The packages are read only when their contents are needed.
class StudyOfflineVault {
  StudyOfflineVault({HiveEncryptionService? encryption})
      : _encryption = encryption;

  static final StudyOfflineVault instance = StudyOfflineVault();

  static const String boxName = 'study_offline_vault';

  /// The summaries of the packages, one per package. Packages stored before this box existed are
  /// summarised the first time it is read.
  static const String indexBoxName = 'study_offline_index';

  /// Set in the index once every package in [boxName] has its summary there.
  static const String _indexedMarker = '__indexed_v1';

  final HiveEncryptionService? _encryption;

  Future<Box<dynamic>?> _openBox(String name) async {
    try {
      final encryption = _encryption ??
          (getIt.isRegistered<HiveEncryptionService>()
              ? getIt<HiveEncryptionService>()
              : null);
      if (encryption != null) {
        return await encryption.openEncryptedBox<dynamic>(name);
      }
      if (Hive.isBoxOpen(name)) return Hive.box<dynamic>(name);
      return null;
    } catch (e, st) {
      logWarning('[StudyOfflineVault] Could not open Hive box: $e', e, st);
      return null;
    }
  }

  static String _key(String tourId, String bookId) => '${tourId}__$bookId';

  /// The index, with a summary for every package stored before the index existed. Those packages
  /// are read once, the first time the index is used; after that only the index is read. Null when
  /// the index cannot be opened, and then the marker stays unset so the next use tries again.
  Future<Box<dynamic>?> _index() async {
    final index = await _openBox(indexBoxName);
    if (index == null || index.get(_indexedMarker) == true) return index;
    final packages = await _openBox(boxName);
    if (packages == null) return null;
    for (final key in packages.keys) {
      final raw = packages.get(key);
      if (key is! String || raw is! Map) continue;
      final summary = StudyOfflinePackage.summaryFromJson(raw);
      if (summary != null) await index.put(key, summary.toMap());
    }
    await index.put(_indexedMarker, true);
    return index;
  }

  /// Whether a subject book has an active offline package stored locally.
  Future<bool> isCached(String tourId, String bookId) async {
    try {
      final index = await _index();
      if (index == null) return false;
      return index.containsKey(_key(tourId, bookId));
    } catch (_) {
      // Safe fallback when disk access fails or database is locked.
      return false;
    }
  }

  /// The summary of a book's offline package, or null when it has none. Reads the index only: the
  /// solutions of the book are not decoded.
  Future<StudyOfflineSummary?> getSummary(String tourId, String bookId) async {
    try {
      final index = await _index();
      if (index == null) return null;
      final raw = index.get(_key(tourId, bookId));
      if (raw is! Map) return null;
      return StudyOfflineSummary.fromMap(raw);
    } catch (error, stack) {
      logWarning('[StudyOfflineVault] Failed to read summary', error, stack);
      return null;
    }
  }

  /// Retrieves an offline package for a book, or null if not cached. Decodes every solution the
  /// book has, so it is for when the contents are needed, not for showing the book.
  Future<StudyOfflinePackage?> getPackage(String tourId, String bookId) async {
    try {
      final box = await _openBox(boxName);
      if (box == null) return null;
      final raw = box.get(_key(tourId, bookId));
      if (raw is! Map) return null;
      return StudyOfflinePackage.fromJson(raw);
    } catch (error, stack) {
      logWarning('[StudyOfflineVault] Failed to read package', error, stack);
      return null;
    }
  }

  /// Saves or updates an offline package for a book, and its summary.
  Future<void> savePackage(StudyOfflinePackage package) async {
    try {
      final index = await _index();
      final packages = await _openBox(boxName);
      if (packages == null) return;
      final key = _key(package.tourId, package.bookId);
      await packages.put(key, package.toJson());
      await index?.put(key, package.summary.toMap());
    } catch (error, stack) {
      logWarning('[StudyOfflineVault] Failed to save package', error, stack);
    }
  }

  /// Removes an offline package for a book, and its summary.
  Future<void> removePackage(String tourId, String bookId) async {
    try {
      final key = _key(tourId, bookId);
      final index = await _index();
      await index?.delete(key);
      final packages = await _openBox(boxName);
      await packages?.delete(key);
    } catch (error, stack) {
      logWarning('[StudyOfflineVault] Failed to remove package', error, stack);
    }
  }

  /// Lists all offline packages cached for a particular tour group.
  Future<List<StudyOfflinePackage>> listPackages(String tourId) async {
    try {
      final box = await _openBox(boxName);
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

  /// Clears all cached offline packages for a tour, and their summaries.
  Future<void> clearAll(String tourId) async {
    try {
      final prefix = '${tourId}__';
      final index = await _index();
      if (index != null) {
        final summaryKeys = index.keys
            .where((k) => k is String && k.startsWith(prefix))
            .toList();
        for (final k in summaryKeys) {
          await index.delete(k);
        }
      }
      final packages = await _openBox(boxName);
      if (packages == null) return;
      final keysToDelete = packages.keys
          .where((k) => k is String && k.startsWith(prefix))
          .toList();
      for (final k in keysToDelete) {
        await packages.delete(k);
      }
    } catch (error, stack) {
      logWarning('[StudyOfflineVault] Failed to clear packages', error, stack);
    }
  }
}
