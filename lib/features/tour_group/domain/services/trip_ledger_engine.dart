import 'dart:math';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../models/expense_models.dart';
import 'debt_simplifier.dart';

/// Represents a group member participating in the ledger.
class LedgerMember {
  final String id;
  final String name;
  final int familyCount;

  const LedgerMember({
    required this.id,
    required this.name,
    this.familyCount = 1,
  });
}

/// Recommended peer-to-peer transfer from the debt-minimization algorithm.
class SimplifiedDebtTransfer {
  final String fromMemberId;
  final String fromMemberName;
  final String toMemberId;
  final String toMemberName;
  final int amountPaisa;

  const SimplifiedDebtTransfer({
    required this.fromMemberId,
    required this.fromMemberName,
    required this.toMemberId,
    required this.toMemberName,
    required this.amountPaisa,
  });
}

/// Per-member financial standing row for a specific monthly window.
class MemberMonthlyStanding {
  final String memberId;
  final String memberName;
  final int familyCount;

  /// Verified net balance carried forward from before the start of the month (+ = receivable/advance, - = payable/due).
  final int openingBalancePaisa;

  /// Member's share of group expenses incurred during the month.
  final int currentMonthSharePaisa;

  /// Direct group expenses paid by this member during the month (verified or cash).
  final int currentMonthPaidExpensePaisa;

  /// Verified MFS/Cash settlements paid by this member into the group/to creditors during the month.
  final int verifiedSettledPaidPaisa;

  /// Verified MFS/Cash settlements received by this member during the month.
  final int verifiedSettledReceivedPaisa;

  /// Unverified MFS TrxID payments submitted by this member awaiting manager confirmation.
  final int pendingMfsSubmittedPaisa;

  const MemberMonthlyStanding({
    required this.memberId,
    required this.memberName,
    this.familyCount = 1,
    required this.openingBalancePaisa,
    required this.currentMonthSharePaisa,
    required this.currentMonthPaidExpensePaisa,
    required this.verifiedSettledPaidPaisa,
    required this.verifiedSettledReceivedPaisa,
    required this.pendingMfsSubmittedPaisa,
  });

  /// Total verified credits contributed by the member this month (direct expenses paid + verified settlements paid - verified settlements received).
  int get netVerifiedContributionPaisa =>
      currentMonthPaidExpensePaisa +
      verifiedSettledPaidPaisa -
      verifiedSettledReceivedPaisa;

  /// Closing verified net balance at the end of the month:
  /// Positive (> 0) means the member is owed money / has an advance credit (পাওনা/অগ্রিম).
  /// Negative (< 0) means the member owes money / has outstanding dues (বকেয়া/দেয়).
  int get closingNetBalancePaisa =>
      openingBalancePaisa +
      netVerifiedContributionPaisa -
      currentMonthSharePaisa;

  /// Projected closing balance if all pending unverified MFS TrxIDs are approved.
  int get projectedBalanceAfterPendingPaisa =>
      closingNetBalancePaisa + pendingMfsSubmittedPaisa;
}

/// Unified MFS audit entry combining MFS-paid expenses and peer/fund settlements.
class MfsAuditEntry {
  final String recordId;
  final bool isSettlement;
  final DateTime date;
  final String payerName;
  final String receiverOrTitle;
  final MfsPaymentInfo mfsInfo;
  final int principalPaisa;

  const MfsAuditEntry({
    required this.recordId,
    required this.isSettlement,
    required this.date,
    required this.payerName,
    required this.receiverOrTitle,
    required this.mfsInfo,
    required this.principalPaisa,
  });

  int get totalWithFeePaisa => principalPaisa + mfsInfo.feePaisa;
}

/// Complete monthly ledger statement output consumed by the UI and `MonthlyLedgerPdfGenerator`.
class MonthlyLedgerStatement {
  final String tourId;
  final String groupTitle;
  final String
      groupArchetype; // e.g., 'mess', 'samity', 'society', 'tour', 'family'
  final int year;
  final int month;
  final DateTime periodStart;
  final DateTime periodEnd;

  final int totalOpeningNetPaisa;
  final int totalMonthExpensesPaisa;
  final int totalVerifiedMfsCollectionsPaisa;
  final int totalPendingMfsCollectionsPaisa;
  final int totalMfsFeesPaisa;

  final Map<String, int> categoryTotalsPaisa;
  final List<MemberMonthlyStanding> memberStandings;
  final List<ExpenseItem> monthExpenses;
  final List<SettlementRecord> monthSettlements;
  final List<MfsAuditEntry> mfsAuditLog;
  final List<SimplifiedDebtTransfer> recommendedSettlements;

  /// Deterministic SHA-256 verification digest (first 12 hex chars) of verified TrxIDs and closing balances.
  final String verificationDigest;

