import 'package:flutter/material.dart';

import '../../../data/tour_group_repository.dart';
import '../../../domain/models/tour_group.dart';
import '../family/family_home_card.dart';
import 'campus_home_card.dart';
import 'community_home_card.dart';
import 'mess_home_card.dart';
import 'office_home_card.dart';
import 'samity_home_card.dart';
import 'society_home_card.dart';

/// Central dispatcher widget that renders the purpose-driven home hero card for any group preset.
class PresetHomeCard extends StatelessWidget {
  const PresetHomeCard({
    super.key,
    required this.group,
    this.repository,
  });

  final TourGroup group;
  final TourGroupRepository? repository;

  @override
  Widget build(BuildContext context) {
    if (group.isHousehold) {
      return FamilyHomeCard(
        tourId: group.id,
        repository: repository,
      );
    }
    if (group.isMess) {
      return MessHomeCard(
        group: group,
        repository: repository,
      );
    }
    if (group.isSociety) {
      return SocietyHomeCard(
        group: group,
        repository: repository,
      );
    }
    if (group.isSamity) {
      return SamityHomeCard(
        group: group,
        repository: repository,
      );
    }
    if (group.isOffice) {
      return OfficeHomeCard(
        group: group,
        repository: repository,
      );
    }
    if (group.isCampus) {
      return CampusHomeCard(
        group: group,
        repository: repository,
      );
    }
    if (group.isSchool ||
        group.isSports ||
        group.isStudy ||
        group.isCommittee ||
        group.isFriends) {
      return CommunityHomeCard(
        group: group,
        repository: repository,
      );
    }
    return const SizedBox.shrink();
  }
}
