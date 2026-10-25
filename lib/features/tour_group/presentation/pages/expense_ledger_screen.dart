import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/tour_group_repository.dart';
import '../../domain/models/expense_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/trip_ledger_engine.dart';
import '../../../../core/theme/colors.dart';

const List<String> _expenseCategories = [
  'Food',
  'Transport',
  'Hotel',
  'Tickets',
  'Others',
];

class ExpenseLedgerScreen extends StatefulWidget {
  final String tourId;

  const ExpenseLedgerScreen({super.key, required this.tourId});

  @override
  State<ExpenseLedgerScreen> createState() => _ExpenseLedgerScreenState();
}

class _ExpenseLedgerScreenState extends State<ExpenseLedgerScreen>
    with SingleTickerProviderStateMixin {
  final TourGroupRepository _repository = TourGroupRepository();
  late final TabController _tabController =
      TabController(length: 4, vsync: this);

  // Streams are created once; the screen rebuilds them only when data changes.
  late final Stream<List<TourMember>> _members =
      _repository.watchMembers(widget.tourId);
  late final Stream<List<DepositItem>> _deposits =
      _repository.watchDeposits(widget.tourId);
  late final Stream<List<ExpenseItem>> _expenses =
      _repository.watchExpenses(widget.tourId);

  TourGroup? _tourGroup;
  TourRole? _myRole;
  List<TourMember> _latestMembers = const [];
  LedgerSummary? _latestSummary;
  List<ExpenseItem> _latestExpenses = const [];

  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;

  @override
  void initState() {
    super.initState();
    _loadContext();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadContext() async {
    final group = await _repository.getGroup(widget.tourId);
    final role = await _repository.myRole(widget.tourId);
    if (mounted) {
      setState(() {
        _tourGroup = group;
        _myRole = role;
      });
    }
  }

  void _showError(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: Colors.redAccent),
    );
  }

  bool _canEdit(String addedByEmail) =>
      _isAdmin || addedByEmail == _repository.currentEmail;

  String _money(int paisa) => TripLedgerEngine.formatTaka(paisa);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1A1C),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF142428),
        foregroundColor: Colors.white,
        title: const Text('Tour Fund & Ledger',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.table_view_rounded),
            tooltip: 'Excel CSV অডিট এক্সপোর্ট',
            onPressed: _exportLedgerCsv,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.mintGreen,
          labelColor: AppColors.mintGreen,
          unselectedLabelColor: Colors.white60,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Settlements'),
            Tab(text: 'Expenses'),
            Tab(text: 'Deposits'),
            Tab(text: 'Balances'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.midGreen,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Entry'),
        onPressed: () => _showAddEntryMenu(context),
      ),
      body: StreamBuilder<List<TourMember>>(
        stream: _members,
        builder: (context, membersSnap) {
          if (membersSnap.hasData) _latestMembers = membersSnap.data!;
          return StreamBuilder<List<DepositItem>>(
            stream: _deposits,
            builder: (context, depositsSnap) {
              final deposits = depositsSnap.data ?? const <DepositItem>[];
              return StreamBuilder<List<ExpenseItem>>(
                stream: _expenses,
                builder: (context, expensesSnap) {
                  final expenses = expensesSnap.data ?? const <ExpenseItem>[];
                  final members = _latestMembers;
                  final summary = TripLedgerEngine.computeLedger(
                    members: [
                      for (final m in members)
                        LedgerMemberInput(
                          id: m.email,
                          name: m.displayName,
                          familyCount: m.familyCount,
                        ),
                    ],
                    expenses: expenses,
                    deposits: deposits,
                  );
                  _latestSummary = summary;
                  _latestExpenses = expenses;

                  return Column(
                    children: [
                      _buildSummaryHeader(summary),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildSettlementsTab(summary),
                            _buildExpensesTab(expenses),
                            _buildDepositsTab(deposits),
                            _buildBalancesTab(summary),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSummaryHeader(LedgerSummary summary) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF142428),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _headerStat(
                  'Fund Balance',
                  _money(summary.fundBalancePaisa),
                  summary.fundBalancePaisa >= 0
                      ? AppColors.mintGreen
                      : Colors.redAccent),
              _headerStat('Total Spent', _money(summary.totalExpensePaisa),
                  Colors.white),
              _headerStat('Total Deposits', _money(summary.totalDepositsPaisa),
                  AppColors.gold),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'সদস্য: ${summary.headcount} জন • মাথাপিছু খরচ: ${_money(summary.perHeadCostPaisa)}',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _headerStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 15)),
      ],
    );
  }

  Widget _emptyText(String text) => Center(
        child: Text(text, style: const TextStyle(color: Colors.white38)),
      );

  Widget _card({required Widget child, VoidCallback? onLongPress}) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF142428),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
        ),
        child: child,
      ),
    );
  }

  Widget _buildSettlementsTab(LedgerSummary summary) {
    if (summary.settlements.isEmpty) {
      return _emptyText('সবার হিসাব মেলানো আছে। কোনো লেনদেন দরকার নেই।');
    }
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        for (final s in summary.settlements)
          _card(
            child: Row(
              children: [
                const Icon(Icons.swap_horiz_rounded,
                    color: AppColors.mintGreen),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${s.from} ➔ ${s.to}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(
                        s.fromFund
                            ? 'ফান্ড থেকে ${s.to}-কে ফেরত'
                            : s.toFund
                                ? '${s.from} ফান্ডে বাকি অংশ দেবেন'
                                : 'সরাসরি লেনদেন',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Text(_money(s.amountPaisa),
                    style: const TextStyle(
                        color: AppColors.gold, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildExpensesTab(List<ExpenseItem> expenses) {
    if (expenses.isEmpty) return _emptyText('এখনও কোনো খরচ যোগ হয়নি।');
    final dateFormat = DateFormat('dd MMM yyyy');
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        for (final exp in expenses)
          _card(
            onLongPress: _canEdit(exp.addedByEmail)
                ? () => _confirmDelete(
                      'খরচটি মুছবেন?',
                      exp.title,
                      () => _repository.deleteExpense(widget.tourId, exp.id),
                    )
                : null,
            child: Row(
              children: [
                Icon(
                  exp.paidById == null
                      ? Icons.account_balance_rounded
                      : Icons.person_rounded,
                  color: exp.paidById == null
                      ? const Color(0xFF38BDF8)
                      : AppColors.gold,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(exp.title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(
                        '${exp.paidById == null ? 'ফান্ড থেকে' : 'দিয়েছেন: ${exp.paidByName ?? exp.paidById}'} • ${dateFormat.format(exp.date)}',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11),
                      ),
                      if (exp.participantIds != null)
                        Text('${exp.participantIds!.length} জন ভাগ করছেন',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 10)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_money(exp.amountPaisa),
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    Text(exp.category,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildDepositsTab(List<DepositItem> deposits) {
    if (deposits.isEmpty) return _emptyText('এখনও কোনো জমা যোগ হয়নি।');
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        for (final d in deposits)
          _card(
            onLongPress: _canEdit(d.addedByEmail)
                ? () => _confirmDelete(
                      'জমাটি মুছবেন?',
                      '${d.memberName} — ${_money(d.amountPaisa)}',
                      () => _repository.deleteDeposit(widget.tourId, d.id),
                    )
                : null,
            child: Row(
              children: [
                const Icon(Icons.arrow_downward_rounded,
                    color: AppColors.mintGreen),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.memberName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      const Text('ফান্ডে জমা',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 11)),
                    ],
                  ),
                ),
                Text(_money(d.amountPaisa),
                    style: const TextStyle(
                        color: AppColors.gold, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildBalancesTab(LedgerSummary summary) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        for (final r in summary.rows)
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.isFormerMember ? '${r.name} (আর সদস্য নন)' : r.name,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (r.netPaisa >= 0
                                ? AppColors.mintGreen
                                : Colors.redAccent)
                            .withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        r.netPaisa >= 0
                            ? '+${_money(r.netPaisa)} (পাবেন)'
                            : '-${_money(-r.netPaisa)} (দেবেন)',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'জমা: ${_money(r.depositPaisa)} • নিজে দিয়েছেন: ${_money(r.directPaidPaisa)} • ভাগ: ${_money(r.sharePaisa)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
        if (summary.rows.isEmpty) _emptyText('এখনও কোনো সদস্য নেই।'),
      ],
    );
  }

  Future<void> _confirmDelete(
      String title, String subject, Future<void> Function() delete) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF142428),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(subject, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('না')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('মুছুন',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await delete();
    } catch (_) {
      _showError('মোছা যায়নি। শুধু যিনি যোগ করেছেন বা অ্যাডমিন মুছতে পারবেন।');
    }
  }

  void _showAddEntryMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF142428),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.receipt_long_rounded,
                  color: AppColors.mintGreen),
              title: const Text('খরচ যোগ করুন',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('হোটেল, খাবার, টিকিট, যাতায়াত ইত্যাদি',
                  style: TextStyle(color: Colors.white54)),
              onTap: () {
                Navigator.pop(ctx);
                _showAddExpenseDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.savings_rounded, color: AppColors.gold),
              title: const Text('ফান্ডে জমা দিন',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('সদস্যের ফান্ডে টাকা জমা',
                  style: TextStyle(color: Colors.white54)),
              onTap: () {
                Navigator.pop(ctx);
                _showAddDepositDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAddExpenseDialog() {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String category = 'Food';
    DateTime date = DateTime.now();
    bool paidFromFund = true;
    final me = _repository.currentEmail;
    final members = _latestMembers;
    String? payerEmail = members.any((m) => m.email == me)
        ? me
        : (members.isNotEmpty ? members.first.email : null);
    final participants = {for (final m in members) m.email};
    String? error;

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF142428),
          title:
              const Text('খরচ যোগ করুন', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  maxLength: 80,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'খরচের বিবরণ'),
                ),
                TextField(
                  controller: amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'পরিমাণ (টাকা)'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  dropdownColor: const Color(0xFF1B4332),
                  decoration: const InputDecoration(labelText: 'খাত'),
                  items: _expenseCategories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDialogState(() => category = v);
                  },
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(2022),
                      lastDate: DateTime(2035),
                    );
                    if (picked != null) setDialogState(() => date = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'তারিখ'),
                    child: Text(DateFormat('dd MMM yyyy').format(date),
                        style: const TextStyle(color: Colors.white)),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('ফান্ড থেকে দেওয়া হয়েছে',
                      style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    paidFromFund
                        ? 'সরাসরি ফান্ড থেকে কাটা হবে'
                        : 'একজন সদস্য নিজের পকেট থেকে দিয়েছেন',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  value: paidFromFund,
                  activeThumbColor: AppColors.mintGreen,
                  onChanged: (v) => setDialogState(() => paidFromFund = v),
                ),
                if (!paidFromFund && members.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: payerEmail,
                    dropdownColor: const Color(0xFF1B4332),
                    decoration: const InputDecoration(labelText: 'কে দিয়েছেন'),
                    items: members
                        .map((m) => DropdownMenuItem(
                              value: m.email,
                              child: Text(m.displayName,
                                  overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) => setDialogState(() => payerEmail = v),
                  ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('এই খরচ কারা ভাগ করবেন',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final m in members)
                      FilterChip(
                        label: Text(m.displayName,
                            style: const TextStyle(fontSize: 11)),
                        selected: participants.contains(m.email),
                        selectedColor: AppColors.mintGreen,
                        onSelected: (v) => setDialogState(() {
                          v
                              ? participants.add(m.email)
                              : participants.remove(m.email);
                        }),
                      ),
                  ],
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error!,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 12)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('বাতিল')),
            ElevatedButton(
              onPressed: () async {
                final title = titleCtrl.text.trim();
                final paisa = TripLedgerEngine.parseTakaInput(amountCtrl.text);
                if (title.isEmpty) {
                  setDialogState(() => error = 'খরচের বিবরণ লিখুন।');
                  return;
                }
                if (paisa == null) {
                  setDialogState(() => error =
                      'সঠিক পরিমাণ লিখুন (০ এর বেশি, সর্বোচ্চ ১ কোটি)।');
                  return;
                }
                if (participants.isEmpty) {
                  setDialogState(
                      () => error = 'অন্তত একজন সদস্য নির্বাচন করুন।');
                  return;
                }
                final payer = paidFromFund
                    ? null
                    : members.where((m) => m.email == payerEmail).firstOrNull;
                if (!paidFromFund && payer == null) {
                  setDialogState(() => error = 'কে দিয়েছেন তা নির্বাচন করুন।');
                  return;
                }
                Navigator.pop(ctx);
                try {
                  await _repository.addExpense(
                    tourId: widget.tourId,
                    title: title,
                    amountPaisa: paisa,
                    paidById: payer?.email,
                    paidByName: payer?.displayName,
                    category: category,
                    date: date,
                    participantIds: participants.length == members.length
                        ? null
                        : participants.toList(),
                  );
                } catch (e) {
                  _showError('খরচ সংরক্ষণ করা যায়নি: $e');
                }
              },
              child:
                  const Text('সংরক্ষণ', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      titleCtrl.dispose();
      amountCtrl.dispose();
    });
  }

  void _showAddDepositDialog() {
    final amountCtrl = TextEditingController();
    final members = _latestMembers;
    final me = _repository.currentEmail;
    String? memberEmail = members.any((m) => m.email == me)
        ? me
        : (members.isNotEmpty ? members.first.email : null);
    String? error;

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF142428),
          title:
              const Text('ফান্ডে জমা', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (members.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: memberEmail,
                  dropdownColor: const Color(0xFF1B4332),
                  decoration:
                      const InputDecoration(labelText: 'কে জমা দিচ্ছেন'),
                  items: members
                      .map((m) => DropdownMenuItem(
                            value: m.email,
                            child: Text(m.displayName,
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) => setDialogState(() => memberEmail = v),
                ),
              TextField(
                controller: amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration:
                    const InputDecoration(labelText: 'জমার পরিমাণ (টাকা)'),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 12)),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('বাতিল')),
            ElevatedButton(
              onPressed: () async {
                final paisa = TripLedgerEngine.parseTakaInput(amountCtrl.text);
                final member =
                    members.where((m) => m.email == memberEmail).firstOrNull;
                if (paisa == null) {
                  setDialogState(() => error =
                      'সঠিক পরিমাণ লিখুন (০ এর বেশি, সর্বোচ্চ ১ কোটি)।');
                  return;
                }
                if (member == null) {
                  setDialogState(() => error = 'সদস্য নির্বাচন করুন।');
                  return;
                }
                Navigator.pop(ctx);
                try {
                  await _repository.addDeposit(
                    tourId: widget.tourId,
                    memberId: member.email,
                    memberName: member.displayName,
                    amountPaisa: paisa,
                  );
                } catch (e) {
                  _showError('জমা সংরক্ষণ করা যায়নি: $e');
                }
              },
              child:
                  const Text('জমা দিন', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    ).whenComplete(amountCtrl.dispose);
  }

  /// CSV for the audit. Member emails are left out; names and amounts are kept.
  Future<void> _exportLedgerCsv() async {
    final summary = _latestSummary;
    if (summary == null) {
      _showError('হিসাবের ডেটা লোড হচ্ছে, অপেক্ষা করুন।');
      return;
    }
    final group = _tourGroup;
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

    line([group?.name ?? 'ট্যুর ফান্ড', 'অডিট বিবরণী']);
    line([
      'ভ্রমণ রুট',
      group == null ? '' : '${group.originCity} ➔ ${group.destination}'
    ]);
    line([
      'তৈরির সময়',
      DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())
    ]);
    line([]);
    line(['সারসংক্ষেপ']);
    line(['মোট জমা (টাকা)', taka(summary.totalDepositsPaisa)]);
    line(['মোট খরচ (টাকা)', taka(summary.totalExpensePaisa)]);
    line(['ফান্ড ব্যালেন্স (টাকা)', taka(summary.fundBalancePaisa)]);
    line(['সদস্য সংখ্যা', summary.headcount]);
    line([]);
    line(['খাত', 'মোট (টাকা)', 'শতাংশ']);
    for (final ct in summary.categoryTotals) {
      final pct = summary.totalExpensePaisa > 0
          ? (ct.amountPaisa * 100 / summary.totalExpensePaisa)
              .toStringAsFixed(1)
          : '0.0';
      line([ct.category, taka(ct.amountPaisa), pct]);
    }
    line([]);
    line(['তারিখ', 'খাত', 'বিবরণ', 'কে দিয়েছেন', 'টাকা']);
    for (final exp in _latestExpenses) {
      line([
        DateFormat('yyyy-MM-dd').format(exp.date),
        exp.category,
        exp.title,
        exp.paidById == null ? 'ফান্ড' : (exp.paidByName ?? 'সদস্য'),
        taka(exp.amountPaisa),
      ]);
    }
    line([]);
    line([
      'সদস্য',
      'জমা (টাকা)',
      'নিজে দিয়েছেন (টাকা)',
      'ভাগ (টাকা)',
      'হিসাব (+ পাবেন / - দেবেন)'
    ]);
    for (final r in summary.rows) {
      line([
        r.isFormerMember ? '${r.name} (প্রাক্তন)' : r.name,
        taka(r.depositPaisa),
        taka(r.directPaidPaisa),
        taka(r.sharePaisa),
        taka(r.netPaisa),
      ]);
    }
    line([]);
    line(['কে দেবেন', 'কাকে দেবেন', 'টাকা']);
    for (final st in summary.settlements) {
      line([st.from, st.to, taka(st.amountPaisa)]);
    }

    // A BOM lets Excel read the Bengali text correctly.
    final bytes = '﻿${buffer.toString()}'.codeUnits;
    final name =
        'Bhromon_Ledger_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
    // ignore: deprecated_member_use
    await Share.shareXFiles(
      [
        XFile.fromData(Uint8List.fromList(bytes),
            mimeType: 'text/csv', name: name)
      ],
      subject: name,
    );
  }
}
