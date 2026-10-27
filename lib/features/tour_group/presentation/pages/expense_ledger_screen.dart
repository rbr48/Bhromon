import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../data/tour_group_repository.dart';
import '../../data/tour_media_uploader.dart';
import '../../domain/models/expense_models.dart';
import '../../domain/models/itinerary_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/fund_analytics.dart';
import '../../domain/services/trip_ledger_engine.dart';
import '../../domain/services/debt_simplifier.dart';
import '../widgets/fund/expense_editor.dart';
import '../widgets/fund/fund_sheets.dart';
import '../../../../core/localization/localized_date.dart';

const _bg = Color(0xFF0F1A1C);
const _card = Color(0xFF142428);
const _fundBlue = Color(0xFF38BDF8);

/// The tour fund: what was collected and spent, against the budget, who owes
/// whom, and the record of payments that settled it.
class ExpenseLedgerScreen extends StatefulWidget {
  final String tourId;

  const ExpenseLedgerScreen({super.key, required this.tourId});

  @override
  State<ExpenseLedgerScreen> createState() => _ExpenseLedgerScreenState();
}

class _ExpenseLedgerScreenState extends State<ExpenseLedgerScreen>
    with SingleTickerProviderStateMixin {
  final TourGroupRepository _repository = TourGroupRepository();
  late final TabController _tabs = TabController(length: 5, vsync: this);
  final List<StreamSubscription<Object?>> _subs = [];

  TourGroup? _group;
  TourRole? _myRole;
  List<TourMember> _members = const [];
  List<ExpenseItem> _expenses = const [];
  List<DepositItem> _deposits = const [];
  List<TransferItem> _transfers = const [];
  bool _loaded = false;

  // Expense list filters.
  final _search = TextEditingController();
  String? _catFilter;
  String? _stopFilter;
  bool _simplifyDebts = false;

  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;
  String get _me => _repository.currentEmail;

  @override
  void initState() {
    super.initState();
    _repository.myRole(widget.tourId).then((r) {
      if (mounted) setState(() => _myRole = r);
    });
    void on<T>(Stream<T> s, void Function(T) apply) {
      _subs.add(s.listen((v) {
        if (mounted) setState(() => apply(v));
      }, onError: (Object _) {}));
    }

    on(_repository.watchGroup(widget.tourId), (g) => _group = g);
    on(_repository.watchMembers(widget.tourId), (m) => _members = m);
    on(_repository.watchDeposits(widget.tourId), (d) => _deposits = d);
    on(_repository.watchTransfers(widget.tourId), (t) => _transfers = t);
    on(_repository.watchExpenses(widget.tourId), (e) {
      _expenses = e;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _money(int paisa) => TripLedgerEngine.formatTaka(paisa);

  List<LedgerMemberInput> get _inputs => [
        for (final m in _members)
          LedgerMemberInput(
              id: m.email, name: m.displayName, familyCount: m.familyCount),
      ];

  int get _headcount =>
      _members.fold<int>(0, (n, m) => n + m.familyCount.clamp(1, 20));

  bool _canEdit(String addedByEmail) =>
      _isAdmin || addedByEmail.toLowerCase() == _me;

  String _party(AppLocalizations l10n, String name, bool fund) =>
      fund ? l10n.translate('fund_the_fund') : name;

  String? _stopName(String? id) {
    if (id == null) return null;
    for (final s in _group?.effectiveStops ?? const <TourStop>[]) {
      if (s.id == id) return s.name;
    }
    return null;
  }

  void _toast(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.redAccent : AppColors.darkGreen));
  }

  Future<void> _run(Future<void> Function() action, String failKey) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        _toast('${context.l10n.translate(failKey)} $e', error: true);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final summary = TripLedgerEngine.computeLedger(
      members: _inputs,
      expenses: _expenses,
      deposits: _deposits,
      transfers: _transfers,
    );
    final group = _group;
    final report = group == null
        ? null
        : FundReport.build(
            group: group,
            members: _inputs,
            expenses: _expenses,
            deposits: _deposits,
            transfers: _transfers,
          );

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: _card,
        foregroundColor: Colors.white,
        title: Text(l10n.translate('fund_title'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          if (_isAdmin && group != null)
            IconButton(
              icon: const Icon(Icons.savings_outlined),
              tooltip: l10n.translate('fund_budget_title'),
              onPressed: () => _editBudget(group),
            ),
          IconButton(
            icon: const Icon(Icons.table_view_rounded),
            tooltip: l10n.translate('fund_export_csv'),
            onPressed: () => _exportCsv(summary, report),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.mintGreen,
          labelColor: AppColors.mintGreen,
          unselectedLabelColor: Colors.white60,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: l10n.translate('fund_tab_overview')),
            Tab(text: l10n.translate('fund_tab_expenses')),
            Tab(
                text: summary.settlements.isEmpty
                    ? l10n.translate('fund_tab_settle')
                    : '${l10n.translate('fund_tab_settle')} '
                        '(${l10n.number(summary.settlements.length)})'),
            Tab(text: l10n.translate('fund_tab_people')),
            Tab(text: l10n.translate('fund_tab_deposits')),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.mintGreen,
        foregroundColor: AppColors.darkGreen,
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.translate('fund_add')),
        onPressed: () => _addMenu(group),
      ),
      body: !_loaded
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.mintGreen))
          : TabBarView(
              controller: _tabs,
              children: [
                _overview(l10n, summary, report),
                _expensesTab(l10n),
                _settleTab(l10n, summary),
                _peopleTab(l10n, summary, report),
                _depositsTab(l10n),
              ],
            ),
    );
  }

  Widget _box({required Widget child, EdgeInsets? padding}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: padding ?? const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: child,
      );

  Widget _heading(String text, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
          ),
          if (trailing != null) trailing,
        ]),
      );

  Widget _empty(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54)),
        ),
      );

  Widget _stat(String label, String value, Color color) => Expanded(
        child: Column(children: [
          FittedBox(
            child: Text(value,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 17)),
          ),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ]),
      );

  /// A labelled bar for a share of [max].
  Widget _bar({
    required String label,
    required int value,
    required int max,
    Color color = AppColors.mintGreen,
    String? trailing,
    IconData? icon,
  }) {
    final ratio = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: Colors.white70),
              const SizedBox(width: 6),
            ],
            Expanded(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13))),
            Text(trailing ?? _money(value),
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 7,
              color: color,
              backgroundColor: Colors.white10,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Overview
  // ---------------------------------------------------------------------------

  Widget _overview(
      AppLocalizations l10n, LedgerSummary summary, FundReport? report) {
    final mine =
        summary.rows.where((r) => r.id.toLowerCase() == _me).firstOrNull;
    final myDue =
        report?.collection.where((c) => c.id.toLowerCase() == _me).firstOrNull;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
      children: [
        _box(
          child: Column(children: [
            Row(children: [
              _stat(
                  l10n.translate('fund_balance'),
                  _money(summary.fundBalancePaisa),
                  summary.fundBalancePaisa >= 0
                      ? AppColors.mintGreen
                      : Colors.redAccent),
              _stat(l10n.translate('fund_spent'),
                  _money(summary.totalExpensePaisa), Colors.white),
              _stat(l10n.translate('fund_collected'),
                  _money(summary.totalDepositsPaisa), AppColors.gold),
            ]),
            const SizedBox(height: 10),
            Text(
              l10n.translate('fund_per_head_line', args: {
                'people': l10n.number(summary.headcount),
                'amount': _money(summary.perHeadCostPaisa),
              }),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            if (summary.fundBalancePaisa < 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(l10n.translate('fund_negative_warning'),
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ),
          ]),
        ),
        if (mine != null) _myCard(l10n, mine, myDue),
        if (report != null) ..._budgetSection(l10n, report),
        if (report != null && report.collection.isNotEmpty)
          _collectionCard(l10n, report),
        if (report != null) ..._spendSections(l10n, report, summary),
        if (_expenses.isEmpty) _empty(l10n.translate('fund_empty_overview')),
      ],
    );
  }

  Widget _myCard(
      AppLocalizations l10n, LedgerMemberRow mine, CollectionRow? due) {
    final settled = mine.netPaisa == 0;
    final gets = mine.netPaisa > 0;
    final color = settled
        ? Colors.white70
        : (gets ? AppColors.mintGreen : AppColors.gold);
    return _box(
      child: Row(children: [
        CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.18),
          child: Icon(
              settled
                  ? Icons.check_rounded
                  : (gets
                      ? Icons.call_received_rounded
                      : Icons.call_made_rounded),
              color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                settled
                    ? l10n.translate('fund_me_settled')
                    : l10n.translate(gets ? 'fund_me_gets' : 'fund_me_owes',
                        args: {'amount': _money(mine.netPaisa.abs())}),
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 2),
              Text(
                l10n.translate('fund_me_detail', args: {
                  'paid': _money(mine.contributedPaisa),
                  'share': _money(mine.sharePaisa),
                }),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              if (due != null && due.duePaisa > 0)
                Text(
                  l10n.translate('fund_me_due',
                      args: {'amount': _money(due.duePaisa)}),
                  style: const TextStyle(color: AppColors.gold, fontSize: 11),
                ),
            ],
          ),
        ),
        if (!settled)
          TextButton(
            onPressed: () => _tabs.animateTo(2),
            child: Text(l10n.translate('fund_tab_settle'),
                style: const TextStyle(color: AppColors.mintGreen)),
          ),
      ]),
    );
  }

  List<Widget> _budgetSection(AppLocalizations l10n, FundReport r) {
    final hasBudget = r.budgetPaisa > 0;
    final group = _group;
    if (!hasBudget && r.lines.isEmpty) {
      if (!_isAdmin || group == null) return const [];
      return [
        _box(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading:
                const Icon(Icons.savings_outlined, color: AppColors.mintGreen),
            title: Text(l10n.translate('fund_budget_cta'),
                style: const TextStyle(color: Colors.white)),
            subtitle: Text(l10n.translate('fund_budget_cta_help'),
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            onTap: () => _editBudget(group),
          ),
        ),
      ];
    }

    final over = r.isOverBudget;
    final projectedOver = hasBudget && r.projectedPaisa > r.budgetPaisa;
    return [
      _box(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _heading(
              l10n.translate('fund_budget_vs_spent'),
              trailing: _isAdmin && group != null
                  ? IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.edit_rounded,
                          size: 18, color: Colors.white54),
                      onPressed: () => _editBudget(group),
                    )
                  : null,
            ),
            if (hasBudget) ...[
              _bar(
                label: l10n.translate('fund_budget_total'),
                value: r.spentPaisa,
                max: r.budgetPaisa,
                color: over ? Colors.redAccent : AppColors.mintGreen,
                trailing: '${_money(r.spentPaisa)} / ${_money(r.budgetPaisa)}',
              ),
              Text(
                over
                    ? l10n.translate('fund_over_by',
                        args: {'amount': _money(-r.leftPaisa)})
                    : l10n.translate('fund_left',
                        args: {'amount': _money(r.leftPaisa)}),
                style: TextStyle(
                    color: over ? Colors.redAccent : Colors.white70,
                    fontSize: 12),
              ),
              const SizedBox(height: 12),
            ],
            if (r.daysElapsed > 0) ...[
              Row(children: [
                const Icon(Icons.speed_rounded, size: 18, color: _fundBlue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.translate('fund_burn', args: {
                      'perDay': _money(r.perDayPaisa),
                      'day': l10n.number(r.daysElapsed),
                      'days': l10n.number(r.totalDays),
                    }),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ]),
              if (r.daysElapsed < r.totalDays)
                Padding(
                  padding: const EdgeInsets.only(left: 26, top: 2, bottom: 8),
                  child: Text(
                    l10n.translate(
                        projectedOver
                            ? 'fund_projection_over'
                            : 'fund_projection',
                        args: {
                          'amount': _money(r.projectedPaisa),
                          'over': _money(r.projectedPaisa - r.budgetPaisa),
                        }),
                    style: TextStyle(
                        color: projectedOver ? AppColors.gold : Colors.white54,
                        fontSize: 12),
                  ),
                ),
            ],
            for (final line in r.lines)
              _bar(
                icon: fundCategoryIcon(line.category),
                label: fundCategoryLabel(l10n, line.category),
                value: line.spentPaisa,
                max: line.budgetPaisa > 0
                    ? line.budgetPaisa
                    : (r.spentPaisa == 0 ? 1 : r.spentPaisa),
                color: line.isOver
                    ? Colors.redAccent
                    : (line.budgetPaisa > 0 && line.ratio > 0.85
                        ? AppColors.gold
                        : AppColors.mintGreen),
                trailing: line.budgetPaisa > 0
                    ? '${_money(line.spentPaisa)} / ${_money(line.budgetPaisa)}'
                    : _money(line.spentPaisa),
              ),
          ],
        ),
      ),
    ];
  }

  Widget _collectionCard(AppLocalizations l10n, FundReport r) {
    final dues = r.collection.where((c) => c.duePaisa > 0).toList();
    return _box(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(
            l10n.translate('fund_collection'),
            trailing: dues.isEmpty
                ? null
                : TextButton.icon(
                    onPressed: () => _shareReminder(r),
                    icon: const Icon(Icons.campaign_rounded,
                        size: 18, color: AppColors.gold),
                    label: Text(l10n.translate('fund_remind'),
                        style: const TextStyle(color: AppColors.gold)),
                  ),
          ),
          _bar(
            label: l10n.translate('fund_collected'),
            value: r.collectedPaisa.clamp(0, r.collectionTargetPaisa),
            max: r.collectionTargetPaisa,
            color: AppColors.gold,
            trailing:
                '${_money(r.collectedPaisa)} / ${_money(r.collectionTargetPaisa)}',
          ),
          if (dues.isEmpty)
            Text(l10n.translate('fund_collection_done'),
                style: const TextStyle(color: AppColors.mintGreen))
          else
            for (final c in dues)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title:
                    Text(c.name, style: const TextStyle(color: Colors.white)),
                subtitle: Text(
                  l10n.translate('fund_paid_of', args: {
                    'paid': _money(c.paidPaisa),
                    'target': _money(c.targetPaisa),
                  }),
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(_money(c.duePaisa),
                      style: const TextStyle(
                          color: AppColors.gold, fontWeight: FontWeight.bold)),
                  if (_isAdmin || c.id.toLowerCase() == _me)
                    IconButton(
                      tooltip: l10n.translate('fund_add_deposit'),
                      icon: const Icon(Icons.add_card_rounded,
                          color: AppColors.mintGreen, size: 20),
                      onPressed: () =>
                          _deposit(memberId: c.id, suggestedPaisa: c.duePaisa),
                    ),
                ]),
              ),
        ],
      ),
    );
  }

  List<Widget> _spendSections(
      AppLocalizations l10n, FundReport r, LedgerSummary summary) {
    final stops = _group?.effectiveStops ?? const <TourStop>[];
    final maxDay = r.byDay.fold<int>(0, (m, d) => d.paisa > m ? d.paisa : m);
    final start = _group?.startDate;
    return [
      if (stops.length > 1 && r.byStop.isNotEmpty)
        _box(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heading(l10n.translate('fund_by_destination')),
              for (final s in stops)
                if ((r.byStop[s.id] ?? 0) > 0)
                  _bar(
                    icon: Icons.place_rounded,
                    label: s.name,
                    value: r.byStop[s.id]!,
                    max: r.spentPaisa,
                    color: _fundBlue,
                    trailing: s.nights > 0
                        ? '${_money(r.byStop[s.id]!)} · '
                            '${l10n.translate('fund_per_night', args: {
                                'amount': _money(r.byStop[s.id]! ~/ s.nights)
                              })}'
                        : null,
                  ),
              if ((r.byStop[null] ?? 0) > 0)
                _bar(
                  icon: Icons.route_rounded,
                  label: l10n.translate('fund_where_none'),
                  value: r.byStop[null]!,
                  max: r.spentPaisa,
                  color: Colors.white38,
                ),
            ],
          ),
        ),
      if (r.byDay.length > 1)
        _box(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heading(l10n.translate('fund_by_day')),
              SizedBox(
                height: 130,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final d in r.byDay.length > 14
                        ? r.byDay.sublist(r.byDay.length - 14)
                        : r.byDay)
                      Expanded(
                        child: Tooltip(
                          message:
                              '${localizedDateFormat('d MMM').format(d.day)}: ${_money(d.paisa)}',
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                height: maxDay == 0 ? 0 : 96 * d.paisa / maxDay,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 3),
                                decoration: BoxDecoration(
                                  color: d.paisa == maxDay
                                      ? AppColors.gold
                                      : AppColors.mintGreen,
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(4)),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                start != null &&
                                        !d.day.isBefore(DateTime(
                                            start.year, start.month, start.day))
                                    ? l10n.translate('fund_day_short', args: {
                                        'n': l10n.number(d.day
                                                .difference(DateTime(start.year,
                                                    start.month, start.day))
                                                .inDays +
                                            1)
                                      })
                                    : localizedDateFormat('d/M').format(d.day),
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 9),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      if (r.topExpenses.isNotEmpty)
        _box(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heading(l10n.translate('fund_top_expenses')),
              for (final e in r.topExpenses)
                _bar(
                  icon: fundCategoryIcon(e.category),
                  label: e.title,
                  value: e.amountPaisa,
                  max: r.topExpenses.first.amountPaisa,
                  color: AppColors.gold,
                ),
            ],
          ),
        ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Expenses
  // ---------------------------------------------------------------------------

  Widget _expensesTab(AppLocalizations l10n) {
    if (_expenses.isEmpty) return _empty(l10n.translate('fund_empty_expenses'));
    final q = _search.text.trim().toLowerCase();
    final stops = _group?.effectiveStops ?? const <TourStop>[];
    final filtered = _expenses.where((e) {
      if (_catFilter != null && e.category != _catFilter) return false;
      if (_stopFilter != null &&
          (e.stopId ?? _group?.stopOn(e.date)?.id) != _stopFilter) {
        return false;
      }
      if (q.isEmpty) return true;
      return e.title.toLowerCase().contains(q) ||
          (e.notes ?? '').toLowerCase().contains(q) ||
          (e.paidByName ?? '').toLowerCase().contains(q);
    }).toList();
    final total = filtered.fold<int>(0, (n, e) => n + e.amountPaisa);
    final categories = {for (final e in _expenses) e.category}.toList()
      ..sort((a, b) {
        final ia = kExpenseCategories.indexOf(a);
        final ib = kExpenseCategories.indexOf(b);
        return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
      });

    // Grouped by day, newest first.
    final days = <DateTime, List<ExpenseItem>>{};
    for (final e in filtered) {
      days
          .putIfAbsent(
              DateTime(e.date.year, e.date.month, e.date.day), () => [])
          .add(e);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 96),
      children: [
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
            hintText: l10n.translate('fund_search'),
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: _card,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _filterChip(l10n.translate('fund_all'), _catFilter == null,
                  () => setState(() => _catFilter = null)),
              for (final c in categories)
                _filterChip(fundCategoryLabel(l10n, c), _catFilter == c,
                    () => setState(() => _catFilter = c)),
            ],
          ),
        ),
        if (stops.length > 1)
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _filterChip(
                    l10n.translate('fund_all_places'),
                    _stopFilter == null,
                    () => setState(() => _stopFilter = null)),
                for (final s in stops)
                  _filterChip(s.name, _stopFilter == s.id,
                      () => setState(() => _stopFilter = s.id)),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            l10n.translate('fund_showing', args: {
              'count': l10n.number(filtered.length),
              'amount': _money(total),
            }),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
        for (final day in days.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 6),
            child: Row(children: [
              Expanded(
                child: Text(localizedDateFormat('EEE, d MMM').format(day.key),
                    style: const TextStyle(
                        color: AppColors.mintGreen,
                        fontWeight: FontWeight.bold)),
              ),
              Text(_money(day.value.fold<int>(0, (n, e) => n + e.amountPaisa)),
                  style: const TextStyle(color: Colors.white70)),
            ]),
          ),
          for (final e in day.value) _expenseTile(l10n, e),
        ],
      ],
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label, style: const TextStyle(fontSize: 12)),
          selected: selected,
          selectedColor: AppColors.mintGreen,
          backgroundColor: _card,
          labelStyle:
              TextStyle(color: selected ? AppColors.darkGreen : Colors.white),
          onSelected: (_) => onTap(),
        ),
      );

  String _splitLabel(AppLocalizations l10n, ExpenseItem e) {
    final count =
        e.splitShares?.length ?? e.participantIds?.length ?? _members.length;
    return l10n.translate('fund_split_label', args: {
      'mode': l10n.translate('fund_split_${e.splitMode.name}'),
      'count': l10n.number(count),
    });
  }

  Widget _expenseTile(AppLocalizations l10n, ExpenseItem e) {
    final stop = _stopName(e.stopId);
    final fromFund = e.paidById == null;
    final symbol = kFundCurrencies
            .where((c) => c.code == e.currency)
            .map((c) => c.symbol)
            .firstOrNull ??
        e.currency;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: ListTile(
        onTap: () => _expenseDetails(l10n, e),
        onLongPress: _canEdit(e.addedByEmail) ? () => _expenseActions(e) : null,
        leading: CircleAvatar(
          backgroundColor:
              (fromFund ? _fundBlue : AppColors.gold).withValues(alpha: 0.16),
          child: Icon(fundCategoryIcon(e.category),
              color: fromFund ? _fundBlue : AppColors.gold, size: 20),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(e.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
            if (e.receiptUrl != null && e.receiptUrl!.isNotEmpty) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: () => _viewReceipt(e.receiptUrl!, e.title),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.mintGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: AppColors.mintGreen.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.receipt_long_rounded,
                          size: 11, color: AppColors.mintGreen),
                      const SizedBox(width: 3),
                      Text(l10n.translate('fund_receipt'),
                          style: const TextStyle(
                              color: AppColors.mintGreen,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          [
            fromFund
                ? l10n.translate('fund_paid_by_fund')
                : l10n.translate('fund_paid_by',
                    args: {'name': e.paidByName ?? e.paidById ?? ''}),
            _splitLabel(l10n, e),
            if (stop != null) stop,
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(_money(e.amountPaisa),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            if (e.isForeign)
              Text(
                  '$symbol${TripLedgerEngine.formatTaka(e.originalMinor ?? 0).replaceAll('৳', '')}',
                  style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  /// Who pays what for one expense, worked out the same way as the books.
  void _expenseDetails(AppLocalizations l10n, ExpenseItem e) {
    final s = TripLedgerEngine.computeLedger(members: _inputs, expenses: [e]);
    final shares = s.rows.where((r) => r.sharePaisa > 0).toList()
      ..sort((a, b) => b.sharePaisa.compareTo(a.sharePaisa));
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _card,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                  '${_money(e.amountPaisa)} · ${fundCategoryLabel(l10n, e.category)} · '
                  '${localizedDateFormat('d MMM yyyy').format(e.date)}',
                  style: const TextStyle(color: Colors.white70)),
              if (e.isForeign)
                Text(
                    l10n.translate('fund_fx_line', args: {
                      'currency': e.currency!,
                      'amount':
                          TripLedgerEngine.plainTakaInput(e.originalMinor ?? 0),
                      'rate': '${e.fxRate}',
                    }),
                    style: const TextStyle(color: Colors.white54)),
              if ((e.notes ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(e.notes!,
                      style: const TextStyle(color: Colors.white70)),
                ),
              if (e.receiptUrl != null && e.receiptUrl!.isNotEmpty) ...[
                const SizedBox(height: 12),
                InkWell(
                  onTap: () => _viewReceipt(e.receiptUrl!, e.title),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.mintGreen.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            e.receiptUrl!,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.receipt_long_rounded,
                                color: AppColors.mintGreen),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l10n.translate('fund_receipt'),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                              Text(l10n.translate('fund_receipt_view'),
                                  style: const TextStyle(
                                      color: AppColors.mintGreen,
                                      fontSize: 11)),
                            ],
                          ),
                        ),
                        const Icon(Icons.open_in_full_rounded,
                            size: 16, color: AppColors.mintGreen),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(_splitLabel(l10n, e),
                  style: const TextStyle(
                      color: AppColors.mintGreen, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              for (final r in shares)
                _bar(
                  label: r.familyCount > 1 && e.splitMode == SplitMode.family
                      ? '${r.name} ×${l10n.number(r.familyCount)}'
                      : r.name,
                  value: r.sharePaisa,
                  max: e.amountPaisa,
                ),
              if (_canEdit(e.addedByEmail))
                Row(children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _editExpense(e);
                    },
                    icon: const Icon(Icons.edit_rounded,
                        color: AppColors.mintGreen),
                    label: Text(l10n.translate('fund_edit'),
                        style: const TextStyle(color: AppColors.mintGreen)),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _confirmDelete(e.title,
                          () => _repository.deleteExpense(widget.tourId, e.id));
                    },
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: Colors.redAccent),
                    label: Text(l10n.translate('fund_delete'),
                        style: const TextStyle(color: Colors.redAccent)),
                  ),
                ]),
            ],
          ),
        ),
      ),
    );
  }

  void _expenseActions(ExpenseItem e) => _itemActions(
        onEdit: () => _editExpense(e),
        onDuplicate: () => _editExpense(e, true),
        subject: e.title,
        delete: () => _repository.deleteExpense(widget.tourId, e.id),
      );

  // ---------------------------------------------------------------------------
  // Settle up
  // ---------------------------------------------------------------------------

  bool _mayRecord(SettlementTransaction s) =>
      _isAdmin ||
      s.fromId?.toLowerCase() == _me ||
      s.toId?.toLowerCase() == _me;

  Widget _settleTab(AppLocalizations l10n, LedgerSummary summary) {
    final activeSettlements = _simplifyDebts
        ? DebtSimplifier.simplifyFromSummary(
            summary,
            fundLabel: l10n.translate('fund_the_fund'),
          )
        : summary.settlements;
    final savedCount = summary.settlements.length - activeSettlements.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
      children: [
        _box(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heading(
                l10n.translate('fund_settle_plan'),
                trailing: activeSettlements.isEmpty
                    ? null
                    : IconButton(
                        tooltip: l10n.translate('fund_share_plan'),
                        icon: const Icon(Icons.share_rounded,
                            color: AppColors.mintGreen),
                        onPressed: () =>
                            _sharePlan(summary, activeSettlements),
                      ),
              ),
              if (summary.settlements.isNotEmpty) ...[
                InkWell(
                  onTap: () =>
                      setState(() => _simplifyDebts = !_simplifyDebts),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _simplifyDebts
                          ? AppColors.mintGreen.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _simplifyDebts
                            ? AppColors.mintGreen
                            : Colors.white12,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bolt_rounded,
                          size: 16,
                          color: _simplifyDebts
                              ? AppColors.mintGreen
                              : Colors.white60,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          l10n.translate('fund_simplify_debts'),
                          style: TextStyle(
                            color: _simplifyDebts
                                ? AppColors.mintGreen
                                : Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_simplifyDebts && savedCount > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.mintGreen,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              l10n.translate('fund_simplify_debts_badge',
                                  args: {'count': l10n.number(savedCount)}),
                              style: const TextStyle(
                                color: AppColors.darkGreen,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (activeSettlements.isEmpty)
                Row(children: [
                  const Icon(Icons.verified_rounded,
                      color: AppColors.mintGreen),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(l10n.translate('fund_all_settled'),
                        style: const TextStyle(color: Colors.white70)),
                  ),
                ])
              else ...[
                Text(
                  _simplifyDebts
                      ? '${l10n.translate('fund_settle_help', args: {
                          'count': l10n.number(activeSettlements.length),
                        })} (${l10n.translate('fund_simplify_debts_active')})'
                      : l10n.translate('fund_settle_help', args: {
                          'count': l10n.number(activeSettlements.length),
                        }),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 8),
                for (final s in activeSettlements) _settlementTile(l10n, s),
              ],
            ],
          ),
        ),
        _heading(
          l10n.translate('fund_payments'),
          trailing: TextButton.icon(
            onPressed: () => _transfer(),
            icon: const Icon(Icons.add_rounded, color: AppColors.mintGreen),
            label: Text(l10n.translate('fund_record_payment'),
                style: const TextStyle(color: AppColors.mintGreen)),
          ),
        ),
        if (_transfers.isEmpty)
          Text(l10n.translate('fund_no_payments'),
              style: const TextStyle(color: Colors.white54, fontSize: 12))
        else
          for (final t in _transfers)
            _box(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: ListTile(
                onLongPress: _canEdit(t.addedByEmail)
                    ? () => _confirmDelete('${t.fromName} → ${t.toName}',
                        () => _repository.deleteTransfer(widget.tourId, t.id))
                    : null,
                leading: const Icon(Icons.payments_rounded,
                    color: AppColors.mintGreen),
                title: Text(
                  '${_party(l10n, t.fromName, t.fromId == null)} → '
                  '${_party(l10n, t.toName, t.toId == null)}',
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  [
                    localizedDateFormat('d MMM, h:mm a').format(t.date),
                    if ((t.notes ?? '').isNotEmpty) t.notes!,
                  ].join(' · '),
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                trailing: Text(_money(t.amountPaisa),
                    style: const TextStyle(
                        color: AppColors.gold, fontWeight: FontWeight.bold)),
              ),
            ),
      ],
    );
  }

  Widget _settlementTile(AppLocalizations l10n, SettlementTransaction s) {
    final mineOut = s.fromId?.toLowerCase() == _me;
    final mineIn = s.toId?.toLowerCase() == _me;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: (mineOut || mineIn)
            ? AppColors.mintGreen.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: (mineOut || mineIn)
                ? AppColors.mintGreen.withValues(alpha: 0.4)
                : Colors.white10),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_party(l10n, s.from, s.fromFund)} → ${_party(l10n, s.to, s.toFund)}',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
              Text(
                l10n.translate(s.fromFund
                    ? 'fund_settle_refund'
                    : s.toFund
                        ? 'fund_settle_topup'
                        : 'fund_settle_direct'),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(_money(s.amountPaisa),
                style: const TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: l10n.translate('fund_bkash_nagad_assist'),
                  icon: const Icon(Icons.account_balance_wallet_rounded,
                      color: Color(0xFFE2136E), size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _showBkashNagadAssist(l10n, s),
                ),
                if (_mayRecord(s)) ...[
                  const SizedBox(width: 6),
                  TextButton(
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8)),
                    onPressed: () => _transfer(suggestion: s),
                    child: Text(l10n.translate('fund_mark_paid'),
                        style: const TextStyle(color: AppColors.mintGreen)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------------------
  // People
  // ---------------------------------------------------------------------------

  Widget _peopleTab(
      AppLocalizations l10n, LedgerSummary summary, FundReport? report) {
    if (summary.rows.isEmpty) return _empty(l10n.translate('fund_no_members'));
    final rows = [...summary.rows]
      ..sort((a, b) => a.netPaisa.compareTo(b.netPaisa));
    final due = {
      for (final c in report?.collection ?? const <CollectionRow>[])
        c.id.toLowerCase(): c,
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
      children: [
        for (final r in rows)
          _box(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      [
                        r.name,
                        if (r.familyCount > 1)
                          '(${l10n.translate('fund_family_of', args: {
                                'n': l10n.number(r.familyCount)
                              })})',
                        if (r.isFormerMember) l10n.translate('fund_former'),
                      ].join(' '),
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (r.netPaisa == 0
                              ? Colors.white24
                              : r.netPaisa > 0
                                  ? AppColors.mintGreen
                                  : Colors.redAccent)
                          .withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      r.netPaisa == 0
                          ? l10n.translate('fund_settled')
                          : l10n.translate(
                              r.netPaisa > 0 ? 'fund_gets' : 'fund_owes',
                              args: {'amount': _money(r.netPaisa.abs())}),
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 14, runSpacing: 4, children: [
                  _kv(l10n.translate('fund_k_deposit'), r.depositPaisa),
                  _kv(l10n.translate('fund_k_paid'), r.directPaidPaisa),
                  _kv(l10n.translate('fund_k_share'), r.sharePaisa),
                  if (r.transfersOutPaisa > 0)
                    _kv(l10n.translate('fund_k_sent'), r.transfersOutPaisa),
                  if (r.transfersInPaisa > 0)
                    _kv(l10n.translate('fund_k_received'), r.transfersInPaisa),
                  if ((due[r.id.toLowerCase()]?.duePaisa ?? 0) > 0)
                    _kv(l10n.translate('fund_k_due'),
                        due[r.id.toLowerCase()]!.duePaisa,
                        color: AppColors.gold),
                ]),
              ],
            ),
          ),
      ],
    );
  }

  Widget _kv(String k, int paisa, {Color color = Colors.white70}) => Text.rich(
        TextSpan(children: [
          TextSpan(
              text: '$k ',
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
          TextSpan(
              text: _money(paisa),
              style: TextStyle(color: color, fontSize: 12)),
        ]),
      );

  // ---------------------------------------------------------------------------
  // Deposits
  // ---------------------------------------------------------------------------

  Widget _depositsTab(AppLocalizations l10n) {
    if (_deposits.isEmpty) return _empty(l10n.translate('fund_empty_deposits'));
    final byMember = <String, int>{};
    for (final d in _deposits) {
      byMember[d.memberName] = (byMember[d.memberName] ?? 0) + d.amountPaisa;
    }
    final total = byMember.values.fold<int>(0, (a, b) => a + b);
    final top = byMember.values.fold<int>(0, (m, v) => v > m ? v : m);
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
      children: [
        _box(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heading(l10n.translate('fund_deposits_by_member'),
                  trailing: Text(_money(total),
                      style: const TextStyle(
                          color: AppColors.gold, fontWeight: FontWeight.bold))),
              for (final e in byMember.entries)
                _bar(
                    label: e.key,
                    value: e.value,
                    max: top,
                    color: AppColors.gold),
            ],
          ),
        ),
        for (final d in _deposits)
          _box(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: ListTile(
              onLongPress: _canEdit(d.addedByEmail)
                  ? () => _itemActions(
                        onEdit: () => _deposit(existing: d),
                        subject: '${d.memberName} — ${_money(d.amountPaisa)}',
                        delete: () =>
                            _repository.deleteDeposit(widget.tourId, d.id),
                      )
                  : null,
              leading: const Icon(Icons.south_west_rounded,
                  color: AppColors.mintGreen),
              title: Text(d.memberName,
                  style: const TextStyle(color: Colors.white)),
              subtitle: Text(
                [
                  localizedDateFormat('d MMM yyyy').format(d.date),
                  if ((d.notes ?? '').isNotEmpty) d.notes!,
                ].join(' · '),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              trailing: Text(_money(d.amountPaisa),
                  style: const TextStyle(
                      color: AppColors.gold, fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _addMenu(TourGroup? group) {
    final l10n = context.l10n;
    Widget item(IconData icon, Color color, String title, String sub,
            VoidCallback onTap) =>
        ListTile(
          leading: Icon(icon, color: color),
          title: Text(title, style: const TextStyle(color: Colors.white)),
          subtitle: Text(sub, style: const TextStyle(color: Colors.white54)),
          onTap: () {
            Navigator.pop(context);
            onTap();
          },
        );
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _card,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            item(
                Icons.receipt_long_rounded,
                AppColors.mintGreen,
                l10n.translate('fund_add_expense'),
                l10n.translate('fund_add_expense_sub'),
                _editExpense),
            item(
                Icons.savings_rounded,
                AppColors.gold,
                l10n.translate('fund_add_deposit'),
                l10n.translate('fund_add_deposit_sub'),
                _deposit),
            item(
                Icons.payments_rounded,
                _fundBlue,
                l10n.translate('fund_record_payment'),
                l10n.translate('fund_record_payment_sub'),
                _transfer),
            if (_isAdmin && group != null)
              item(
                  Icons.pie_chart_rounded,
                  Colors.white70,
                  l10n.translate('fund_budget_title'),
                  l10n.translate('fund_budget_sub'),
                  () => _editBudget(group)),
          ],
        ),
      ),
    );
  }

  Future<void> _editExpense(
      [ExpenseItem? existing, bool duplicate = false]) async {
    if (_members.isEmpty) return;
    final draft = await showExpenseEditor(
      context,
      members: _members,
      group: _group,
      me: _me,
      existing: existing,
    );
    if (draft == null || !mounted) return;
    await _run(() async {
      String? finalReceiptUrl = draft.receiptUrl;
      if (draft.newReceiptFile != null) {
        final upload = await TourMediaUploader.start(
          tourId: widget.tourId,
          folder: 'expenses',
          file: draft.newReceiptFile!,
          contentType: 'image/jpeg',
          extension: 'jpg',
          maxBytes: 10 * 1024 * 1024,
        );
        finalReceiptUrl = await upload.finish();
      }

      if (existing == null || duplicate) {
        await _repository.addExpense(
          tourId: widget.tourId,
          title: draft.title,
          amountPaisa: draft.amountPaisa,
          paidById: draft.paidById,
          paidByName: draft.paidByName,
          category: draft.category,
          date: draft.date,
          notes: draft.notes,
          participantIds: draft.participantIds,
          splitMode: draft.splitMode,
          splitShares: draft.splitShares,
          stopId: draft.stopId,
          currency: draft.currency,
          originalMinor: draft.originalMinor,
          fxRate: draft.fxRate,
          receiptUrl: finalReceiptUrl,
        );
      } else {
        await _repository.updateExpense(ExpenseItem(
          id: existing.id,
          tourId: widget.tourId,
          title: draft.title,
          amountPaisa: draft.amountPaisa,
          paidById: draft.paidById,
          paidByName: draft.paidByName,
          category: draft.category,
          date: draft.date,
          notes: draft.notes,
          addedByEmail: existing.addedByEmail,
          participantIds: draft.participantIds,
          splitMode: draft.splitMode,
          splitShares: draft.splitShares,
          stopId: draft.stopId,
          currency: draft.currency,
          originalMinor: draft.originalMinor,
          fxRate: draft.fxRate,
          receiptUrl: finalReceiptUrl,
        ));
      }
    }, 'fund_err_save');
  }

  Future<void> _deposit(
      {DepositItem? existing, String? memberId, int? suggestedPaisa}) async {
    final draft = await showDepositSheet(
      context,
      members: _members,
      me: _me,
      existing: existing,
      memberId: memberId,
      suggestedPaisa: suggestedPaisa,
    );
    if (draft == null || !mounted) return;
    await _run(() async {
      if (existing == null) {
        await _repository.addDeposit(
          tourId: widget.tourId,
          memberId: draft.memberId,
          memberName: draft.memberName,
          amountPaisa: draft.amountPaisa,
          date: draft.date,
          notes: draft.notes,
        );
      } else {
        await _repository.updateDeposit(DepositItem(
          id: existing.id,
          tourId: widget.tourId,
          memberId: draft.memberId,
          memberName: draft.memberName,
          amountPaisa: draft.amountPaisa,
          date: draft.date,
          notes: draft.notes,
          addedByEmail: existing.addedByEmail,
        ));
      }
    }, 'fund_err_save');
  }

  Future<void> _transfer({SettlementTransaction? suggestion}) async {
    final draft = await showTransferSheet(
      context,
      members: _members,
      me: _me,
      isAdmin: _isAdmin,
      suggestion: suggestion,
    );
    if (draft == null || !mounted) return;
    final l10n = context.l10n;
    await _run(() async {
      await _repository.addTransfer(
        tourId: widget.tourId,
        fromId: draft.fromId,
        fromName: draft.fromName,
        toId: draft.toId,
        toName: draft.toName,
        amountPaisa: draft.amountPaisa,
        date: draft.date,
        notes: draft.notes,
      );
      _toast(l10n.translate('fund_payment_saved'));
    }, 'fund_err_save');
  }

  Future<void> _editBudget(TourGroup group) async {
    final budget = await showBudgetSheet(
      context,
      budget: group.fundBudget,
      headcount: _headcount,
      totalDays: group.totalDays,
    );
    if (budget == null || !mounted) return;
    await _run(() => _repository.saveFundBudget(widget.tourId, budget),
        'fund_err_save');
  }

  void _itemActions({
    required VoidCallback onEdit,
    VoidCallback? onDuplicate,
    required String subject,
    required Future<void> Function() delete,
  }) {
    final l10n = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _card,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  const Icon(Icons.edit_rounded, color: AppColors.mintGreen),
              title: Text(l10n.translate('fund_edit'),
                  style: const TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                onEdit();
              },
            ),
            if (onDuplicate != null)
              ListTile(
                leading: const Icon(Icons.copy_rounded, color: _fundBlue),
                title: Text(l10n.translate('fund_duplicate'),
                    style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  onDuplicate();
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: Colors.redAccent),
              title: Text(l10n.translate('fund_delete'),
                  style: const TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(subject, delete);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
      String subject, Future<void> Function() delete) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: _card,
        title: Text(l10n.translate('fund_delete_confirm'),
            style: const TextStyle(color: Colors.white)),
        content: Text(subject, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l10n.translate('tour_cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(l10n.translate('fund_delete'),
                  style: const TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok != true) return;
    await _run(delete, 'fund_err_delete');
  }

  // ---------------------------------------------------------------------------
  // Sharing and export
  // ---------------------------------------------------------------------------

  void _sharePlan(LedgerSummary summary,
      [List<SettlementTransaction>? activeSettlements]) {
    final l10n = context.l10n;
    final settlements = activeSettlements ?? summary.settlements;
    final lines = [
      l10n.translate('fund_share_plan_title',
          args: {'tour': _group?.name ?? ''}),
      '',
      for (final s in settlements)
        '• ${_party(l10n, s.from, s.fromFund)} → '
            '${_party(l10n, s.to, s.toFund)}: ${_money(s.amountPaisa)}',
      '',
      l10n.translate('fund_share_totals', args: {
        'spent': _money(summary.totalExpensePaisa),
        'perHead': _money(summary.perHeadCostPaisa),
      }),
    ];
    // ignore: deprecated_member_use
    Share.share(lines.join('\n'), subject: _group?.name);
  }

  void _shareReminder(FundReport r) {
    final l10n = context.l10n;
    final lines = [
      l10n.translate('fund_remind_title', args: {'tour': _group?.name ?? ''}),
      '',
      for (final c in r.collection.where((c) => c.duePaisa > 0))
        '• ${c.name}: ${_money(c.duePaisa)}',
      '',
      l10n.translate('fund_remind_footer', args: {
        'collected': _money(r.collectedPaisa),
        'target': _money(r.collectionTargetPaisa),
      }),
    ];
    // ignore: deprecated_member_use
    Share.share(lines.join('\n'), subject: _group?.name);
  }

  /// CSV for the audit. Member emails are left out; names and amounts are kept.
  Future<void> _exportCsv(LedgerSummary summary, FundReport? report) async {
    final group = _group;
    final buffer = StringBuffer();

    String cell(Object? value) {
      final text = value?.toString() ?? '';
      if (text.contains(',') || text.contains('"') || text.contains('\n')) {
        return '"${text.replaceAll('"', '""')}"';
      }
      return text;
    }

    void line(List<Object?> values) =>
        buffer.writeln(values.map(cell).join(','));
    String taka(int paisa) => (paisa / 100).toStringAsFixed(2);

    line([group?.name ?? 'Tour fund', 'Audit statement']);
    line(['Route', group == null ? '' : group.destinationSummary]);
    line([
      'Generated',
      DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())
    ]);
    line([]);
    line(['Summary']);
    line(['Deposits (BDT)', taka(summary.totalDepositsPaisa)]);
    line(['Expenses (BDT)', taka(summary.totalExpensePaisa)]);
    line(['Fund balance (BDT)', taka(summary.fundBalancePaisa)]);
    line(['People', summary.headcount]);
    if (report != null && report.budgetPaisa > 0) {
      line(['Budget (BDT)', taka(report.budgetPaisa)]);
      line(['Projected (BDT)', taka(report.projectedPaisa)]);
    }
    line([]);
    line(['Category', 'Budget (BDT)', 'Spent (BDT)', 'Left (BDT)']);
    for (final l in report?.lines ?? const <BudgetLine>[]) {
      line([
        l.category,
        taka(l.budgetPaisa),
        taka(l.spentPaisa),
        l.budgetPaisa > 0 ? taka(l.leftPaisa) : '',
      ]);
    }
    line([]);
    line([
      'Date',
      'Category',
      'Title',
      'Paid by',
      'Split',
      'Place',
      'Original',
      'Rate',
      'BDT',
    ]);
    for (final e in _expenses) {
      line([
        DateFormat('yyyy-MM-dd').format(e.date),
        e.category,
        e.title,
        e.paidById == null ? 'Fund' : (e.paidByName ?? 'Member'),
        e.splitMode.name,
        _stopName(e.stopId ?? group?.stopOn(e.date)?.id) ?? '',
        e.isForeign
            ? '${e.currency} ${TripLedgerEngine.plainTakaInput(e.originalMinor ?? 0)}'
            : '',
        e.isForeign ? e.fxRate : '',
        taka(e.amountPaisa),
      ]);
    }
    line([]);
    line(['Date', 'Member', 'Deposit (BDT)', 'Note']);
    for (final d in _deposits) {
      line([
        DateFormat('yyyy-MM-dd').format(d.date),
        d.memberName,
        taka(d.amountPaisa),
        d.notes ?? '',
      ]);
    }
    line([]);
    line(['Date', 'From', 'To', 'Payment (BDT)', 'Note']);
    for (final t in _transfers) {
      line([
        DateFormat('yyyy-MM-dd').format(t.date),
        t.fromName,
        t.toName,
        taka(t.amountPaisa),
        t.notes ?? '',
      ]);
    }
    line([]);
    line([
      'Member',
      'Deposits',
      'Paid directly',
      'Payments sent',
      'Payments received',
      'Share',
      'Net (+ gets / - owes)',
    ]);
    for (final r in summary.rows) {
      line([
        r.isFormerMember ? '${r.name} (former)' : r.name,
        taka(r.depositPaisa),
        taka(r.directPaidPaisa),
        taka(r.transfersOutPaisa),
        taka(r.transfersInPaisa),
        taka(r.sharePaisa),
        taka(r.netPaisa),
      ]);
    }
    line([]);
    line(['Who pays', 'To whom', 'BDT']);
    for (final s in summary.settlements) {
      line([s.from, s.to, taka(s.amountPaisa)]);
    }

    // A BOM lets Excel read the Bengali text correctly. UTF-16 code units
    // would corrupt it, so the text is encoded as UTF-8.
    final bytes =
        Uint8List.fromList(const Utf8Codec().encode('﻿${buffer.toString()}'));
    final name =
        'Bhromon_Fund_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
    // ignore: deprecated_member_use
    await Share.shareXFiles(
      [XFile.fromData(bytes, mimeType: 'text/csv', name: name)],
      subject: name,
    );
  }

  void _viewReceipt(String url, String title) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      height: 300,
                      color: const Color(0xFF1B4332),
                      child: const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.mintGreen),
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B4332),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.broken_image_rounded,
                            size: 48, color: Colors.white54),
                        const SizedBox(height: 12),
                        Text(
                          title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        const Text('রসিদের ছবি লোড করা যায়নি',
                            style:
                                TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: CircleAvatar(
                radius: 18,
                backgroundColor: Colors.black54,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 20),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBkashNagadAssist(AppLocalizations l10n, SettlementTransaction s) {
    final amountTaka = TripLedgerEngine.plainTakaInput(s.amountPaisa);
    final recipientName = _party(l10n, s.to, s.toFund);
    final senderName = _party(l10n, s.from, s.fromFund);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
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
                      color: const Color(0xFFE2136E).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('৳',
                        style: TextStyle(
                            color: Color(0xFFE2136E),
                            fontWeight: FontWeight.bold,
                            fontSize: 18)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.translate('fund_bkash_nagad_assist'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
                        ),
                        Text(
                          '$senderName → $recipientName',
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                l10n.translate('fund_bkash_nagad_help'),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l10n.translate('fund_balance_owed'),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13)),
                        Text('৳ $amountTaka',
                            style: const TextStyle(
                                color: AppColors.gold,
                                fontWeight: FontWeight.bold,
                                fontSize: 18)),
                      ],
                    ),
                    const Divider(color: Colors.white12, height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(recipientName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        if (s.toId != null && s.toId!.isNotEmpty)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact),
                            icon: const Icon(Icons.copy_rounded,
                                size: 14, color: AppColors.mintGreen),
                            label: Text(l10n.translate('fund_copy_payee'),
                                style: const TextStyle(
                                    color: AppColors.mintGreen, fontSize: 12)),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: s.toId!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      l10n.translate('fund_payee_copied')),
                                  backgroundColor: AppColors.midGreen,
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFE2136E),
                        side: const BorderSide(color: Color(0xFFE2136E)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: Text(l10n.translate('fund_copy_amount',
                          args: {'amount': amountTaka})),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: amountTaka));
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n.translate('fund_amount_copied',
                                args: {'amount': amountTaka})),
                            backgroundColor: AppColors.midGreen,
                          ),
                        );
                      },
                    ),
                  ),
                  if (_mayRecord(s)) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.mintGreen,
                          foregroundColor: AppColors.darkGreen,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.check_circle_outline_rounded,
                            size: 16),
                        label: Text(l10n.translate('fund_mark_paid')),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _transfer(suggestion: s);
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
