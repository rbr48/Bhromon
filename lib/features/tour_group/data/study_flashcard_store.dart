import 'package:bhromon/app/di/injection.dart';
import 'package:bhromon/core/security/hive_encryption_service.dart';
import 'package:hive/hive.dart';

import '../domain/models/study_flashcard_models.dart';

/// The flashcards a member keeps on this device. They live in an encrypted box and never go to the server. A card
/// leaves the phone only when the member exports its deck to a file.
class StudyFlashcardStore {
  StudyFlashcardStore({HiveEncryptionService? encryption})
      : _encryption = encryption;

  /// The encrypted box that holds the cards, by id.
  static const String boxName = 'study_flashcards';

  final HiveEncryptionService? _encryption;

  Future<Box<dynamic>> _box() {
    final service = _encryption ?? getIt<HiveEncryptionService>();
    return service.openEncryptedBox<dynamic>(boxName);
  }

  /// Every card on the device, in no particular order. A damaged entry is left out.
  Future<List<StudyFlashcard>> loadAll() async {
    final box = await _box();
    final cards = <StudyFlashcard>[];
    for (final raw in box.values) {
      if (raw is! Map) continue;
      final card = StudyFlashcard.fromJson(raw);
      if (card != null) cards.add(card);
    }
    return cards;
  }

  /// Writes cards, replacing any card with the same id.
  Future<void> putAll(Iterable<StudyFlashcard> cards) async {
    final box = await _box();
    await box.putAll({for (final card in cards) card.id: card.toJson()});
  }

  /// Removes a card by id.
  Future<void> delete(String id) async {
    final box = await _box();
    await box.delete(id);
  }
}