  const MonthlyLedgerStatement({
    required this.tourId,
    required this.groupTitle,
    required this.groupArchetype,
    required this.year,
    required this.month,
    required this.periodStart,
    required this.periodEnd,
    required this.totalOpeningNetPaisa,
    required this.totalMonthExpensesPaisa,
    required this.totalVerifiedMfsCollectionsPaisa,
    required this.totalPendingMfsCollectionsPaisa,
    required this.totalMfsFeesPaisa,
    required this.categoryTotalsPaisa,
    required this.memberStandings,
    required this.monthExpenses,
    required this.monthSettlements,
    required this.mfsAuditLog,
    required this.recommendedSettlements,
    required this.verificationDigest,
  });
}

class LedgerMemberInput {
  final String id;
  final String name;
  final int familyCount;
  final int depositPaisa;

  const LedgerMemberInput({
    required this.id,
    required this.name,
    this.familyCount = 1,
    this.depositPaisa = 0,
  });
}

class LedgerMemberRow {
  final String id;
  final String name;
  final int familyCount;
  final int depositPaisa;
  final int directPaidPaisa;
  final int contributedPaisa;
  final int sharePaisa;
  final int netPaisa;

  /// Settle-up money this person handed over, and money they were handed.
  final int transfersOutPaisa;
  final int transfersInPaisa;

  /// Someone who paid or deposited but has since left the tour. They keep
  /// their balance so the books still add up, but they owe no share.
  final bool isFormerMember;

  const LedgerMemberRow({
    required this.id,
    required this.name,
    required this.familyCount,
    required this.depositPaisa,
    required this.directPaidPaisa,
    required this.contributedPaisa,
    required this.sharePaisa,
    required this.netPaisa,
    this.isFormerMember = false,
    this.transfersOutPaisa = 0,
    this.transfersInPaisa = 0,
  });

  double get depositTaka => depositPaisa / 100.0;
  double get directPaidTaka => directPaidPaisa / 100.0;
  double get contributedTaka => contributedPaisa / 100.0;
  double get shareTaka => sharePaisa / 100.0;
  double get netTaka => netPaisa / 100.0;
}

class SettlementTransaction {
  final String from;
  final String to;

  /// Member ids (emails) of the two sides; null for the fund.
  final String? fromId;
  final String? toId;
  final bool fromFund;
  final bool toFund;
  final int amountPaisa;

  const SettlementTransaction({
    required this.from,
    required this.to,
    this.fromId,
    this.toId,
    this.fromFund = false,
    this.toFund = false,
    required this.amountPaisa,
  });

  double get amountTaka => amountPaisa / 100.0;
}

class CategoryTotal {
  final String category;
  final int amountPaisa;

  const CategoryTotal({required this.category, required this.amountPaisa});
  double get amountTaka => amountPaisa / 100.0;
}

class LedgerSummary {
  final int headcount;
  final int totalDepositsPaisa;
  final int totalExpensePaisa;
  final int fundPaidPaisa;
  final int fundBalancePaisa;
  final int perHeadCostPaisa;
  final List<LedgerMemberRow> rows;
  final List<SettlementTransaction> settlements;
  final List<CategoryTotal> categoryTotals;

  const LedgerSummary({
    required this.headcount,
    required this.totalDepositsPaisa,
    required this.totalExpensePaisa,
    required this.fundPaidPaisa,
    required this.fundBalancePaisa,
    required this.perHeadCostPaisa,
    required this.rows,
    required this.settlements,
    required this.categoryTotals,
  });

  double get totalDepositsTaka => totalDepositsPaisa / 100.0;
  double get totalExpenseTaka => totalExpensePaisa / 100.0;
  double get fundPaidTaka => fundPaidPaisa / 100.0;
  double get fundBalanceTaka => fundBalancePaisa / 100.0;
  double get perHeadCostTaka => perHeadCostPaisa / 100.0;
}

/// Pure Dart financial ledger engine operating in whole integer paisa.
/// Eliminates floating-point rounding errors and keeps the books balanced to
/// the paisa: every expense share and every deposit lands somewhere.
class TripLedgerEngine {
  const TripLedgerEngine();

