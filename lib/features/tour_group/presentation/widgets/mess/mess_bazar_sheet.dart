import 'package:flutter/material.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/localization/localized_date.dart';
import '../../../../../core/theme/colors.dart';
import '../../../../../core/theme/forest_palette.dart';
import '../../../data/tour_group_repository.dart';
import '../../../domain/models/date_codec.dart';
import '../../../domain/models/mess_bazar_model.dart';
import '../../../domain/models/tour_group.dart';
import '../../../domain/services/meal_engine.dart';

const _sheetBg = Color(0xFF142428);
const _cardBg = Color(0xFF1B2E33);

/// Opens the Mess Bazar Duty & Routine manager bottom sheet.
Future<void> showMessBazarSheet(
  BuildContext context, {
  required String tourId,
  required bool isAdmin,
  required List<TourMember> members,
  String? initialDateKey,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => MessBazarSheet(
      tourId: tourId,
      isAdmin: isAdmin,
      members: members,
      initialDateKey: initialDateKey,
    ),
  );
}

class MessBazarSheet extends StatefulWidget {
  const MessBazarSheet({
    super.key,
    required this.tourId,
    required this.isAdmin,
    required this.members,
    this.initialDateKey,
  });

  final String tourId;
  final bool isAdmin;
  final List<TourMember> members;
  final String? initialDateKey;

  @override
  State<MessBazarSheet> createState() => _MessBazarSheetState();
}

class _MessBazarSheetState extends State<MessBazarSheet> {
  final TourGroupRepository _repo = TourGroupRepository();
  late DateTime _selectedDate;

  String get _dateKey => mealDateKey(_selectedDate);
  String get _myEmail => normalizeEmail(_repo.currentEmail);

  @override
  void initState() {
    super.initState();
    if (widget.initialDateKey != null) {
      _selectedDate =
          DateTime.tryParse(widget.initialDateKey!) ?? DateTime.now();
    } else {
      _selectedDate = DateTime.now();
    }
  }

  void _stepDay(int days) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: AppColors.mintGreen,
              surface: context.forest.surfaceFor(_cardBg),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  String _nameForEmail(String email) {
    final clean = normalizeEmail(email);
    for (final m in widget.members) {
      if (normalizeEmail(m.email) == clean) {
        return m.displayName.isNotEmpty
            ? m.displayName
            : m.email.split('@').first;
      }
    }
    return email.split('@').first;
  }

