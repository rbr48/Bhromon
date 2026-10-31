import 'package:flutter/material.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/theme/colors.dart';
import '../../../domain/models/expense_models.dart';
import '../../../domain/models/tour_group.dart';
import '../../../domain/services/fund_analytics.dart';
import '../../../domain/services/trip_ledger_engine.dart';
import 'expense_editor.dart';
import '../../../../../core/localization/localized_date.dart';

const _sheetColor = Color(0xFF142428);
const _menuColor = Color(0xFF1B4332);

/// The key used for the fund in party pickers; members use their email.
const String _fundKey = '__fund__';

Future<T?> _sheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _sheetColor,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SafeArea(child: SingleChildScrollView(child: child)),
    ),
  );
}

Widget _title(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
    );

Widget _errorText(String? error) => error == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(error, style: const TextStyle(color: Colors.redAccent)),
      );

Widget _saveButton(String label, VoidCallback onPressed) => FilledButton(
      style: FilledButton.styleFrom(
          backgroundColor: AppColors.mintGreen,
          foregroundColor: AppColors.darkGreen,
          padding: const EdgeInsets.symmetric(vertical: 14)),
      onPressed: onPressed,
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
    );

// ---------------------------------------------------------------------------
// Payments between people (settling up)
// ---------------------------------------------------------------------------

class TransferDraft {
  const TransferDraft({
    required this.fromId,
    required this.fromName,
    required this.toId,
    required this.toName,
    required this.amountPaisa,
    required this.date,
    this.notes,
  });

  final String? fromId;
  final String fromName;
  final String? toId;
  final String toName;
  final int amountPaisa;
  final DateTime date;
  final String? notes;
}

/// Records money handed over. [suggestion] fills the form from a settle-up
/// suggestion. Members who are not admins may only record payments they
/// made or received themselves, which the rules also check.
Future<TransferDraft?> showTransferSheet(
  BuildContext context, {
  required List<TourMember> members,
  required String me,
  required bool isAdmin,
  SettlementTransaction? suggestion,
}) {
  return _sheet(
    context,
    _TransferForm(
        members: members, me: me, isAdmin: isAdmin, suggestion: suggestion),
  );
}

class _TransferForm extends StatefulWidget {
  const _TransferForm({
    required this.members,
    required this.me,
    required this.isAdmin,
    this.suggestion,
  });

  final List<TourMember> members;
  final String me;
  final bool isAdmin;
  final SettlementTransaction? suggestion;

  @override
  State<_TransferForm> createState() => _TransferFormState();
}

class _TransferFormState extends State<_TransferForm> {
  late final SettlementTransaction? s = widget.suggestion;
  late String _from =
      s == null ? widget.me : (s!.fromFund ? _fundKey : s!.fromId ?? widget.me);
  late String _to =
      s == null ? _fundKey : (s!.toFund ? _fundKey : s!.toId ?? _fundKey);
  late final _amount = TextEditingController(
      text: s == null ? '' : TripLedgerEngine.plainTakaInput(s!.amountPaisa));
  final _notes = TextEditingController();
  String _method = 'cash';
  String? _error;

  static const _methods = ['cash', 'bkash', 'nagad', 'rocket', 'bank', 'card'];

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  String _nameOf(String key, AppLocalizations l10n) {
    if (key == _fundKey) return TripLedgerEngine.fundLabel;
    for (final m in widget.members) {
      if (m.email == key) return m.displayName;
    }
    // A former member from a suggestion.
    if (key == s?.fromId) return s!.from;
    if (key == s?.toId) return s!.to;
    return key;
  }