  /// Computes how a single [ExpenseItem] is divided among [members] in integer paisa.
  /// Any remainder paisa from integer division is distributed 1 paisa at a time
  /// in deterministic member order so the sum of shares always equals `expense.effectiveAmountPaisa`.
  Map<String, int> allocateExpenseShares(
    ExpenseItem expense,
    List<LedgerMember> members,
  ) {
    if (members.isEmpty) return const {};

    final activeIds =
        (expense.participantIds == null || expense.participantIds!.isEmpty)
            ? members.map((m) => m.id).toSet()
            : expense.participantIds!.toSet();

    final participants =
        members.where((m) => activeIds.contains(m.id)).toList();
    if (participants.isEmpty) return const {};

    final totalPaisa = expense.effectiveAmountPaisa;
    final result = <String, int>{for (final m in members) m.id: 0};

    switch (expense.splitMode) {
      case SplitMode.exact:
        final shares = expense.splitShares ?? const {};
        var allocated = 0;
        for (final p in participants) {
          final exact = shares[p.id] ?? 0;
          result[p.id] = exact;
          allocated += exact;
        }
        // If custom exact shares don't sum to totalPaisa (e.g., MFS fee added), distribute remainder equally.
        final diff = totalPaisa - allocated;
        if (diff != 0) {
          _distributeProportionally(
            result: result,
            participants: participants,
            weights: {for (final p in participants) p.id: 1},
            amountToDistribute: diff,
          );
        }
        break;

      case SplitMode.shares:
        final shares = expense.splitShares ?? const {};
        final weights = <String, int>{
          for (final p in participants) p.id: math.max(0, shares[p.id] ?? 1),
        };
        _distributeProportionally(
          result: result,
          participants: participants,
          weights: weights,
          amountToDistribute: totalPaisa,
        );
        break;

      case SplitMode.family:
        final weights = <String, int>{
          for (final p in participants) p.id: math.max(1, p.familyCount),
        };
        _distributeProportionally(
          result: result,
          participants: participants,
          weights: weights,
          amountToDistribute: totalPaisa,
        );
        break;

      case SplitMode.equal:
        final weights = <String, int>{for (final p in participants) p.id: 1};
        _distributeProportionally(
          result: result,
          participants: participants,
          weights: weights,
          amountToDistribute: totalPaisa,
        );
        break;
    }

    return result;
  }

  void _distributeProportionally({
    required Map<String, int> result,
    required List<LedgerMember> participants,
    required Map<String, int> weights,
    required int amountToDistribute,
  }) {
    final totalWeight =
        weights.values.fold<int>(0, (sum, weight) => sum + weight);
    if (totalWeight <= 0) return;

    var distributed = 0;
    for (final p in participants) {
      final w = weights[p.id] ?? 0;
      final share = (amountToDistribute * w) ~/ totalWeight;
      result[p.id] = (result[p.id] ?? 0) + share;
      distributed += share;
    }

    var remainder = amountToDistribute - distributed;
    var idx = 0;
    final step = remainder >= 0 ? 1 : -1;
    while (remainder != 0) {
      final member = participants[idx % participants.length];
      if ((weights[member.id] ?? 0) > 0) {
        result[member.id] = (result[member.id] ?? 0) + step;
        remainder -= step;
      }
      idx++;
    }
  }

