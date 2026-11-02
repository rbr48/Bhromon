/// Keeps the message list in order while pages arrive.
///
/// The list is newest first. The newest page arrives in real time; older pages
/// are fetched when the user scrolls up. Both helpers are pure so the chat
/// screen can use them and tests can cover them without Firestore.
library;

/// Merges the newest page from the live query into [loaded].
///
/// Messages already loaded are replaced by their newer version, and messages
/// that are not loaded yet are added at the top, in the order they came.
List<T> applyNewestPage<T>({
  required List<T> loaded,
  required List<T> newest,
  required String Function(T item) idOf,
}) {
  final newestById = {for (final item in newest) idOf(item): item};
  final loadedIds = {for (final item in loaded) idOf(item)};
  final fresh = [
    for (final item in newest)
      if (!loadedIds.contains(idOf(item))) item,
  ];
  return [
    ...fresh,
    for (final item in loaded) newestById[idOf(item)] ?? item,
  ];
}

/// Appends an older page to [loaded], skipping any message already there.
List<T> appendOlderPage<T>({
  required List<T> loaded,
  required List<T> older,
  required String Function(T item) idOf,
}) {
  final seen = {for (final item in loaded) idOf(item)};
  return [
    ...loaded,
    for (final item in older)
      if (seen.add(idOf(item))) item,
  ];
}
