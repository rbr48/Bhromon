import 'package:bhromon/app/di/injection.dart';
import 'package:bhromon/core/security/hive_encryption_service.dart';
import 'package:hive/hive.dart';

import '../domain/services/study_flashcard_rules.dart' show dayKey;

/// The study a member does on this device, counted per day: cards reviewed and quiz attempts saved. A streak and a
/// progress card count these days without the server, and the counts never leave the device. They sit in an
/// encrypted box, as the flashcards do.
class StudyActivityLog {
  StudyActivityLog({HiveEncryptionService? encryption})
      : _encryption = encryption;

  /// The encrypted box that holds the daily counts.
  static const String boxName = 'study_activity';

  static const String _reviewPrefix = 'review|';
  static const String _quizPrefix = 'quiz|';

  final HiveEncryptionService? _encryption;

  Future<Box<dynamic>> _box() {
    final service = _encryption ?? getIt<HiveEncryptionService>();
    return service.openEncryptedBox<dynamic>(boxName);
  }

  /// Counts one card reviewed on [day].
  Future<void> recordReview(DateTime day) =>
      _add('$_reviewPrefix${dayKey(day)}');

  /// Counts one quiz attempt saved on [day].
  Future<void> recordQuiz(DateTime day) => _add('$_quizPrefix${dayKey(day)}');

  Future<void> _add(String key) async {
    final box = await _box();
    final current = box.get(key);
    await box.put(key, (current is int ? current : 0) + 1);
  }

  /// The days, from any kind of study, on which the member did something. A day appears once.
  Future<List<DateTime>> activeDays() async {
    final box = await _box();
    final days = <DateTime>{};
    for (final key in box.keys) {
      final parsed = _dayOf(key.toString());
      if (parsed != null) days.add(parsed);
    }
    return days.toList()..sort();
  }

  /// The number of cards reviewed on this device, in total.
  Future<int> cardsReviewed() async {
    final box = await _box();
    var total = 0;
    for (final key in box.keys) {
      if (!key.toString().startsWith(_reviewPrefix)) continue;
      final value = box.get(key);
      if (value is int) total += value;
    }
    return total;
  }

  /// The day a stored key stands for, or null when the key is not a day key.
  static DateTime? _dayOf(String key) {
    final bar = key.indexOf('|');
    if (bar < 0) return null;
    return DateTime.tryParse(key.substring(bar + 1));
  }
}