  /// Generates a complete [MonthlyLedgerStatement] for `(year, month)` with carry-forward
  /// opening balances and verified vs. pending MFS TrxID reconciliation.
  MonthlyLedgerStatement computeMonthlyStatement({
    required String tourId,
    required String groupTitle,
    String groupArchetype = 'mess',
    required int year,
    required int month,
    required List<LedgerMember> members,
    required List<ExpenseItem> allExpenses,
    required List<SettlementRecord> allSettlements,
  }) {
    final periodStart = DateTime(year, month, 1);
    final periodEnd =
        DateTime(year, month + 1, 1).subtract(const Duration(milliseconds: 1));

    final memberMap = {for (final m in members) m.id: m};

    // 1. Opening carry-forward balances (all verified activity prior to periodStart)
    final openingBalances = <String, int>{for (final m in members) m.id: 0};

    for (final exp in allExpenses) {
      if (exp.tourId != tourId) continue;
      if (exp.date.isBefore(periodStart)) {
        final isVerified = exp.mfsInfo == null || exp.mfsInfo!.isVerified;
        if (!isVerified) continue;

        final shares = allocateExpenseShares(exp, members);
        for (final entry in shares.entries) {
          openingBalances[entry.key] =
              (openingBalances[entry.key] ?? 0) - entry.value;
        }
        if (exp.paidById != null && openingBalances.containsKey(exp.paidById)) {
          openingBalances[exp.paidById!] =
              openingBalances[exp.paidById!]! + exp.effectiveAmountPaisa;
        }
      }
    }

    for (final set in allSettlements) {
      if (set.tourId != tourId) continue;
      if (set.date.isBefore(periodStart) && set.isVerified) {
        if (openingBalances.containsKey(set.fromMemberId)) {
          openingBalances[set.fromMemberId] =
              openingBalances[set.fromMemberId]! + set.creditedPaisa;
        }
        if (openingBalances.containsKey(set.toMemberId)) {
          openingBalances[set.toMemberId] =
              openingBalances[set.toMemberId]! - set.amountPaisa;
        }
      }
    }

    // 2. Current month activity
    final monthShare = <String, int>{for (final m in members) m.id: 0};
    final monthPaidExpense = <String, int>{for (final m in members) m.id: 0};
    final monthVerifiedSettledPaid = <String, int>{
      for (final m in members) m.id: 0
    };
    final monthVerifiedSettledReceived = <String, int>{
      for (final m in members) m.id: 0
    };
    final monthPendingMfs = <String, int>{for (final m in members) m.id: 0};

    final monthExpenses = <ExpenseItem>[];
    final monthSettlements = <SettlementRecord>[];
    final mfsAuditLog = <MfsAuditEntry>[];
    final categoryTotalsPaisa = <String, int>{};

    var totalMonthExpensesPaisa = 0;
    var totalVerifiedMfsCollectionsPaisa = 0;
    var totalPendingMfsCollectionsPaisa = 0;
    var totalMfsFeesPaisa = 0;

    for (final exp in allExpenses) {
      if (exp.tourId != tourId) continue;
      final inMonth =
          !exp.date.isBefore(periodStart) && !exp.date.isAfter(periodEnd);
      if (!inMonth) continue;

      monthExpenses.add(exp);

      if (exp.mfsInfo != null && exp.mfsInfo!.provider != MfsProvider.cash) {
        mfsAuditLog.add(
          MfsAuditEntry(
            recordId: exp.id,
            isSettlement: false,
            date: exp.date,
            payerName: exp.paidByName ??
                memberMap[exp.paidById]?.name ??
                exp.addedByEmail,
            receiverOrTitle: exp.title,
            mfsInfo: exp.mfsInfo!,
            principalPaisa: exp.amountPaisa,
          ),
        );
        totalMfsFeesPaisa += exp.mfsInfo!.feePaisa;
      }

      final isVerified = exp.mfsInfo == null || exp.mfsInfo!.isVerified;
      if (isVerified) {
        totalMonthExpensesPaisa += exp.effectiveAmountPaisa;
        categoryTotalsPaisa[exp.category] =
            (categoryTotalsPaisa[exp.category] ?? 0) + exp.effectiveAmountPaisa;

        final shares = allocateExpenseShares(exp, members);
        for (final entry in shares.entries) {
          monthShare[entry.key] = (monthShare[entry.key] ?? 0) + entry.value;
        }
        if (exp.paidById != null &&
            monthPaidExpense.containsKey(exp.paidById)) {
          monthPaidExpense[exp.paidById!] =
              monthPaidExpense[exp.paidById!]! + exp.effectiveAmountPaisa;
        }
      } else if (exp.paidById != null &&
          exp.mfsInfo?.status == MfsVerificationStatus.unverified &&
          monthPendingMfs.containsKey(exp.paidById)) {
        monthPendingMfs[exp.paidById!] =
            monthPendingMfs[exp.paidById!]! + exp.effectiveAmountPaisa;
      }
    }

    for (final set in allSettlements) {
      if (set.tourId != tourId) continue;
      final inMonth =
          !set.date.isBefore(periodStart) && !set.date.isAfter(periodEnd);
      if (!inMonth) continue;

      monthSettlements.add(set);

      if (set.mfsInfo.provider != MfsProvider.cash) {
        mfsAuditLog.add(
          MfsAuditEntry(
            recordId: set.id,
            isSettlement: true,
            date: set.date,
            payerName: set.fromMemberName,
            receiverOrTitle: set.toMemberName,
            mfsInfo: set.mfsInfo,
            principalPaisa: set.amountPaisa,
          ),
        );
        totalMfsFeesPaisa += set.mfsInfo.feePaisa;
      }

      if (set.isVerified) {
        if (set.mfsInfo.provider != MfsProvider.cash) {
          totalVerifiedMfsCollectionsPaisa += set.amountPaisa;
        }
        if (monthVerifiedSettledPaid.containsKey(set.fromMemberId)) {
          monthVerifiedSettledPaid[set.fromMemberId] =
              monthVerifiedSettledPaid[set.fromMemberId]! + set.creditedPaisa;
        }
        if (monthVerifiedSettledReceived.containsKey(set.toMemberId)) {
          monthVerifiedSettledReceived[set.toMemberId] =
              monthVerifiedSettledReceived[set.toMemberId]! + set.amountPaisa;
        }
      } else if (set.mfsInfo.status == MfsVerificationStatus.unverified) {
        totalPendingMfsCollectionsPaisa += set.amountPaisa;
        if (monthPendingMfs.containsKey(set.fromMemberId)) {
          monthPendingMfs[set.fromMemberId] =
              monthPendingMfs[set.fromMemberId]! + set.creditedPaisa;
        }
      }
    }

    monthExpenses.sort((a, b) => a.date.compareTo(b.date));
    monthSettlements.sort((a, b) => a.date.compareTo(b.date));
    mfsAuditLog.sort((a, b) => a.date.compareTo(b.date));

    final standings = <MemberMonthlyStanding>[];
    final closingNetById = <String, int>{};

    for (final m in members) {
      final standing = MemberMonthlyStanding(
        memberId: m.id,
        memberName: m.name,
        familyCount: m.familyCount,
        openingBalancePaisa: openingBalances[m.id] ?? 0,
        currentMonthSharePaisa: monthShare[m.id] ?? 0,
        currentMonthPaidExpensePaisa: monthPaidExpense[m.id] ?? 0,
        verifiedSettledPaidPaisa: monthVerifiedSettledPaid[m.id] ?? 0,
        verifiedSettledReceivedPaisa: monthVerifiedSettledReceived[m.id] ?? 0,
        pendingMfsSubmittedPaisa: monthPendingMfs[m.id] ?? 0,
      );
      standings.add(standing);
      closingNetById[m.id] = standing.closingNetBalancePaisa;
    }

    final totalOpeningNetPaisa = openingBalances.values
        .where((v) => v > 0)
        .fold<int>(0, (a, b) => a + b);

    final recommendedSettlements = simplifyDebts(
      netBalancesPaisa: closingNetById,
      memberNames: {for (final m in members) m.id: m.name},
    );

    final verificationDigest = _computeStatementDigest(
      tourId: tourId,
      year: year,
      month: month,
      standings: standings,
      mfsAuditLog: mfsAuditLog,
    );

    return MonthlyLedgerStatement(
      tourId: tourId,
      groupTitle: groupTitle,
      groupArchetype: groupArchetype,
      year: year,
      month: month,
      periodStart: periodStart,
      periodEnd: periodEnd,
      totalOpeningNetPaisa: totalOpeningNetPaisa,
      totalMonthExpensesPaisa: totalMonthExpensesPaisa,
      totalVerifiedMfsCollectionsPaisa: totalVerifiedMfsCollectionsPaisa,
      totalPendingMfsCollectionsPaisa: totalPendingMfsCollectionsPaisa,
      totalMfsFeesPaisa: totalMfsFeesPaisa,
      categoryTotalsPaisa: categoryTotalsPaisa,
      memberStandings: standings,
      monthExpenses: monthExpenses,
      monthSettlements: monthSettlements,
      mfsAuditLog: mfsAuditLog,
      recommendedSettlements: recommendedSettlements,
      verificationDigest: verificationDigest,
    );
  }

