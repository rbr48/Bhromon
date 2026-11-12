// The rules of a group's PDF record: which parts it holds for each kind of group, what it
// keeps from the content, and how its file and menu entries are named. Pure Dart, so the
// collector, the PDF writer and the group menu agree, and the rules are unit-tested.

import '../models/expense_models.dart';
import '../models/family_date_models.dart';
import '../models/family_task_models.dart';
import '../models/safety_alert_models.dart';
import '../models/service_request_models.dart';
import '../models/tour_group.dart';
import '../models/tour_post_models.dart';
import 'hub_modules.dart';

/// The parts a group's PDF record can hold, in the order the record prints them.
enum TourRecordSection {
  overview,
  members,
  journey,
  notices,
  money,
  checklist,
  transport,
  rooms,
  familyDates,
  dependents,
  sharedList,
  requests,
  safety,
  feed,
  stories,
  highlights,
}

/// The parts [group]'s record holds. They follow the group's own tools ([hubModulesFor]),
/// so the record shows what the group's hub shows: a trip keeps the trip parts, and every
/// other kind keeps only the parts its kind uses.
List<TourRecordSection> recordSectionsFor(TourGroup group) {
  final tools = hubModulesFor(group).toSet();
  final isTrip = !group.isFamily;
  return [
    TourRecordSection.overview,
    TourRecordSection.members,
    if (isTrip && tools.contains('journey')) TourRecordSection.journey,
    TourRecordSection.notices,
    TourRecordSection.money,
    if (isTrip && tools.contains('checklist')) TourRecordSection.checklist,
    if (isTrip && tools.contains('seats')) TourRecordSection.transport,
    if (isTrip && tools.contains('seats')) TourRecordSection.rooms,
    if (group.isHousehold) TourRecordSection.familyDates,
    if (tools.contains('dependents')) TourRecordSection.dependents,
    if (tools.contains('family_tasks')) TourRecordSection.sharedList,
    if (tools.contains('requests')) TourRecordSection.requests,
    if (tools.contains('safety')) TourRecordSection.safety,
    if (tools.contains('feed')) TourRecordSection.feed,
    if (tools.contains('feed')) TourRecordSection.stories,
    if (tools.contains('feed')) TourRecordSection.highlights,
  ];
}

/// The posts the record keeps: every post but the archived ones, which the scrapbook
/// leaves out too.
List<TourPostItem> recordPosts(Iterable<TourPostItem> posts) => [
      for (final post in posts)
        if (!post.isArchived) post,
    ];

/// The stories the record keeps: those still within their 24 hours at [now]. Stories
/// older than that are gone from the app, so the record leaves them out as well.
List<TourStoryItem> recordStories(
    Iterable<TourStoryItem> stories, DateTime now) {
  final oldest = now.subtract(TourStoryItem.lifetime);
  return [
    for (final story in stories)
      if (!story.createdAt.isBefore(oldest)) story,
  ];
}

/// The SOS alerts as counts only. The record never names who raised an alert or when.
({int raised, int resolved}) recordSafetyCounts(Iterable<SafetyAlert> alerts) {
  var raised = 0;
  var resolved = 0;
  for (final alert in alerts) {
    raised++;
    if (alert.resolved) resolved++;
  }
  return (raised: raised, resolved: resolved);
}

/// A name safe for a file: its letters, digits and combining marks in any script, joined by
/// underscores. The marks keep Bengali vowel signs. A name with none (or an empty one) reads
/// as "group". At most sixty characters.
String recordSafeName(String name) {
  final joined = name
      .trim()
      .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (joined.isEmpty) return 'group';
  final shortened = String.fromCharCodes(joined.runes.take(60));
  return shortened.replaceAll(RegExp(r'_+$'), '');
}

/// The file name of a group's record: `bhromon_<name>_record.pdf`.
String recordFileName(String groupName) =>
    'bhromon_${recordSafeName(groupName)}_record.pdf';

/// A PDF the group menu can offer.
enum RecordExportOption {
  /// The samity's own statement of schedule, payments and payouts.
  samityStatement,

  /// The mess's monthly meal sheet and balance.
  mealSheet,

  /// The study pack of a book.
  studyPack,

  /// The group's own record, for admins and owners only.
  groupRecord,
}

/// The PDFs the group menu offers [group] for a viewer who is an admin or owner
/// ([isAdmin]). A preset's own document comes first and is open to every member who can
/// see that tool; the group record comes last and is for admins only.
List<RecordExportOption> recordExportOptions(
  TourGroup group, {
  required bool isAdmin,
}) {
  return [
    if (group.isSamity && group.samity.isSetUp)
      RecordExportOption.samityStatement,
    if (group.isMess) RecordExportOption.mealSheet,
    if (group.isStudy) RecordExportOption.studyPack,
    if (isAdmin) RecordExportOption.groupRecord,
  ];
}

