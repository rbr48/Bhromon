import 'package:flutter/foundation.dart';

import 'study_material_models.dart';
import 'study_models.dart';

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
  String get formattedSize {
    if (totalSizeBytes <= 0) return '0 B';
    if (totalSizeBytes < 1024) return '$totalSizeBytes B';
    if (totalSizeBytes < 1024 * 1024) {
      return '${(totalSizeBytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(totalSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

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

      final rawCached = map['cachedAt'];
      final cachedAt = rawCached is String
          ? DateTime.tryParse(rawCached) ?? DateTime.now()
          : (rawCached is DateTime ? rawCached : DateTime.now());

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
}
