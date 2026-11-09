import '../models/tour_group.dart';

/// The order of the group tools for a trip. Tools missing from the order come after it.
const List<String> tripModuleOrder = [
  'feed',
  'ledger',
  'seats',
  'calendar',
  'tide',
  'notices',
  'journey',
  'safety',
  'games',
  'quiz',
  'scrapbook',
  'checklist',
  'channels',
  'news',
];

/// The order of the group tools for a family circle and the other group types: the
/// day-to-day tools first, and the shared news last.
const List<String> familyModuleOrder = [
  'channels',
  'notices',
  'study_subjects',
  'study_reading',
  'study_books',
  'requests',
  'samity',
  'family_tasks',
  'meals',
  'dependents',
  'album',
  'calendar',
  'safety',
  'feed',
  'ledger',
  'games',
  'news',
];

/// The ids of the group tools that apply to [group], in the order the hub shows them.
///
/// Pure: the hub only builds the tile for each id. [momentsOpen] defaults to the
/// group's own setting. The conditions are the ones the hub has always used, so the
/// hub's golden test (test/features/tour_group/hub_modules_golden_test.dart) pins them.
List<String> hubModulesFor(TourGroup group, {bool? momentsOpen}) {
  final moments = momentsOpen ?? group.momentsOpen;
  // Family circles have no trip, so the trip-only tools stay hidden.
  final isTrip = !group.isFamily;
  final applicable = <String>[
    if (moments) 'feed',
    'ledger',
    if (isTrip && group.modules.seatsRooms) 'seats',
    if (!group.isManaged &&
        !group.isMess &&
        !group.isSociety &&
        !group.isSamity)
      'calendar',
    if (group.isFamily && !group.isManaged) 'family_tasks',
    if (group.isMess) 'meals',
    if (group.isSociety || group.isCommittee) 'requests',
    if (group.isSamity) 'samity',
    if (group.isHousehold) 'dependents',
    if (group.isHousehold) 'album',
    if (isTrip && group.modules.tideSafety) 'tide',
    'notices',
    if (group.isStudy) 'study_subjects',
    if (group.isStudy) 'study_reading',
    if (group.isStudy) 'study_books',
    if (isTrip) 'journey',
    if (!group.isManaged) 'safety',
    if (group.modules.games) 'games',
    if (isTrip) 'quiz',
    if (isTrip) 'scrapbook',
    if (isTrip) 'checklist',
    if (group.modules.chat) 'channels',
    'news',
  ];
  final order = isTrip ? tripModuleOrder : familyModuleOrder;
  return [
    for (final id in order)
      if (applicable.contains(id)) id,
    for (final id in applicable)
      if (!order.contains(id)) id,
  ];
}
