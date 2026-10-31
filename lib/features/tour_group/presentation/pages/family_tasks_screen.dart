import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/utils/logger.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/family_task_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/family_task_rules.dart';

const _bg = Color(0xFF0F1A1C);
const _card = Color(0xFF142428);

/// A family circle's shared shopping and to-do list. Anyone in the circle adds an
/// item and ticks it off, and the tick says who did it. The item's creator or an
/// admin changes its text or removes it.
class FamilyTasksScreen extends StatefulWidget {
  const FamilyTasksScreen({super.key, required this.tourId});

  final String tourId;

  @override
  State<FamilyTasksScreen> createState() => _FamilyTasksScreenState();
}

class _FamilyTasksScreenState extends State<FamilyTasksScreen> {
  final TourGroupRepository _repository = TourGroupRepository();
  late final Stream<List<FamilyTask>> _tasks =
      _repository.watchFamilyTasks(widget.tourId);
  late final Stream<List<TourMember>> _members =
      _repository.watchMembers(widget.tourId);
  final TextEditingController _input = TextEditingController();
  FamilyTaskKind _kind = FamilyTaskKind.shopping;
  String? _assignee;
  TourRole? _myRole;
  bool _adding = false;

  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;
  String get _me => _repository.currentEmail;
  bool _canEdit(FamilyTask task) =>
      _isAdmin ||
      (task.createdByEmail.isNotEmpty && task.createdByEmail == _me);

  @override
  void initState() {
    super.initState();
    _repository.myRole(widget.tourId).then((role) {
      if (mounted) setState(() => _myRole = role);
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _toast(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.redAccent : AppColors.darkGreen));
  }

  Future<void> _add() async {
    final l10n = context.l10n;
    final title = _input.text.trim();
    if (title.isEmpty || _adding) return;
    setState(() => _adding = true);
    try {
      await _repository.addFamilyTask(
        widget.tourId,
        title: title,
        kind: _kind,
        assigneeEmail: _assignee,
      );
      if (!mounted) return;
      _input.clear();
      setState(() => _adding = false);
    } catch (err) {
      logError('Family task add failed: $err');
      if (!mounted) return;
      setState(() => _adding = false);
      _toast(l10n.translate('ft_save_failed'), error: true);
    }
  }

  Future<void> _toggle(FamilyTask task, bool done) async {
    final l10n = context.l10n;
    try {
      await _repository.setFamilyTaskDone(widget.tourId, task.id, done);
    } catch (err) {
      logError('Family task tick failed: $err');
      _toast(l10n.translate('ft_save_failed'), error: true);
    }
  }

  Future<void> _rename(FamilyTask task) async {
    final l10n = context.l10n;
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _RenamePrompt(initial: task.title),
    );
    if (title == null || title.isEmpty || !mounted) return;
    try {
      await _repository.editFamilyTask(
        widget.tourId,
        task.id,
        title: title,
        kind: task.kind,
        assigneeEmail: task.assigneeEmail,
      );
    } catch (err) {
      logError('Family task edit failed: $err');
      _toast(l10n.translate('ft_save_failed'), error: true);
    }
  }

  Future<void> _remove(FamilyTask task) async {
    final l10n = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text(l10n.translate('ft_delete_title'),
            style: const TextStyle(color: Colors.white)),
        content: Text(l10n.translate('ft_delete_body'),
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.translate('fd_cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.translate('fd_delete')),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    try {
      await _repository.deleteFamilyTask(widget.tourId, task.id);
    } catch (err) {
      logError('Family task delete failed: $err');
      _toast(l10n.translate('ft_save_failed'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return StreamBuilder<List<TourMember>>(
      stream: _members,
      builder: (context, memberSnap) {
        final members = memberSnap.data ?? const <TourMember>[];
        return Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            title: Text(l10n.translate('ft_title'),
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            backgroundColor: _card,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: Column(
            children: [
              Expanded(
                child: StreamBuilder<List<FamilyTask>>(
                  stream: _tasks,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return _message(l10n.translate('ft_load_failed'));
                    }
                    final tasks = snap.data;
                    if (tasks == null) {
                      return const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.mintGreen));
                    }
                    if (tasks.isEmpty) {
                      return _message(l10n.translate('ft_empty'));
                    }
                    return _list(tasks, members, l10n);
                  },
                ),
              ),
              _inputBar(l10n, members),
            ],
          ),
        );
      },
    );
  }

