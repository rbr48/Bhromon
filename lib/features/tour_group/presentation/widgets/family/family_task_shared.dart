import 'package:flutter/material.dart';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';

/// The page background and the card colour of the family list.
const Color familyTaskBackground = AppColors.tealPanelDeep;
const Color familyTaskCard = AppColors.tealPanel;

/// The name a member is shown by in the shared list: their name in the circle, or "A member"
/// when it is blank.
String familyTaskMemberName(TourMember member, AppLocalizations l10n) {
  final name = member.displayName.trim();
  return name.isEmpty ? l10n.translate('ft_unnamed') : name;
}

/// What the list calls [email]: the name of an active member, or "Former member" when they have
/// left the circle. It never shows their address.
String familyTaskNameFor(
  List<TourMember> members,
  String email,
  AppLocalizations l10n,
) {
  for (final member in members) {
    if (member.email == email) return familyTaskMemberName(member, l10n);
  }
  return l10n.translate('ft_former_member');
}
