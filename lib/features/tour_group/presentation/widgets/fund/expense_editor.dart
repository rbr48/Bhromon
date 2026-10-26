import 'package:flutter/material.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/theme/colors.dart';
import '../../../domain/models/expense_models.dart';
import '../../../domain/models/itinerary_models.dart';
import '../../../domain/models/tour_group.dart';
import '../../../domain/services/fund_analytics.dart';
import '../../../domain/services/trip_ledger_engine.dart';
import '../../../../../core/localization/localized_date.dart';

String fundCategoryLabel(AppLocalizations l10n, String category) {
  final key = 'fund_cat_${category.toLowerCase()}';
  final label = l10n.translate(key);
  return label == key ? category : label;
}

IconData fundCategoryIcon(String category) => switch (category) {
      'Food' => Icons.restaurant_rounded,
      'Transport' => Icons.directions_bus_rounded,
      'Hotel' => Icons.hotel_rounded,
      'Tickets' => Icons.confirmation_number_rounded,
      'Guide' => Icons.hiking_rounded,
      'Activities' => Icons.kayaking_rounded,
      'Shopping' => Icons.shopping_bag_rounded,
      'Medical' => Icons.medical_services_rounded,
      'Tips' => Icons.volunteer_activism_rounded,
      _ => Icons.receipt_long_rounded,
    };

/// What the editor returns: everything the repository needs to save.
class ExpenseDraft {
  const ExpenseDraft({
    required this.title,
    required this.amountPaisa,
    required this.category,
    required this.date,
    required this.paidById,
    required this.paidByName,
    required this.participantIds,
    required this.splitMode,
    required this.splitShares,
    required this.stopId,
    required this.currency,
    required this.originalMinor,
    required this.fxRate,
    required this.notes,
  });

  final String title;
  final int amountPaisa;
  final String category;
  final DateTime date;
  final String? paidById;
  final String? paidByName;
  final List<String>? participantIds;
  final SplitMode splitMode;
  final Map<String, int>? splitShares;
  final String? stopId;
  final String? currency;
  final int? originalMinor;
  final double? fxRate;
  final String? notes;
}

Future<ExpenseDraft?> showExpenseEditor(
  BuildContext context, {
  required List<TourMember> members,
  required TourGroup? group,
  required String me,
  ExpenseItem? existing,
}) {
  return showModalBottomSheet<ExpenseDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF142428),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _ExpenseEditor(
        members: members, group: group, me: me, existing: existing),
  );
}

class _ExpenseEditor extends StatefulWidget {
  const _ExpenseEditor({
    required this.members,
    required this.group,
    required this.me,
    this.existing,
  });

  final List<TourMember> members;
  final TourGroup? group;
  final String me;
  final ExpenseItem? existing;

  @override
  State<_ExpenseEditor> createState() => _ExpenseEditorState();
}