  /// Greedy debt-minimization algorithm that matches the largest debtor with the largest creditor.
  List<SimplifiedDebtTransfer> simplifyDebts({
    required Map<String, int> netBalancesPaisa,
    required Map<String, String> memberNames,
  }) {
    final debtors = <MapEntry<String, int>>[];
    final creditors = <MapEntry<String, int>>[];

    for (final entry in netBalancesPaisa.entries) {
      if (entry.value < 0) {
        debtors.add(MapEntry(entry.key, -entry.value));
      } else if (entry.value > 0) {
        creditors.add(MapEntry(entry.key, entry.value));
      }
    }

    debtors.sort((a, b) => b.value.compareTo(a.value));
    creditors.sort((a, b) => b.value.compareTo(a.value));

    final transfers = <SimplifiedDebtTransfer>[];
    var i = 0;
    var j = 0;

    while (i < debtors.length && j < creditors.length) {
      final debtor = debtors[i];
      final creditor = creditors[j];
      final settled = math.min(debtor.value, creditor.value);

      if (settled > 0) {
        transfers.add(
          SimplifiedDebtTransfer(
            fromMemberId: debtor.key,
            fromMemberName: memberNames[debtor.key] ?? debtor.key,
            toMemberId: creditor.key,
            toMemberName: memberNames[creditor.key] ?? creditor.key,
            amountPaisa: settled,
          ),
        );
      }

      final remainingDebt = debtor.value - settled;
      final remainingCredit = creditor.value - settled;

      if (remainingDebt == 0) {
        i++;
      } else {
        debtors[i] = MapEntry(debtor.key, remainingDebt);
      }

      if (remainingCredit == 0) {
        j++;
      } else {
        creditors[j] = MapEntry(creditor.key, remainingCredit);
      }
    }

    return transfers;
  }

  String _computeStatementDigest({
    required String tourId,
    required int year,
    required int month,
    required List<MemberMonthlyStanding> standings,
    required List<MfsAuditEntry> mfsAuditLog,
  }) {
    final buffer = StringBuffer('$tourId|$year-$month|');
    for (final s in standings) {
      buffer.write('${s.memberId}:${s.closingNetBalancePaisa};');
    }
    for (final audit in mfsAuditLog) {
      if (audit.mfsInfo.isVerified) {
        buffer.write(
          '${audit.mfsInfo.provider.name}:${audit.mfsInfo.normalizedTrxId ?? "CASH"}:${audit.principalPaisa};',
        );
      }
    }
    final bytes = utf8.encode(buffer.toString());
    return sha256.convert(bytes).toString().substring(0, 12).toUpperCase();
  }

  static const String fundLabel = 'গ্রুপ ফান্ড';
  static const int maxSafeAmountTaka = 10000000;

