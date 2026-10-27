// Domain models for trip expenses, deposits and settle-up payments.

import 'date_codec.dart';

/// How an expense is shared among its participants.
enum SplitMode {
  /// By family size: a member travelling with three others pays four parts.
  family,

  /// One equal part for each participating member, whatever their family.
  equal,

  /// A set amount each, in [ExpenseItem.splitShares] (paisa).
  exact,

  /// Custom parts each, in [ExpenseItem.splitShares] (whole numbers).
  shares;

  static SplitMode fromString(String? value) {
    for (final m in values) {
      if (m.name == value) return m;
    }
    return SplitMode.family;
  }
}

class ExpenseItem {
  final String id;
  final String tourId;
  final String title;
  final int amountPaisa; // Integer paisa: 100 paisa = 1 BDT

  /// Member email, or null when the expense came out of the shared fund.
  final String? paidById;
  final String? paidByName;
  final String category; // e.g. Food, Transport, Hotel, Tickets, Others
  final DateTime date;
  final String? notes;

  /// Who entered this expense. Rules let only this person (or an admin) edit it.
  final String addedByEmail;

  /// Members who share this cost. Null means every current member shares it.
  final List<String>? participantIds;

  final SplitMode splitMode;

  /// For [SplitMode.exact], each member's amount in paisa; for
  /// [SplitMode.shares], each member's parts. Keys are member emails.
  final Map<String, int>? splitShares;

  /// The itinerary stop this was spent at, if any.
  final String? stopId;

  /// For a cost paid in another currency: its code (such as INR), the amount
  /// in that currency's minor units, and the BDT price of one unit.
  /// [amountPaisa] is always the BDT value the books use.
  final String? currency;
  final int? originalMinor;
  final double? fxRate;

  /// Attached photo receipt / memo URL on the media server or storage.
  final String? receiptUrl;

  bool get isForeign => currency != null && currency != 'BDT';

  const ExpenseItem({
    required this.id,
    required this.tourId,
    required this.title,
    required this.amountPaisa,
    this.paidById,
    this.paidByName,
    required this.category,
    required this.date,
    this.notes,
    this.addedByEmail = '',
    this.participantIds,
    this.splitMode = SplitMode.family,
    this.splitShares,
    this.stopId,
    this.currency,
    this.originalMinor,
    this.fxRate,
    this.receiptUrl,
  });

  double get amountTaka => amountPaisa / 100.0;

  ExpenseItem copyWith({
    String? id,
    String? tourId,
    String? title,
    int? amountPaisa,
    String? paidById,
    String? paidByName,
    String? category,
    DateTime? date,
    String? notes,
    String? addedByEmail,
    List<String>? participantIds,
    SplitMode? splitMode,
    Map<String, int>? splitShares,
    String? stopId,
    String? currency,
    int? originalMinor,
    double? fxRate,
    String? receiptUrl,
  }) {
    return ExpenseItem(
      id: id ?? this.id,
      tourId: tourId ?? this.tourId,
      title: title ?? this.title,
      amountPaisa: amountPaisa ?? this.amountPaisa,
      paidById: paidById ?? this.paidById,
      paidByName: paidByName ?? this.paidByName,
      category: category ?? this.category,
      date: date ?? this.date,
      notes: notes ?? this.notes,
      addedByEmail: addedByEmail ?? this.addedByEmail,
      participantIds: participantIds ?? this.participantIds,
      splitMode: splitMode ?? this.splitMode,
      splitShares: splitShares ?? this.splitShares,
      stopId: stopId ?? this.stopId,
      currency: currency ?? this.currency,
      originalMinor: originalMinor ?? this.originalMinor,
      fxRate: fxRate ?? this.fxRate,
      receiptUrl: receiptUrl ?? this.receiptUrl,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tourId': tourId,
      'title': title,
      'splitMode': splitMode.name,
      if (splitShares != null)
        'splitShares': {
          for (final e in splitShares!.entries) normalizeEmail(e.key): e.value,
        },
      if (stopId != null) 'stopId': stopId,
      if (currency != null) 'currency': currency,
      if (originalMinor != null) 'originalMinor': originalMinor,
      if (fxRate != null) 'fxRate': fxRate,
      if (receiptUrl != null) 'receiptUrl': receiptUrl,
      'amountPaisa': amountPaisa,
      'paidById': paidById == null ? null : normalizeEmail(paidById!),
      'paidByName': paidByName,
      'category': category,
      'date': writeDate(date),
      'notes': notes,
      'addedByEmail': normalizeEmail(addedByEmail),
      if (participantIds != null)
        'participantIds': participantIds!.map(normalizeEmail).toList(),
    };
  }

  factory ExpenseItem.fromMap(String id, Map<String, dynamic> map) {
    int parsedPaisa = 0;
    if (map['amountPaisa'] != null) {
      parsedPaisa = (map['amountPaisa'] as num).toInt();
    } else if (map['amount'] != null) {
      parsedPaisa = ((map['amount'] as num).toDouble() * 100).round();
    }

    final payer = map['paidById'] as String?;
    final participants = (map['participantIds'] as List<dynamic>?)
        ?.map((e) => normalizeEmail(e.toString()))
        .toList();

    return ExpenseItem(
      id: id,
      tourId: map['tourId'] as String? ?? '',
      title: map['title'] as String? ?? 'Expense',
      amountPaisa: parsedPaisa,
      paidById: payer == null || payer.isEmpty ? null : normalizeEmail(payer),
      paidByName: map['paidByName'] as String? ?? map['paidBy'] as String?,
      category: map['category'] as String? ?? 'Others',
      date: readDate(map['date']) ?? DateTime.now(),
      notes: map['notes'] as String?,
      addedByEmail: normalizeEmail(map['addedByEmail'] as String? ?? ''),
      participantIds: participants,
      splitMode: SplitMode.fromString(map['splitMode'] as String?),
      splitShares: (map['splitShares'] as Map?)?.map((k, v) =>
          MapEntry(normalizeEmail(k.toString()), (v as num?)?.toInt() ?? 0)),
      stopId: map['stopId'] as String?,
      currency: map['currency'] as String?,
      originalMinor: (map['originalMinor'] as num?)?.toInt(),
      fxRate: (map['fxRate'] as num?)?.toDouble(),
      receiptUrl: map['receiptUrl'] as String?,
    );
  }
}

