import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../domain/models/channel_models.dart';
import '../../domain/models/tour_group.dart';

const Color _sheetColor = Color(0xFF1F2C34);

RoundedRectangleBorder _sheetShape() => const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    );

/// What the reader picked from the message sheet: a reaction, or an action.
enum ChannelAction { reply, edit, copy, pin, unpin, delete }

class ChannelActionChoice {
  final String? emoji;
  final ChannelAction? action;

  const ChannelActionChoice.react(String this.emoji) : action = null;

  const ChannelActionChoice.perform(ChannelAction this.action) : emoji = null;
}

/// The sheet opened by a long press on a message.
Future<ChannelActionChoice?> showChannelMessageActions(
  BuildContext context, {
  required ChannelMessage message,
  required bool isMine,
  required bool isAdmin,
  required String? myReaction,
}) {
  return showModalBottomSheet<ChannelActionChoice>(
    context: context,
    backgroundColor: _sheetColor,
    shape: _sheetShape(),
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (final emoji in kQuickReactions)
                  InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => Navigator.pop(
                        context, ChannelActionChoice.react(emoji)),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: myReaction == emoji
                            ? AppColors.mintGreen.withValues(alpha: 0.35)
                            : Colors.transparent,
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 24)),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          const _ActionTile(
            icon: Icons.reply,
            label: 'chan_action_reply',
            action: ChannelAction.reply,
          ),
          if (message.kind == ChannelMessageKind.text && isMine)
            const _ActionTile(
              icon: Icons.edit_outlined,
              label: 'chan_action_edit',
              action: ChannelAction.edit,
            ),
          if (message.text.isNotEmpty)
            const _ActionTile(
              icon: Icons.copy,
              label: 'chan_action_copy',
              action: ChannelAction.copy,
            ),
          if (isAdmin)
            _ActionTile(
              icon: Icons.push_pin_outlined,
              label: message.isPinned ? 'chan_action_unpin' : 'chan_action_pin',
              action:
                  message.isPinned ? ChannelAction.unpin : ChannelAction.pin,
            ),
          if (isMine || isAdmin)
            const _ActionTile(
              icon: Icons.delete_outline,
              label: 'chan_action_delete',
              action: ChannelAction.delete,
              danger: true,
            ),
        ],
      ),
    ),
  );
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final ChannelAction action;
  final bool danger;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.action,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? Colors.redAccent : Colors.white;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(context.l10n.translate(label),
          style: TextStyle(color: color, fontSize: 14)),
      onTap: () => Navigator.pop(context, ChannelActionChoice.perform(action)),
    );
  }
}

/// Where a new attachment comes from.
enum AttachSource { photos, camera, video }

Future<AttachSource?> showAttachSheet(BuildContext context) {
  final l10n = context.l10n;
  return showModalBottomSheet<AttachSource>(
    context: context,
    backgroundColor: _sheetColor,
    shape: _sheetShape(),
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined,
                color: AppColors.mintGreen),
            title: Text(l10n.translate('chan_attach_photos'),
                style: const TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(context, AttachSource.photos),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined,
                color: AppColors.mintGreen),
            title: Text(l10n.translate('chan_attach_camera'),
                style: const TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(context, AttachSource.camera),
          ),
          ListTile(
            leading:
                const Icon(Icons.videocam_outlined, color: AppColors.mintGreen),
            title: Text(l10n.translate('chan_attach_video'),
                style: const TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(context, AttachSource.video),
          ),
        ],
      ),
    ),
  );
}

/// The name, topic and posting rule a channel is saved with.
class ChannelDraft {
  final String name;
  final String topic;
  final bool adminOnly;

  const ChannelDraft({
    required this.name,
    required this.topic,
    required this.adminOnly,
  });
}

/// Asks for a channel's details. The name is only asked for when
/// [nameEditable] is true, which is never the case for a built-in channel.
Future<ChannelDraft?> showChannelEditor(
  BuildContext context, {
  required String title,
  required bool nameEditable,
  TourChannel? existing,
}) {
  return showDialog<ChannelDraft>(
    context: context,
    builder: (_) => _ChannelEditorDialog(
      title: title,
      nameEditable: nameEditable,
      existing: existing,
    ),
  );
}

class _ChannelEditorDialog extends StatefulWidget {
  final String title;
  final bool nameEditable;
  final TourChannel? existing;

  const _ChannelEditorDialog({
    required this.title,
    required this.nameEditable,
    required this.existing,
  });

  @override
  State<_ChannelEditorDialog> createState() => _ChannelEditorDialogState();
}

class _ChannelEditorDialogState extends State<_ChannelEditorDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _topic =
      TextEditingController(text: widget.existing?.topic ?? '');
  late bool _adminOnly = widget.existing?.adminOnly ?? false;
  bool _nameMissing = false;

  @override
  void dispose() {
    _name.dispose();
    _topic.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (widget.nameEditable && name.isEmpty) {
      setState(() => _nameMissing = true);
      return;
    }
    Navigator.pop(
      context,
      ChannelDraft(
          name: name, topic: _topic.text.trim(), adminOnly: _adminOnly),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      backgroundColor: _sheetColor,
      title: Text(widget.title, style: const TextStyle(color: Colors.white)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.nameEditable)
              TextField(
                controller: _name,
                autofocus: true,
                maxLength: 40,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: l10n.translate('chan_name_label'),
                  labelStyle: const TextStyle(color: Colors.white60),
                  errorText: _nameMissing
                      ? l10n.translate('chan_name_required')
                      : null,
                ),
              ),
            TextField(
              controller: _topic,
              maxLength: 200,
              minLines: 1,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: l10n.translate('chan_topic_label'),
                labelStyle: const TextStyle(color: Colors.white60),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: AppColors.mintGreen,
              title: Text(l10n.translate('chan_admin_only_label'),
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
              value: _adminOnly,
              onChanged: (v) => setState(() => _adminOnly = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.translate('tour_cancel')),
        ),
        ElevatedButton(
          onPressed: _save,
          child: Text(l10n.translate('tour_save')),
        ),
      ],
    );
  }
}

/// Everyone in the tour, with their role and where they sit or sleep.
Future<void> showChannelMembersSheet(
  BuildContext context, {
  required List<TourMember> members,
  required String myEmail,
  required String Function(String email) badgeFor,
}) {
  final l10n = context.l10n;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _sheetColor,
    shape: _sheetShape(),
    builder: (_) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                l10n.translate('chan_members_title'),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
            ),
            for (final m in members)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.midGreen,
                  child: Text(
                    m.displayName.isEmpty ? '?' : m.displayName.substring(0, 1),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Text(
                  m.email == myEmail
                      ? '${m.displayName} (${l10n.translate('chan_you')})'
                      : m.displayName,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  _roleLabel(l10n, m.role),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                trailing: badgeFor(m.email).isEmpty
                    ? null
                    : Text(
                        badgeFor(m.email),
                        style: const TextStyle(
                            color: AppColors.mintGreen, fontSize: 11),
                      ),
              ),
          ],
        ),
      ),
    ),
  );
}

String _roleLabel(AppLocalizations l10n, TourRole role) {
  switch (role) {
    case TourRole.owner:
      return l10n.translate('chan_role_owner');
    case TourRole.admin:
      return l10n.translate('chan_role_admin');
    case TourRole.member:
      return l10n.translate('chan_role_member');
  }
}
