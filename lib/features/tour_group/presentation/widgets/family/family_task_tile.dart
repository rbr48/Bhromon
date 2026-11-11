import 'package:flutter/material.dart';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:bhromon/features/tour_group/domain/models/family_task_models.dart';

import 'family_task_shared.dart';

/// What the menu of an item can do. Only the item's creator or an admin sees the menu.
enum FamilyTaskAction { rename, assign, moveKind, remove }

/// One item of the shared list: its tick, its text, a line on who it is for and who ticked it,
/// and the menu for the members who may change it.
class FamilyTaskTile extends StatelessWidget {
  const FamilyTaskTile({
    super.key,
    required this.task,
    required this.note,
    required this.canEdit,
    required this.onToggle,
    required this.onAction,
  });

  final FamilyTask task;

  /// The line under the text, or null when there is none to show.
  final String? note;
  final bool canEdit;
  final ValueChanged<bool> onToggle;
  final ValueChanged<FamilyTaskAction> onAction;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final moveLabel = task.kind == FamilyTaskKind.shopping
        ? l10n.translate('ft_move_to_todo')
        : l10n.translate('ft_move_to_buy');
    return Card(
      color: palette.surfaceFor(familyTaskCard),
      margin: const EdgeInsets.only(bottom: 6),
      child: CheckboxListTile(
        value: task.done,
        onChanged: (value) => onToggle(value ?? false),
        activeColor: AppColors.mintGreen,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          task.isUntitled ? l10n.translate('ft_untitled') : task.title,
          style: TextStyle(
            color: task.done ? palette.text38 : palette.text,
            fontStyle: task.isUntitled ? FontStyle.italic : null,
            decoration: task.done ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: note == null
            ? null
            : Text(
                note!,
                style: TextStyle(color: palette.text54, fontSize: 12),
              ),
        secondary: canEdit
            ? PopupMenuButton<FamilyTaskAction>(
                tooltip: l10n.translate('ft_item_options'),
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: palette.text54,
                  size: 20,
                ),
                onSelected: onAction,
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: FamilyTaskAction.rename,
                    child: Text(l10n.translate('ft_edit')),
                  ),
                  PopupMenuItem(
                    value: FamilyTaskAction.assign,
                    child: Text(l10n.translate('ft_assign_action')),
                  ),
                  PopupMenuItem(
                    value: FamilyTaskAction.moveKind,
                    child: Text(moveLabel),
                  ),
                  PopupMenuItem(
                    value: FamilyTaskAction.remove,
                    child: Text(l10n.translate('ft_remove')),
                  ),
                ],
              )
            : null,
      ),
    );
  }
}
