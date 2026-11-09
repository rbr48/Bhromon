import '../models/study_flashcard_models.dart';

// The rules of the flashcards kept on a member's device: Leitner boxes with fixed intervals, the day a card is
// due, the Anki CSV that students import, and the deck file that moves a deck to another phone. Nothing here
// reads or writes storage.

/// How many days a card waits before it is due again, by Leitner box (box 1 waits one day, box 5 sixteen).
const List<int> kLeitnerIntervalDays = [1, 2, 4, 8, 16];

/// The format name and version written into a deck file. A file with another name or version is refused.
const String kDeckFormat = 'bhromon-deck';
const int kDeckVersion = 1;

/// The box a card moves to after a review. A recalled card moves up one box, up to the top. A missed card goes
/// back to box 1.
int nextLeitnerBox(int box, {required bool recalled}) {
  if (!recalled) return StudyFlashcardLimits.boxMin;
  final next = box + 1;
  return next > StudyFlashcardLimits.boxMax
      ? StudyFlashcardLimits.boxMax
      : next;
}

/// The days a box waits before its card is due again. A box outside the range uses the nearest one.
int leitnerIntervalDays(int box) {
  var index = box - 1;
  if (index < 0) index = 0;
  if (index >= kLeitnerIntervalDays.length) {
    index = kLeitnerIntervalDays.length - 1;
  }
  return kLeitnerIntervalDays[index];
}

/// The yyyy-MM-dd key of a day, in local time.
String dayKey(DateTime day) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${day.year.toString().padLeft(4, '0')}-${two(day.month)}-${two(day.day)}';
}

/// The key of the day a card in [box] is next due, counted from [today].
String dueKeyAfterReview(DateTime today, int box) {
  final base = DateTime(today.year, today.month, today.day);
  final due = DateTime(
    base.year,
    base.month,
    base.day + leitnerIntervalDays(box),
  );
  return dayKey(due);
}

/// The card after a review: its box moves, and it is due again after the box's interval.
StudyFlashcard reviewCard(
  StudyFlashcard card, {
  required bool recalled,
  required DateTime today,
}) {
  final box = nextLeitnerBox(card.box, recalled: recalled);
  return card.copyWith(box: box, dueOn: dueKeyAfterReview(today, box));
}

/// Whether a card is due on [today]: its due day has come.
bool isCardDue(StudyFlashcard card, DateTime today) =>
    dayKey(today).compareTo(card.dueOn) >= 0;

/// The cards due on [today], the oldest due day first.
List<StudyFlashcard> dueCards(Iterable<StudyFlashcard> cards, DateTime today) {
  final due = [
    for (final card in cards)
      if (isCardDue(card, today)) card,
  ];
  due.sort((a, b) => a.dueOn.compareTo(b.dueOn));
  return due;
}

/// The cards as the CSV that Anki imports: the front and the back of each card, in two columns, each in
/// double quotes with an inner quote doubled. Anki reads the file as UTF-8 with no header row.
String toAnkiCsv(Iterable<StudyFlashcard> cards) {
  String field(String value) => '"${value.replaceAll('"', '""')}"';
  return [
    for (final card in cards) '${field(card.front)},${field(card.back)}',
  ].join('\n');
}

/// The deck file for a set of cards: a format name, a version, and the cards.
Map<String, dynamic> deckToJson(Iterable<StudyFlashcard> cards) => {
      'format': kDeckFormat,
      'version': kDeckVersion,
      'cards': [for (final card in cards) card.toJson()],
    };

/// Reads a deck file. Returns null when the file is not a deck of this format and version. Each card is
/// checked again, and a damaged one is left out. Imported cards take new ids from [newId], so an import never
/// overwrites a card the member already has, and they go into [deckId].
List<StudyFlashcard>? deckFromJson(
  Object? raw, {
  required String deckId,
  required String Function() newId,
}) {
  if (raw is! Map) return null;
  if (raw['format'] != kDeckFormat || raw['version'] != kDeckVersion) {
    return null;
  }
  final cards = raw['cards'];
  if (cards is! List) return null;
  final imported = <StudyFlashcard>[];
  for (final item in cards) {
    if (item is! Map) continue;
    final card = StudyFlashcard.fromJson(item);
    if (card == null) continue;
    imported.add(
      StudyFlashcard(
        id: newId(),
        deckId: deckId,
        front: card.front,
        back: card.back,
        box: card.box,
        dueOn: card.dueOn,
        termId: card.termId,
      ),
    );
  }
  return imported;
}
