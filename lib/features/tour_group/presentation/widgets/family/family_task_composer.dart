import 'package:flutter/material.dart';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:bhromon/features/tour_group/domain/models/family_task_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';

import 'family_task_shared.dart';

/// The bar under the list: the two kind chips, the member a new item is for, the text box
/// and the add button.
class FamilyTaskComposer extends StatelessWidget {
  const FamilyTaskComposer({
    super.key,
    required this.controller,
    required this.kind,
    required this.onKind,
    required this.members,
    required this.assignee,
    required this.onAssignee,
    required this.adding,
    required this.onSend,
  });

  final TextEditingController controller;
  final FamilyTaskKind kind;
  final ValueChanged<FamilyTaskKind> onKind;

  /// The active members, the only people an item can be given to.
  final List<TourMember> members;

  /// The member the new item is for, or null for the whole circle.
  final String? assignee;
  final ValueChanged<String?> onAssignee;

  /// True while an add is being saved, so a second one is not started.
  final bool adding;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final assigneeLabel = assignee == null
        ? l10n.translate('ft_anyone')
        : familyTaskNameFor(members, assignee!, l10n);
    return SafeArea(
      top: false,
      child: Container(
        color: palette.surfaceFor(familyTaskCard),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _kindChip(
                  context,
                  FamilyTaskKind.shopping,
                  '🛒 ${l10n.translate('ft_kind_shopping')}',
                ),
                const SizedBox(width: 6),
                _kindChip(
                  context,
                  FamilyTaskKind.todo,
                  '✅ ${l10n.translate('ft_kind_todo')}',
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  tooltip: l10n.translate('ft_for_label'),
                  onSelected: (email) =>
                      onAssignee(email.isEmpty ? null : email),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: '',
                      child: Text(l10n.translate('ft_anyone')),
                    ),
                    for (final member in members)
                      PopupMenuItem(
                        value: member.email,
                        child: Text(familyTaskMemberName(member, l10n)),
                      ),
                  ],
                  child: Chip(
                    avatar: const Icon(Icons.person_outline_rounded, size: 16),
                    label: Text(
                      '${l10n.translate('ft_for_label')}: $assigneeLabel',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    maxLength: 120,
                    style: TextStyle(color: palette.text),
                    decoration: InputDecoration(
                      hintText: l10n.translate('ft_add_hint'),
                      hintStyle: TextStyle(color: palette.text38),
                      counterText: '',
                    ),
                    onSubmitted: adding ? null : (_) => onSend(),
                  ),
                ),
                IconButton(
                  tooltip: l10n.translate('ft_send'),
                  onPressed: adding ? null : onSend,
                  icon: Icon(Icons.send_rounded, color: palette.accentText),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kindChip(BuildContext context, FamilyTaskKind value, String label) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: kind == value,
      selectedColor: AppColors.mintGreen,
      backgroundColor: context.forest.surfaceFor(AppColors.forestRaised),
      onSelected: (_) => onKind(value),
    );
  }
}
