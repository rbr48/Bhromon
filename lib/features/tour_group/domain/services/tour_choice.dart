import '../models/tour_group.dart';

/// The tour a screen should show: the first of [preferredIds] that is one of
/// [groups], in the order given, else the first group.
///
/// Null, empty and unknown ids are skipped, so an id for a tour the user has
/// left, or has not been listed yet, never picks a tour the user is not in.
/// Returns null only when [groups] is empty.
TourGroup? pickTour(List<TourGroup> groups, Iterable<String?> preferredIds) {
  if (groups.isEmpty) return null;
  for (final id in preferredIds) {
    if (id == null || id.isEmpty) continue;
    for (final group in groups) {
      if (group.id == id) return group;
    }
  }
  return groups.first;
}
