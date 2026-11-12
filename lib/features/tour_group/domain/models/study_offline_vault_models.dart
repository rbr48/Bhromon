import 'package:flutter/foundation.dart';

import 'study_material_models.dart';
import 'study_models.dart';

/// Formats a storage size the way the offline vault shows it: bytes, kilobytes or megabytes.
String formatOfflineBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// When a stored package was cached. Falls back to now when the stored value is missing or damaged.
DateTime _cachedAtFrom(Object? raw) {
  if (raw is String) return DateTime.tryParse(raw) ?? DateTime.now();
  if (raw is DateTime) return raw;
  return DateTime.now();
}

/// An offline-ready study package containing a subject book's complete metadata,
/// all chapter outlines, published examiner-grade solutions (English and Bengali),
/// and raw markdown text.
@immutable
class StudyOfflinePackage {
  final String tourId;
  final String bookId;
  final String bookTitle;
  final DateTime cachedAt;
  final int totalSizeBytes;
  final List<StudyChapter> chapters;
  final List<StudyMaterial> materials;
  final Map<String, String> contents;

  const StudyOfflinePackage({
    required this.tourId,
    required this.bookId,
    required this.bookTitle,
    required this.cachedAt,
    required this.totalSizeBytes,
    required this.chapters,
    required this.materials,
    required this.contents,
  });

  int get chapterCount => chapters.length;
  int get materialCount => materials.length;

  /// Retrieves raw markdown text for a specific material if available in the vault.
  String? contentFor(String materialId) => contents[materialId];

  /// Human-readable storage size representation (e.g. "850 KB", "1.4 MB").
  String get formattedSize => formatOfflineBytes(totalSizeBytes);

  /// What the index keeps for this package: enough to show the book as saved, without its contents.
  StudyOfflineSummary get summary => StudyOfflineSummary(
        tourId: tourId,
        bookId: bookId,
        bookTitle: bookTitle,
        cachedAt: cachedAt,
        totalSizeBytes: totalSizeBytes,
        chapterCount: chapterCount,
        materialCount: materialCount,
      );

  Map<String, dynamic> toJson() => {
        'tourId': tourId,
        'bookId': bookId,
        'bookTitle': bookTitle,
        'cachedAt': cachedAt.toIso8601String(),
        'totalSizeBytes': totalSizeBytes,
        'chapters': [
          for (final c in chapters)
            {
              'id': c.id,
              ...c.toFields(),
            }
        ],
        'materials': [
          for (final m in materials)
            {
              'id': m.id,
              ...m.toFields(status: m.status),
            }
        ],
        'contents': contents,
      };

  static StudyOfflinePackage? fromJson(Map<dynamic, dynamic> map) {
    try {
      final tourId = (map['tourId'] as String?)?.trim() ?? '';
      final bookId = (map['bookId'] as String?)?.trim() ?? '';
      final bookTitle = (map['bookTitle'] as String?)?.trim() ?? '';
      if (tourId.isEmpty || bookId.isEmpty) return null;

      final cachedAt = _cachedAtFrom(map['cachedAt']);

      final totalSizeBytes = (map['totalSizeBytes'] as num?)?.toInt() ?? 0;

      final rawChapters = map['chapters'];
      final chapters = <StudyChapter>[];
      if (rawChapters is List) {
        for (final raw in rawChapters) {
          if (raw is Map) {
            final id = (raw['id'] as String?) ?? '';
            final c = StudyChapter.fromMap(id, Map<String, dynamic>.from(raw));
            if (c != null) chapters.add(c);
          }
        }
      }

      final rawMaterials = map['materials'];
      final materials = <StudyMaterial>[];
      if (rawMaterials is List) {
        for (final raw in rawMaterials) {
          if (raw is Map) {
            final id = (raw['id'] as String?) ?? '';
            final m = StudyMaterial.fromMap(id, Map<String, dynamic>.from(raw));
            if (m != null) materials.add(m);
          }
        }
      }

      final rawContents = map['contents'];
      final contents = <String, String>{};
      if (rawContents is Map) {
        for (final entry in rawContents.entries) {
          if (entry.key is String && entry.value is String) {
            contents[entry.key as String] = entry.value as String;
          }
        }
      }

      return StudyOfflinePackage(
        tourId: tourId,
        bookId: bookId,
        bookTitle: bookTitle,
        cachedAt: cachedAt,
        totalSizeBytes: totalSizeBytes,
        chapters: chapters,
        materials: materials,
        contents: contents,
      );
    } catch (_) {
      // Safe fallback when stored package format is damaged or corrupted.
      return null;
    }
  }

  /// The summary of a stored package, read from its top level and the lengths of its lists, so its
  /// chapters, materials and contents are not decoded. Null when the stored value is not a package.
  static StudyOfflineSummary? summaryFromJson(Map<dynamic, dynamic> map) {
    final tourId = (map['tourId'] as String?)?.trim() ?? '';
    final bookId = (map['bookId'] as String?)?.trim() ?? '';
    if (tourId.isEmpty || bookId.isEmpty) return null;
    final rawChapters = map['chapters'];
    final rawMaterials = map['materials'];
    return StudyOfflineSummary(
      tourId: tourId,
      bookId: bookId,
      bookTitle: (map['bookTitle'] as String?)?.trim() ?? '',
      cachedAt: _cachedAtFrom(map['cachedAt']),
      totalSizeBytes: (map['totalSizeBytes'] as num?)?.toInt() ?? 0,
      chapterCount: rawChapters is List ? rawChapters.length : 0,
      materialCount: rawMaterials is List ? rawMaterials.length : 0,
    );
  }
}

/// A subject book's offline package as the index keeps it: its name, when it was cached, its size
/// and its counts. The chapters screen shows a book's saved state from this, so a book is opened
/// without decoding the solutions stored with it.
@immutable
class StudyOfflineSummary {
  final String tourId;
  final String bookId;
  final String bookTitle;
  final DateTime cachedAt;
  final int totalSizeBytes;
  final int chapterCount;
  final int materialCount;

  const StudyOfflineSummary({
    required this.tourId,
    required this.bookId,
    required this.bookTitle,
    required this.cachedAt,
    required this.totalSizeBytes,
    required this.chapterCount,
    required this.materialCount,
  });

  /// Human-readable storage size, as the package shows it.
  String get formattedSize => formatOfflineBytes(totalSizeBytes);

  Map<String, dynamic> toMap() => {
        'tourId': tourId,
        'bookId': bookId,
        'bookTitle': bookTitle,
        'cachedAt': cachedAt.toIso8601String(),
        'totalSizeBytes': totalSizeBytes,
        'chapterCount': chapterCount,
        'materialCount': materialCount,
      };

  /// The summary a stored map describes, or null when the map names no tour or book.
  static StudyOfflineSummary? fromMap(Map<dynamic, dynamic> map) {
    final tourId = (map['tourId'] as String?)?.trim() ?? '';
    final bookId = (map['bookId'] as String?)?.trim() ?? '';
    if (tourId.isEmpty || bookId.isEmpty) return null;
    return StudyOfflineSummary(
      tourId: tourId,
      bookId: bookId,
      bookTitle: (map['bookTitle'] as String?)?.trim() ?? '',
      cachedAt: _cachedAtFrom(map['cachedAt']),
      totalSizeBytes: (map['totalSizeBytes'] as num?)?.toInt() ?? 0,
      chapterCount: (map['chapterCount'] as num?)?.toInt() ?? 0,
      materialCount: (map['materialCount'] as num?)?.toInt() ?? 0,
    );
  }
}
