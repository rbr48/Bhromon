import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:flutter/material.dart';

// Every preset is stored as a family-kind circle, so `isFamily` alone cannot say what
// a group is. These two functions name a group by its preset (a housing society, a
// mess, a gym) and fall back to the family or the trip name and icon.

/// The translation key of the type [group] shows: its preset's name, "Family circles"
/// for a plain family circle, or "Trips" for a trip.
String groupTypeKey(TourGroup group) {
  switch (group.effectivePreset) {
    case TourGroup.friendsPreset:
      return 'hub_friends_badge';
    case TourGroup.officePreset:
      return 'hub_office_badge';
    case TourGroup.campusPreset:
      return 'hub_campus_badge';
    case TourGroup.messPreset:
      return 'hub_mess_badge';
    case TourGroup.societyPreset:
      return 'hub_society_badge';
    case TourGroup.samityPreset:
      return 'hub_samity_badge';
    case TourGroup.schoolPreset:
      return 'hub_school_badge';
    case TourGroup.sportsPreset:
      return 'hub_sports_badge';
    case TourGroup.studyPreset:
      return 'hub_study_badge';
    case TourGroup.committeePreset:
      return 'hub_committee_badge';
  }
  return group.isFamily ? 'hub_section_family' : 'hub_section_trips';
}

/// The icon of the type [group] shows when it has no photo.
IconData groupTypeIcon(TourGroup group) {
  switch (group.effectivePreset) {
    case TourGroup.friendsPreset:
      return Icons.people_alt_rounded;
    case TourGroup.officePreset:
      return Icons.work_outline_rounded;
    case TourGroup.campusPreset:
      return Icons.account_balance_outlined;
    case TourGroup.messPreset:
      return Icons.restaurant_rounded;
    case TourGroup.societyPreset:
      return Icons.apartment_rounded;
    case TourGroup.samityPreset:
      return Icons.account_balance_wallet_outlined;
    case TourGroup.schoolPreset:
      return Icons.school_rounded;
    case TourGroup.sportsPreset:
      return Icons.fitness_center_rounded;
    case TourGroup.studyPreset:
      return Icons.menu_book_rounded;
    case TourGroup.committeePreset:
      return Icons.groups_rounded;
  }
  return group.isFamily
      ? Icons.family_restroom_rounded
      : Icons.card_travel_rounded;
}
