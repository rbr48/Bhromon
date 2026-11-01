import '../models/samity_models.dart';

/// One cycle of a samity: whose turn it is to take the pot, and when the payments fall
/// due.
class SamityCycle {
  const SamityCycle({
    required this.index,
    required this.recipientEmail,
    required this.dueOn,
    required this.potTaka,
  });

  /// The 0-based position in the schedule.
  final int index;

  /// The member who takes the pot this cycle.
  final String recipientEmail;

  /// The day payments for the cycle are due.
  final DateTime dueOn;

  /// What the cycle pays out: everyone's contribution.
  final int potTaka;

  /// The cycle as a person counts it: the first is cycle 1.
  int get number => index + 1;

  /// The first day of the month the cycle falls due in. The cycle opens then.
  DateTime get opensOn => DateTime(dueOn.year, dueOn.month);
}

/// Where a cycle stands today.
enum SamityCycleStatus {
  /// Its month has not started.
  upcoming,

  /// Its month has started and the due day has not passed.
  due,

  /// The due day has passed and the pot is not fully paid in.
  overdue,

  /// The pot is paid in, and the handover is not recorded yet.
  collected,

  /// The pot has been handed to its recipient.
  paidOut,
}

/// What one member has paid and owes, from the cycles that have fallen due.
class SamityStanding {
  const SamityStanding({
    required this.email,
    required this.owedTaka,
    required this.paidTaka,
  });

  final String email;

  /// Taka short of the contribution in cycles that have fallen due. A payment made for
  /// a later cycle does not cover an earlier one: each cycle is checked on its own.
  final int owedTaka;

  /// Taka paid across the schedule, whichever cycle it was for.
  final int paidTaka;

  bool get isUpToDate => owedTaka == 0;
}

/// The cycles of a samity, in order: one for each member in the payout order, starting
/// from the first month, with payments due on the due day of each month. Empty when the
/// samity is not set up.
List<SamityCycle> samitySchedule(SamityConfig config) {
  final first = config.firstMonth;
  if (!config.isSetUp || first == null) return const [];
  return [
    for (var i = 0; i < config.payoutOrder.length; i++)
      SamityCycle(
        index: i,
        recipientEmail: config.payoutOrder[i],
        dueOn: DateTime(first.year, first.month + i, config.dueDay),
        potTaka: config.potTaka,
      ),
  ];
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// A samity's schedule with its records, worked out for one day. Build it from the
/// tour's samity settings, its payments and its payouts, then read the cycles, their
/// statuses and what each member owes from it.
class SamityLedger {
  SamityLedger({
    required this.config,
    required Iterable<SamityPayment> payments,
    required Iterable<SamityPayout> payouts,
    required DateTime today,
  })  : today = _day(today),
        schedule = samitySchedule(config),
        _paid = <String, int>{},
        _collected = <int, int>{},
        _payoutByCycle = {for (final p in payouts) p.cycle: p} {
    for (final p in payments) {
      final key = _paidKey(p.cycle, p.email);
      _paid[key] = (_paid[key] ?? 0) + p.amountTaka;
      _collected[p.cycle] = (_collected[p.cycle] ?? 0) + p.amountTaka;
    }
  }

  final SamityConfig config;

  /// The day the ledger is worked out for, with the time dropped.
  final DateTime today;

  /// Every cycle in order. Empty when the samity is not set up.
  final List<SamityCycle> schedule;

  final Map<String, int> _paid;
  final Map<int, int> _collected;
  final Map<int, SamityPayout> _payoutByCycle;

  static String _paidKey(int cycle, String email) => '$cycle|$email';

  /// Whether the cycle's due day has come, so its payments are owed.
  bool hasFallenDue(SamityCycle cycle) => !cycle.dueOn.isAfter(today);

  /// The taka [email] has paid for [cycle].
  int paidBy(String email, int cycle) => _paid[_paidKey(cycle, email)] ?? 0;

  /// The taka paid into [cycle] by everyone.
  int collectedFor(int cycle) => _collected[cycle] ?? 0;

  /// The record of the handover for [cycle], or null when it is not recorded.
  SamityPayout? payoutFor(int cycle) => _payoutByCycle[cycle];

  /// The status of [cycle] today.
  SamityCycleStatus statusOf(SamityCycle cycle) {
    if (_payoutByCycle.containsKey(cycle.index)) {
      return SamityCycleStatus.paidOut;
    }
    if (collectedFor(cycle.index) >= cycle.potTaka) {
      return SamityCycleStatus.collected;
    }
    if (today.isBefore(cycle.opensOn)) return SamityCycleStatus.upcoming;
    if (today.isAfter(cycle.dueOn)) return SamityCycleStatus.overdue;
    return SamityCycleStatus.due;
  }

  /// The cycle the group is in today: the latest one that has opened, the first one
  /// before any has opened, or the last one once they have all opened. Null when the
  /// samity is not set up.
  SamityCycle? get currentCycle {
    if (schedule.isEmpty) return null;
    var current = schedule.first;
    for (final c in schedule) {
      if (!today.isBefore(c.opensOn)) current = c;
    }
    return current;
  }

  /// The first cycle whose handover is not recorded yet, or null when all are.
  SamityCycle? get nextPayout {
    for (final c in schedule) {
      if (!_payoutByCycle.containsKey(c.index)) return c;
    }
    return null;
  }

  /// The taka [email] still owes across the cycles that have fallen due.
  int owedBy(String email) {
    var owed = 0;
    for (final c in schedule) {
      if (!hasFallenDue(c)) continue;
      final short = config.contributionTaka - paidBy(email, c.index);
      if (short > 0) owed += short;
    }
    return owed;
  }

  /// The taka [email] has paid across the whole schedule.
  int paidAcross(String email) {
    var total = 0;
    for (final c in schedule) {
      total += paidBy(email, c.index);
    }
    return total;
  }

  /// Every member in the rotation with what they owe and have paid: the most owed
  /// first, then by email.
  List<SamityStanding> standings() {
    final members = <String>{...config.payoutOrder};
    final rows = [
      for (final email in members)
        SamityStanding(
          email: email,
          owedTaka: owedBy(email),
          paidTaka: paidAcross(email),
        ),
    ];
    rows.sort((a, b) {
      final byOwed = b.owedTaka.compareTo(a.owedTaka);
      return byOwed != 0 ? byOwed : a.email.compareTo(b.email);
    });
    return rows;
  }
}