class DepositItem {
  final String id;
  final String tourId;
  final String memberId; // Member email
  final String memberName;
  final int amountPaisa;
  final DateTime date;
  final String? notes;
  final String addedByEmail;

  const DepositItem({
    required this.id,
    required this.tourId,
    required this.memberId,
    required this.memberName,
    required this.amountPaisa,
    required this.date,
    this.notes,
    this.addedByEmail = '',
  });

  double get amountTaka => amountPaisa / 100.0;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tourId': tourId,
      'memberId': normalizeEmail(memberId),
      'memberName': memberName,
      'amountPaisa': amountPaisa,
      'date': writeDate(date),
      'notes': notes,
      'addedByEmail': normalizeEmail(addedByEmail),
    };
  }

  factory DepositItem.fromMap(String id, Map<String, dynamic> map) {
    int parsedPaisa = 0;
    if (map['amountPaisa'] != null) {
      parsedPaisa = (map['amountPaisa'] as num).toInt();
    } else if (map['amount'] != null) {
      parsedPaisa = ((map['amount'] as num).toDouble() * 100).round();
    }

    return DepositItem(
      id: id,
      tourId: map['tourId'] as String? ?? '',
      memberId: normalizeEmail(map['memberId'] as String? ?? ''),
      memberName: map['memberName'] as String? ?? 'Member',
      amountPaisa: parsedPaisa,
      date: readDate(map['date']) ?? DateTime.now(),
      notes: map['notes'] as String?,
      addedByEmail: normalizeEmail(map['addedByEmail'] as String? ?? ''),
    );
  }
}

/// Money handed over to settle up: member to member, a member paying into the
/// fund, or the fund paying a member back. A null id means the fund.
class TransferItem {
  final String id;
  final String tourId;
  final String? fromId;
  final String fromName;
  final String? toId;
  final String toName;
  final int amountPaisa;
  final DateTime date;
  final String? notes;
  final String addedByEmail;

  const TransferItem({
    required this.id,
    required this.tourId,
    this.fromId,
    required this.fromName,
    this.toId,
    required this.toName,
    required this.amountPaisa,
    required this.date,
    this.notes,
    this.addedByEmail = '',
  });

  bool get fromFund => fromId == null;
  bool get toFund => toId == null;

  Map<String, dynamic> toMap() => {
        'id': id,
        'tourId': tourId,
        'fromId': fromId == null ? null : normalizeEmail(fromId!),
        'fromName': fromName,
        'toId': toId == null ? null : normalizeEmail(toId!),
        'toName': toName,
        'amountPaisa': amountPaisa,
        'date': writeDate(date),
        'notes': notes,
        'addedByEmail': normalizeEmail(addedByEmail),
      };

  factory TransferItem.fromMap(String id, Map<String, dynamic> map) {
    String? who(Object? v) {
      final s = v as String?;
      return s == null || s.isEmpty ? null : normalizeEmail(s);
    }

    return TransferItem(
      id: id,
      tourId: map['tourId'] as String? ?? '',
      fromId: who(map['fromId']),
      fromName: map['fromName'] as String? ?? '',
      toId: who(map['toId']),
      toName: map['toName'] as String? ?? '',
      amountPaisa: (map['amountPaisa'] as num?)?.toInt() ?? 0,
      date: readDate(map['date']) ?? DateTime.now(),
      notes: map['notes'] as String?,
      addedByEmail: normalizeEmail(map['addedByEmail'] as String? ?? ''),
    );
  }
}

/// What the tour plans to spend, set by an admin: a budget per category and
/// the amount each person is asked to pay into the fund.
class FundBudget {
  const FundBudget({
    this.categoryPaisa = const {},
    this.perHeadTargetPaisa = 0,
  });

  /// Budget per expense category, in paisa.
  final Map<String, int> categoryPaisa;

  /// What each person is asked to deposit. A member travelling with three
  /// others is asked for four times this.
  final int perHeadTargetPaisa;

  int get totalPaisa => categoryPaisa.values.fold(0, (a, b) => a + b);
  bool get isEmpty => totalPaisa == 0 && perHeadTargetPaisa == 0;

  Map<String, dynamic> toMap() => {
        'categoryPaisa': categoryPaisa,
        'perHeadTargetPaisa': perHeadTargetPaisa,
      };

  factory FundBudget.fromMap(Object? value) {
    if (value is! Map) return const FundBudget();
    final cats = value['categoryPaisa'];
    return FundBudget(
      categoryPaisa: cats is Map
          ? {
              for (final e in cats.entries)
                if (e.value is num && (e.value as num) > 0)
                  e.key.toString(): (e.value as num).toInt(),
            }
          : const {},
      perHeadTargetPaisa: (value['perHeadTargetPaisa'] as num?)?.toInt() ?? 0,
    );
  }
}
