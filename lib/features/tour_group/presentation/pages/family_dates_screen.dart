import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/localized_date.dart';
import '../../../../core/theme/colors.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/family_date_models.dart';
import '../../domain/models/holiday_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/family_date_rules.dart';
import '../../domain/services/holiday_calendar.dart';
import '../widgets/family/family_date_editor.dart';

const _bg = Color(0xFF0F1A1C);
const _card = Color(0xFF142428);

/// A family circle's dates: birthdays, bills, school days and medicine times.
/// Everyone in the circle sees them and gets the reminders. The member who added
/// a date, or an admin, changes it.
class FamilyDatesScreen extends StatefulWidget {
  const FamilyDatesScreen({super.key, required this.tourId});

  final String tourId;

  @override
  State<FamilyDatesScreen> createState() => _FamilyDatesScreenState();
}

class _FamilyDatesScreenState extends State<FamilyDatesScreen> {
  final TourGroupRepository _repository = TourGroupRepository();
  late final Stream<List<FamilyDate>> _dates =
      _repository.watchFamilyDates(widget.tourId);
  TourRole? _myRole;

  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;
  String get _me => _repository.currentEmail;
  bool _canEdit(FamilyDate date) =>
      _isAdmin ||
      (date.createdByEmail.isNotEmpty && date.createdByEmail == _me);

  @override
  void initState() {
    super.initState();
    _repository.myRole(widget.tourId).then((role) {
      if (mounted) setState(() => _myRole = role);
    }, onError: (Object _) {});
  }

  Future<void> _add() async {
    await showFamilyDateEditor(
      context,
      tourId: widget.tourId,
      repository: _repository,
    );
  }

  Future<void> _open(FamilyDate date) async {
    await showFamilyDateEditor(
      context,
      tourId: widget.tourId,
      repository: _repository,
      existing: date,
      canEdit: _canEdit(date),
    );
  }

  /// Picks a public holiday and opens the editor with it filled in, as a one-time
  /// date a day ahead. Moon-based holidays move each year, so they are not repeated.
  Future<void> _addHoliday() async {
    final picked = await showModalBottomSheet<HolidayOccurrence>(
      context: context,
      backgroundColor: _card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _HolidayPicker(),
    );
    if (picked == null || !mounted) return;
    final bengali = context.l10n.locale.languageCode == 'bn';
    await showFamilyDateEditor(
      context,
      tourId: widget.tourId,
      repository: _repository,
      presetTitle: bengali ? picked.holiday.nameBn : picked.holiday.nameEn,
      presetDate: picked.date,
      presetKind: FamilyDateKind.custom,
      presetRecurrence: FamilyRecurrence.once,
      presetRemindDays: 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final today = DateUtils.dateOnly(DateTime.now());
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text(l10n.translate('fd_title'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: _card,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: l10n.translate('fd_holiday_add'),
            icon: const Icon(Icons.flag_rounded),
            onPressed: _addHoliday,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.mintGreen,
        foregroundColor: AppColors.darkGreen,
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.translate('fd_add')),
        onPressed: _add,
      ),
      body: StreamBuilder<List<FamilyDate>>(
        stream: _dates,
        builder: (context, snap) {
          if (snap.hasError) return _message(l10n.translate('fd_load_failed'));
          final dates = snap.data;
          if (dates == null) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.mintGreen));
          }
          final sections = FamilyDateRules.sections(dates, today);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              Text(l10n.translate('fd_intro'),
                  style: const TextStyle(color: Colors.white60, fontSize: 13)),
              const SizedBox(height: 8),
              if (dates.isEmpty)
                _message(l10n.translate('fd_empty'))
              else
                for (final section in sections) ...[
                  _sectionHeader(
                      l10n.translate('fd_section_${section.timing.name}')),
                  for (final date in section.items) _tile(date, today),
                ],
            ],
          );
        },
      ),
    );
  }

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
        child: Text(text,
            style: const TextStyle(
                color: AppColors.mintGreen,
                fontWeight: FontWeight.bold,
                fontSize: 13)),
      );

  Widget _message(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14)),
      );

  Widget _tile(FamilyDate date, DateTime today) {
    final l10n = context.l10n;
    final due = FamilyDateRules.nextDue(date, today);
    final days = FamilyDateRules.daysBetween(today, due);
    final parts = <String>[
      localizedDateFormat('EEE, d MMM yyyy').format(due),
      if (days == 0)
        l10n.translate('fd_when_today')
      else if (days == 1)
        l10n.translate('fd_when_tomorrow')
      else if (days > 1)
        l10n.translate('fd_when_in_days', args: {'days': l10n.number(days)}),
      l10n.translate('fd_repeat_${date.recurrence.name}'),
    ];
    final editable = _canEdit(date);
    return Card(
      color: _card,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF1E3326),
          child: Text(date.kind.emoji),
        ),
        title: Text(date.title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text(parts.join(' · '),
            style: const TextStyle(color: Colors.white60, fontSize: 12)),
        trailing: editable
            ? null
            : const Icon(Icons.lock_outline_rounded,
                color: Colors.white38, size: 18),
        onTap: () => _open(date),
      ),
    );
  }
}

/// The holidays of the holiday calendar, for picking one as a family date.
class _HolidayPicker extends StatelessWidget {
  const _HolidayPicker();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bengali = l10n.locale.languageCode == 'bn';
    final holidays = HolidayCalendar().occurrences;
    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(l10n.translate('fd_holiday_title'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(l10n.translate('fd_holiday_help'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: holidays.length,
                itemBuilder: (context, i) {
                  final o = holidays[i];
                  return ListTile(
                    title: Text(bengali ? o.holiday.nameBn : o.holiday.nameEn,
                        style: const TextStyle(color: Colors.white)),
                    subtitle: Text(
                        localizedDateFormat('EEE, d MMM yyyy').format(o.date),
                        style: const TextStyle(color: Colors.white54)),
                    onTap: () => Navigator.pop(context, o),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