  List<DropdownMenuItem<String>> _parties(AppLocalizations l10n) {
    final keys = <String>{
      _fundKey,
      for (final m in widget.members) m.email,
      _from,
      _to,
    };
    return [
      for (final k in keys)
        DropdownMenuItem(
          value: k,
          child: Row(children: [
            Icon(
                k == _fundKey
                    ? Icons.account_balance_rounded
                    : Icons.person_rounded,
                size: 16,
                color:
                    k == _fundKey ? const Color(0xFF38BDF8) : Colors.white70),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                  k == _fundKey
                      ? l10n.translate('fund_the_fund')
                      : _nameOf(k, l10n),
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
        ),
    ];
  }

  void _save() {
    final l10n = context.l10n;
    final paisa = TripLedgerEngine.parseTakaInput(_amount.text);
    if (_from == _to) {
      setState(() => _error = l10n.translate('fund_err_same_party'));
      return;
    }
    if (paisa == null) {
      setState(() => _error = l10n.translate('fund_err_amount'));
      return;
    }
    if (!widget.isAdmin && _from != widget.me && _to != widget.me) {
      setState(() => _error = l10n.translate('fund_err_not_yours'));
      return;
    }
    final method = l10n.translate('fund_method_$_method');
    final note = _notes.text.trim();
    Navigator.pop(
      context,
      TransferDraft(
        fromId: _from == _fundKey ? null : _from,
        fromName: _nameOf(_from, l10n),
        toId: _to == _fundKey ? null : _to,
        toName: _nameOf(_to, l10n),
        amountPaisa: paisa,
        date: DateTime.now(),
        notes: note.isEmpty ? method : '$method · $note',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final parties = _parties(l10n);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title(l10n.translate('fund_record_payment')),
          Text(l10n.translate('fund_record_payment_help'),
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _from,
            isExpanded: true,
            dropdownColor: _menuColor,
            decoration: InputDecoration(labelText: l10n.translate('fund_from')),
            items: parties,
            onChanged: (v) => setState(() => _from = v ?? _from),
          ),
          Center(
            child: IconButton(
              tooltip: l10n.translate('fund_swap'),
              icon: const Icon(Icons.swap_vert_rounded,
                  color: AppColors.mintGreen),
              onPressed: () => setState(() {
                final t = _from;
                _from = _to;
                _to = t;
              }),
            ),
          ),
          DropdownButtonFormField<String>(
            initialValue: _to,
            isExpanded: true,
            dropdownColor: _menuColor,
            decoration: InputDecoration(labelText: l10n.translate('fund_to')),
            items: parties,
            onChanged: (v) => setState(() => _to = v ?? _to),
          ),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white),
            decoration:
                InputDecoration(labelText: l10n.translate('fund_amount_taka')),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in _methods)
                ChoiceChip(
                  label: Text(l10n.translate('fund_method_$m')),
                  selected: _method == m,
                  selectedColor: AppColors.mintGreen,
                  backgroundColor: const Color(0xFF1E3326),
                  labelStyle: TextStyle(
                      color: _method == m ? AppColors.darkGreen : Colors.white),
                  onSelected: (_) => setState(() => _method = m),
                ),
            ],
          ),
          TextField(
            controller: _notes,
            maxLength: 120,
            style: const TextStyle(color: Colors.white),
            decoration:
                InputDecoration(labelText: l10n.translate('fund_payment_ref')),
          ),
          _errorText(_error),
          _saveButton(l10n.translate('fund_mark_paid'), _save),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Deposits into the fund
// ---------------------------------------------------------------------------

class DepositDraft {
  const DepositDraft({
    required this.memberId,
    required this.memberName,
    required this.amountPaisa,
    required this.date,
    this.notes,
  });

  final String memberId;
  final String memberName;
  final int amountPaisa;
  final DateTime date;
  final String? notes;
}

/// Adds a deposit, or edits [existing]. [suggestedPaisa] fills in what the
/// member still owes the collection.
Future<DepositDraft?> showDepositSheet(
  BuildContext context, {
  required List<TourMember> members,
  required String me,
  DepositItem? existing,
  String? memberId,
  int? suggestedPaisa,
}) {
  return _sheet(
    context,
    _DepositForm(
      members: members,
      me: me,
      existing: existing,
      memberId: memberId,
      suggestedPaisa: suggestedPaisa,
    ),
  );
}

class _DepositForm extends StatefulWidget {
  const _DepositForm({
    required this.members,
    required this.me,
    this.existing,
    this.memberId,
    this.suggestedPaisa,
  });

  final List<TourMember> members;
  final String me;
  final DepositItem? existing;
  final String? memberId;
  final int? suggestedPaisa;

  @override
  State<_DepositForm> createState() => _DepositFormState();
}

class _DepositFormState extends State<_DepositForm> {
  late final DepositItem? d = widget.existing;

  /// Email to name; a former member already on the row stays selectable.
  late final Map<String, String> _options = {
    for (final m in widget.members) m.email: m.displayName,
    if (d != null) d!.memberId: d!.memberName,
  };
  late String? _member = d?.memberId ??
      widget.memberId ??
      (_options.containsKey(widget.me)
          ? widget.me
          : (_options.isEmpty ? null : _options.keys.first));
  late final _amount = TextEditingController(
      text: d != null
          ? TripLedgerEngine.plainTakaInput(d!.amountPaisa)
          : widget.suggestedPaisa == null
              ? ''
              : TripLedgerEngine.plainTakaInput(widget.suggestedPaisa!));
  late final _notes = TextEditingController(text: d?.notes ?? '');
  late DateTime _date = d?.date ?? DateTime.now();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    final l10n = context.l10n;
    final paisa = TripLedgerEngine.parseTakaInput(_amount.text);
    final id = _member;
    if (id == null || !_options.containsKey(id)) {
      setState(() => _error = l10n.translate('fund_err_member'));
      return;
    }
    if (paisa == null) {
      setState(() => _error = l10n.translate('fund_err_amount'));
      return;
    }
    final note = _notes.text.trim();
    Navigator.pop(
      context,
      DepositDraft(
        memberId: id,
        memberName: _options[id]!,
        amountPaisa: paisa,
        date: _date,
        notes: note.isEmpty ? null : note,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title(l10n
              .translate(d == null ? 'fund_add_deposit' : 'fund_edit_deposit')),
          if (_options.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: _member,
              isExpanded: true,
              dropdownColor: _menuColor,
              decoration: InputDecoration(
                  labelText: l10n.translate('fund_who_deposits')),
              items: [
                for (final e in _options.entries)
                  DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _member = v),
            ),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white),
            decoration:
                InputDecoration(labelText: l10n.translate('fund_amount_taka')),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_rounded, color: AppColors.gold),
            title: Text(localizedDateFormat('EEE, d MMM yyyy').format(_date),
                style: const TextStyle(color: Colors.white)),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate:
                    _date.isBefore(DateTime(2022)) ? _date : DateTime(2022),
                lastDate:
                    _date.isAfter(DateTime(2035)) ? _date : DateTime(2035),
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
          TextField(
            controller: _notes,
            maxLength: 120,
            style: const TextStyle(color: Colors.white),
            decoration:
                InputDecoration(labelText: l10n.translate('fund_payment_ref')),
          ),
          _errorText(_error),
          _saveButton(l10n.translate('tour_save'), _save),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Budget and collection target (admins)
// ---------------------------------------------------------------------------

/// Edits the per-category budget and the amount each person is asked to put
/// in. [headcount] (people, counting families) shows the collection total.
Future<FundBudget?> showBudgetSheet(
  BuildContext context, {
  required FundBudget budget,
  required int headcount,
  required int totalDays,
  bool family = false,
}) {
  return _sheet(
    context,
    _BudgetForm(
      budget: budget,
      headcount: headcount,
      totalDays: totalDays,
      family: family,
    ),
  );
}

class _BudgetForm extends StatefulWidget {
  const _BudgetForm({
    required this.budget,
    required this.headcount,
    required this.totalDays,
    required this.family,
  });

  final FundBudget budget;
  final int headcount;
  final int totalDays;
  final bool family;

  @override
  State<_BudgetForm> createState() => _BudgetFormState();
}

class _BudgetFormState extends State<_BudgetForm> {
  late final List<String> _offered =
      expenseCategoriesFor(family: widget.family);
  late final List<String> _cats = [
    ..._offered,
    for (final c in widget.budget.categoryPaisa.keys)
      if (!_offered.contains(c)) c,
  ];
  late final Map<String, TextEditingController> _ctrl = {
    for (final c in _cats)
      c: TextEditingController(
          text: (widget.budget.categoryPaisa[c] ?? 0) > 0
              ? TripLedgerEngine.plainTakaInput(widget.budget.categoryPaisa[c]!)
              : ''),
  };
  late final _perHead = TextEditingController(
      text: widget.budget.perHeadTargetPaisa > 0
          ? TripLedgerEngine.plainTakaInput(widget.budget.perHeadTargetPaisa)
          : '');
  String? _error;

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    _perHead.dispose();
    super.dispose();
  }

  int _parse(TextEditingController c) => c.text.trim().isEmpty
      ? 0
      : (TripLedgerEngine.parseTakaInput(c.text) ?? -1);

  int get _total => _ctrl.values.fold<int>(0, (n, c) {
        final v = _parse(c);
        return v > 0 ? n + v : n;
      });

  /// Spreads the budget's total evenly as the per-person target.
  void _fillPerHead() {
    if (widget.headcount <= 0 || _total <= 0) return;
    // Rounded up to the next 10 taka, so the collection covers the budget.
    final per = (_total / widget.headcount / 1000).ceil() * 1000;
    setState(() => _perHead.text = TripLedgerEngine.plainTakaInput(per));
  }

  void _save() {
    final l10n = context.l10n;
    final map = <String, int>{};
    for (final e in _ctrl.entries) {
      final v = _parse(e.value);
      if (v < 0) {
        setState(() => _error = l10n.translate('fund_err_amount'));
        return;
      }
      if (v > 0) map[e.key] = v;
    }
    final per = _parse(_perHead);
    if (per < 0) {
      setState(() => _error = l10n.translate('fund_err_amount'));
      return;
    }
    Navigator.pop(
        context, FundBudget(categoryPaisa: map, perHeadTargetPaisa: per));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final total = _total;
    final per = _parse(_perHead);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title(l10n.translate('fund_budget_title')),
          Text(l10n.translate('fund_budget_help'),
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 8),
          for (final c in _cats)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(fundCategoryIcon(c), color: Colors.white70, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(fundCategoryLabel(l10n, c),
                          style: const TextStyle(color: Colors.white))),
                  SizedBox(
                    width: 130,
                    child: TextField(
                      controller: _ctrl[c],
                      onChanged: (_) => setState(() {}),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.end,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                          isDense: true,
                          prefixText: '৳ ',
                          hintText: '0',
                          hintStyle: TextStyle(color: Colors.white24)),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(color: Colors.white12, height: 24),
          Row(
            children: [
              Expanded(
                child: Text(l10n.translate('fund_budget_total'),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              Text(TripLedgerEngine.formatTaka(total),
                  style: const TextStyle(
                      color: AppColors.gold, fontWeight: FontWeight.bold)),
            ],
          ),
          if (widget.headcount > 0 && total > 0)
            Text(
              // A one-day tour, such as a family circle, has no per-day figure.
              widget.totalDays > 1
                  ? l10n.translate('fund_budget_per_head_day', args: {
                      'head': TripLedgerEngine.formatTaka(
                          total ~/ widget.headcount),
                      'day': TripLedgerEngine.formatTaka(
                          total ~/ widget.totalDays),
                    })
                  : l10n.translate('fund_budget_per_head', args: {
                      'head': TripLedgerEngine.formatTaka(
                          total ~/ widget.headcount),
                    }),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _perHead,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: l10n.translate('fund_per_head_target'),
              helperText: l10n.translate('fund_per_head_help'),
              helperMaxLines: 3,
              helperStyle: const TextStyle(color: Colors.white38),
              prefixText: '৳ ',
              suffixIcon: IconButton(
                tooltip: l10n.translate('fund_per_head_from_budget'),
                icon: const Icon(Icons.auto_fix_high_rounded,
                    color: AppColors.mintGreen),
                onPressed: _fillPerHead,
              ),
            ),
          ),
          if (per > 0 && widget.headcount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l10n.translate('fund_collection_total', args: {
                  'amount': TripLedgerEngine.formatTaka(per * widget.headcount),
                  'people': l10n.number(widget.headcount),
                }),
                style: const TextStyle(color: AppColors.gold, fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          _errorText(_error),
          _saveButton(l10n.translate('tour_save'), _save),
        ],
      ),
    );
  }
}
