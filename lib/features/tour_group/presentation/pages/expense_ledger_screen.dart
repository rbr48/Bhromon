import '../widgets/group_back_button.dart';
import 'dart:async';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'dart:convert';

import 'package:bhromon/core/media/media_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../data/tour_group_repository.dart';
import '../../data/tour_media_journal.dart';
import '../../data/tour_media_uploader.dart';
import '../../domain/models/expense_models.dart';
import '../../domain/models/itinerary_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/debt_simplifier.dart';
import '../../domain/services/fund_analytics.dart';
import '../../domain/services/media_rules.dart';
import '../../domain/services/trip_ledger_engine.dart';
import '../../data/monthly_ledger_pdf.dart';
import '../../domain/services/bangla_qr_engine.dart';
import '../../domain/services/payment_profile_service.dart';
import '../monthly_ledger_pdf_export.dart';
import '../widgets/bangla_qr_view.dart';
import '../widgets/fund/expense_editor.dart';
import '../widgets/fund/fund_sheets.dart';
import '../widgets/fund/mfs_settlement_sheet.dart';
import '../widgets/mess/mess_balance_sheet.dart';
import '../../../../core/localization/localized_date.dart';
import '../../../../core/utils/logger.dart';

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
  List<SettlementRecord> _settlements = const [];
  bool _loaded = false;

  // Expense list filters.
  final _search = TextEditingController();
  String? _catFilter;
  String? _stopFilter;
  // A family looks at one month of spending at a time; a trip shows everything.
  DateTime _month = monthOf(DateTime.now());
  bool _allMonths = false;
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
    on(_repository.watchSettlements(widget.tourId), (s) => _settlements = s);
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

  String _money(int paisa) =>
      context.l10n.number(TripLedgerEngine.formatTaka(paisa));

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
    final allTransfers = [
      ..._transfers,
      for (final s in _settlements.where((x) => x.isVerified))
        TransferItem(
          id: s.id,
          tourId: s.tourId,
          fromId: s.fromMemberId,
          fromName: s.fromMemberName,
          toId: s.toMemberId,
          toName: s.toMemberName,
          amountPaisa: s.creditedPaisa,
          date: s.date,
          notes: s.mfsInfo.provider.requiresTrxId
              ? '${s.mfsInfo.provider.name.toUpperCase()} TrxID: ${s.mfsInfo.trxId ?? ''}'
              : (s.notes ?? 'MFS Settlement'),
          addedByEmail: s.addedByEmail,
        ),
    ];
    final summary = TripLedgerEngine.computeLedger(
      members: _inputs,
      expenses: _expenses,
      deposits: _deposits,
      transfers: allTransfers,
    );
    final group = _group;
    final report = group == null
        ? null
        : FundReport.build(
            group: group,
            members: _inputs,
            expenses: _expenses,
            deposits: _deposits,
            transfers: allTransfers,
          );

    return GroupPopScope(
      tourId: widget.tourId,
      child: Scaffold(
        backgroundColor: context.forest.surfaceFor(_bg),
        appBar: AppBar(
          leading: GroupBackButton(tourId: widget.tourId),
          elevation: 0,
          backgroundColor: context.forest.surfaceFor(_card),
          foregroundColor: context.forest.text,
          title: Text(l10n.translate('fund_title'),
              style: TextStyle(
                  color: context.forest.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          actions: [
            if (_isAdmin && group != null)
              IconButton(
                icon: const Icon(Icons.account_balance_wallet_outlined),
                tooltip: l10n.translate('fund_budget_title'),
                onPressed: () => _editBudget(group),
              ),
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_rounded),
              tooltip: l10n.translate('fund_export_pdf'),
              onPressed: _exportMonthlyPdf,
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
            unselectedLabelColor: context.forest.text60,
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
      ),
    );
  }

  Widget _box({required Widget child, EdgeInsets? padding}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: padding ?? const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.forest.surfaceFor(_card),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.forest.divider10),
        ),
        child: child,
      );

  Widget _heading(String text, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: context.forest.text,
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
              style: TextStyle(color: context.forest.text54)),
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
              style: TextStyle(color: context.forest.text54, fontSize: 11)),
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
              Icon(icon, size: 16, color: context.forest.text70),
              const SizedBox(width: 6),
            ],
            Expanded(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: context.forest.text, fontSize: 13))),
            Text(trailing ?? _money(value),
                style: TextStyle(color: context.forest.text70, fontSize: 12)),
          ]),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 7,
              color: color,
              backgroundColor: context.forest.divider10,
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
                  _money(summary.totalExpensePaisa), context.forest.text),
              _stat(l10n.translate('fund_collected'),
                  _money(summary.totalDepositsPaisa), AppColors.gold),
            ]),
            const SizedBox(height: 10),
            Text(
              l10n.translate('fund_per_head_line', args: {
                'people': l10n.number(summary.headcount),
                'amount': _money(summary.perHeadCostPaisa),
              }),
              style: TextStyle(color: context.forest.text54, fontSize: 12),
            ),
            if (summary.fundBalancePaisa < 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(l10n.translate('fund_negative_warning'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: context.forest.readable(Colors.redAccent),
                        fontSize: 12)),
              ),
          ]),
        ),
        _box(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.mintGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.picture_as_pdf_rounded,
                    color: AppColors.mintGreen, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.translate('fund_export_pdf'),
                      style: TextStyle(
                          color: context.forest.text,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                    ),
                    Text(
                      '${BanglaLedgerFormatter.formatMonthYearBangla(_month.year, _month.month)} এর হিসাব ও অডিট স্টেটমেন্ট',
                      style:
                          TextStyle(color: context.forest.text54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                onPressed: _exportMonthlyPdf,
                child: const Text('PDF',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
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
        ? context.forest.text70
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
                style: TextStyle(color: context.forest.text54, fontSize: 11),
              ),
              if (due != null && due.duePaisa > 0)
                Text(
                  l10n.translate('fund_me_due',
                      args: {'amount': _money(due.duePaisa)}),
                  style: TextStyle(
                      color: context.forest.readable(AppColors.gold),
                      fontSize: 11),
                ),
            ],
          ),
        ),
        if (!settled)
          TextButton(
            onPressed: () => _tabs.animateTo(2),
            child: Text(l10n.translate('fund_tab_settle'),
                style: TextStyle(color: context.forest.accentText)),
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
            leading: Icon(Icons.account_balance_wallet_outlined,
                color: context.forest.accentText),
            title: Text(
                l10n.translate(group.isHousehold
                    ? 'fund_budget_cta_family'
                    : 'fund_budget_cta'),
                style: TextStyle(color: context.forest.text)),
            subtitle: Text(
                l10n.translate(group.isHousehold
                    ? 'fund_budget_cta_help_family'
                    : 'fund_budget_cta_help'),
                style: TextStyle(color: context.forest.text54, fontSize: 12)),
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
                      icon: Icon(Icons.edit_rounded,
                          size: 18, color: context.forest.text54),
                      onPressed: () => _editBudget(group),
                    )
                  : null,
            ),
            if (hasBudget) ...[
              if (r.alertLevel.isCritical)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          size: 18, color: Colors.redAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.translate('fund_alert_critical'),
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else if (r.alertLevel.isCaution)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.gold.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          size: 18, color: AppColors.gold),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.translate('fund_alert_caution'),
                          style: TextStyle(
                            color: context.forest.readable(AppColors.gold),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              _bar(
                label: l10n.translate('fund_budget_total'),
                value: r.spentPaisa,
                max: r.budgetPaisa,
                color: over
                    ? Colors.redAccent
                    : (r.alertLevel.isCaution
                        ? AppColors.gold
                        : AppColors.mintGreen),
                trailing: '${_money(r.spentPaisa)} / ${_money(r.budgetPaisa)}',
              ),
              Text(
                over
                    ? l10n.translate('fund_over_by',
                        args: {'amount': _money(-r.leftPaisa)})
                    : l10n.translate('fund_left',
                        args: {'amount': _money(r.leftPaisa)}),
                style: TextStyle(
                    color: over
                        ? context.forest.readable(Colors.redAccent)
                        : context.forest.text70,
                    fontSize: 12),
              ),
              const SizedBox(height: 12),
            ],
            // A family circle has no trip days, so it has no daily burn or projection.
            if (!(group?.isFamily ?? false) && r.daysElapsed > 0) ...[
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
                    style: TextStyle(color: context.forest.text, fontSize: 12),
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
                        color: projectedOver
                            ? context.forest.readable(AppColors.gold)
                            : context.forest.text54,
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
                    : (line.alertLevel.isCaution
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
                    icon: Icon(Icons.campaign_rounded,
                        size: 18,
                        color: context.forest.readable(AppColors.gold)),
                    label: Text(l10n.translate('fund_remind'),
                        style: TextStyle(
                            color: context.forest.readable(AppColors.gold))),
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
                style: TextStyle(color: context.forest.accentText))
          else
            for (final c in dues)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title:
                    Text(c.name, style: TextStyle(color: context.forest.text)),
                subtitle: Text(
                  l10n.translate('fund_paid_of', args: {
                    'paid': _money(c.paidPaisa),
                    'target': _money(c.targetPaisa),
                  }),
                  style: TextStyle(color: context.forest.text54, fontSize: 11),
                ),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(_money(c.duePaisa),
                      style: TextStyle(
                          color: context.forest.readable(AppColors.gold),
                          fontWeight: FontWeight.bold)),
                  if (_isAdmin || c.id.toLowerCase() == _me)
                    IconButton(
                      tooltip: l10n.translate('fund_add_deposit'),
                      icon: Icon(Icons.add_card_rounded,
                          color: context.forest.accentText, size: 20),
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
                  color: context.forest.text38,
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
                                style: TextStyle(
                                    color: context.forest.text54, fontSize: 9),
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

  /// Steps through the months of a family's spending, or shows every month.
  Widget _monthBar(AppLocalizations l10n, List<ExpenseItem> inMonth) {
    final thisMonth = monthOf(DateTime.now());
    final nextMonth = DateTime(_month.year, _month.month + 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: l10n.translate('fund_month_prev'),
              icon: Icon(Icons.chevron_left_rounded,
                  color: context.forest.text70),
              onPressed: _allMonths
                  ? null
                  : () => setState(
                      () => _month = DateTime(_month.year, _month.month - 1)),
            ),
            Expanded(
              child: Text(
                _allMonths
                    ? l10n.translate('fund_month_all_label')
                    : localizedDateFormat('MMMM yyyy').format(_month),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: context.forest.text, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              tooltip: l10n.translate('fund_month_next'),
              icon: Icon(Icons.chevron_right_rounded,
                  color: context.forest.text70),
              // No month after the current one.
              onPressed: _allMonths || nextMonth.isAfter(thisMonth)
                  ? null
                  : () => setState(() => _month = nextMonth),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => setState(() => _allMonths = !_allMonths),
            child: Text(l10n
                .translate(_allMonths ? 'fund_month_one' : 'fund_month_all')),
          ),
        ),
        if (!_allMonths && inMonth.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(l10n.translate('fund_month_empty'),
                textAlign: TextAlign.center,
                style: TextStyle(color: context.forest.text54, fontSize: 13)),
          ),
      ],
    );
  }

  Widget _expensesTab(AppLocalizations l10n) {
    if (_expenses.isEmpty) return _empty(l10n.translate('fund_empty_expenses'));
    final q = _search.text.trim().toLowerCase();
    final stops = _group?.effectiveStops ?? const <TourStop>[];
    final family = _group?.isFamily ?? false;
    final inMonth =
        family && !_allMonths ? expensesInMonth(_expenses, _month) : _expenses;
    final filtered = inMonth.where((e) {
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
    final offered = expenseCategoriesForGroup(_group);
    final categories = {for (final e in _expenses) e.category}.toList()
      ..sort((a, b) {
        final ia = offered.indexOf(a);
        final ib = offered.indexOf(b);
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
        if (family) _monthBar(l10n, inMonth),
        if (family) const SizedBox(height: 4),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          style: TextStyle(color: context.forest.text),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon:
                Icon(Icons.search_rounded, color: context.forest.text54),
            hintText: l10n.translate('fund_search'),
            hintStyle: TextStyle(color: context.forest.text38),
            filled: true,
            fillColor: context.forest.surfaceFor(_card),
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
            style: TextStyle(color: context.forest.text54, fontSize: 12),
          ),
        ),
        for (final day in days.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 6),
            child: Row(children: [
              Expanded(
                child: Text(localizedDateFormat('EEE, d MMM').format(day.key),
                    style: TextStyle(
                        color: context.forest.accentText,
                        fontWeight: FontWeight.bold)),
              ),
              Text(_money(day.value.fold<int>(0, (n, e) => n + e.amountPaisa)),
                  style: TextStyle(color: context.forest.text70)),
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
          backgroundColor: context.forest.surfaceFor(_card),
          labelStyle: TextStyle(
              color: selected ? AppColors.darkGreen : context.forest.text),
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
        color: context.forest.surfaceFor(_card),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.forest.divider10),
      ),
      child: ListTile(
        onTap: () => _expenseDetails(l10n, e),
        onLongPress: _canEdit(e.addedByEmail) ? () => _expenseActions(e) : null,
        leading: CircleAvatar(
          backgroundColor:
              (fromFund ? _fundBlue : AppColors.gold).withValues(alpha: 0.16),
          child: Icon(fundCategoryIcon(e.category),
              color: fromFund
                  ? _fundBlue
                  : context.forest.readable(AppColors.gold),
              size: 20),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(e.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: context.forest.text, fontWeight: FontWeight.w600)),
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
                      Icon(Icons.receipt_long_rounded,
                          size: 11, color: context.forest.accentText),
                      const SizedBox(width: 3),
                      Text(l10n.translate('fund_receipt'),
                          style: TextStyle(
                              color: context.forest.accentText,
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
          style: TextStyle(color: context.forest.text54, fontSize: 11),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(_money(e.amountPaisa),
                style: TextStyle(
                    color: context.forest.text, fontWeight: FontWeight.bold)),
            if (e.isForeign)
              Text(
                  '$symbol${TripLedgerEngine.formatTaka(e.originalMinor ?? 0).replaceAll('৳', '')}',
                  style: TextStyle(color: context.forest.text38, fontSize: 10)),
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
      backgroundColor: context.forest.surfaceFor(_card),
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.title,
                  style: TextStyle(
                      color: context.forest.text,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                  '${_money(e.amountPaisa)} · ${fundCategoryLabel(l10n, e.category)} · '
                  '${localizedDateFormat('d MMM yyyy').format(e.date)}',
                  style: TextStyle(color: context.forest.text70)),
              if (e.isForeign)
                Text(
                    l10n.translate('fund_fx_line', args: {
                      'currency': e.currency!,
                      'amount':
                          TripLedgerEngine.plainTakaInput(e.originalMinor ?? 0),
                      'rate': '${e.fxRate}',
                    }),
                    style: TextStyle(color: context.forest.text54)),
              if ((e.notes ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(e.notes!,
                      style: TextStyle(color: context.forest.text70)),
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
                            signedMediaUrl(e.receiptUrl!),
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                                Icons.receipt_long_rounded,
                                color: context.forest.accentText),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l10n.translate('fund_receipt'),
                                  style: TextStyle(
                                      color: context.forest.text,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                              Text(l10n.translate('fund_receipt_view'),
                                  style: TextStyle(
                                      color: context.forest.accentText,
                                      fontSize: 11)),
                            ],
                          ),
                        ),
                        Icon(Icons.open_in_full_rounded,
                            size: 16, color: context.forest.accentText),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(_splitLabel(l10n, e),
                  style: TextStyle(
                      color: context.forest.accentText,
                      fontWeight: FontWeight.bold)),
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
                    icon: Icon(Icons.edit_rounded,
                        color: context.forest.accentText),
                    label: Text(l10n.translate('fund_edit'),
                        style: TextStyle(color: context.forest.accentText)),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _confirmDelete(e.title,
                          () => _repository.deleteExpense(widget.tourId, e.id));
                    },
                    icon: Icon(Icons.delete_outline_rounded,
                        color: context.forest.readable(Colors.redAccent)),
                    label: Text(l10n.translate('fund_delete'),
                        style: TextStyle(
                            color: context.forest.readable(Colors.redAccent))),
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
                        icon: Icon(Icons.share_rounded,
                            color: context.forest.accentText),
                        onPressed: () => _sharePlan(summary, activeSettlements),
                      ),
              ),
              if (summary.settlements.isNotEmpty) ...[
                InkWell(
                  onTap: () => setState(() => _simplifyDebts = !_simplifyDebts),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _simplifyDebts
                          ? AppColors.mintGreen.withValues(alpha: 0.15)
                          : context.forest.text.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _simplifyDebts
                            ? AppColors.mintGreen
                            : context.forest.divider12,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bolt_rounded,
                          size: 16,
                          color: _simplifyDebts
                              ? context.forest.accentText
                              : context.forest.text60,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          l10n.translate('fund_simplify_debts'),
                          style: TextStyle(
                            color: _simplifyDebts
                                ? context.forest.accentText
                                : context.forest.text70,
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
                  Icon(Icons.verified_rounded,
                      color: context.forest.accentText),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(l10n.translate('fund_all_settled'),
                        style: TextStyle(color: context.forest.text70)),
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
                  style: TextStyle(color: context.forest.text54, fontSize: 12),
                ),
                const SizedBox(height: 8),
                for (final s in activeSettlements) _settlementTile(l10n, s),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.translate('fund_payments'),
                style: TextStyle(
                  color: context.forest.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _openMfsSettlementSheet(),
                    icon: const Icon(Icons.receipt_long,
                        size: 15, color: Color(0xFFE2136E)),
                    label: Text(l10n.translate('fund_record_mfs'),
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFE2136E))),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE2136E)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _transfer(),
                    icon: Icon(Icons.add,
                        size: 16, color: context.forest.accentText),
                    label: Text(l10n.translate('fund_record_payment'),
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: context.forest.accentText)),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          context.forest.accentText.withValues(alpha: 0.12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_transfers.isEmpty && _settlements.isEmpty)
          Text(l10n.translate('fund_no_payments'),
              style: TextStyle(color: context.forest.text54, fontSize: 12))
        else ...[
          for (final s in _settlements) _mfsSettlementTile(l10n, s),
          for (final t in _transfers)
            _box(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: ListTile(
                onLongPress: _canEdit(t.addedByEmail)
                    ? () => _confirmDelete('${t.fromName} → ${t.toName}',
                        () => _repository.deleteTransfer(widget.tourId, t.id))
                    : null,
                leading: Icon(Icons.payments_rounded,
                    color: context.forest.accentText),
                title: Text(
                  '${_party(l10n, t.fromName, t.fromId == null)} → '
                  '${_party(l10n, t.toName, t.toId == null)}',
                  style: TextStyle(color: context.forest.text),
                ),
                subtitle: Text(
                  [
                    localizedDateFormat('d MMM, h:mm a').format(t.date),
                    if ((t.notes ?? '').isNotEmpty) t.notes!,
                  ].join(' · '),
                  style: TextStyle(color: context.forest.text54, fontSize: 11),
                ),
                trailing: Text(_money(t.amountPaisa),
                    style: TextStyle(
                        color: context.forest.readable(AppColors.gold),
                        fontWeight: FontWeight.bold)),
              ),
            ),
        ],
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
            : context.forest.text.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: (mineOut || mineIn)
                ? AppColors.mintGreen.withValues(alpha: 0.4)
                : context.forest.divider10),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_party(l10n, s.from, s.fromFund)} → ${_party(l10n, s.to, s.toFund)}',
                style: TextStyle(
                    color: context.forest.text, fontWeight: FontWeight.bold),
              ),
              Text(
                l10n.translate(s.fromFund
                    ? 'fund_settle_refund'
                    : s.toFund
                        ? 'fund_settle_topup'
                        : 'fund_settle_direct'),
                style: TextStyle(color: context.forest.text54, fontSize: 11),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(_money(s.amountPaisa),
                style: TextStyle(
                    color: context.forest.readable(AppColors.gold),
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
                        style: TextStyle(color: context.forest.accentText)),
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
                      style: TextStyle(
                          color: context.forest.text,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (r.netPaisa == 0
                              ? context.forest.text24
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
                      style:
                          TextStyle(color: context.forest.text, fontSize: 11),
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

  Widget _kv(String k, int paisa, {Color? color}) => Text.rich(
        TextSpan(children: [
          TextSpan(
              text: '$k ',
              style: TextStyle(color: context.forest.text38, fontSize: 11)),
          TextSpan(
              text: _money(paisa),
              style: TextStyle(
                  color: color ?? context.forest.text70, fontSize: 12)),
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
                      style: TextStyle(
                          color: context.forest.readable(AppColors.gold),
                          fontWeight: FontWeight.bold))),
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
              leading: Icon(Icons.south_west_rounded,
                  color: context.forest.accentText),
              title: Text(d.memberName,
                  style: TextStyle(color: context.forest.text)),
              subtitle: Text(
                [
                  localizedDateFormat('d MMM yyyy').format(d.date),
                  if ((d.notes ?? '').isNotEmpty) d.notes!,
                ].join(' · '),
                style: TextStyle(color: context.forest.text54, fontSize: 11),
              ),
              trailing: Text(_money(d.amountPaisa),
                  style: TextStyle(
                      color: context.forest.readable(AppColors.gold),
                      fontWeight: FontWeight.bold)),
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
          title: Text(title, style: TextStyle(color: context.forest.text)),
          subtitle: Text(sub, style: TextStyle(color: context.forest.text54)),
          onTap: () {
            Navigator.pop(context);
            onTap();
          },
        );
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.forest.surfaceFor(_card),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            item(
                Icons.receipt_long_rounded,
                AppColors.mintGreen,
                l10n.translate('fund_add_expense'),
                l10n.translate(group?.isFriends == true
                    ? 'friends_add_expense_sub'
                    : group?.isOffice == true
                        ? 'office_add_expense_sub'
                        : group?.isCampus == true
                            ? 'campus_add_expense_sub'
                            : group?.isMess == true
                                ? 'mess_add_expense_sub'
                                : group?.isSociety == true
                                    ? 'society_add_expense_sub'
                                    : group?.isSamity == true
                                        ? 'samity_add_expense_sub'
                                        : 'fund_add_expense_sub'),
                _editExpense),
            if (group?.isFriends == true)
              item(
                  Icons.restaurant_rounded,
                  AppColors.gold,
                  l10n.translate('friends_quick_dining'),
                  l10n.translate('friends_quick_dining_sub'),
                  () => _editExpense(null, false,
                      l10n.translate('friends_quick_dining'), 'Dining')),
            if (group?.isOffice == true)
              item(
                  Icons.restaurant_rounded,
                  AppColors.gold,
                  l10n.translate('ledger_quick_lunch'),
                  l10n.translate('ledger_quick_lunch_sub'),
                  () => _editExpense(null, false,
                      l10n.translate('ledger_quick_lunch'), 'Dining')),
            if (group?.isCampus == true)
              item(
                  Icons.restaurant_rounded,
                  AppColors.gold,
                  l10n.translate('campus_quick_snacks'),
                  l10n.translate('campus_quick_snacks_sub'),
                  () => _editExpense(null, false,
                      l10n.translate('campus_quick_snacks'), 'Food')),
            if (group?.isMess == true) ...[
              item(
                  Icons.shopping_basket_rounded,
                  AppColors.gold,
                  l10n.translate('mess_quick_bazar'),
                  l10n.translate('mess_quick_bazar_sub'),
                  () => _addMessBazar(l10n.translate('mess_quick_bazar'))),
              item(
                  Icons.receipt_long_rounded,
                  AppColors.mintGreen,
                  'মেস মিল ও ব্যালেন্স',
                  'স্বয়ংক্রিয় মিল রেট ও সদস্যভিত্তিক বকেয়া/ফেরত হিসাব',
                  () => showMessBalanceSheet(context, tourId: widget.tourId)),
            ],
            item(
                Icons.account_balance_wallet_rounded,
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
                  context.forest.text70,
                  l10n.translate('fund_budget_title'),
                  l10n.translate('fund_budget_sub'),
                  () => _editBudget(group)),
          ],
        ),
      ),
    );
  }

  /// A bazar bought for the mess opens split by this month's meal counts, so each
  /// member shares the cost of the meals they ate. With no meal counts yet, the split
  /// is left to fill in by hand.
  Future<void> _addMessBazar(String title) async {
    Map<String, int>? meals;
    try {
      meals =
          await _repository.mealTotalsForMonth(widget.tourId, DateTime.now());
    } catch (err) {
      logError('Meal totals failed: $err');
    }
    if (!mounted) return;
    await _editExpense(null, false, title, 'Groceries', meals);
  }

  Future<void> _editExpense(
      [ExpenseItem? existing,
      bool duplicate = false,
      String? quickTitle,
      String? quickCategory,
      Map<String, int>? mealShares]) async {
    if (_members.isEmpty) return;
    final draft = await showExpenseEditor(
      context,
      members: _members,
      group: _group,
      me: _me,
      existing: existing,
      initialTitle: quickTitle,
      initialCategory: quickCategory,
      initialSplit: mealShares == null ? null : SplitMode.shares,
      initialShares: mealShares,
    );
    if (draft == null || !mounted) return;
    final l10n = context.l10n;
    await _run(() async {
      String? finalReceiptUrl = draft.receiptUrl;
      if (draft.newReceiptFile != null) {
        final file = draft.newReceiptFile!;
        final ext = storedExtension(file.name, 'jpg');
        final cType = imageContentType(file.name) ?? 'image/jpeg';
        final upload = await TourMediaUploader.start(
          tourId: widget.tourId,
          folder: 'media',
          file: file,
          contentType: cType,
          extension: ext,
          maxBytes: kMaxImageBytes,
          journal: TourMediaJournal.untracked,
        );
        finalReceiptUrl = await upload.finish();
      }

      if (existing == null || duplicate) {
        final trxId = draft.mfsInfo?.trxId?.trim().toUpperCase();
        if (trxId != null &&
            trxId.isNotEmpty &&
            (draft.mfsInfo?.provider.requiresTrxId ?? false)) {
          final isRegistered =
              await _repository.isMfsTrxRegistered(widget.tourId, trxId);
          if (isRegistered) {
            if (mounted) {
              _toast(
                l10n.translate('fund_mfs_duplicate_trxid'),
                error: true,
              );
            }
            return;
          }
        }
        try {
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
            mfsInfo: draft.mfsInfo,
          );
        } catch (e) {
          if (trxId != null &&
              trxId.isNotEmpty &&
              (e.toString().contains('permission-denied') ||
                  await _repository.isMfsTrxRegistered(widget.tourId, trxId))) {
            if (mounted) {
              _toast(
                l10n.translate('fund_mfs_duplicate_trxid'),
                error: true,
              );
            }
            return;
          }
          rethrow;
        }
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
          mfsInfo: draft.mfsInfo,
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

  void _openMfsSettlementSheet({SettlementTransaction? prefill}) {
    final group = _group;
    if (group == null) return;

    final ledgerMembers = [
      for (final m in _members)
        LedgerMember(
          id: m.email,
          name: m.displayName,
          familyCount: m.familyCount,
        ),
    ];

    String? fromId = prefill?.fromId;
    String? toId = prefill?.toId;
    if (fromId == null && ledgerMembers.isNotEmpty) {
      fromId = ledgerMembers.first.id;
    }
    if (toId == null && ledgerMembers.length > 1) {
      toId = ledgerMembers[1].id;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.forest.surfaceFor(_card),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => MfsSettlementSheet(
        tourId: widget.tourId,
        members: ledgerMembers,
        currentUserEmail: _me,
        isGroupManager: _isAdmin,
        existingExpenses: _expenses,
        existingSettlements: _settlements,
        initialFromMemberId: fromId,
        initialToMemberId: toId,
        initialAmountPaisa: prefill?.amountPaisa,
        onSaveSettlement: (record) async {
          final l10n = context.l10n;
          final trxId = record.mfsInfo.trxId?.trim().toUpperCase();
          if (trxId != null &&
              trxId.isNotEmpty &&
              record.mfsInfo.provider.requiresTrxId) {
            final isRegistered =
                await _repository.isMfsTrxRegistered(widget.tourId, trxId);
            if (isRegistered) {
              if (mounted) {
                _toast(
                  l10n.translate('fund_mfs_duplicate_trxid'),
                  error: true,
                );
              }
              return;
            }
          }
          await _run(() async {
            try {
              await _repository.addSettlement(widget.tourId, record);
              _toast(l10n.translate('fund_payment_saved'));
            } catch (e) {
              if (trxId != null &&
                  trxId.isNotEmpty &&
                  (e.toString().contains('permission-denied') ||
                      await _repository.isMfsTrxRegistered(
                          widget.tourId, trxId))) {
                if (mounted) {
                  _toast(l10n.translate('fund_mfs_duplicate_trxid'),
                      error: true);
                }
                return;
              }
              rethrow;
            }
          }, 'fund_err_save');
        },
      ),
    );
  }

  Widget _mfsSettlementTile(AppLocalizations l10n, SettlementRecord s) {
    Color providerColor;
    switch (s.mfsInfo.provider) {
      case MfsProvider.bkash:
        providerColor = const Color(0xFFE2136E);
        break;
      case MfsProvider.nagad:
        providerColor = const Color(0xFFF7931E);
        break;
      case MfsProvider.rocket:
        providerColor = const Color(0xFF8C3494);
        break;
      case MfsProvider.upay:
        providerColor = const Color(0xFF005696);
        break;
      case MfsProvider.bankTransfer:
        providerColor = Colors.teal;
        break;
      case MfsProvider.cash:
        providerColor = AppColors.mintGreen;
        break;
    }

    final isVerified = s.isVerified;
    final isDisputed = s.mfsInfo.status == MfsVerificationStatus.disputed;
    final statusColor = isVerified
        ? AppColors.mintGreen
        : isDisputed
            ? Colors.redAccent
            : Colors.orangeAccent;
    final statusText = isVerified
        ? l10n.translate('fund_mfs_verified')
        : isDisputed
            ? l10n.translate('fund_mfs_disputed')
            : l10n.translate('fund_mfs_unverified');

    return _box(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: ListTile(
        onLongPress: (_canEdit(s.addedByEmail) && !isVerified) || _isAdmin
            ? () => _confirmDelete(
                  '${s.fromMemberName} → ${s.toMemberName}',
                  () => _repository.deleteSettlement(widget.tourId, s),
                )
            : null,
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: providerColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: providerColor.withValues(alpha: 0.5)),
          ),
          child: Text(
            s.mfsInfo.provider.banglaLabel,
            style: TextStyle(
              color: providerColor,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                '${s.fromMemberName} → ${s.toMemberName}',
                style: TextStyle(
                    color: context.forest.text, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isVerified
                        ? Icons.check_circle_rounded
                        : isDisputed
                            ? Icons.warning_amber_rounded
                            : Icons.schedule_rounded,
                    size: 11,
                    color: statusColor,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              [
                localizedDateFormat('d MMM, h:mm a').format(s.date),
                if (s.mfsInfo.trxId != null) 'TrxID: ${s.mfsInfo.trxId}',
                if (s.mfsInfo.feePaisa > 0) 'ফি: ${_money(s.mfsInfo.feePaisa)}',
                if ((s.notes ?? '').isNotEmpty) s.notes!,
              ].join(' · '),
              style: TextStyle(color: context.forest.text54, fontSize: 11),
            ),
            if (isDisputed && (s.mfsInfo.disputeReason ?? '').isNotEmpty)
              Text(
                'আপত্তি: ${s.mfsInfo.disputeReason}',
                style: const TextStyle(color: Colors.redAccent, fontSize: 11),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _money(s.amountPaisa),
              style: TextStyle(
                color: context.forest.readable(AppColors.gold),
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_isAdmin && !isVerified) ...[
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.check_circle_rounded,
                    color: AppColors.mintGreen, size: 20),
                tooltip: l10n.translate('fund_verify_payment'),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _verifySettlement(s),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.cancel_outlined,
                    color: Colors.redAccent, size: 20),
                tooltip: l10n.translate('fund_dispute_payment'),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _disputeSettlement(s),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _verifySettlement(SettlementRecord s) async {
    final l10n = context.l10n;
    await _run(() async {
      await _repository.updateSettlementStatus(
        widget.tourId,
        s.id,
        MfsVerificationStatus.verified,
      );
      _toast(l10n.translate('fund_mfs_verified'));
    }, 'fund_err_save');
  }

  Future<void> _disputeSettlement(SettlementRecord s) async {
    final reasonController = TextEditingController();
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.forest.surfaceFor(_card),
        title: Text(l10n.translate('fund_dispute_reason_prompt'),
            style: TextStyle(color: context.forest.text)),
        content: TextField(
          controller: reasonController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: l10n.translate('fund_dispute_reason_hint'),
            hintStyle: TextStyle(color: context.forest.text54),
          ),
          style: TextStyle(color: context.forest.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.translate('tour_cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.translate('fund_dispute_payment')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _run(() async {
        await _repository.updateSettlementStatus(
          widget.tourId,
          s.id,
          MfsVerificationStatus.disputed,
          disputeReason: reasonController.text.trim().isNotEmpty
              ? reasonController.text.trim()
              : null,
        );
        _toast(l10n.translate('fund_mfs_disputed'), error: true);
      }, 'fund_err_save');
    }
  }

  Future<void> _exportMonthlyPdf() async {
    final group = _group;
    if (group == null) return;
    final ledgerMembers = [
      for (final m in _members)
        LedgerMember(
          id: m.email,
          name: m.displayName,
          familyCount: m.familyCount,
        ),
    ];

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.forest.surfaceFor(const Color(0xFF142428)),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'লেজার স্টেটমেন্ট এক্সপোর্ট',
                style: TextStyle(
                  fontFamily: 'NotoSansBengali',
                  fontFamilyFallback: const ['HindSiliguri', 'Roboto'],
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: context.forest.text,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.calendar_month_rounded,
                    color: AppColors.mintGreen),
                title: Text(
                  'চলতি মাস (${BanglaLedgerFormatter.formatMonthYearBangla(_month.year, _month.month)})',
                  style: TextStyle(
                    fontFamily: 'NotoSansBengali',
                    fontFamilyFallback: const ['HindSiliguri', 'Roboto'],
                    color: context.forest.text,
                  ),
                ),
                onTap: () => Navigator.of(sheetCtx).pop('month'),
              ),
              ListTile(
                leading: const Icon(Icons.history_rounded,
                    color: AppColors.mintGreen),
                title: Text(
                  'সম্পূর্ণ ট্যুর / গ্রুপ ইতিহাস (সব খরচ ও জমা)',
                  style: TextStyle(
                    fontFamily: 'NotoSansBengali',
                    fontFamilyFallback: const ['HindSiliguri', 'Roboto'],
                    color: context.forest.text,
                  ),
                ),
                onTap: () => Navigator.of(sheetCtx).pop('all'),
              ),
              ListTile(
                leading: const Icon(Icons.date_range_rounded,
                    color: AppColors.mintGreen),
                title: Text(
                  'কাস্টম তারিখ সীমা নির্বাচন...',
                  style: TextStyle(
                    fontFamily: 'NotoSansBengali',
                    fontFamilyFallback: const ['HindSiliguri', 'Roboto'],
                    color: context.forest.text,
                  ),
                ),
                onTap: () => Navigator.of(sheetCtx).pop('custom'),
              ),
            ],
          ),
        ),
      ),
    );

    if (choice == null || !mounted) return;

    DateTime? customStart;
    DateTime? customEnd;

    if (choice == 'all') {
      customStart = DateTime(1900, 1, 1);
      customEnd = DateTime(2100, 12, 31);
    } else if (choice == 'custom') {
      final now = DateTime.now();
      final pickedRange = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 5),
        lastDate: DateTime(now.year + 2),
        initialDateRange: DateTimeRange(
          start: DateTime(_month.year, _month.month, 1),
          end: DateTime(_month.year, _month.month + 1, 0),
        ),
      );
      if (pickedRange == null || !mounted) return;
      customStart = pickedRange.start;
      customEnd = pickedRange.end;
    }

    await exportMonthlyLedgerPdf(
      context,
      group: group,
      year: _month.year,
      month: _month.month,
      members: ledgerMembers,
      allExpenses: _expenses,
      allSettlements: _settlements,
      customStart: customStart,
      customEnd: customEnd,
      preparedByName: _repository.currentDisplayName,
    );
  }

  Future<void> _editBudget(TourGroup group) async {
    final budget = await showBudgetSheet(
      context,
      budget: group.fundBudget,
      headcount: _headcount,
      totalDays: group.totalDays,
      family: group.isFamily,
      categories: expenseCategoriesForGroup(group),
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
      backgroundColor: context.forest.surfaceFor(_card),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  Icon(Icons.edit_rounded, color: context.forest.accentText),
              title: Text(l10n.translate('fund_edit'),
                  style: TextStyle(color: context.forest.text)),
              onTap: () {
                Navigator.pop(ctx);
                onEdit();
              },
            ),
            if (onDuplicate != null)
              ListTile(
                leading: const Icon(Icons.copy_rounded, color: _fundBlue),
                title: Text(l10n.translate('fund_duplicate'),
                    style: TextStyle(color: context.forest.text)),
                onTap: () {
                  Navigator.pop(ctx);
                  onDuplicate();
                },
              ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded,
                  color: context.forest.readable(Colors.redAccent)),
              title: Text(l10n.translate('fund_delete'),
                  style: TextStyle(color: context.forest.text)),
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
        backgroundColor: context.forest.surfaceFor(_card),
        title: Text(l10n.translate('fund_delete_confirm'),
            style: TextStyle(color: context.forest.text)),
        content: Text(subject, style: TextStyle(color: context.forest.text70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l10n.translate('tour_cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(l10n.translate('fund_delete'),
                  style: TextStyle(
                      color: context.forest.readable(Colors.redAccent)))),
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

    line([group?.name ?? 'Group fund', 'Audit statement']);
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
                  signedMediaUrl(url),
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
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(context.l10n.translate('fund_receipt_load_failed'),
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12)),
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
      backgroundColor: context.forest.surfaceFor(_card),
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
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
                          style: TextStyle(
                              color: context.forest.text,
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
                        ),
                        Text(
                          '$senderName → $recipientName',
                          style: TextStyle(
                              color: context.forest.text60, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                l10n.translate('fund_bkash_nagad_help'),
                style: TextStyle(color: context.forest.text70, fontSize: 13),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.forest.text.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.forest.divider12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l10n.translate('fund_balance_owed'),
                            style: TextStyle(
                                color: context.forest.text70, fontSize: 13)),
                        Text('৳ $amountTaka',
                            style: TextStyle(
                                color: context.forest.readable(AppColors.gold),
                                fontWeight: FontWeight.bold,
                                fontSize: 18)),
                      ],
                    ),
                    Divider(color: context.forest.divider12, height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(recipientName,
                            style: TextStyle(
                                color: context.forest.text,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        if (s.toId != null && s.toId!.isNotEmpty)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact),
                            icon: Icon(Icons.copy_rounded,
                                size: 14, color: context.forest.accentText),
                            label: Text(l10n.translate('fund_copy_payee'),
                                style: TextStyle(
                                    color: context.forest.accentText,
                                    fontSize: 12)),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: s.toId!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content:
                                      Text(l10n.translate('fund_payee_copied')),
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
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFE2136E),
                        side: const BorderSide(color: Color(0xFFE2136E)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.phone_in_talk_rounded, size: 16),
                      label: const Text('bKash (*247#)',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () async {
                        final uri = Uri.parse('tel:*247%23');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFF7931E),
                        side: const BorderSide(color: Color(0xFFF7931E)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.phone_in_talk_rounded, size: 16),
                      label: const Text('Nagad (*167#)',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () async {
                        final uri = Uri.parse('tel:*167%23');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE2136E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.receipt_long_rounded, size: 18),
                  label: Text(l10n.translate('fund_mfs_settle_up'),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _openMfsSettlementSheet(prefill: s);
                  },
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.mintGreen,
                    foregroundColor: AppColors.darkGreen,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                  label: Text(
                      l10n.locale.languageCode == 'bn'
                          ? 'বাংলা কিউআর তৈরি করুন'
                          : 'Generate Bangla QR',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    final parsedTaka =
                        int.tryParse(amountTaka.replaceAll(',', ''));
                    final rawAccount =
                        (s.toId != null && s.toId!.isNotEmpty) ? s.toId! : '';

                    // Find payee member in tour members
                    final payee = _members
                        .where((m) =>
                            m.email.toLowerCase() == s.toId?.toLowerCase() ||
                            m.uid == s.toId)
                        .firstOrNull;

                    PaymentProfileInfo? paymentProfile;
                    if (payee?.uid != null && payee!.uid!.isNotEmpty) {
                      paymentProfile =
                          await PaymentProfileService.getPaymentProfile(
                        payee.uid!,
                      );
                    }

                    final effectiveAccount =
                        paymentProfile?.accountNumber?.isNotEmpty == true
                            ? paymentProfile!.accountNumber!
                            : (rawAccount.contains('@') ? '' : rawAccount);

                    final effectiveProvider = paymentProfile?.provider != null
                        ? BanglaQrProvider.values.firstWhere(
                            (p) =>
                                p.name.toLowerCase() ==
                                paymentProfile!.provider!.toLowerCase(),
                            orElse: () => BanglaQrProvider.bkash,
                          )
                        : BanglaQrProvider.bkash;

                    if (!mounted) return;
                    showBanglaQrSheet(
                      context,
                      savedQrUrl: paymentProfile?.banglaQrUrl,
                      payeeUid: payee?.uid,
                      isOwnQr: false,
                      payload: BanglaQrPayload(
                        accountNumber: effectiveAccount,
                        payeeName: recipientName,
                        provider: effectiveProvider,
                        amountTaka: parsedTaka,
                        reference: l10n.locale.languageCode == 'bn'
                            ? 'হিসাব মেলানো'
                            : 'Settlement',
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
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