  Future<void> _toggleComplete(MessBazarSchedule schedule) async {
    try {
      final updated = schedule.copyWith(isCompleted: !schedule.isCompleted);
      await _repo.saveBazarSchedule(widget.tourId, updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.translate('mess_bazar_save_success')),
            backgroundColor: AppColors.darkGreen,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: AppColors.amber,
          ),
        );
      }
    }
  }

  Future<void> _openAssignDialog([MessBazarSchedule? existing]) async {
    final selectedEmails = <String>{
      ...?existing?.assignedEmails.map(normalizeEmail),
    };
    final budgetCtrl = TextEditingController(
      text: existing?.estimatedBudgetPaisa != null
          ? (existing!.estimatedBudgetPaisa! ~/ 100).toString()
          : '',
    );
    final noteCtrl = TextEditingController(text: existing?.note ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final l10n = ctx.l10n;
          return AlertDialog(
            backgroundColor: ctx.forest.surfaceFor(_cardBg),
            title: Text(
              l10n.translate('mess_bazar_assign_btn'),
              style: TextStyle(color: ctx.forest.text, fontSize: 16),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    localizedDateFormat('EEEE, d MMMM yyyy')
                        .format(_selectedDate),
                    style:
                        TextStyle(color: ctx.forest.accentText, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.translate('mess_bazar_assigned_to'),
                    style: TextStyle(
                      color: ctx.forest.text70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final member in widget.members)
                        FilterChip(
                          selected: selectedEmails
                              .contains(normalizeEmail(member.email)),
                          label: Text(
                            member.displayName.isNotEmpty
                                ? member.displayName
                                : member.email.split('@').first,
                            style: const TextStyle(fontSize: 12),
                          ),
                          selectedColor: AppColors.mintGreen,
                          onSelected: (sel) {
                            setDialogState(() {
                              final email = normalizeEmail(member.email);
                              if (sel) {
                                selectedEmails.add(email);
                              } else {
                                selectedEmails.remove(email);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: budgetCtrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: ctx.forest.text),
                    decoration: InputDecoration(
                      labelText: l10n.translate('mess_bazar_budget_hint'),
                      labelStyle: TextStyle(color: ctx.forest.text70),
                      prefixText: '৳ ',
                      prefixStyle: TextStyle(color: ctx.forest.accentText),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteCtrl,
                    maxLines: 2,
                    style: TextStyle(color: ctx.forest.text),
                    decoration: InputDecoration(
                      labelText: l10n.translate('mess_bazar_note_hint'),
                      labelStyle: TextStyle(color: ctx.forest.text70),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child:
                    const Text('বাতিল', style: TextStyle(color: Colors.grey)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.mintGreen),
                onPressed: () {
                  if (selectedEmails.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                          content: Text('কমপক্ষে একজন সদস্য নির্বাচন করুন')),
                    );
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('সংরক্ষণ করুন',
                    style: TextStyle(color: AppColors.darkGreen)),
              ),
            ],
          );
        },
      ),
    );

    if (result == true && mounted) {
      final budgetTaka = int.tryParse(budgetCtrl.text.trim());
      final budgetPaisa =
          budgetTaka != null && budgetTaka > 0 ? budgetTaka * 100 : null;
      final assignedNames = selectedEmails.map(_nameForEmail).toList();

      final schedule = MessBazarSchedule(
        dateKey: _dateKey,
        assignedEmails: selectedEmails.toList(),
        assignedNames: assignedNames,
        note: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
        estimatedBudgetPaisa: budgetPaisa,
        isCompleted: existing?.isCompleted ?? false,
        actualExpensePaisa: existing?.actualExpensePaisa,
        expenseId: existing?.expenseId,
      );

      await _repo.saveBazarSchedule(widget.tourId, schedule);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.translate('mess_bazar_save_success')),
            backgroundColor: AppColors.darkGreen,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isToday = mealDateKey(DateTime.now()) == _dateKey;

    return Container(
      decoration: BoxDecoration(
        color: context.forest.surfaceFor(_sheetBg),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.storefront_rounded,
                      color: context.forest.accentText, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.translate('mess_bazar_duty_title'),
                      style: TextStyle(
                        color: context.forest.text,
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Date navigation bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: context.forest.surfaceFor(_cardBg),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded),
                    onPressed: () => _stepDay(-1),
                    tooltip: 'পূর্ববর্তী দিন',
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  localizedDateFormat('EEE, d MMM yyyy')
                                      .format(_selectedDate),
                                  style: TextStyle(
                                    color: isToday
                                        ? AppColors.mintGreen
                                        : context.forest.text,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.calendar_today_rounded,
                                    size: 14, color: Colors.grey),
                              ],
                            ),
                            if (isToday)
                              Text(
                                'আজকের দিন',
                                style: TextStyle(
                                  color: AppColors.mintGreen
                                      .withValues(alpha: 0.8),
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded),
                    onPressed: () => _stepDay(1),
                    tooltip: 'পরবর্তী দিন',
                  ),
                ],
              ),
            ),
            // Content
            StreamBuilder<MessBazarSchedule?>(
              stream: _repo.watchBazarScheduleForDay(widget.tourId, _dateKey),
              builder: (context, snapshot) {
                final schedule = snapshot.data;
                final isAssignedToMe = schedule?.isAssigned(_myEmail) ?? false;
                final canModify = widget.isAdmin || isAssignedToMe;

                if (schedule == null || schedule.assignedEmails.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(Icons.event_busy_rounded,
                            size: 48, color: context.forest.text38),
                        const SizedBox(height: 12),
                        Text(
                          l10n.translate('mess_bazar_no_duty'),
                          style: TextStyle(
                              color: context.forest.text70, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                        if (widget.isAdmin) ...[
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.mintGreen,
                              foregroundColor: AppColors.darkGreen,
                            ),
                            onPressed: () => _openAssignDialog(),
                            icon: const Icon(Icons.add_task_rounded, size: 18),
                            label:
                                Text(l10n.translate('mess_bazar_assign_btn')),
                          ),
                        ],
                      ],
                    ),
                  );
                }

                // Render duty details
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: context.forest.surfaceFor(_cardBg),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: schedule.isCompleted
                            ? AppColors.mintGreen.withValues(alpha: 0.4)
                            : AppColors.gold.withValues(alpha: 0.3),
                      ),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Status badge & toggle
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: schedule.isCompleted
                                    ? AppColors.darkGreen
                                    : const Color(0xFF332A15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    schedule.isCompleted
                                        ? Icons.check_circle_rounded
                                        : Icons.schedule_rounded,
                                    size: 14,
                                    color: schedule.isCompleted
                                        ? AppColors.mintGreen
                                        : AppColors.gold,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    schedule.isCompleted
                                        ? l10n.translate('mess_bazar_completed')
                                        : l10n.translate('mess_bazar_pending'),
                                    style: TextStyle(
                                      color: schedule.isCompleted
                                          ? AppColors.mintGreen
                                          : AppColors.gold,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            if (widget.isAdmin)
                              IconButton(
                                icon: const Icon(Icons.edit_rounded, size: 18),
                                color: context.forest.accentText,
                                onPressed: () => _openAssignDialog(schedule),
                                tooltip: 'সম্পাদনা করুন',
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Assigned members
                        Text(
                          l10n.translate('mess_bazar_assigned_to'),
                          style: TextStyle(
                              color: context.forest.text54, fontSize: 12),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final email in schedule.assignedEmails)
                              Chip(
                                avatar: CircleAvatar(
                                  backgroundColor: AppColors.mintGreen,
                                  child: Text(
                                    _nameForEmail(email)
                                        .characters
                                        .first
                                        .toUpperCase(),
                                    style: const TextStyle(
                                      color: AppColors.darkGreen,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                label: Text(
                                  _nameForEmail(email),
                                  style: TextStyle(
                                    color: normalizeEmail(email) == _myEmail
                                        ? AppColors.mintGreen
                                        : context.forest.text,
                                    fontWeight:
                                        normalizeEmail(email) == _myEmail
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                    fontSize: 12,
                                  ),
                                ),
                                backgroundColor:
                                    context.forest.surfaceFor(_sheetBg),
                              ),
                          ],
                        ),
                        if (schedule.estimatedBudgetPaisa != null) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(Icons.account_balance_wallet_outlined,
                                  size: 16, color: context.forest.accentText),
                              const SizedBox(width: 6),
                              Text(
                                'আনুমানিক বাজেট: ৳ ${schedule.estimatedBudgetPaisa! ~/ 100}',
                                style: TextStyle(
                                  color: context.forest.text,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (schedule.note != null &&
                            schedule.note!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.notes_rounded,
                                  size: 16, color: context.forest.text54),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  schedule.note!,
                                  style: TextStyle(
                                      color: context.forest.text70,
                                      fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                        if (canModify)
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: schedule.isCompleted
                                    ? AppColors.gold
                                    : AppColors.mintGreen,
                                side: BorderSide(
                                  color: schedule.isCompleted
                                      ? AppColors.gold
                                      : AppColors.mintGreen,
                                ),
                              ),
                              onPressed: () => _toggleComplete(schedule),
                              icon: Icon(
                                schedule.isCompleted
                                    ? Icons.undo_rounded
                                    : Icons.check_circle_outline_rounded,
                              ),
                              label: Text(
                                schedule.isCompleted
                                    ? 'অসম্পূর্ণ চিহ্নিত করুন'
                                    : l10n
                                        .translate('mess_bazar_mark_completed'),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
