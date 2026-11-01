/// Which media files a deletion may remove.
///
/// A file can be used by more than one post, story or highlight, so removing it
/// for one of them would break the others. A file is removed only when no other
/// content still uses it. A file that cannot be checked counts as in use.
library;

/// The URLs in [candidates] that no content still uses, in their original order
/// and without repeats. Empty URLs are dropped.
List<String> mediaUrlsSafeToRemove(
  Iterable<String> candidates,
  Set<String> stillInUse,
) {
  final seen = <String>{};
  final safe = <String>[];
  for (final url in candidates) {
    if (url.isEmpty || !seen.add(url)) continue;
    if (stillInUse.contains(url)) continue;
    safe.add(url);
  }
  return safe;
}