/// The translation key of the kind badge the hub shows for [group], or null for a trip.
String? recordKindKey(TourGroup group) {
  if (group.isOffice) return 'hub_office_badge';
  if (group.isCampus) return 'hub_campus_badge';
  if (group.isMess) return 'hub_mess_badge';
  if (group.isSociety) return 'hub_society_badge';
  if (group.isSamity) return 'hub_samity_badge';
  if (group.isSchool) return 'hub_school_badge';
  if (group.isSports) return 'hub_sports_badge';
  if (group.isStudy) return 'hub_study_badge';
  if (group.isCommittee) return 'hub_committee_badge';
  if (group.isFriends) return 'hub_friends_badge';
  if (group.isFamily) return 'hub_family_badge';
  return null;
}

/// The translation key of a preset expense category, matched without regard to case, or
/// null for a category the app does not name (a custom one prints as it was typed).
String? recordCategoryKey(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'food':
      return 'fund_cat_food';
    case 'transport':
      return 'fund_cat_transport';
    case 'hotel':
      return 'fund_cat_hotel';
    case 'tickets':
    case 'ticket':
      return 'fund_cat_tickets';
    case 'guide':
      return 'fund_cat_guide';
    case 'activities':
    case 'activity':
      return 'fund_cat_activities';
    case 'shopping':
      return 'fund_cat_shopping';
    case 'medical':
    case 'medicine':
    case 'medicines':
      return 'fund_cat_medical';
    case 'tips':
    case 'tip':
      return 'fund_cat_tips';
    case 'groceries':
    case 'grocery':
      return 'fund_cat_groceries';
    case 'utilities':
    case 'utility':
      return 'fund_cat_utilities';
    case 'rent':
      return 'fund_cat_rent';
    case 'school':
      return 'fund_cat_school';
    case 'dining':
      return 'fund_cat_dining';
    case 'gifts':
    case 'gift':
      return 'fund_cat_gifts';
    case 'others':
    case 'other':
      return 'fund_cat_others';
    case 'security':
      return 'fund_cat_security';
    case 'cleaning':
      return 'fund_cat_cleaning';
    case 'repairs':
      return 'fund_cat_repairs';
    case 'generator':
      return 'fund_cat_generator';
    case 'lift':
      return 'fund_cat_lift';
    case 'books':
      return 'fund_cat_books';
    case 'coaching':
      return 'fund_cat_coaching';
    case 'venue':
      return 'fund_cat_venue';
    case 'equipment':
      return 'fund_cat_equipment';
    case 'printing':
      return 'fund_cat_printing';
    case 'events':
      return 'fund_cat_events';
    default:
      return null;
  }
}

/// The translation key of a family date's kind, such as `fd_kind_birthday`.
String recordFamilyDateKindKey(FamilyDateKind kind) => 'fd_kind_${kind.name}';

/// The translation key of a family task's kind: to buy or to do.
String recordFamilyTaskKindKey(FamilyTaskKind kind) => switch (kind) {
      FamilyTaskKind.shopping => 'ft_kind_shopping',
      FamilyTaskKind.todo => 'ft_kind_todo',
    };

/// The translation key of a service request's category.
String recordRequestCategoryKey(ServiceRequestCategory category) =>
    switch (category) {
      ServiceRequestCategory.lift => 'society_cat_lift',
      ServiceRequestCategory.water => 'society_cat_water',
      ServiceRequestCategory.power => 'society_cat_power',
      ServiceRequestCategory.security => 'society_cat_security',
      ServiceRequestCategory.cleaning => 'society_cat_cleaning',
      ServiceRequestCategory.other => 'society_cat_other',
    };

/// The translation key of a service request's status.
String recordRequestStatusKey(ServiceRequestStatus status) => switch (status) {
      ServiceRequestStatus.open => 'society_request_status_open',
      ServiceRequestStatus.inProgress => 'society_request_status_in_progress',
      ServiceRequestStatus.resolved => 'society_request_status_resolved',
    };

/// The transfers the books count: the recorded settle-up payments plus every verified MFS
/// or peer settlement, at the amount its receiver is credited. This is the rule the Fund
/// tab uses, so the record's balances match the app's.
List<TransferItem> ledgerTransfers(
  List<TransferItem> transfers,
  List<SettlementRecord> settlements,
) =>
    [
      ...transfers,
      for (final settlement in settlements.where((s) => s.isVerified))
        TransferItem(
          id: settlement.id,
          tourId: settlement.tourId,
          fromId: settlement.fromMemberId,
          fromName: settlement.fromMemberName,
          toId: settlement.toMemberId,
          toName: settlement.toMemberName,
          amountPaisa: settlement.creditedPaisa,
          date: settlement.date,
          notes: settlement.mfsInfo.provider.requiresTrxId
              ? '${settlement.mfsInfo.provider.name.toUpperCase()} TrxID: ${settlement.mfsInfo.trxId ?? ''}'
              : (settlement.notes ?? 'MFS Settlement'),
          addedByEmail: settlement.addedByEmail,
        ),
    ];
