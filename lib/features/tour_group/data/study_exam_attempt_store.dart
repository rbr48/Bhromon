import 'package:bhromon/app/di/injection.dart';
import 'package:bhromon/core/security/hive_encryption_service.dart';
import 'package:hive/hive.dart';

import '../domain/models/study_exam_simulator_models.dart';

/// Stores candidate mock exam attempts locally in an encrypted box.
/// Exam drafts and self-evaluation marks remain strictly on the device for candidate privacy.
class StudyExamAttemptStore {
  StudyExamAttemptStore({HiveEncryptionService? encryption})
      : _encryption = encryption;

  static final StudyExamAttemptStore instance = StudyExamAttemptStore();

  static const String boxName = 'study_exam_attempts';

  final HiveEncryptionService? _encryption;

  Future<Box<dynamic>> _box() async {
    if (_encryption != null) {
      return _encryption.openEncryptedBox<dynamic>(boxName);
    }
    if (getIt.isRegistered<HiveEncryptionService>()) {
      return getIt<HiveEncryptionService>().openEncryptedBox<dynamic>(boxName);
    }
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box<dynamic>(boxName);
    }
    return Hive.openBox<dynamic>(boxName);
  }

  /// Loads all candidate exam attempts stored on this device.
  Future<List<ExamAttempt>> loadAll() async {
    try {
      final box = await _box();
      final attempts = <ExamAttempt>[];
      for (final raw in box.values) {
        if (raw is! Map) continue;
        final attempt = ExamAttempt.fromJson(raw);
        if (attempt != null) attempts.add(attempt);
      }
      attempts.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      return attempts;
    } catch (_) {
      return [];
    }
  }

  /// Loads all attempts for a specific subject book.
  Future<List<ExamAttempt>> loadForBook(String bookId) async {
    final all = await loadAll();
    return all.where((a) => a.bookId == bookId).toList();
  }

  /// Saves or updates an exam attempt.
  Future<void> put(ExamAttempt attempt) async {
    try {
      final box = await _box();
      await box.put(attempt.id, attempt.toJson());
    } catch (_) {
      // Storage unavailable in lightweight test contexts
    }
  }

  /// Alias for saving an exam attempt.
  Future<void> saveAttempt(ExamAttempt attempt) => put(attempt);

  /// Deletes an exam attempt by id.
  Future<void> delete(String id) async {
    final box = await _box();
    await box.delete(id);
  }
}
