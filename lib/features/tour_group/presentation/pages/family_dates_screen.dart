import 'package:flutter/material.dart';

import 'package:bhromon/core/theme/forest_palette.dart';
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
  const FamilyDatesScreen({super.key, required this.tourId, this.group});

  final String tourId;
  final TourGroup? group;

  @override
  State<FamilyDatesScreen> createState() => _FamilyDatesScreenState();
}

class _FamilyDatesScreenState extends State<FamilyDatesScreen> {
  final TourGroupRepository _repository = TourGroupRepository();
  late final Stream<List<FamilyDate>> _dates =
      _repository.watchFamilyDates(widget.tourId);
  TourRole? _myRole;
  TourGroup? _group;

  String _screenTitle(AppLocalizations l10n) {
    final g = _group;
    if (g != null) {
      if (g.isOffice) return l10n.translate('hub_module_dates_office');
      if (g.isCampus) return l10n.translate('hub_module_dates_campus');
      if (g.isMess) return l10n.translate('hub_module_dates_mess');
      if (g.isSociety) return l10n.translate('hub_module_dates_society');
      if (g.isSamity) return l10n.translate('hub_module_dates_samity');
      if (g.isStudy) return l10n.translate('hub_module_dates_study');
      if (!g.isFamily) return l10n.translate('hub_module_dates_trip');
    }
    return l10n.translate('fd_title');
  }

  String _introText(AppLocalizations l10n) {
    final g = _group;
    if (g != null) {
      if (g.isOffice) return l10n.translate('hub_module_dates_office_sub');
      if (g.isCampus) return l10n.translate('hub_module_dates_campus_sub');
      if (g.isMess) return l10n.translate('hub_module_dates_mess_sub');
      if (g.isSociety) return l10n.translate('hub_module_dates_society_sub');
      if (g.isSamity) return l10n.translate('hub_module_dates_samity_sub');
      if (g.isStudy) return l10n.translate('hub_module_dates_study_sub');
      if (!g.isFamily) return l10n.translate('hub_module_dates_trip_sub');
    }
    return l10n.translate('fd_intro');
  }

  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;
  String get _me => _repository.currentEmail;
  bool _canEdit(FamilyDate date) =>
      _isAdmin ||
      (date.createdByEmail.isNotEmpty && date.createdByEmail == _me);

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _repository.myRole(widget.tourId).then((role) {
      if (mounted) setState(() => _myRole = role);
    }, onError: (Object _) {});
    _repository.watchGroup(widget.tourId).listen((g) {
      if (mounted) setState(() => _group = g);
    }, onError: (Object _) {});
  }

  Future<void> _add() async {
    await showFamilyDateEditor(
      context,
      tourId: widget.tourId,
      repository: _repository,
      group: _group,
    );
  }

  Future<void> _open(FamilyDate date) async {
    await showFamilyDateEditor(
      context,
      tourId: widget.tourId,
      repository: _repository,
      group: _group,
      existing: date,
      canEdit: _canEdit(date),
    );
  }

  /// Picks a public holiday and opens the editor with it filled in, as a one-time
  /// date a day ahead. Moon-based holidays move each year, so they are not repeated.
  Future<void> _addHoliday() async {
    final picked = await showModalBottomSheet<HolidayOccurrence>(
      context: context,
      backgroundColor: context.forest.surfaceFor(_card),
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
      group: _group,
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
      backgroundColor: context.forest.surfaceFor(_bg),
      appBar: AppBar(
        title: Text(_screenTitle(l10n),
            style: TextStyle(
                color: context.forest.text,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
        backgroundColor: context.forest.surfaceFor(_card),
        foregroundColor: context.forest.text,
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
              Text(_introText(l10n),
                  style: TextStyle(color: context.forest.text60, fontSize: 13)),
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
            style: TextStyle(
                color: context.forest.accentText,
                fontWeight: FontWeight.bold,
                fontSize: 13)),
      );

  Widget _message(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.forest.text70, fontSize: 14)),
      );

  Widget _tile(FamilyDate date, DateTime today) {
    final l10n = context.l10n;
    final due = FamilyDateRules.nextDue(date, today);
    final days = FamilyDateRules.daysBetween(today, due);
    final start = parseFamilyDay(date.startOn);
    final parts = <String>[
      localizedDateFormat('EEE, d MMM yyyy').format(due),
      if (days == 0)
        l10n.translate('fd_when_today')
      else if (days == 1)
        l10n.translate('fd_when_tomorrow')
      else if (days > 1)
        l10n.translate('fd_when_in_days', args: {'days': l10n.number(days)}),
      l10n.translate('fd_repeat_${date.recurrence.name}'),
      if (start != null &&
          date.recurrence == FamilyRecurrence.yearly &&
          start.year < today.year)
        (l10n.locale.languageCode == 'bn'
            ? '${l10n.number(today.year - start.year)}ম বছর (শুরু ${l10n.number(start.year)})'
            : 'Year ${today.year - start.year} (Since ${start.year})')
      else if (start != null &&
          date.recurrence == FamilyRecurrence.once &&
          start.year != due.year)
        '(${start.year})',
    ];
    final editable = _canEdit(date);
    return Card(
      color: context.forest.surfaceFor(_card),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: context.forest.surfaceFor(const Color(0xFF1E3326)),
          child: Text(date.kind.emoji),
        ),
        title: Text(date.title,
            style: TextStyle(
                color: context.forest.text, fontWeight: FontWeight.w600)),
        subtitle: Text(parts.join(' · '),
            style: TextStyle(color: context.forest.text60, fontSize: 12)),
        trailing: editable
            ? null
            : Icon(Icons.lock_outline_rounded,
                color: context.forest.text38, size: 18),
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
                  style: TextStyle(
                      color: context.forest.text,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(l10n.translate('fd_holiday_help'),
                  style: TextStyle(color: context.forest.text54, fontSize: 12)),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: holidays.length,
                itemBuilder: (context, i) {
                  final o = holidays[i];
                  return ListTile(
                    title: Text(bengali ? o.holiday.nameBn : o.holiday.nameEn,
                        style: TextStyle(color: context.forest.text)),
                    subtitle: Text(
                        localizedDateFormat('EEE, d MMM yyyy').format(o.date),
                        style: TextStyle(color: context.forest.text54)),
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
