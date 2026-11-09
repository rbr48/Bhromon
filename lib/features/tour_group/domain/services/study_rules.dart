import '../models/study_models.dart';

/// The order the book list shows its sections: what is being read, what is to be read,
/// then what is finished.
const List<StudyBookStatus> kStudyBookSectionOrder = [
  StudyBookStatus.reading,
  StudyBookStatus.toRead,
  StudyBookStatus.finished,
];

/// Whether [title] can be saved: it has text once trimmed. Its length is not limited.
bool isValidStudyTitle(String title) {
  final trimmed = title.trim();
  return trimmed.isNotEmpty;
}

/// Whether a member may change or remove an item made by [createdByEmail]: its creator,
/// or an admin. Matches the rules in firestore.rules.
bool canEditStudyItem({
  required String createdByEmail,
  required String currentEmail,
  required bool isAdmin,
}) =>
    isAdmin || (createdByEmail.isNotEmpty && createdByEmail == currentEmail);

/// Sessions split into those still to come, soonest first, and those already past,
/// latest first. A session that starts exactly at [now] is still to come.
({List<ReadingSession> upcoming, List<ReadingSession> past}) splitSessions(
  List<ReadingSession> sessions,
  DateTime now,
) {
  final upcoming = sessions.where((s) => !s.startsAt.isBefore(now)).toList()
    ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  final past = sessions.where((s) => s.startsAt.isBefore(now)).toList()
    ..sort((a, b) => b.startsAt.compareTo(a.startsAt));
  return (upcoming: upcoming, past: past);
}

/// The listed books grouped by status. Every status has a list, even an empty one. A
/// proposal or a declined book is in no status section. Each list is sorted by title,
/// ignoring case.
Map<StudyBookStatus, List<StudyBook>> groupStudyBooks(List<StudyBook> books) {
  final groups = {
    for (final status in StudyBookStatus.values) status: <StudyBook>[],
  };
  for (final book in books.where((b) => b.isListed)) {
    groups[book.status]!.add(book);
  }
  for (final group in groups.values) {
    group
        .sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }
  return groups;
}

/// The proposals waiting for an admin, sorted by title, ignoring case.
List<StudyBook> studyBookProposals(List<StudyBook> books) =>
    _byTitle(books.where((b) => b.isProposed));

/// The declined proposals, sorted by title, ignoring case.
List<StudyBook> studyBookDeclined(List<StudyBook> books) =>
    _byTitle(books.where((b) => b.isDeclined));

List<StudyBook> _byTitle(Iterable<StudyBook> books) => books.toList()
  ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
