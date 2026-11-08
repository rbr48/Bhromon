import 'package:flutter/material.dart';

import 'package:bhromon/core/theme/forest_palette.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/widgets/swipe_pager.dart';
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
  final PageController _kindPager = PageController();
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
    _kindPager.dispose();
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
        backgroundColor: context.forest.surfaceFor(_card),
        title: Text(l10n.translate('ft_delete_title'),
            style: TextStyle(color: context.forest.text)),
        content: Text(l10n.translate('ft_delete_body'),
            style: TextStyle(color: context.forest.text70)),
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
          backgroundColor: context.forest.surfaceFor(_bg),
          appBar: AppBar(
            title: Text(l10n.translate('ft_title'),
                style: TextStyle(
                    color: context.forest.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
            backgroundColor: context.forest.surfaceFor(_card),
            foregroundColor: context.forest.text,
            iconTheme: IconThemeData(color: context.forest.text),
            elevation: 0,
            actions: [
              IconButton(
                icon: Icon(Icons.info_outline_rounded,
                    color: context.forest.accentText),
                tooltip: l10n.isBn ? 'কার্যপরিধি ও সহায়তা' : 'Scope & Help',
                onPressed: () => _showScopeInfo(context, l10n),
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
                    return _kindPages(tasks, members, l10n);
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

  /// Two pages, shopping and to-dos, from the same stream. A swipe sets the kind a
  /// new item gets, and the kind chips move the pages. Only the shown page takes
  /// taps.
  Widget _kindPages(
      List<FamilyTask> tasks, List<TourMember> members, AppLocalizations l10n) {
    const kinds = [FamilyTaskKind.shopping, FamilyTaskKind.todo];
    final index = kinds.indexOf(_kind);
    return SwipePager(
      controller: _kindPager,
      count: kinds.length,
      selectedIndex: index,
      onSettled: (i) => setState(() => _kind = kinds[i]),
      itemBuilder: (context, i) => IgnorePointer(
        ignoring: i != index,
        child: _list(tasks, kinds[i], members, l10n),
      ),
    );
  }

  Widget _list(List<FamilyTask> tasks, FamilyTaskKind kind,
      List<TourMember> members, AppLocalizations l10n) {
    final sections = familyTaskPage(tasks, kind);
    if (sections.isEmpty) return _emptyScopeView(l10n, kind);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      children: [
        for (final group in sections) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
            child: Text(l10n.translate('ft_section_${group.section.name}'),
                style: TextStyle(
                    color: context.forest.accentText,
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
      color: context.forest.surfaceFor(_card),
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: Checkbox(
          value: task.done,
          activeColor: AppColors.mintGreen,
          onChanged: (v) => _toggle(task, v ?? false),
        ),
        title: Text(task.title,
            style: TextStyle(
                color: task.done ? context.forest.text38 : context.forest.text,
                decoration: task.done ? TextDecoration.lineThrough : null)),
        subtitle: notes.isEmpty
            ? null
            : Text(notes.join(' · '),
                style: TextStyle(color: context.forest.text54, fontSize: 12)),
        trailing: editable
            ? PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded,
                    color: context.forest.text54, size: 20),
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
        color: context.forest.surfaceFor(_card),
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
                  backgroundColor:
                      context.forest.surfaceFor(const Color(0xFF1E3326)),
                  onSelected: (_) =>
                      setState(() => _kind = FamilyTaskKind.shopping),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: Text('✅ ${l10n.translate('ft_kind_todo')}',
                      style: const TextStyle(fontSize: 12)),
                  selected: _kind == FamilyTaskKind.todo,
                  selectedColor: AppColors.mintGreen,
                  backgroundColor:
                      context.forest.surfaceFor(const Color(0xFF1E3326)),
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
                    style: TextStyle(color: context.forest.text),
                    decoration: InputDecoration(
                      hintText: l10n.translate('ft_add_hint'),
                      hintStyle: TextStyle(color: context.forest.text38),
                      counterText: '',
                    ),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                IconButton(
                  tooltip: l10n.translate('ft_add_hint'),
                  onPressed: _adding ? null : _add,
                  icon: Icon(Icons.send_rounded,
                      color: context.forest.accentText),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyScopeView(AppLocalizations l10n, FamilyTaskKind kind) {
    final isBn = l10n.isBn;
    final isShopping = kind == FamilyTaskKind.shopping;
    final suggestions = isShopping
        ? (isBn
            ? [
                'মুদি বাজার',
                'কাঁচাবাজার',
                'ওষুধ আনা',
                'দুধ ও ফলমূল',
                'স্টেশনারি'
              ]
            : [
                'Groceries',
                'Fresh vegetables',
                'Medicines',
                'Milk & Fruits',
                'Stationery'
              ])
        : (isBn
            ? [
                'বিদ্যুৎ বিল পরিশোধ',
                'রুম পরিষ্কার',
                'টিকেট বুকিং',
                'লন্ড্রি করা',
                'প্যাকিং সম্পন্ন'
              ]
            : [
                'Pay electricity bill',
                'Clean room',
                'Book tickets',
                'Laundry',
                'Finish packing'
              ]);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.mintGreen.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isShopping
                    ? Icons.shopping_basket_outlined
                    : Icons.playlist_add_check_rounded,
                color: context.forest.accentText,
                size: 40,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              isShopping
                  ? (isBn ? 'কেনাকাটার তালিকা খালি' : 'Shopping list is empty')
                  : (isBn ? 'করণীয় তালিকা খালি' : 'To-do list is empty'),
              style: TextStyle(
                color: context.forest.text,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isShopping
                  ? (isBn
                      ? 'প্রয়োজনীয় জিনিস লিখে রাখুন বা নিচের সাজেশনে ট্যাপ করুন'
                      : 'Add items you need or tap a quick suggestion')
                  : (isBn
                      ? 'যৌথ কাজ যোগ করুন বা সদস্যের নামে দায়িত্ব বণ্টন করুন'
                      : 'Add group tasks or assign chores to members'),
              textAlign: TextAlign.center,
              style: TextStyle(color: context.forest.text54, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final s in suggestions)
                  ActionChip(
                    backgroundColor: context.forest.surfaceFor(_card),
                    label: Text(s,
                        style: TextStyle(
                            color: context.forest.accentText, fontSize: 12)),
                    onPressed: () {
                      _input.text = s;
                      _add();
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showScopeInfo(BuildContext context, AppLocalizations l10n) {
    final isBn = l10n.isBn;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.forest.surfaceFor(_card),
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
                      color: context.forest.text38,
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
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.checklist_rtl_rounded,
                          color: AppColors.midGreen, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isBn
                                ? 'করণীয় মডিউলের কার্যপরিধি'
                                : 'To-do Activity Scope',
                            style: TextStyle(
                              color: context.forest.text,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            isBn
                                ? 'গ্রুপের সবার সমন্বিত কাজ ও পরিকল্পনা'
                                : 'Shared group coordination & planning',
                            style: TextStyle(
                              color: context.forest.text54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _scopeItem(
                  icon: Icons.shopping_cart_outlined,
                  title: isBn
                      ? 'বাজার ও প্রয়োজনীয় কেনাকাটা'
                      : 'Shopping & Groceries',
                  desc: isBn
                      ? 'পরিবারের মুদি বাজার, মেস ও ক্যাম্পাসের রসদ বা ট্যুরের প্রয়োজনীয় জিনিসপত্রের সম্মিলিত তালিকা।'
                      : 'Shared groceries, supplies, and shopping lists for household, mess, office, or trip.',
                ),
                _scopeItem(
                  icon: Icons.task_alt_rounded,
                  title: isBn
                      ? 'দৈনন্দিন কাজ ও গৃহস্থালি দায়িত্ব'
                      : 'Daily Chores & Tasks',
                  desc: isBn
                      ? 'বাসা বা মেসের বিল পরিশোধ, ঘর পরিষ্কার, লন্ড্রি বা রুটিনমাফিক কাজ।'
                      : 'Utility bills, room cleaning, laundry, maintenance, and routine group tasks.',
                ),
                _scopeItem(
                  icon: Icons.person_pin_circle_outlined,
                  title: isBn
                      ? 'সদস্যভিত্তিক দায়িত্ব বণ্টন'
                      : 'Member Assignment & Accountability',
                  desc: isBn
                      ? 'নির্দিষ্ট সদস্যকে দায়িত্ব প্রদান এবং কে কাজটি সম্পন্ন করেছেন তা স্বয়ংক্রিয়ভাবে সংরক্ষিত থাকা।'
                      : 'Assign items to specific members with transparent tracking of who checked them off.',
                ),
                _scopeItem(
                  icon: Icons.luggage_outlined,
                  title: isBn
                      ? 'ট্যুর ও ইভেন্ট প্রস্তুতি'
                      : 'Trip & Event Preparation',
                  desc: isBn
                      ? 'প্যাকিং প্রস্তুতি, টিকিট সংগ্রহ, রিজার্ভেশন ও যেকোনো পারিবারিক বা দলীয় অনুষ্ঠানের চেকলিস্ট।'
                      : 'Packing checklists, ticket collection, booking verifications, and event setup.',
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
                    child: Text(isBn ? 'বুঝেছি' : 'Got it',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _scopeItem({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: context.forest.accentText, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: context.forest.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: TextStyle(
                    color: context.forest.text70,
                    fontSize: 12.5,
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

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.forest.text70, fontSize: 14)),
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
      backgroundColor: context.forest.surfaceFor(_card),
      title: Text(l10n.translate('ft_rename_title'),
          style: TextStyle(color: context.forest.text)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 120,
        style: TextStyle(color: context.forest.text),
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