class _ExpenseEditorState extends State<_ExpenseEditor> {
  late final ExpenseItem? e = widget.existing;
  late final _title = TextEditingController(text: e?.title ?? '');
  late final _amount = TextEditingController(
      text: e == null
          ? ''
          : TripLedgerEngine.plainTakaInput(
              e!.isForeign ? (e!.originalMinor ?? 0) : e!.amountPaisa));
  late final _rate = TextEditingController(text: e?.fxRate?.toString() ?? '');
  late final _notes = TextEditingController(text: e?.notes ?? '');
  late String _currency = e?.isForeign == true ? e!.currency! : 'BDT';
  late String _category = e?.category ?? 'Food';
  late DateTime _date = e?.date ?? DateTime.now();
  late String? _stopId = e?.stopId ?? widget.group?.stopOn(_date)?.id;
  late bool _fromFund = e == null || e!.paidById == null;
  late String? _payer = e?.paidById ??
      (widget.members.any((m) => m.email == widget.me)
          ? widget.me
          : (widget.members.isEmpty ? null : widget.members.first.email));
  late SplitMode _mode = e?.splitMode ?? SplitMode.family;
  late final Set<String> _people = {
    ...(e?.participantIds ??
        e?.splitShares?.keys ??
        widget.members.map((m) => m.email)),
  };
  late final Map<String, TextEditingController> _share = {
    for (final m in widget.members)
      m.email: TextEditingController(
          text: switch (e?.splitMode) {
        // Exact amounts are stored in BDT; the form shows them in the
        // currency they were entered in.
        SplitMode.exact => e!.splitShares?[m.email] == null
            ? ''
            : TripLedgerEngine.plainTakaInput(e!.isForeign
                ? (e!.splitShares![m.email]! / e!.fxRate!).round()
                : e!.splitShares![m.email]!),
        SplitMode.shares => e!.splitShares?[m.email]?.toString() ?? '',
        _ => '',
      }),
  };
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _rate.dispose();
    _notes.dispose();
    for (final c in _share.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// The amount in the entry currency's minor units, or null.
  int? get _enteredMinor => TripLedgerEngine.parseTakaInput(_amount.text);

  double? get _rateValue =>
      double.tryParse(_rate.text.trim().replaceAll(',', ''));

  /// The BDT paisa the books will use, or null when not yet valid.
  int? get _bdtPaisa {
    final minor = _enteredMinor;
    if (minor == null) return null;
    if (_currency == 'BDT') return minor;
    final rate = _rateValue;
    return rate == null ? null : convertToPaisa(minor, rate);
  }

  int get _exactTotal =>
      _share.entries.where((e) => _people.contains(e.key)).fold<int>(0,
          (n, e) => n + (TripLedgerEngine.parseTakaInput(e.value.text) ?? 0));

  void _save() {
    final l10n = context.l10n;
    final title = _title.text.trim();
    final paisa = _bdtPaisa;
    if (title.isEmpty) {
      setState(() => _error = l10n.translate('fund_err_title'));
      return;
    }
    if (_currency != 'BDT' && (_rateValue == null || _rateValue! <= 0)) {
      setState(() => _error = l10n.translate('fund_err_rate'));
      return;
    }
    if (paisa == null || paisa <= 0) {
      setState(() => _error = l10n.translate('fund_err_amount'));
      return;
    }
    if (_people.isEmpty) {
      setState(() => _error = l10n.translate('fund_err_people'));
      return;
    }
    if (!_fromFund && _payer == null) {
      setState(() => _error = l10n.translate('fund_err_payer'));
      return;
    }

    Map<String, int>? shares;
    if (_mode == SplitMode.exact || _mode == SplitMode.shares) {
      shares = {};
      for (final email in _people) {
        final text = _share[email]?.text ?? '';
        final v = _mode == SplitMode.exact
            ? TripLedgerEngine.parseTakaInput(text)
            : int.tryParse(text.trim());
        if (v != null && v > 0) shares[email] = v;
      }
      if (shares.isEmpty) {
        setState(() => _error = l10n.translate('fund_err_shares'));
        return;
      }
      // Exact amounts are in the entry currency; the books keep BDT.
      if (_mode == SplitMode.exact) {
        final total = shares.values.fold<int>(0, (a, b) => a + b);
        // A foreign split read back from BDT may be off by rounding.
        final slack = _currency == 'BDT' ? 0 : shares.length;
        if ((total - (_enteredMinor ?? 0)).abs() > slack) {
          setState(() => _error = l10n.translate('fund_err_exact', args: {
                'split': TripLedgerEngine.formatTaka(total),
                'total': TripLedgerEngine.formatTaka(_enteredMinor ?? 0),
              }));
          return;
        }
        if (_currency != 'BDT') {
          final rate = _rateValue!;
          shares = {
            for (final s in shares.entries) s.key: (s.value * rate).round(),
          };
        }
        // Rounding goes to the largest share, so the split matches the total.
        final diff = paisa - shares.values.fold<int>(0, (a, b) => a + b);
        if (diff != 0) {
          final top =
              shares.entries.reduce((a, b) => b.value > a.value ? b : a).key;
          shares[top] = shares[top]! + diff;
        }
      }
    }

    final payerName = _fromFund
        ? null
        : widget.members
                .where((m) => m.email == _payer)
                .map((m) => m.displayName)
                .firstOrNull ??
            e?.paidByName;
    final memberEmails = [for (final m in widget.members) m.email];
    Navigator.pop(
      context,
      ExpenseDraft(
        title: title,
        amountPaisa: paisa,
        category: _category,
        date: _date,
        paidById: _fromFund ? null : _payer,
        paidByName: payerName,
        participantIds: shares != null
            ? null
            : TripLedgerEngine.participantSelection(
                selected: _people, memberEmails: memberEmails),
        splitMode: _mode,
        splitShares: shares,
        stopId: _stopId,
        currency: _currency == 'BDT' ? null : _currency,
        originalMinor: _currency == 'BDT' ? null : _enteredMinor,
        fxRate: _currency == 'BDT' ? null : _rateValue,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final stops = widget.group?.effectiveStops ?? const <TourStop>[];
    final bdt = _bdtPaisa;
    final categories = [
      ...kExpenseCategories,
      if (!kExpenseCategories.contains(_category)) _category,
    ];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      maxChildSize: 0.96,
      builder: (context, scroll) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            Text(
                l10n.translate(
                    e == null ? 'fund_add_expense' : 'fund_edit_expense'),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            TextField(
              controller: _title,
              maxLength: 80,
              style: const TextStyle(color: Colors.white),
              decoration:
                  InputDecoration(labelText: l10n.translate('fund_what')),
            ),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _amount,
                    onChanged: (_) => setState(() {}),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                        labelText: l10n.translate('fund_amount')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    initialValue: _currency,
                    dropdownColor: const Color(0xFF1B4332),
                    decoration: InputDecoration(
                        labelText: l10n.translate('fund_currency')),
                    items: [
                      for (final c in kFundCurrencies)
                        DropdownMenuItem(
                            value: c.code,
                            child: Text('${c.symbol} ${c.code}')),
                    ],
                    onChanged: (v) => setState(() => _currency = v ?? 'BDT'),
                  ),
                ),
              ],
            ),
            if (_currency != 'BDT') ...[
              TextField(
                controller: _rate,
                onChanged: (_) => setState(() {}),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: l10n
                      .translate('fund_rate', args: {'currency': _currency}),
                  helperText: l10n.translate('fund_rate_help'),
                  helperStyle: const TextStyle(color: Colors.white38),
                ),
              ),
              if (bdt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                      l10n.translate('fund_in_taka',
                          args: {'amount': TripLedgerEngine.formatTaka(bdt)}),
                      style: const TextStyle(color: AppColors.gold)),
                ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in categories)
                  ChoiceChip(
                    avatar: Icon(fundCategoryIcon(c),
                        size: 16,
                        color: c == _category
                            ? AppColors.darkGreen
                            : Colors.white70),
                    label: Text(fundCategoryLabel(l10n, c)),
                    selected: c == _category,
                    selectedColor: AppColors.mintGreen,
                    backgroundColor: const Color(0xFF1E3326),
                    labelStyle: TextStyle(
                        color: c == _category
                            ? AppColors.darkGreen
                            : Colors.white),
                    onSelected: (_) => setState(() => _category = c),
                  ),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded, color: AppColors.gold),
              title: Text(localizedDateFormat('EEE, d MMM yyyy').format(_date),
                  style: const TextStyle(color: Colors.white)),
              subtitle: Text(l10n.translate('fund_date'),
                  style: const TextStyle(color: Colors.white54)),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate:
                      _date.isBefore(DateTime(2022)) ? _date : DateTime(2022),
                  lastDate:
                      _date.isAfter(DateTime(2035)) ? _date : DateTime(2035),
                );
                if (picked == null) return;
                setState(() {
                  _date = picked;
                  _stopId = widget.group?.stopOn(picked)?.id ?? _stopId;
                });
              },
            ),
            if (stops.length > 1)
              DropdownButtonFormField<String?>(
                initialValue:
                    stops.any((s) => s.id == _stopId) ? _stopId : null,
                dropdownColor: const Color(0xFF1B4332),
                decoration:
                    InputDecoration(labelText: l10n.translate('fund_where')),
                items: [
                  DropdownMenuItem<String?>(
                      value: null,
                      child: Text(l10n.translate('fund_where_none'))),
                  for (final s in stops)
                    DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) => setState(() => _stopId = v),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.translate('fund_paid_from_fund'),
                  style: const TextStyle(color: Colors.white)),
              subtitle: Text(
                  l10n.translate(_fromFund
                      ? 'fund_paid_fund_note'
                      : 'fund_paid_member_note'),
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
              value: _fromFund,
              activeThumbColor: AppColors.mintGreen,
              onChanged: (v) => setState(() => _fromFund = v),
            ),
            if (!_fromFund && widget.members.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: widget.members.any((m) => m.email == _payer)
                    ? _payer
                    : null,
                dropdownColor: const Color(0xFF1B4332),
                decoration:
                    InputDecoration(labelText: l10n.translate('fund_who_paid')),
                items: [
                  for (final m in widget.members)
                    DropdownMenuItem(
                        value: m.email,
                        child: Text(m.displayName,
                            overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _payer = v),
              ),
            const SizedBox(height: 14),
            Text(l10n.translate('fund_split_how'),
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 6),
            SegmentedButton<SplitMode>(
              showSelectedIcon: false,
              segments: [
                for (final m in SplitMode.values)
                  ButtonSegment(
                      value: m,
                      label: Text(l10n.translate('fund_split_${m.name}'),
                          style: const TextStyle(fontSize: 12))),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 6),
            Text(l10n.translate('fund_split_${_mode.name}_help'),
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
            const SizedBox(height: 8),
            if (_mode == SplitMode.family || _mode == SplitMode.equal)
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final m in widget.members)
                    FilterChip(
                      label: Text(
                          _mode == SplitMode.family && m.familyCount > 1
                              ? '${m.displayName} ×${l10n.number(m.familyCount)}'
                              : m.displayName,
                          style: const TextStyle(fontSize: 12)),
                      selected: _people.contains(m.email),
                      selectedColor: AppColors.mintGreen,
                      onSelected: (v) => setState(() =>
                          v ? _people.add(m.email) : _people.remove(m.email)),
                    ),
                ],
              )
            else ...[
              for (final m in widget.members)
                Row(
                  children: [
                    Checkbox(
                      value: _people.contains(m.email),
                      activeColor: AppColors.mintGreen,
                      onChanged: (v) => setState(() => v == true
                          ? _people.add(m.email)
                          : _people.remove(m.email)),
                    ),
                    Expanded(
                        child: Text(m.displayName,
                            style: const TextStyle(color: Colors.white))),
                    SizedBox(
                      width: 110,
                      child: TextField(
                        controller: _share[m.email],
                        enabled: _people.contains(m.email),
                        onChanged: (_) => setState(() {}),
                        keyboardType: TextInputType.numberWithOptions(
                            decimal: _mode == SplitMode.exact),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: l10n.translate(_mode == SplitMode.exact
                              ? 'fund_amount'
                              : 'fund_parts'),
                          hintStyle: const TextStyle(color: Colors.white38),
                        ),
                      ),
                    ),
                  ],
                ),
              if (_mode == SplitMode.exact)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    l10n.translate('fund_exact_left', args: {
                      'left': TripLedgerEngine.formatTaka(
                          (_enteredMinor ?? 0) - _exactTotal),
                    }),
                    style: TextStyle(
                        color: (_enteredMinor ?? 0) == _exactTotal
                            ? AppColors.mintGreen
                            : AppColors.gold),
                  ),
                ),
            ],
            TextField(
              controller: _notes,
              maxLines: 2,
              maxLength: 300,
              style: const TextStyle(color: Colors.white),
              decoration:
                  InputDecoration(labelText: l10n.translate('fund_notes')),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.redAccent)),
              ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.mintGreen,
                  foregroundColor: AppColors.darkGreen,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _save,
              child: Text(l10n.translate('tour_save'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
