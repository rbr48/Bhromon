// What the desktop sidebar and the right dock show for a group: the name of its type, its
// tools, and where each tool lives. Pure Dart: it follows hubModulesFor, so the sidebar can
// never offer a tool the group's own hub does not have.

import '../models/tour_group.dart';
import 'hub_modules.dart';

/// The translation key of the name of [group]'s type, or null for a trip, which is named by
/// its route. The hub's badge, the sidebar and the right dock all use it, so a group has one
/// type name everywhere.
String? groupTypeLabelKey(TourGroup group) {
  if (group.isFriends) return 'hub_friends_badge';
  if (group.isOffice) return 'hub_office_badge';
  if (group.isCampus) return 'hub_campus_badge';
  if (group.isMess) return 'hub_mess_badge';
  if (group.isSociety) return 'hub_society_badge';
  if (group.isSamity) return 'hub_samity_badge';
  if (group.isSchool) return 'hub_school_badge';
  if (group.isSports) return 'hub_sports_badge';
  if (group.isStudy) return 'hub_study_badge';
  if (group.isCommittee) return 'hub_committee_badge';
  if (group.isFamily) return 'hub_family_badge';
  return null;
}

/// The last part of the route of each group tool, under `/group/{id}/`. A tool that is not
/// here has no page of its own under the group: games and news are the same for every group.
const Map<String, String> kGroupToolRoutes = {
  'feed': 'feed',
  'ledger': 'ledger',
  'seats': 'logistics',
  'calendar': 'family-dates',
  'family_tasks': 'family-tasks',
  'meals': 'meals',
  'requests': 'requests',
  'samity': 'samity',
  'dependents': 'dependents',
  'album': 'album',
  'tide': 'tide',
  'notices': 'notices',
  'study_subjects': 'study-subjects',
  'study_reading': 'study-reading',
  'study_books': 'study-books',
  'journey': 'journey',
  'safety': 'safety',
  'quiz': 'quiz',
  'scrapbook': 'scrapbook',
  'checklist': 'checklist',
  'channels': 'channels',
};

/// The route of tool [id] in the group [tourId], or null when the tool has no page under
/// the group.
String? groupToolRoute(String tourId, String id) {
  final part = kGroupToolRoutes[id];
  return part == null ? null : '/group/$tourId/$part';
}

/// The tools of [group] the sidebar lists under the group, in the hub's order. Games and
/// news are left out: they belong to no group and have their own section.
List<String> sidebarGroupTools(TourGroup group) => [
      for (final id in hubModulesFor(group))
        if (kGroupToolRoutes.containsKey(id)) id,
    ];

/// The tool a path under a group belongs to, or null when the path is not a tool's page.
/// `/group/x/study-subjects` gives `study_subjects`.
String? groupToolOfPath(String path) {
  final segments = path.split('/');
  // '', 'group', id, part, ...
  if (segments.length < 4 || segments[1] != 'group') return null;
  final part = segments[3];
  for (final entry in kGroupToolRoutes.entries) {
    if (entry.value == part) return entry.key;
  }
  return null;
}

/// Where the app goes when the user picks [group] while looking at [currentPath]. The same
/// tool in the new group when that group has it, and otherwise the group's own page: a study
/// circle picked from a trip's seat plan does not open a seat plan.
String pathForGroupSwitch(TourGroup group, String currentPath) {
  final tool = groupToolOfPath(currentPath);
  if (tool != null && hubModulesFor(group).contains(tool)) {
    return groupToolRoute(group.id, tool)!;
  }
  return '/group-hub?tourId=${group.id}';
}
