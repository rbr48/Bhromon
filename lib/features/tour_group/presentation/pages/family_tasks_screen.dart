import 'package:flutter/material.dart';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:bhromon/core/utils/logger.dart';
import 'package:bhromon/core/widgets/swipe_pager.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/family_task_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/family_task_rules.dart';
import '../widgets/family/family_task_composer.dart';
import '../widgets/family/family_task_dialogs.dart';
import '../widgets/family/family_task_empty_view.dart';
import '../widgets/family/family_task_shared.dart';
import '../widgets/family/family_task_tile.dart';
import '../widgets/group_back_button.dart';

/// What the screen knows about the member looking at the list. [members] is null until the
/// member list has loaded.
typedef _Viewer = ({
  String me,
  bool isAdmin,
  String? assignee,
  List<TourMember>? members,
});

/// A family circle's shared shopping and to-do list. Anyone in the circle adds an item and ticks
/// it off, and the tick records who did it and when. The item's creator or an admin changes its
/// text, its kind or its assignee, and removes it.
class FamilyTasksScreen extends StatefulWidget {
  const FamilyTasksScreen({super.key, required this.tourId, this.repository});

  final String tourId;

  /// The repository the screen reads and writes through. Tests pass a fake.
  final TourGroupRepository? repository;

  @override
  State<FamilyTasksScreen> createState() => _FamilyTasksScreenState();
}

