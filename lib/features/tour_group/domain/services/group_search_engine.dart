import '../models/tour_group.dart';
import 'destination_catalog.dart';

/// Search and filtering engine for tour groups and community circles.
///
/// Matches groups by:
/// 1. Name
/// 2. Category / preset identifiers (office, mess, family, campus, etc.)
/// 3. Bilingual category aliases (e.g. Friends / বন্ধু, Mess / মেস)
/// 4. Destination / stops (English & Bengali from the destination catalog)
/// 5. Invite code
class GroupSearchEngine {
  const GroupSearchEngine._();

  /// Filters a list of [groups] against [rawQuery].
  ///
  /// Returns the original list if [rawQuery] is empty or whitespace only.
  static List<TourGroup> filter({
    required List<TourGroup> groups,
    required String rawQuery,
  }) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) return groups;

    return groups.where((group) => matches(group, query)).toList();
  }

  /// Whether [group] matches the search [query] (already trimmed and lowercased).
  static bool matches(TourGroup group, String query) {
    if (query.isEmpty) return true;

    // 1. Group Name
    if (group.name.toLowerCase().contains(query)) return true;

    // 2. Preset & Kind identifier
    final preset = group.preset?.toLowerCase();
    if (preset != null && preset.contains(query)) return true;
    if (group.kind.name.toLowerCase().contains(query)) return true;

    // 3. Preset / Kind aliases (bilingual)
    final labels = _presetLabelsFor(group);
    for (final label in labels) {
      if (label.toLowerCase().contains(query)) return true;
    }

    // 4. Trip Destination & stops
    if (group.destination.toLowerCase().contains(query)) return true;
    final currentDest = group.currentDestination();
    if (currentDest.toLowerCase().contains(query)) {
      return true;
    }
    final catalogPreset = presetForName(group.destination);
    if (catalogPreset != null) {
      if (catalogPreset.nameEn.toLowerCase().contains(query) ||
          catalogPreset.nameBn.toLowerCase().contains(query)) {
        return true;
      }
    }

    // 5. Invite Code
    if (group.inviteCode.isNotEmpty &&
        group.inviteCode.toLowerCase().contains(query)) {
      return true;
    }

    return false;
  }

  static List<String> _presetLabelsFor(TourGroup group) {
    final list = <String>[];
    if (group.isFamily) {
      list.addAll(['family', 'পরিবার', 'পরিবারের গ্রুপ']);
    } else {
      list.addAll(['trip', 'tour', 'ট্যুর', 'ভ্রমণ', 'ট্রিপ']);
    }

    switch (group.preset) {
      case TourGroup.friendsPreset:
        list.addAll(['friends', 'friend', 'বন্ধু', 'দোস্ত']);
      case TourGroup.officePreset:
        list.addAll(['office', 'team', 'work', 'অফিস', 'টিম', 'সহকর্মী']);
      case TourGroup.campusPreset:
        list.addAll([
          'campus',
          'batch',
          'college',
          'varsity',
          'university',
          'ক্যাম্পাস',
          'ব্যাচ',
          'বিশ্ববিদ্যালয়',
        ]);
      case TourGroup.messPreset:
        list.addAll(['mess', 'hostel', 'flat', 'মেস', 'হোস্টেল', 'ফ্ল্যাট']);
      case TourGroup.societyPreset:
        list.addAll([
          'society',
          'building',
          'apartment',
          'housing',
          'সোসাইটি',
          'বিল্ডিং',
          'অ্যাপার্টমেন্ট',
        ]);
      case TourGroup.samityPreset:
        list.addAll(['samity', 'savings', 'সমিতি', 'সঞ্চয়']);
      case TourGroup.schoolPreset:
        list.addAll(['school', 'class', 'স্কুল', 'ক্লাস']);
      case TourGroup.sportsPreset:
        list.addAll(['sports', 'club', 'খেলাধুলা', 'ক্লাব']);
      case TourGroup.studyPreset:
        list.addAll(['study', 'study circle', 'পড়াশোনা', 'স্টাডি']);
      case TourGroup.committeePreset:
        list.addAll(['committee', 'board', 'কমিটি']);
    }

    return list;
  }
}