  /// Converts taka to paisa. Throws [ArgumentError] for negative, non-finite
  /// or above-cap amounts. Null and zero both return 0.
  static int toPaisa(num? taka) {
    if (taka == null) return 0;
    if (taka.isNaN || taka.isInfinite) {
      throw ArgumentError.value(taka, 'taka', 'must be a finite number');
    }
    if (taka < 0) {
      throw ArgumentError.value(taka, 'taka', 'must not be negative');
    }
    if (taka > maxSafeAmountTaka) {
      throw ArgumentError.value(taka, 'taka', 'exceeds the ledger limit');
    }
    return (taka * 100).round();
  }

  /// Parses an amount typed by a user. Accepts Bengali digits, commas, the ৳
  /// sign and up to two decimal places. Returns null when the input is not a
  /// positive amount within the limit.
  static int? parseTakaInput(String raw) {
    const bengaliDigits = '০১২৩৪৫৬৭৮৯';
    var text = raw.trim().replaceAll(RegExp(r'[,\s৳]'), '');
    for (var i = 0; i < 10; i++) {
      text = text.replaceAll(bengaliDigits[i], '$i');
    }
    final match = RegExp(r'^(\d{1,8})(?:\.(\d{1,2}))?$').firstMatch(text);
    if (match == null) return null;
    final whole = int.parse(match.group(1)!);
    final fraction = (match.group(2) ?? '').padRight(2, '0');
    final paisa = whole * 100 + int.parse(fraction);
    if (paisa <= 0 || paisa > maxSafeAmountTaka * 100) return null;
    return paisa;
  }

