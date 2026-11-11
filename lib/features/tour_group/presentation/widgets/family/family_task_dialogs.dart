import 'package:flutter/material.dart';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';

import 'family_task_shared.dart';

/// Asks for an item's new text. Returns the text, trimmed, or null when cancelled.
Future<String?> showFamilyTaskRename(BuildContext context, String current) {
  return showDialog<String>(
    context: context,
    builder: (_) => _RenameDialog(initial: current),
  );
}

/// Asks the member to confirm removing an item. Returns true when they do.
Future<bool> confirmFamilyTaskRemoval(BuildContext context) async {
  final l10n = context.l10n;
  final sure = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ctx.forest.surfaceFor(familyTaskCard),
      title: Text(
        l10n.translate('ft_delete_title'),
        style: TextStyle(color: ctx.forest.text),
      ),
      content: Text(
        l10n.translate('ft_delete_body'),
        style: TextStyle(color: ctx.forest.text70),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.translate('ft_cancel')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.amber,
            foregroundColor: AppColors.darkGreen,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.translate('ft_remove')),
        ),
      ],
    ),
  );
  return sure == true;
}

/// Asks the member to confirm clearing the finished items they may remove. Returns true when
/// they do.
Future<bool> confirmClearFinished(BuildContext context, int count) async {
  final l10n = context.l10n;
  final sure = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ctx.forest.surfaceFor(familyTaskCard),
      title: Text(
        l10n.translate('ft_clear_done_title'),
        style: TextStyle(color: ctx.forest.text),
      ),
      content: Text(
        l10n.translate(
          'ft_clear_done_body',
          args: {'count': l10n.number(count)},
        ),
        style: TextStyle(color: ctx.forest.text70),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.translate('ft_cancel')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.amber,
            foregroundColor: AppColors.darkGreen,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.translate('ft_clear_done')),
        ),
      ],
    ),
  );
  return sure == true;
}

/// Asks who an item is for. Returns the chosen member's email, an empty string for the whole
/// circle, or null when cancelled.
Future<String?> showFamilyTaskAssignee(
  BuildContext context, {
  required List<TourMember> members,
}) {
  final l10n = context.l10n;
  return showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      backgroundColor: ctx.forest.surfaceFor(familyTaskCard),
      title: Text(
        l10n.translate('ft_assign_title'),
        style: TextStyle(color: ctx.forest.text),
      ),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, ''),
          child: Text(
            l10n.translate('ft_anyone'),
            style: TextStyle(color: ctx.forest.text),
          ),
        ),
        for (final member in members)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, member.email),
            child: Text(
              familyTaskMemberName(member, l10n),
              style: TextStyle(color: ctx.forest.text),
            ),
          ),
      ],
    ),
  );
}

/// Shows what the shared list is for, and which circles have it.
void showFamilyTaskScope(BuildContext context) {
  final l10n = context.l10n;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.forest.surfaceFor(familyTaskCard),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ctx.forest.text38,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.mintGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.checklist_rtl_rounded,
                      color: AppColors.midGreen,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.translate('ft_scope_title'),
                          style: TextStyle(
                            color: ctx.forest.text,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          l10n.translate('ft_scope_subtitle'),
                          style: TextStyle(
                            color: ctx.forest.text54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _ScopeItem(
                icon: Icons.shopping_cart_outlined,
                title: l10n.translate('ft_scope_shopping_title'),
                body: l10n.translate('ft_scope_shopping_body'),
              ),
              _ScopeItem(
                icon: Icons.task_alt_rounded,
                title: l10n.translate('ft_scope_chores_title'),
                body: l10n.translate('ft_scope_chores_body'),
              ),
              _ScopeItem(
                icon: Icons.person_pin_circle_outlined,
                title: l10n.translate('ft_scope_members_title'),
                body: l10n.translate('ft_scope_members_body'),
              ),
              _ScopeItem(
                icon: Icons.event_outlined,
                title: l10n.translate('ft_scope_events_title'),
                body: l10n.translate('ft_scope_events_body'),
              ),
              Text(
                l10n.translate('ft_scope_excluded'),
                style: TextStyle(color: ctx.forest.text54, fontSize: 12),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.mintGreen,
                    foregroundColor: AppColors.darkGreen,
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    l10n.translate('ft_got_it'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ScopeItem extends StatelessWidget {
  const _ScopeItem({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final palette = context.forest;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: palette.accentText, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(
                    color: palette.text70,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The dialog that changes an item's text. It owns its controller, so the controller is
/// disposed with the dialog.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      backgroundColor: context.forest.surfaceFor(familyTaskCard),
      title: Text(
        l10n.translate('ft_rename_title'),
        style: TextStyle(color: context.forest.text),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 120,
        style: TextStyle(color: context.forest.text),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.translate('ft_cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(l10n.translate('ft_save')),
        ),
      ],
    );
  }
}