  Widget _list(
      List<FamilyTask> tasks, List<TourMember> members, AppLocalizations l10n) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      children: [
        for (final group in familyTaskSections(tasks)) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
            child: Text(l10n.translate('ft_section_${group.section.name}'),
                style: const TextStyle(
                    color: AppColors.mintGreen,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
          ),
          for (final task in group.items) _tile(task, members, l10n),
        ],
      ],
    );
  }

  Widget _tile(
      FamilyTask task, List<TourMember> members, AppLocalizations l10n) {
    final notes = <String>[
      if (task.assigneeEmail != null)
        l10n.translate('ft_for',
            args: {'name': _nameOf(members, task.assigneeEmail!)}),
      if (task.done && task.doneByEmail != null)
        l10n.translate('ft_ticked_by',
            args: {'name': _nameOf(members, task.doneByEmail!)}),
    ];
    final editable = _canEdit(task);
    return Card(
      color: _card,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: Checkbox(
          value: task.done,
          activeColor: AppColors.mintGreen,
          onChanged: (v) => _toggle(task, v ?? false),
        ),
        title: Text(task.title,
            style: TextStyle(
                color: task.done ? Colors.white38 : Colors.white,
                decoration: task.done ? TextDecoration.lineThrough : null)),
        subtitle: notes.isEmpty
            ? null
            : Text(notes.join(' · '),
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
        trailing: editable
            ? PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded,
                    color: Colors.white54, size: 20),
                onSelected: (v) => v == 'edit' ? _rename(task) : _remove(task),
                itemBuilder: (_) => [
                  PopupMenuItem(
                      value: 'edit', child: Text(l10n.translate('ft_edit'))),
                  PopupMenuItem(
                      value: 'remove',
                      child: Text(l10n.translate('ft_remove'))),
                ],
              )
            : null,
      ),
    );
  }

  Widget _inputBar(AppLocalizations l10n, List<TourMember> members) {
    final assigneeLabel = _assignee == null
        ? l10n.translate('ft_anyone')
        : _nameOf(members, _assignee!);
    return SafeArea(
      top: false,
      child: Container(
        color: _card,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ChoiceChip(
                  label: Text('🛒 ${l10n.translate('ft_kind_shopping')}',
                      style: const TextStyle(fontSize: 12)),
                  selected: _kind == FamilyTaskKind.shopping,
                  selectedColor: AppColors.mintGreen,
                  backgroundColor: const Color(0xFF1E3326),
                  onSelected: (_) =>
                      setState(() => _kind = FamilyTaskKind.shopping),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: Text('✅ ${l10n.translate('ft_kind_todo')}',
                      style: const TextStyle(fontSize: 12)),
                  selected: _kind == FamilyTaskKind.todo,
                  selectedColor: AppColors.mintGreen,
                  backgroundColor: const Color(0xFF1E3326),
                  onSelected: (_) =>
                      setState(() => _kind = FamilyTaskKind.todo),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  tooltip: l10n.translate('ft_for_label'),
                  onSelected: (v) =>
                      setState(() => _assignee = v.isEmpty ? null : v),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                        value: '', child: Text(l10n.translate('ft_anyone'))),
                    for (final m in members)
                      PopupMenuItem(
                          value: m.email,
                          child: Text(
                              m.displayName.isEmpty ? m.email : m.displayName)),
                  ],
                  child: Chip(
                    avatar: const Icon(Icons.person_outline_rounded, size: 16),
                    label: Text(
                        '${l10n.translate('ft_for_label')}: $assigneeLabel',
                        style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    maxLength: 120,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: l10n.translate('ft_add_hint'),
                      hintStyle: const TextStyle(color: Colors.white38),
                      counterText: '',
                    ),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                IconButton(
                  tooltip: l10n.translate('ft_add_hint'),
                  onPressed: _adding ? null : _add,
                  icon: const Icon(Icons.send_rounded,
                      color: AppColors.mintGreen),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14)),
        ),
      );

  String _nameOf(List<TourMember> members, String email) {
    for (final m in members) {
      if (m.email == email && m.displayName.isNotEmpty) return m.displayName;
    }
    return email;
  }
}

/// The dialog that changes an item's text. It owns its controller, so the
/// controller is disposed with the dialog.
class _RenamePrompt extends StatefulWidget {
  const _RenamePrompt({required this.initial});

  final String initial;

  @override
  State<_RenamePrompt> createState() => _RenamePromptState();
}

class _RenamePromptState extends State<_RenamePrompt> {
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
      backgroundColor: _card,
      title: Text(l10n.translate('ft_rename_title'),
          style: const TextStyle(color: Colors.white)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 120,
        style: const TextStyle(color: Colors.white),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.translate('fd_cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(l10n.translate('fd_save')),
        ),
      ],
    );
  }
}
