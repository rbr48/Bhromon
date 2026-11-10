// A flashcard a member keeps on their own device. Cards and their review state live in an encrypted local box
// and never go to the server. A card holds its question (front), its answer (back), its Leitner box (1 to 5) and
// the day it is next due, as a yyyy-MM-dd key.

/// The limits a flashcard is checked against when it is added or imported.
class StudyFlashcardLimits {
  const StudyFlashcardLimits._();

  static const int boxMin = 1;
  static const int boxMax = 5;
}

/// One flashcard on the device.
class StudyFlashcard {
  const StudyFlashcard({
    required this.id,
    required this.deckId,
    required this.front,
    required this.back,
    required this.dueOn,
    this.box = StudyFlashcardLimits.boxMin,
    this.termId,
    this.moduleCode,
  });

  final String id;

  /// The deck the card belongs to, usually the id of its book.
  final String deckId;

  /// The question, shown first.
  final String front;

  /// The answer, shown on a tap.
  final String back;

  /// The Leitner box, from 1 (new or missed) to 5 (known well).
  final int box;

  /// The day the card is next due, as yyyy-MM-dd.
  final String dueOn;

  /// The glossary term the card came from, or null when the member wrote it.
  final String? termId;

  /// The official IBB syllabus module code (e.g. 'A', 'B'), or null.
  final String? moduleCode;

  StudyFlashcard copyWith({int? box, String? dueOn, String? moduleCode}) =>
      StudyFlashcard(
        id: id,
        deckId: deckId,
        front: front,
        back: back,
        box: box ?? this.box,
        dueOn: dueOn ?? this.dueOn,
        termId: termId,
        moduleCode: moduleCode ?? this.moduleCode,
      );

  /// The card as it is written to the device box or to a deck file.
  Map<String, dynamic> toJson() => {
        'id': id,
        'deckId': deckId,
        'front': front,
        'back': back,
        'box': box,
        'dueOn': dueOn,
        if (termId != null) 'termId': termId,
        if (moduleCode != null) 'moduleCode': moduleCode,
      };

  /// Reads one card. Returns null when a text is blank, the box is out of range, or the due day
  /// is not a yyyy-MM-dd key. A damaged card is left out rather than breaking the deck.
  static StudyFlashcard? fromJson(Map<dynamic, dynamic> json) {
    final id = json['id'];
    final deckId = json['deckId'];
    final front = (json['front'] as String?)?.trim() ?? '';
    final back = (json['back'] as String?)?.trim() ?? '';
    final box = (json['box'] as num?)?.toInt();
    final dueOn = json['dueOn'];
    final termId = json['termId'];
    final moduleCode = json['moduleCode'];
    if (id is! String || id.isEmpty || deckId is! String) return null;
    if (front.isEmpty || back.isEmpty) return null;
    if (box == null ||
        box < StudyFlashcardLimits.boxMin ||
        box > StudyFlashcardLimits.boxMax) {
      return null;
    }
    if (dueOn is! String || !_dayKeyPattern.hasMatch(dueOn)) return null;
    return StudyFlashcard(
      id: id,
      deckId: deckId,
      front: front,
      back: back,
      box: box,
      dueOn: dueOn,
      termId: termId is String && termId.isNotEmpty ? termId : null,
      moduleCode:
          moduleCode is String && moduleCode.isNotEmpty ? moduleCode : null,
    );
  }

  static final RegExp _dayKeyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
}
