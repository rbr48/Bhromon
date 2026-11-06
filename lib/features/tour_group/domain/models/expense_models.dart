// Domain models for trip expenses, deposits and settle-up payments.

import 'date_codec.dart';
import 'package:flutter/foundation.dart';

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

/// Supported Mobile Financial Services (MFS) and payment rails in Bangladesh.
enum MfsProvider {
  cash,
  bkash,
  nagad,
  rocket,
  upay,
  bankTransfer;

  static MfsProvider fromString(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'bkash':
        return MfsProvider.bkash;
      case 'nagad':
        return MfsProvider.nagad;
      case 'rocket':
        return MfsProvider.rocket;
      case 'upay':
        return MfsProvider.upay;
      case 'banktransfer':
      case 'bank_transfer':
      case 'bank':
        return MfsProvider.bankTransfer;
      case 'cash':
      default:
        return MfsProvider.cash;
    }
  }

  /// Display name in Bangla for UI badges and Bangla PDF reports.
  String get banglaLabel {
    switch (this) {
      case MfsProvider.cash:
        return 'নগদ ক্যাশ';
      case MfsProvider.bkash:
        return 'বিকাশ (bKash)';
      case MfsProvider.nagad:
        return 'নগদ (Nagad)';
      case MfsProvider.rocket:
        return 'রকেট (Rocket)';
      case MfsProvider.upay:
        return 'উপায় (Upay)';
      case MfsProvider.bankTransfer:
        return 'ব্যাংক ট্রান্সফার';
    }
  }

  /// Short English label for compact badges.
  String get shortLabel {
    switch (this) {
      case MfsProvider.cash:
        return 'Cash';
      case MfsProvider.bkash:
        return 'bKash';
      case MfsProvider.nagad:
        return 'Nagad';
      case MfsProvider.rocket:
        return 'Rocket';
      case MfsProvider.upay:
        return 'Upay';
      case MfsProvider.bankTransfer:
        return 'Bank';
    }
  }

  /// Whether this payment rail requires an alphanumeric Transaction ID (TrxID).
  bool get requiresTrxId => this != MfsProvider.cash;

  /// Default app Cash-Out fee rate (in basis points, where 185 = 1.85%) for quick fee estimation.
  int get defaultCashOutFeeBps {
    switch (this) {
      case MfsProvider.bkash:
        return 185; // 1.85% standard app cash-out
      case MfsProvider.nagad:
        return 125; // ~1.25% standard app cash-out (with VAT)
      case MfsProvider.rocket:
        return 167; // 1.67%
      case MfsProvider.upay:
        return 140; // 1.40%
      case MfsProvider.cash:
      case MfsProvider.bankTransfer:
        return 0;
    }
  }
}

/// Treasurer / group manager verification status for an MFS transaction.
enum MfsVerificationStatus {
  unverified,
  verified,
  disputed;

  static MfsVerificationStatus fromString(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'verified':
        return MfsVerificationStatus.verified;
      case 'disputed':
        return MfsVerificationStatus.disputed;
      case 'unverified':
      default:
        return MfsVerificationStatus.unverified;
    }
  }

  String get banglaLabel {
    switch (this) {
      case MfsVerificationStatus.unverified:
        return 'অপেক্ষমাণ';
      case MfsVerificationStatus.verified:
        return 'যাচাইকৃত';
      case MfsVerificationStatus.disputed:
        return 'বিতর্কিত';
    }
  }
}

/// Structured MFS metadata attached to an [ExpenseItem] or [SettlementRecord].
@immutable
class MfsPaymentInfo {
  final MfsProvider provider;

  /// Normalized uppercase alphanumeric Transaction ID (e.g., 10-char bKash TrxID `BKL890XYZ1`).
  final String? trxId;

  /// Privacy-masked sender phone number (e.g., `017****4821`).
  final String? senderMaskedPhone;

  /// Privacy-masked receiver/merchant phone number (e.g., `018****9012`).
  final String? receiverMaskedPhone;

  /// MFS Send-Money or Cash-Out fee in integer paisa (100 paisa = 1 BDT).
  final int feePaisa;

  /// If true, the MFS fee is added to the group expense or credited to the payer.
  final bool feeAbsorbedByGroup;

  /// Verification state controlled by the group manager / mess manager / samity cashier.
  final MfsVerificationStatus status;

