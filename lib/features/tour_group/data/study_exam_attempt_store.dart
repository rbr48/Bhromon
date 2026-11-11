import 'package:bhromon/app/di/injection.dart';
import 'package:bhromon/core/security/hive_encryption_service.dart';
import 'package:bhromon/core/utils/app_logger.dart';
import 'package:hive/hive.dart';

import '../domain/models/study_exam_simulator_models.dart';

/// Stores candidate exam attempts locally in an encrypted box.
/// Exam drafts and self-evaluation marks remain strictly on the device for candidate privacy.
/// Without an encryption service nothing is read or written: the box is never opened in plain text.
class StudyExamAttemptStore {
  StudyExamAttemptStore({HiveEncryptionService? encryption})
      : _encryption = encryption;

  static final StudyExamAttemptStore instance = StudyExamAttemptStore();

  static const String boxName = 'study_exam_attempts';

  final HiveEncryptionService? _encryption;

  /// The encrypted box, or null when no encryption service is available.
  /// There is no plain-box fallback: exam drafts and marks would reach the disk unencrypted.
  Future<Box<dynamic>?> _box() async {
    final encryption = _encryption ??
        (getIt.isRegistered<HiveEncryptionService>()
            ? getIt<HiveEncryptionService>()
            : null);
    if (encryption == null) {
      logWarning('Exam attempts not stored: no encryption service');
      return null;
    }
    return encryption.openEncryptedBox<dynamic>(boxName);
  }

  /// Every attempt stored on this device, newest first. A record that cannot be read is left
  /// out on its own, so the others still show.
  Future<List<ExamAttempt>> loadAll() async {
    try {
      final box = await _box();
      if (box == null) return [];
      final attempts = <ExamAttempt>[];
      for (final raw in box.values) {
        try {
          final attempt = ExamAttempt.fromJson(raw);
          if (attempt != null) attempts.add(attempt);
        } catch (error, stack) {
          logWarning('Exam attempt record skipped', error, stack);
        }
      }
      attempts.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      return attempts;
    } catch (error, stack) {
      logWarning('Exam attempts could not be read', error, stack);
      return [];
    }
  }

  /// The attempt still open for this paper, the newest when there are several. Null when none.
  Future<ExamAttempt?> loadOpenFor({
    required String bookId,
    required String chapterId,
  }) async {
    final all = await loadAll();
    for (final attempt in all) {
      if (attempt.isOpen &&
          attempt.bookId == bookId &&
          attempt.chapterId == chapterId) {
        return attempt;
      }
    }
    return null;
  }

  /// Loads all attempts for a specific subject book.
  Future<List<ExamAttempt>> loadForBook(String bookId) async {
    final all = await loadAll();
    return all.where((a) => a.bookId == bookId).toList();
  }

  /// Saves or updates an exam attempt. Returns false when it could not be stored, so the
  /// caller can tell the candidate instead of letting the exam look saved.
  Future<bool> put(ExamAttempt attempt) async {
    try {
      final box = await _box();
      if (box == null) return false;
      await box.put(attempt.id, attempt.toJson());
      return true;
    } catch (error, stack) {
      logWarning('Exam attempt could not be saved', error, stack);
      return false;
    }
  }

  /// Alias for saving an exam attempt.
  Future<bool> saveAttempt(ExamAttempt attempt) => put(attempt);

  /// Deletes an exam attempt by id.
  Future<void> delete(String id) async {
    try {
      final box = await _box();
      if (box == null) return;
      await box.delete(id);
    } catch (error, stack) {
      logWarning('Exam attempt could not be deleted', error, stack);
    }
  }
}
