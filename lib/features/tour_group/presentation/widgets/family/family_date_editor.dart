import 'package:flutter/material.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/localization/localized_date.dart';
import '../../../../../core/theme/colors.dart';
import '../../../../../core/utils/logger.dart';
import '../../../data/tour_group_repository.dart';
import '../../../domain/models/family_date_models.dart';

const _sheet = Color(0xFF142428);
const _chip = Color(0xFF1E3326);

/// Adds a family date, or shows and changes an existing one. Returns true when
/// the list changed (a date was saved or removed).
///
/// [presetTitle], [presetDate], [presetKind], [presetRecurrence] and
/// [presetRemindDays] pre-fill a new date, such as one taken from the holiday
/// calendar. [canEdit] false shows a date read-only, for members who may not
/// change it.
Future<bool> showFamilyDateEditor(
  BuildContext context, {
  required String tourId,
  required TourGroupRepository repository,
  FamilyDate? existing,
  bool canEdit = true,
  String? presetTitle,
  DateTime? presetDate,
  FamilyDateKind? presetKind,
  FamilyRecurrence? presetRecurrence,
  int? presetRemindDays,
}) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _sheet,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _FamilyDateEditor(
      tourId: tourId,
      repository: repository,
      existing: existing,
      canEdit: canEdit,
      presetTitle: presetTitle,
      presetDate: presetDate,
      presetKind: presetKind,
      presetRecurrence: presetRecurrence,
      presetRemindDays: presetRemindDays,
    ),
  );
  return changed ?? false;
}

class _FamilyDateEditor extends StatefulWidget {
  const _FamilyDateEditor({
    required this.tourId,
    required this.repository,
    required this.canEdit,
    this.existing,
    this.presetTitle,
    this.presetDate,
    this.presetKind,
    this.presetRecurrence,
    this.presetRemindDays,
  });

  final String tourId;
  final TourGroupRepository repository;
  final FamilyDate? existing;
  final bool canEdit;
  final String? presetTitle;
  final DateTime? presetDate;
  final FamilyDateKind? presetKind;
  final FamilyRecurrence? presetRecurrence;
  final int? presetRemindDays;

  @override
  State<_FamilyDateEditor> createState() => _FamilyDateEditorState();
}

class _FamilyDateEditorState extends State<_FamilyDateEditor> {
  late final FamilyDate? _e = widget.existing;
  late final TextEditingController _title =
      TextEditingController(text: _e?.title ?? widget.presetTitle ?? '');
  late final TextEditingController _note =
      TextEditingController(text: _e?.note ?? '');
  late FamilyDateKind _kind =
      _e?.kind ?? widget.presetKind ?? FamilyDateKind.birthday;
  late FamilyRecurrence _recurrence =
      _e?.recurrence ?? widget.presetRecurrence ?? FamilyRecurrence.yearly;
  late DateTime _startOn = _e == null
      ? DateUtils.dateOnly(widget.presetDate ?? DateTime.now())
      : (parseFamilyDay(_e.startOn) ?? DateUtils.dateOnly(DateTime.now()));
  late int _remindDays = _e?.remindDays ?? widget.presetRemindDays ?? 1;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startOn,
      firstDate: DateTime(2000),
      lastDate: DateTime(2040),
    );
    if (picked == null || !mounted) return;
    setState(() => _startOn = DateUtils.dateOnly(picked));
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = l10n.translate('fd_name_required'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.saveFamilyDate(
        widget.tourId,
        id: _e?.id,
        title: title,
        kind: _kind,
        recurrence: _recurrence,
        startOn: _startOn,
        remindDays: _remindDays,
        note: _note.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (err) {
      logError('Family date save failed: $err');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = l10n.translate('fd_save_failed');
      });
    }
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _sheet,
        title: Text(l10n.translate('fd_delete_title'),
            style: const TextStyle(color: Colors.white)),
        content: Text(l10n.translate('fd_delete_body'),
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
    if (sure != true || _e == null || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.deleteFamilyDate(widget.tourId, _e.id);
      if (mounted) Navigator.pop(context, true);
    } catch (err) {
      logError('Family date delete failed: $err');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = l10n.translate('fd_delete_failed');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final editable = widget.canEdit && !_saving;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: AbsorbPointer(
          absorbing: !editable,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  l10n.translate(_e == null
                      ? 'fd_add_title'
                      : (widget.canEdit ? 'fd_edit_title' : 'fd_view_title')),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              if (!widget.canEdit) ...[
                const SizedBox(height: 6),
                Text(l10n.translate('fd_view_only'),
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                maxLength: 80,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: l10n.translate('fd_name_label'),
                  hintText: l10n.translate('fd_name_hint'),
                  hintStyle: const TextStyle(color: Colors.white38),
                ),
              ),
              const SizedBox(height: 8),
              Text(l10n.translate('fd_kind_label'),
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final k in FamilyDateKind.values)
                    _choice(
                      label:
                          '${k.emoji} ${l10n.translate('fd_kind_${k.name}')}',
                      selected: _kind == k,
                      onTap: () => setState(() => _kind = k),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(l10n.translate('fd_repeat_label'),
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final r in FamilyRecurrence.values)
                    _choice(
                      label: l10n.translate('fd_repeat_${r.name}'),
                      selected: _recurrence == r,
                      onTap: () => setState(() => _recurrence = r),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_rounded, color: AppColors.gold),
                title: Text(l10n.translate('fd_date_label'),
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
                subtitle: Text(
                    localizedDateFormat('EEE, d MMM yyyy').format(_startOn),
                    style: const TextStyle(color: Colors.white, fontSize: 15)),
                trailing: const Icon(Icons.edit_calendar_rounded,
                    color: Colors.white54),
                onTap: editable ? _pickDate : null,
              ),
              const SizedBox(height: 4),
              Text(l10n.translate('fd_remind_label'),
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final days in kFamilyRemindChoices)
                    _choice(
                      label: l10n.translate('fd_remind_$days'),
                      selected: _remindDays == days,
                      onTap: () => setState(() => _remindDays = days),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                maxLength: 500,
                minLines: 1,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: l10n.translate('fd_note_label'),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.redAccent)),
                ),
              if (widget.canEdit) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (_e != null)
                      TextButton.icon(
                        onPressed: _saving ? null : _delete,
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: Colors.redAccent),
                        label: Text(l10n.translate('fd_delete'),
                            style: const TextStyle(color: Colors.redAccent)),
                      ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.mintGreen,
                          foregroundColor: AppColors.darkGreen),
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(l10n.translate('fd_save')),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _choice({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      selectedColor: AppColors.mintGreen,
      backgroundColor: _chip,
      labelStyle:
          TextStyle(color: selected ? AppColors.darkGreen : Colors.white),
      onSelected: (_) => onTap(),
    );
  }
}