  /// Formats paisa as "৳1,250" or "৳1,250.50" (two decimals only when needed).
  static String formatTaka(int paisa) {
    final sign = paisa < 0 ? '-' : '';
    final absolute = paisa.abs();
    final whole = (absolute ~/ 100).toString();
    final grouped = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(',');
      grouped.write(whole[i]);
    }
    final cents = absolute % 100;
    final decimals = cents == 0 ? '' : '.${cents.toString().padLeft(2, '0')}';
    return '$sign৳$grouped$decimals';
  }

  /// The amount as a plain number the input box accepts: "1250" or "1250.50".
  static String plainTakaInput(int paisa) {
    final whole = paisa ~/ 100;
    final cents = paisa % 100;
    return cents == 0 ? '$whole' : '$whole.${cents.toString().padLeft(2, '0')}';
  }

  /// The participant list to store for a split. Null means every current
  /// member shares it, so members who join later are included. Former members
  /// stay in the list while they are selected.
  static List<String>? participantSelection({
    required Set<String> selected,
    required List<String> memberEmails,
  }) {
    final everyone = memberEmails.every(selected.contains) &&
        selected.length == memberEmails.length;
    return everyone ? null : selected.toList();
  }

  static double toTaka(int paisa) => paisa / 100.0;

  /// Splits `total` integer paisa proportionally by `weights` using the largest-remainder method.
  /// Guarantees that parts sum to exactly `total` with zero lost or created paisa.
  static List<int> allocate(int total, List<int> weights) {
    if (weights.isEmpty) return [];
    final weightSum = weights.fold<int>(0, (sum, w) => sum + w);
    if (weightSum <= 0 || total == 0) return List.filled(weights.length, 0);

    final exact = weights.map((w) => (total * w) / weightSum).toList();
    final parts = exact.map((v) => v.floor()).toList();
    int leftover = total - parts.fold<int>(0, (sum, p) => sum + p);

    final fractions = List.generate(exact.length, (i) => i);
    fractions.sort((a, b) {
      final fracA = exact[a] - exact[a].floor();
      final fracB = exact[b] - exact[b].floor();
      final cmp = fracB.compareTo(fracA);
      return cmp != 0 ? cmp : a.compareTo(b);
    });

    for (int i = 0; leftover > 0 && i < fractions.length; i++, leftover--) {
      parts[fractions[i]] += 1;
    }

    return parts;
  }

  /// Computes a simplified settlement plan with the minimum number of bilateral
  /// cash transfers required to balance all accounts. Falls back to greedy pairing
  /// if non-strict party totals are passed.
  static List<SettlementTransaction> settle(
      List<({String name, int netPaisa, bool fund, String? id})> parties) {
    try {
      return DebtSimplifier.simplifyDebts(parties);
    } catch (_) {
      return _greedySettle(parties);
    }
  }

  static List<SettlementTransaction> _greedySettle(
      List<({String name, int netPaisa, bool fund, String? id})> parties) {
    final balanceSum = parties.fold<int>(0, (sum, p) => sum + p.netPaisa);
    if (balanceSum.abs() > 1) {
      throw StateError(
          'Ledger balances do not sum to zero: total net is $balanceSum paisa');
    }

    final debtors = parties
        .where((p) => p.netPaisa < 0)
        .map((p) => _PartyBalance(
            name: p.name, id: p.id, amountPaisa: -p.netPaisa, isFund: p.fund))
        .toList()
      ..sort((a, b) => b.amountPaisa.compareTo(a.amountPaisa));

    final creditors = parties
        .where((p) => p.netPaisa > 0)
        .map((p) => _PartyBalance(
            name: p.name, id: p.id, amountPaisa: p.netPaisa, isFund: p.fund))
        .toList()
      ..sort((a, b) => b.amountPaisa.compareTo(a.amountPaisa));

    final transactions = <SettlementTransaction>[];
    int d = 0;
    int c = 0;
    final maxIterations = (debtors.length + creditors.length) * 2;
    int iterations = 0;

    while (d < debtors.length &&
        c < creditors.length &&
        iterations < maxIterations) {
      iterations++;
      final amount = min(debtors[d].amountPaisa, creditors[c].amountPaisa);
      if (amount <= 0) break;

      transactions.add(
        SettlementTransaction(
          from: debtors[d].name,
          to: creditors[c].name,
          fromId: debtors[d].id,
          toId: creditors[c].id,
          fromFund: debtors[d].isFund,
          toFund: creditors[c].isFund,
          amountPaisa: amount,
        ),
      );

      debtors[d].amountPaisa -= amount;
      creditors[c].amountPaisa -= amount;

      if (debtors[d].amountPaisa == 0) d++;
      if (creditors[c].amountPaisa == 0) c++;
    }

    return transactions;
  }

  static String _key(String id) => id.trim().toLowerCase();

  /// Each sharer's part of [exp], in paisa, by its [ExpenseItem.splitMode].
  /// [sharers] are member indexes; [familyWeights] gives each member's family
  /// size. Parts always add up to the expense, to the paisa.
  static List<int> splitParts(ExpenseItem exp, List<int> sharers,
      List<int> familyWeights, List<String> memberKeys) {
    List<int> by(List<int> weights) => allocate(exp.amountPaisa, weights);
    final shares = exp.splitShares;
    switch (exp.splitMode) {
      case SplitMode.equal:
        return by(List.filled(sharers.length, 1));
      case SplitMode.exact:
      case SplitMode.shares:
        if (shares == null) break;
        final weights = [
          for (final i in sharers) max(0, shares[memberKeys[i]] ?? 0),
        ];
        // Amounts or parts for people who have left are shared by the rest
        // in proportion, so the books still balance.
        if (weights.fold<int>(0, (a, b) => a + b) > 0) return by(weights);
      case SplitMode.family:
        break;
    }
    return by([for (final i in sharers) familyWeights[i]]);
  }

  /// Computes the complete multi-member ledger summary.
  ///
  /// Each expense is split only among its [ExpenseItem.participantIds] (or all
  /// current members when that is null), weighted by family size. Payers and
  /// depositors who are no longer members still appear, with no share, so no
  /// money disappears from the books.
  static LedgerSummary computeLedger({
    required List<LedgerMemberInput> members,
    required List<ExpenseItem> expenses,
    List<DepositItem> deposits = const [],
    List<TransferItem> transfers = const [],
  }) {
    final memberIndex = <String, int>{};
    for (var i = 0; i < members.length; i++) {
      memberIndex.putIfAbsent(_key(members[i].id), () => i);
    }
    final weights = members.map((m) => max(1, m.familyCount)).toList();
    final memberKeys = [for (final m in members) _key(m.id)];
    final headcount = weights.fold<int>(0, (sum, w) => sum + w);
    final allMemberIdx = List.generate(members.length, (i) => i);

    // Everyone who has money in the books, including former members.
    final extraNames = <String, String>{};
    final depositByKey = <String, int>{};
    int totalDepositsPaisa = 0;

    // Pre-totalled deposits per member, plus individual deposit records.
    for (final m in members) {
      final key = _key(m.id);
      totalDepositsPaisa += m.depositPaisa;
      depositByKey[key] = (depositByKey[key] ?? 0) + m.depositPaisa;
    }
    for (final dep in deposits) {
      final key = _key(dep.memberId);
      totalDepositsPaisa += dep.amountPaisa;
      depositByKey[key] = (depositByKey[key] ?? 0) + dep.amountPaisa;
      if (!memberIndex.containsKey(key)) {
        extraNames.putIfAbsent(key, () => dep.memberName);
      }
    }

    int totalExpensePaisa = 0;
    int fundPaidPaisa = 0;
    final directPaisa = <String, int>{};
    final sharePaisa = List<int>.filled(members.length, 0);
    final categoryMap = <String, int>{};

    for (final exp in expenses) {
      final paisa = exp.amountPaisa;
      totalExpensePaisa += paisa;

      final cat = exp.category.isNotEmpty ? exp.category : 'Others';
      categoryMap[cat] = (categoryMap[cat] ?? 0) + paisa;

      final payerId = exp.paidById;
      if (payerId == null || payerId.isEmpty) {
        fundPaidPaisa += paisa;
      } else {
        final key = _key(payerId);
        directPaisa[key] = (directPaisa[key] ?? 0) + paisa;
        if (!memberIndex.containsKey(key)) {
          extraNames.putIfAbsent(key, () => exp.paidByName ?? payerId);
        }
      }

      // Pick who shares this expense: the named participants who are still
      // members, or everyone when none are named.
      // Exact and custom splits name their sharers in the split itself.
      final named = exp.participantIds ??
          ((exp.splitMode == SplitMode.exact ||
                      exp.splitMode == SplitMode.shares) &&
                  exp.splitShares != null
              ? exp.splitShares!.keys.toList()
              : null);
      var sharers = named == null
          ? allMemberIdx
          : named
              .map((id) => memberIndex[_key(id)])
              .whereType<int>()
              .toSet()
              .toList();
      if (sharers.isEmpty) sharers = allMemberIdx;
      if (sharers.isEmpty) continue; // No members yet, so nothing to share.
      sharers.sort();

      final parts = splitParts(exp, sharers, weights, memberKeys);
      for (var k = 0; k < sharers.length; k++) {
        sharePaisa[sharers[k]] += parts[k];
      }
    }

    // Settle-up payments: handing money over raises your balance, being
    // handed money lowers it. Payments into the fund add to its balance and
    // refunds from it reduce it.
    final outPaisa = <String, int>{};
    final inPaisa = <String, int>{};
    var intoFund = 0, outOfFund = 0;
    for (final t in transfers) {
      final amount = t.amountPaisa;
      if (amount <= 0) continue;
      if (t.fromId == null) {
        outOfFund += amount;
      } else {
        final key = _key(t.fromId!);
        outPaisa[key] = (outPaisa[key] ?? 0) + amount;
        if (!memberIndex.containsKey(key)) {
          extraNames.putIfAbsent(key, () => t.fromName);
        }
      }
      if (t.toId == null) {
        intoFund += amount;
      } else {
        final key = _key(t.toId!);
        inPaisa[key] = (inPaisa[key] ?? 0) + amount;
        if (!memberIndex.containsKey(key)) {
          extraNames.putIfAbsent(key, () => t.toName);
        }
      }
    }

    final rows = <LedgerMemberRow>[];
    for (var i = 0; i < members.length; i++) {
      final m = members[i];
      final key = _key(m.id);
      final deposit = depositByKey[key] ?? 0;
      final direct = directPaisa[key] ?? 0;
      final contributed = deposit + direct;
      final out = outPaisa[key] ?? 0, received = inPaisa[key] ?? 0;
      rows.add(
        LedgerMemberRow(
          id: m.id,
          name: m.name,
          familyCount: weights[i],
          depositPaisa: deposit,
          directPaidPaisa: direct,
          contributedPaisa: contributed,
          sharePaisa: sharePaisa[i],
          netPaisa: contributed + out - received - sharePaisa[i],
          transfersOutPaisa: out,
          transfersInPaisa: received,
        ),
      );
    }

    for (final key in extraNames.keys) {
      final deposit = depositByKey[key] ?? 0;
      final direct = directPaisa[key] ?? 0;
      final out = outPaisa[key] ?? 0, received = inPaisa[key] ?? 0;
      rows.add(
        LedgerMemberRow(
          id: key,
          name: extraNames[key]!,
          familyCount: 0,
          depositPaisa: deposit,
          directPaidPaisa: direct,
          contributedPaisa: deposit + direct,
          sharePaisa: 0,
          netPaisa: deposit + direct + out - received,
          isFormerMember: true,
          transfersOutPaisa: out,
          transfersInPaisa: received,
        ),
      );
    }

    final fundBalancePaisa =
        totalDepositsPaisa - fundPaidPaisa + intoFund - outOfFund;
    final netSumPaisa = rows.fold<int>(0, (sum, r) => sum + r.netPaisa);

    final parties = [
      ...rows.map(
          (r) => (name: r.name, netPaisa: r.netPaisa, fund: false, id: r.id)),
      (name: fundLabel, netPaisa: -netSumPaisa, fund: true, id: null),
    ];

    final settlements = settle(parties);

    final categoryTotalsList = categoryMap.entries
        .map((e) => CategoryTotal(category: e.key, amountPaisa: e.value))
        .toList()
      ..sort((a, b) => b.amountPaisa.compareTo(a.amountPaisa));

    return LedgerSummary(
      headcount: headcount,
      totalDepositsPaisa: totalDepositsPaisa,
      totalExpensePaisa: totalExpensePaisa,
      fundPaidPaisa: fundPaidPaisa,
      fundBalancePaisa: fundBalancePaisa,
      perHeadCostPaisa:
          headcount > 0 ? (totalExpensePaisa / headcount).round() : 0,
      rows: rows,
      settlements: settlements,
      categoryTotals: categoryTotalsList,
    );
  }
}

class _PartyBalance {
  final String name;
  final String? id;
  int amountPaisa;
  final bool isFund;

  _PartyBalance({
    required this.name,
    this.id,
    required this.amountPaisa,
    this.isFund = false,
  });
}