  /// UID or email of the manager who verified or disputed the transaction.
  final String? verifiedByUserId;
  final String? verifiedByName;
  final DateTime? verifiedAt;
  final String? disputeReason;

  const MfsPaymentInfo({
    required this.provider,
    this.trxId,
    this.senderMaskedPhone,
    this.receiverMaskedPhone,
    this.feePaisa = 0,
    this.feeAbsorbedByGroup = false,
    this.status = MfsVerificationStatus.unverified,
    this.verifiedByUserId,
    this.verifiedByName,
    this.verifiedAt,
    this.disputeReason,
  });

  /// Normalized uppercase TrxID for indexing and duplicate detection.
  String? get normalizedTrxId {
    final raw = trxId?.trim().toUpperCase();
    return (raw == null || raw.isEmpty) ? null : raw;
  }

  bool get isVerified =>
      provider == MfsProvider.cash || status == MfsVerificationStatus.verified;

  MfsPaymentInfo copyWith({
    MfsProvider? provider,
    String? trxId,
    String? senderMaskedPhone,
    String? receiverMaskedPhone,
    int? feePaisa,
    bool? feeAbsorbedByGroup,
    MfsVerificationStatus? status,
    String? verifiedByUserId,
    String? verifiedByName,
    DateTime? verifiedAt,
    String? disputeReason,
  }) {
    return MfsPaymentInfo(
      provider: provider ?? this.provider,
      trxId: trxId ?? this.trxId,
      senderMaskedPhone: senderMaskedPhone ?? this.senderMaskedPhone,
      receiverMaskedPhone: receiverMaskedPhone ?? this.receiverMaskedPhone,
      feePaisa: feePaisa ?? this.feePaisa,
      feeAbsorbedByGroup: feeAbsorbedByGroup ?? this.feeAbsorbedByGroup,
      status: status ?? this.status,
      verifiedByUserId: verifiedByUserId ?? this.verifiedByUserId,
      verifiedByName: verifiedByName ?? this.verifiedByName,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      disputeReason: disputeReason ?? this.disputeReason,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'provider': provider.name,
      if (normalizedTrxId != null) 'trxId': normalizedTrxId,
      if (senderMaskedPhone != null) 'senderMaskedPhone': senderMaskedPhone,
      if (receiverMaskedPhone != null)
        'receiverMaskedPhone': receiverMaskedPhone,
      'feePaisa': feePaisa,
      'feeAbsorbedByGroup': feeAbsorbedByGroup,
      'status': status.name,
      if (verifiedByUserId != null) 'verifiedByUserId': verifiedByUserId,
      if (verifiedByName != null) 'verifiedByName': verifiedByName,
      if (verifiedAt != null) 'verifiedAt': verifiedAt!.toIso8601String(),
      if (disputeReason != null) 'disputeReason': disputeReason,
    };
  }

