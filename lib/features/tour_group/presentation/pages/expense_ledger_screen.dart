import 'package:flutter/material.dart';
import '../../domain/models/expense_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/trip_ledger_engine.dart';
import '../../data/tour_group_repository.dart';
import '../../../../core/theme/colors.dart';

class ExpenseLedgerScreen extends StatefulWidget {
  final String tourId;

  const ExpenseLedgerScreen({super.key, required this.tourId});

  @override
  State<ExpenseLedgerScreen> createState() => _ExpenseLedgerScreenState();
}

class _ExpenseLedgerScreenState extends State<ExpenseLedgerScreen>
    with SingleTickerProviderStateMixin {
  final TourGroupRepository _repository = TourGroupRepository();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1A12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1A12),
        elevation: 0,
        title: const Text(
          'Tour Fund & Ledger',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
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
        stream: _repository.watchMembers(widget.tourId),
        builder: (context, membersSnap) {
          final members = membersSnap.data ?? [];

          return StreamBuilder<List<DepositItem>>(
            stream: _repository.watchDeposits(widget.tourId),
            builder: (context, depositsSnap) {
              final deposits = depositsSnap.data ?? [];

              return StreamBuilder<List<ExpenseItem>>(
                stream: _repository.watchExpenses(widget.tourId),
                builder: (context, expensesSnap) {
                  final expenses = expensesSnap.data ?? [];

                  // Build Ledger inputs
                  final ledgerMembers = members.map((m) {
                    final memberDeposits = deposits
                        .where((d) => d.memberId == m.email)
                        .fold<int>(0, (sum, d) => sum + d.amountPaisa);
                    return LedgerMemberInput(
                      id: m.email,
                      name: m.displayName,
                      familyCount: 1,
                      depositPaisa: memberDeposits,
                    );
                  }).toList();

                  final summary = TripLedgerEngine.computeLedger(
                    members: ledgerMembers,
                    expenses: expenses,
                  );

                  return Column(
                    children: [
                      // Financial Summary Header
                      _buildSummaryHeader(summary),

                      // Tab Views
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
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF14241B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildHeaderStat(
                'Fund Balance',
                '৳${summary.fundBalanceTaka.toStringAsFixed(0)}',
                summary.fundBalancePaisa >= 0
                    ? AppColors.mintGreen
                    : Colors.redAccent,
              ),
              _buildHeaderStat(
                'Total Spent',
                '৳${summary.totalExpenseTaka.toStringAsFixed(0)}',
                Colors.white,
              ),
              _buildHeaderStat(
                'Total Deposits',
                '৳${summary.totalDepositsTaka.toStringAsFixed(0)}',
                AppColors.gold,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Headcount: ${summary.headcount}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  'Per-Head Share: ৳${summary.perHeadCostTaka.toStringAsFixed(0)}',
                  style: const TextStyle(
                      color: AppColors.mintGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildSettlementsTab(LedgerSummary summary) {
    if (summary.settlements.isEmpty) {
      return const Center(
        child: Text(
          'All balances are settled! Zero transfers needed.',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: summary.settlements.length,
      itemBuilder: (context, i) {
        final s = summary.settlements[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF14241B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.midGreen.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.swap_horiz_rounded,
                    color: AppColors.mintGreen, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${s.from} ➔ ${s.to}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.fromFund
                          ? 'Fund refund to ${s.to}'
                          : s.toFund
                              ? '${s.from} pays remaining share to Fund'
                              : 'Direct transfer',
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Text(
                '৳${s.amountTaka.toStringAsFixed(0)}',
                style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExpensesTab(List<ExpenseItem> expenses) {
    if (expenses.isEmpty) {
      return const Center(
        child: Text('No expenses recorded yet.',
            style: TextStyle(color: Colors.white54)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: expenses.length,
      itemBuilder: (context, i) {
        final exp = expenses[i];
        final isFund = exp.paidById == null || exp.paidById!.isEmpty;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF14241B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isFund
                      ? const Color(0xFF38BDF8).withValues(alpha: 0.15)
                      : AppColors.gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isFund ? Icons.account_balance_rounded : Icons.person_rounded,
                  color: isFund ? const Color(0xFF38BDF8) : AppColors.gold,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exp.title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isFund
                          ? 'Paid from Shared Fund'
                          : 'Paid by: ${exp.paidByName ?? exp.paidById}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '৳${exp.amountTaka.toStringAsFixed(0)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                  Text(
                    exp.category,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDepositsTab(List<DepositItem> deposits) {
    if (deposits.isEmpty) {
      return const Center(
        child: Text('No deposits recorded yet.',
            style: TextStyle(color: Colors.white54)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: deposits.length,
      itemBuilder: (context, i) {
        final d = deposits[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF14241B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.mintGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.arrow_downward_rounded,
                    color: AppColors.mintGreen, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.memberName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                    const Text(
                      'Deposited into Fund',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Text(
                '৳${d.amountTaka.toStringAsFixed(0)}',
                style: const TextStyle(
                    color: AppColors.mintGreen,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBalancesTab(LedgerSummary summary) {
    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: summary.rows.length,
      itemBuilder: (context, i) {
        final r = summary.rows[i];
        final isOwed = r.netPaisa >= 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF14241B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    r.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isOwed
                          ? AppColors.mintGreen.withValues(alpha: 0.2)
                          : Colors.redAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isOwed
                          ? '+৳${r.netTaka.toStringAsFixed(0)} (Gets Back)'
                          : '-৳${(-r.netTaka).toStringAsFixed(0)} (Owes Fund)',
                      style: TextStyle(
                        color: isOwed ? AppColors.mintGreen : Colors.redAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Deposit: ৳${r.depositTaka.toStringAsFixed(0)} | Paid: ৳${r.directPaidTaka.toStringAsFixed(0)}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  Text(
                    'Fair Share: ৳${r.shareTaka.toStringAsFixed(0)}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddEntryMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF14241B),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.receipt_long_rounded,
                    color: Colors.orangeAccent),
                title: const Text('Add Tour Expense',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text('Hotel, food, tickets, transport, etc.',
                    style: TextStyle(color: Colors.white54)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showAddExpenseDialog(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.savings_rounded,
                    color: AppColors.mintGreen),
                title: const Text('Add Fund Deposit',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text('Member contribution to the shared fund',
                    style: TextStyle(color: Colors.white54)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showAddDepositDialog(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddExpenseDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String category = 'Food';
    bool paidFromFund = true;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF14241B),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              title: const Text('Add Tour Expense',
                  style: TextStyle(color: Colors.white)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Expense Description',
                        labelStyle: TextStyle(color: Colors.white70),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Amount (BDT)',
                        labelStyle: TextStyle(color: Colors.white70),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: category,
                      dropdownColor: const Color(0xFF1B4332),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        labelStyle: TextStyle(color: Colors.white70),
                      ),
                      items: ['Food', 'Transport', 'Hotel', 'Tickets', 'Others']
                          .map((c) =>
                              DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => category = val);
                      },
                    ),
                    const SizedBox(height: 14),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Paid from Shared Fund',
                          style: TextStyle(color: Colors.white, fontSize: 13)),
                      subtitle: Text(
                        paidFromFund
                            ? 'Deducted directly from Fund'
                            : 'Paid out-of-pocket by you',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11),
                      ),
                      value: paidFromFund,
                      activeThumbColor: AppColors.mintGreen,
                      onChanged: (val) =>
                          setDialogState(() => paidFromFund = val),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel',
                      style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.midGreen),
                  onPressed: () async {
                    final title = titleCtrl.text.trim();
                    final amountNum = double.tryParse(amountCtrl.text.trim());
                    if (title.isEmpty || amountNum == null || amountNum <= 0) {
                      return;
                    }

                    Navigator.pop(ctx);
                    await _repository.addExpense(
                      tourId: widget.tourId,
                      title: title,
                      amountPaisa: TripLedgerEngine.toPaisa(amountNum),
                      paidById: paidFromFund ? null : _repository.currentEmail,
                      paidByName: paidFromFund
                          ? null
                          : _repository.currentDisplayName,
                      category: category,
                    );
                  },
                  child: const Text('Save',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAddDepositDialog(BuildContext context) {
    final amountCtrl = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF14241B),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Record Deposit',
              style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Contributing member: ${_repository.currentDisplayName}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Deposit Amount (BDT)',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.midGreen),
              onPressed: () async {
                final amountNum = double.tryParse(amountCtrl.text.trim());
                if (amountNum == null || amountNum <= 0) return;

                Navigator.pop(ctx);
                await _repository.addDeposit(
                  tourId: widget.tourId,
                  memberId: _repository.currentEmail ?? 'unknown',
                  memberName: _repository.currentDisplayName,
                  amountPaisa: TripLedgerEngine.toPaisa(amountNum),
                );
              },
              child:
                  const Text('Record', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
}