class _FamilyTasksScreenState extends State<FamilyTasksScreen> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();
  late final Stream<List<TourMember>> _members;
  late Stream<List<FamilyTask>> _tasks;
  final TextEditingController _input = TextEditingController();
  final PageController _kindPager = PageController();
  FamilyTaskKind _kind = FamilyTaskKind.shopping;
  String? _assignee;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _members = _repository.watchMembers(widget.tourId);
    _tasks = _repository.watchFamilyTasks(widget.tourId);
  }

  @override
  void dispose() {
    _input.dispose();
    _kindPager.dispose();
    super.dispose();
  }

  /// What the screen knows about the member looking at the list. The role comes from the live
  /// member list, so a promotion or a removal shows at once. A member who has left the circle is
  /// no longer a choice, so the composer falls back to "Anyone" for them.
  _Viewer _viewerOf(List<TourMember>? members) {
    final people = members ?? const <TourMember>[];
    final me = _repository.currentEmail;
    var isAdmin = false;
    for (final member in people) {
      if (member.email == me) isAdmin = member.role.isAdminOrOwner;
    }
    final assigneeStillHere =
        members == null || people.any((m) => m.email == _assignee);
    return (
      me: me,
      isAdmin: isAdmin,
      assignee: assigneeStillHere ? _assignee : null,
      members: members,
    );
  }

  bool _canEdit(FamilyTask task, _Viewer viewer) =>
      viewer.isAdmin ||
      (task.createdByEmail.isNotEmpty && task.createdByEmail == viewer.me);

  void _toast(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, style: const TextStyle(color: Colors.white)),
        backgroundColor: error ? Colors.red.shade800 : AppColors.darkGreen,
      ),
    );
  }

  /// Runs one write. A write the server has not confirmed yet stays queued on this device, and
  /// the member is told so.
  Future<void> _save(Future<bool> Function() write, String label) async {
    final l10n = context.l10n;
    try {
      final synced = await write();
      if (!synced) _toast(l10n.translate('ft_saved_offline'));
    } catch (err) {
      logError('$label: $err');
      _toast(l10n.translate('ft_save_failed'), error: true);
    }
  }

  /// Adds one item of the shown kind. Returns true when it was saved, on the server or on this
  /// device. A full day is said so, and the caller keeps the draft.
  Future<bool> _submit(String title, String? assignee) async {
    final l10n = context.l10n;
    try {
      final synced = await _repository.addFamilyTask(
        widget.tourId,
        title: title,
        kind: _kind,
        assigneeEmail: assignee,
      );
      if (!synced) _toast(l10n.translate('ft_saved_offline'));
      return true;
    } on FamilyTaskDailyLimitException {
      _toast(
        l10n.translate(
          'ft_limit_reached',
          args: {'limit': l10n.number(familyTaskDailyLimit)},
        ),
        error: true,
      );
      return false;
    } catch (err) {
      logError('Family task add failed: $err');
      _toast(l10n.translate('ft_save_failed'), error: true);
      return false;
    }
  }

  /// Adds an item from the draft box, or from a suggestion. A suggestion leaves the draft alone,
  /// and the draft is cleared only when it still holds the text that was saved.
  Future<void> _addTitle(
    String title,
    String? assignee, {
    required bool fromDraft,
  }) async {
    if (title.isEmpty || _adding) return;
    setState(() => _adding = true);
    final saved = await _submit(title, assignee);
    if (!mounted) return;
    setState(() => _adding = false);
    if (fromDraft && saved && _input.text.trim() == title) _input.clear();
  }

  Future<void> _toggle(FamilyTask task, bool done) => _save(
        () => _repository.setFamilyTaskDone(widget.tourId, task.id, done),
        'Family task tick failed',
      );

  Future<void> _clearFinished(List<String> ids) async {
    final sure = await confirmClearFinished(context, ids.length);
    if (!sure || !mounted) return;
    await _save(
      () => _repository.clearFamilyTasks(widget.tourId, ids),
      'Family task clear failed',
    );
  }

  Future<void> _act(
    FamilyTask task,
    FamilyTaskAction action,
    _Viewer viewer,
  ) async {
    switch (action) {
      case FamilyTaskAction.rename:
        final title = await showFamilyTaskRename(context, task.title);
        if (title == null || title.isEmpty || !mounted) return;
        await _save(
          () => _repository.renameFamilyTask(widget.tourId, task.id, title),
          'Family task rename failed',
        );
      case FamilyTaskAction.assign:
        final email = await showFamilyTaskAssignee(
          context,
          members: viewer.members ?? const <TourMember>[],
        );
        if (email == null || !mounted) return;
        await _save(
          () => _repository.reassignFamilyTask(
            widget.tourId,
            task.id,
            email.isEmpty ? null : email,
          ),
          'Family task assign failed',
        );
      case FamilyTaskAction.moveKind:
        final kind = task.kind == FamilyTaskKind.shopping
            ? FamilyTaskKind.todo
            : FamilyTaskKind.shopping;
        await _save(
          () => _repository.setFamilyTaskKind(widget.tourId, task.id, kind),
          'Family task move failed',
        );
      case FamilyTaskAction.remove:
        final sure = await confirmFamilyTaskRemoval(context);
        if (!sure || !mounted) return;
        await _save(
          () => _repository.deleteFamilyTask(widget.tourId, task.id),
          'Family task delete failed',
        );
    }
  }

  /// Starts the list again after an error. The failed stream is dropped, and a new one listens.
  Future<void> _retry() async {
    await _repository.forgetFamilyTasks(widget.tourId);
    if (!mounted) return;
    setState(() => _tasks = _repository.watchFamilyTasks(widget.tourId));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return StreamBuilder<List<TourMember>>(
      stream: _members,
      builder: (context, memberSnap) {
        final viewer = _viewerOf(memberSnap.data);
        return GroupPopScope(
          tourId: widget.tourId,
          child: Scaffold(
            backgroundColor: context.forest.surfaceFor(familyTaskBackground),
            appBar: AppBar(
              leading: GroupBackButton(tourId: widget.tourId),
              title: Text(
                l10n.translate('ft_title'),
                style: TextStyle(
                  color: context.forest.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              backgroundColor: context.forest.surfaceFor(familyTaskCard),
              foregroundColor: context.forest.text,
              iconTheme: IconThemeData(color: context.forest.text),
              elevation: 0,
              actions: [
                IconButton(
                  icon: Icon(
                    Icons.info_outline_rounded,
                    color: context.forest.accentText,
                  ),
                  tooltip: l10n.translate('ft_scope_tooltip'),
                  onPressed: () => showFamilyTaskScope(context),
                ),
              ],
            ),
            body: Column(
              children: [
                Expanded(
                  child: StreamBuilder<List<FamilyTask>>(
                    stream: _tasks,
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return _ListMessage(
                          message: l10n.translate('ft_load_failed'),
                          onRetry: _retry,
                        );
                      }
                      final tasks = snap.data;
                      if (tasks == null) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.mintGreen,
                          ),
                        );
                      }
                      return _kindPages(tasks, viewer);
                    },
                  ),
                ),
                FamilyTaskComposer(
                  controller: _input,
                  kind: _kind,
                  onKind: (kind) => setState(() => _kind = kind),
                  members: viewer.members ?? const <TourMember>[],
                  assignee: viewer.assignee,
                  onAssignee: (email) => setState(() => _assignee = email),
                  adding: _adding,
                  onSend: () => _addTitle(
                    _input.text.trim(),
                    viewer.assignee,
                    fromDraft: true,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Two pages, shopping and to-dos, from the same stream. A swipe sets the kind a new item
  /// gets, and the kind chips move the pages. Only the shown page takes taps.
  Widget _kindPages(List<FamilyTask> tasks, _Viewer viewer) {
    const kinds = [FamilyTaskKind.shopping, FamilyTaskKind.todo];
    final index = kinds.indexOf(_kind);
    return SwipePager(
      controller: _kindPager,
      count: kinds.length,
      selectedIndex: index,
      onSettled: (i) => setState(() => _kind = kinds[i]),
      itemBuilder: (context, i) => IgnorePointer(
        ignoring: i != index,
        child: _page(tasks, kinds[i], viewer),
      ),
    );
  }

  Widget _page(List<FamilyTask> tasks, FamilyTaskKind kind, _Viewer viewer) {
    final l10n = context.l10n;
    final sections = familyTaskPage(tasks, kind);
    if (sections.isEmpty) {
      return FamilyTaskEmptyView(
        kind: kind,
        onSuggest: (title) =>
            _addTitle(title, viewer.assignee, fromDraft: false),
      );
    }
    final clearable = [
      for (final task in tasks)
        if (task.done && task.kind == kind && _canEdit(task, viewer)) task.id,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      children: [
        if (familyTaskListIsLong(tasks.length))
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
            child: Text(
              l10n.translate('ft_long_list'),
              style: TextStyle(color: context.forest.text54, fontSize: 12),
            ),
          ),
        for (final group in sections) ...[
          _sectionHeader(
            l10n.translate('ft_section_${group.section.name}'),
            trailing:
                group.section == FamilyTaskSection.done && clearable.isNotEmpty
                    ? TextButton(
                        onPressed: () => _clearFinished(clearable),
                        child: Text(l10n.translate('ft_clear_done')),
                      )
                    : null,
          ),
          for (final task in group.items) _tile(task, viewer),
        ],
      ],
    );
  }

  Widget _sectionHeader(String title, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: context.forest.accentText,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _tile(FamilyTask task, _Viewer viewer) {
    final l10n = context.l10n;
    final members = viewer.members;
    final notes = <String>[
      if (members != null && task.assigneeEmail != null)
        l10n.translate(
          'ft_for',
          args: {
            'name': familyTaskNameFor(members, task.assigneeEmail!, l10n),
          },
        ),
      if (members != null && task.done && task.doneByEmail != null)
        l10n.translate(
          'ft_ticked_by',
          args: {
            'name': familyTaskNameFor(members, task.doneByEmail!, l10n),
          },
        ),
    ];
    return FamilyTaskTile(
      task: task,
      note: notes.isEmpty ? null : notes.join(' · '),
      canEdit: _canEdit(task, viewer),
      onToggle: (done) => _toggle(task, done),
      onAction: (action) => _act(task, action, viewer),
    );
  }
}

/// A message in place of the list. When the list failed to load, it offers a retry.
class _ListMessage extends StatelessWidget {
  const _ListMessage({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.forest.text70, fontSize: 14),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onRetry,
                child: Text(l10n.translate('ft_try_again')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