  factory MfsPaymentInfo.fromMap(Map<String, dynamic> map) {
    return MfsPaymentInfo(
      provider: MfsProvider.fromString(map['provider'] as String?),
      trxId: (map['trxId'] as String?)?.trim().toUpperCase(),
      senderMaskedPhone: map['senderMaskedPhone'] as String?,
      receiverMaskedPhone: map['receiverMaskedPhone'] as String?,
      feePaisa: (map['feePaisa'] as num?)?.toInt() ?? 0,
      feeAbsorbedByGroup: map['feeAbsorbedByGroup'] as bool? ?? false,
      status: MfsVerificationStatus.fromString(map['status'] as String?),
      verifiedByUserId: map['verifiedByUserId'] as String?,
      verifiedByName: map['verifiedByName'] as String?,
      verifiedAt: map['verifiedAt'] != null
          ? DateTime.tryParse(map['verifiedAt'].toString())
          : null,
      disputeReason: map['disputeReason'] as String?,
    );
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

  /// Mobile financial services details for a bKash, Nagad, Rocket or Upay payment.
  /// Null for cash. Written only when set, so existing documents keep their shape.
  final MfsPaymentInfo? mfsInfo;

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
    this.mfsInfo,
  });

  double get amountTaka => amountPaisa / 100.0;

  /// The total the books carry, including the MFS fee when the group absorbs it.
  int get effectiveAmountPaisa {
    if (mfsInfo != null && mfsInfo!.feeAbsorbedByGroup) {
      return amountPaisa + mfsInfo!.feePaisa;
    }
    return amountPaisa;
  }

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
    MfsPaymentInfo? mfsInfo,
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
      mfsInfo: mfsInfo ?? this.mfsInfo,
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
      if (mfsInfo != null) 'mfsInfo': mfsInfo!.toMap(),
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
      final val = map['amountPaisa'];
      if (val is num) {
        parsedPaisa = val.toInt();
      } else {
        parsedPaisa = int.tryParse(val.toString()) ?? 0;
      }
    } else if (map['amount'] != null) {
      final val = map['amount'];
      if (val is num) {
        parsedPaisa = (val.toDouble() * 100).round();
      } else {
        parsedPaisa = ((double.tryParse(val.toString()) ?? 0) * 100).round();
      }
    }

    final payer = map['paidById']?.toString();
    final participants = (map['participantIds'] is Iterable)
        ? (map['participantIds'] as Iterable)
            .map((e) => normalizeEmail(e.toString()))
            .toList()
        : null;

    Map<String, int>? shares;
    if (map['splitShares'] is Map) {
      shares = {};
      (map['splitShares'] as Map).forEach((k, v) {
        final key = normalizeEmail(k.toString());
        final numVal =
            v is num ? v.toInt() : (int.tryParse(v?.toString() ?? '') ?? 0);
        shares![key] = numVal;
      });
    }

    return ExpenseItem(
      id: id,
      tourId: map['tourId']?.toString() ?? '',
      title: map['title']?.toString() ?? 'Expense',
      amountPaisa: parsedPaisa,
      paidById: payer == null || payer.isEmpty ? null : normalizeEmail(payer),
      paidByName: map['paidByName']?.toString() ?? map['paidBy']?.toString(),
      category: map['category']?.toString() ?? 'Others',
      date: readDate(map['date']) ?? DateTime.now(),
      notes: map['notes']?.toString(),
      addedByEmail: normalizeEmail(map['addedByEmail']?.toString() ?? ''),
      participantIds: participants,
      splitMode: SplitMode.fromString(map['splitMode']?.toString()),
      splitShares: shares,
      stopId: map['stopId']?.toString(),
      currency: map['currency']?.toString(),
      originalMinor: map['originalMinor'] is num
          ? (map['originalMinor'] as num).toInt()
          : (int.tryParse(map['originalMinor']?.toString() ?? '')),
      fxRate: map['fxRate'] is num
          ? (map['fxRate'] as num).toDouble()
          : (double.tryParse(map['fxRate']?.toString() ?? '')),
      receiptUrl: map['receiptUrl']?.toString(),
      mfsInfo: map['mfsInfo'] is Map
          ? MfsPaymentInfo.fromMap(
              Map<String, dynamic>.from(map['mfsInfo'] as Map))
          : null,
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
      final val = map['amountPaisa'];
      if (val is num) {
        parsedPaisa = val.toInt();
      } else {
        parsedPaisa = int.tryParse(val.toString()) ?? 0;
      }
    } else if (map['amount'] != null) {
      final val = map['amount'];
      if (val is num) {
        parsedPaisa = (val.toDouble() * 100).round();
      } else {
        parsedPaisa = ((double.tryParse(val.toString()) ?? 0) * 100).round();
      }
    }

    return DepositItem(
      id: id,
      tourId: map['tourId']?.toString() ?? '',
      memberId: normalizeEmail(map['memberId']?.toString() ?? ''),
      memberName: map['memberName']?.toString() ?? 'Member',
      amountPaisa: parsedPaisa,
      date: readDate(map['date']) ?? DateTime.now(),
      notes: map['notes']?.toString(),
      addedByEmail: normalizeEmail(map['addedByEmail']?.toString() ?? ''),
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
      final s = v?.toString();
      return s == null || s.isEmpty ? null : normalizeEmail(s);
    }

    final amtVal = map['amountPaisa'];
    final parsedAmt = amtVal is num
        ? amtVal.toInt()
        : (int.tryParse(amtVal?.toString() ?? '') ?? 0);

    return TransferItem(
      id: id,
      tourId: map['tourId']?.toString() ?? '',
      fromId: who(map['fromId']),
      fromName: map['fromName']?.toString() ?? '',
      toId: who(map['toId']),
      toName: map['toName']?.toString() ?? '',
      amountPaisa: parsedAmt,
      date: readDate(map['date']) ?? DateTime.now(),
      notes: map['notes']?.toString(),
      addedByEmail: normalizeEmail(map['addedByEmail']?.toString() ?? ''),
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

/// Persisted peer-to-peer settlement, mess deposit, or samity installment payment record.
@immutable
class SettlementRecord {
  final String id;
  final String tourId;

  /// Member who sent the money / paid the installment.
  final String fromMemberId;
  final String fromMemberName;

  /// Member or group fund manager who received the money.
  final String toMemberId;
  final String toMemberName;

  /// Principal amount settled in integer paisa (100 paisa = 1 BDT).
  final int amountPaisa;
  final DateTime date;
  final MfsPaymentInfo mfsInfo;
  final String? notes;
  final String addedByEmail;
  final String? receiptUrl;

  const SettlementRecord({
    required this.id,
    required this.tourId,
    required this.fromMemberId,
    required this.fromMemberName,
    required this.toMemberId,
    required this.toMemberName,
    required this.amountPaisa,
    required this.date,
    required this.mfsInfo,
    this.notes,
    required this.addedByEmail,
    this.receiptUrl,
  });

  /// Total credit applied to [fromMemberId] when [mfsInfo.feeAbsorbedByGroup] is enabled.
  int get creditedPaisa =>
      mfsInfo.feeAbsorbedByGroup ? amountPaisa + mfsInfo.feePaisa : amountPaisa;

  bool get isVerified => mfsInfo.isVerified;

  SettlementRecord copyWith({
    String? id,
    String? tourId,
    String? fromMemberId,
    String? fromMemberName,
    String? toMemberId,
    String? toMemberName,
    int? amountPaisa,
    DateTime? date,
    MfsPaymentInfo? mfsInfo,
    String? notes,
    String? addedByEmail,
    String? receiptUrl,
  }) {
    return SettlementRecord(
      id: id ?? this.id,
      tourId: tourId ?? this.tourId,
      fromMemberId: fromMemberId ?? this.fromMemberId,
      fromMemberName: fromMemberName ?? this.fromMemberName,
      toMemberId: toMemberId ?? this.toMemberId,
      toMemberName: toMemberName ?? this.toMemberName,
      amountPaisa: amountPaisa ?? this.amountPaisa,
      date: date ?? this.date,
      mfsInfo: mfsInfo ?? this.mfsInfo,
      notes: notes ?? this.notes,
      addedByEmail: addedByEmail ?? this.addedByEmail,
      receiptUrl: receiptUrl ?? this.receiptUrl,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tourId': tourId,
      'fromMemberId': fromMemberId,
      'fromMemberName': fromMemberName,
      'toMemberId': toMemberId,
      'toMemberName': toMemberName,
      'amountPaisa': amountPaisa,
      'date': date.toIso8601String(),
      'mfsInfo': mfsInfo.toMap(),
      if (notes != null) 'notes': notes,
      'addedByEmail': addedByEmail,
      if (receiptUrl != null) 'receiptUrl': receiptUrl,
    };
  }

  factory SettlementRecord.fromMap(Map<String, dynamic> map) {
    return SettlementRecord(
      id: map['id'] as String? ?? '',
      tourId: map['tourId'] as String? ?? '',
      fromMemberId: map['fromMemberId'] as String? ?? '',
      fromMemberName: map['fromMemberName'] as String? ?? '',
      toMemberId: map['toMemberId'] as String? ?? '',
      toMemberName: map['toMemberName'] as String? ?? '',
      amountPaisa: (map['amountPaisa'] as num?)?.toInt() ?? 0,
      date: map['date'] != null
          ? (DateTime.tryParse(map['date'].toString()) ?? DateTime.now())
          : DateTime.now(),
      mfsInfo: map['mfsInfo'] is Map<String, dynamic>
          ? MfsPaymentInfo.fromMap(map['mfsInfo'] as Map<String, dynamic>)
          : const MfsPaymentInfo(provider: MfsProvider.cash),
      notes: map['notes'] as String?,
      addedByEmail: map['addedByEmail'] as String? ?? '',
      receiptUrl: map['receiptUrl'] as String?,
    );
  }
}
