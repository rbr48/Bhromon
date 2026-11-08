// A rotating savings group (samity). Its schedule is the tour's `samity` map: what each
// member pays every cycle, the month the first cycle falls due, the day payments are
// due, and the order members take the pot in. Each member's payment is a record under
// tours/{id}/samity_payments, and each pot handed over is a record under
// tours/{id}/samity_payouts. The app keeps the records; no money moves through it.

import 'date_codec.dart';

/// The most a member can pay in one cycle, in taka.
const int kSamityMaxContributionTaka = 1000000;

/// The most members a samity can hold. A cycle is one member's turn, so this is also
/// the most cycles.
const int kSamityMaxMembers = 200;

/// The latest day of the month a payment can fall due. Every month has the day.
const int kSamityMaxDueDay = 28;

/// The three-digit key a cycle is stored under, from its 0-based index: 0 is "000".
String samityCycleKey(int index) => index.toString().padLeft(3, '0');

/// The cycle index a stored key names, or null when the key is not three digits.
int? samityCycleIndexFromKey(Object? raw) {
  if (raw is! String || !RegExp(r'^[0-9]{3}$').hasMatch(raw)) return null;
  return int.parse(raw);
}

/// The first day of the month a yyyy-MM string names, or null when it names none.
DateTime? parseSamityMonth(String? raw) {
  if (raw == null) return null;
  final match = RegExp(r'^([0-9]{4})-(0[1-9]|1[0-2])$').firstMatch(raw);
  if (match == null) return null;
  return DateTime(int.parse(match.group(1)!), int.parse(match.group(2)!));
}

/// A month as yyyy-MM, the form it is stored in.
String samityMonthKey(DateTime month) =>
    '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';

/// The schedule of a samity, stored on the tour document under `samity`.
class SamityConfig {
  const SamityConfig({
    this.contributionTaka = 0,
    this.startMonth,
    this.dueDay = 1,
    this.payoutOrder = const [],
  });

  /// What each member pays every cycle, in whole taka. Zero until it is set up.
  final int contributionTaka;

  /// The month the first cycle falls due, as yyyy-MM. Null until it is set up.
  final String? startMonth;

  /// The day of the month payments fall due, from 1 to 28.
  final int dueDay;

  /// The members, by email, in the order they take the pot. Each takes it once, so
  /// the payout order sets both the members in the rotation and the cycles.
  final List<String> payoutOrder;

  /// The first day of the month the first cycle falls due, or null when no valid month
  /// is stored.
  DateTime? get firstMonth => parseSamityMonth(startMonth);

  /// Whether the schedule can be worked out: an amount, a first month and a member.
  bool get isSetUp =>
      contributionTaka > 0 && firstMonth != null && payoutOrder.isNotEmpty;

  /// Whether anything has been set. A circle with nothing set stores no samity map.
  bool get hasSettings =>
      contributionTaka > 0 || startMonth != null || payoutOrder.isNotEmpty;

  /// The number of cycles: one for each member in the payout order.
  int get cycleCount => payoutOrder.length;

  /// The pot a cycle pays out: everyone's contribution for it.
  int get potTaka => contributionTaka * payoutOrder.length;

  SamityConfig copyWith({
    int? contributionTaka,
    String? startMonth,
    int? dueDay,
    List<String>? payoutOrder,
  }) =>
      SamityConfig(
        contributionTaka: contributionTaka ?? this.contributionTaka,
        startMonth: startMonth ?? this.startMonth,
        dueDay: dueDay ?? this.dueDay,
        payoutOrder: payoutOrder ?? this.payoutOrder,
      );

  /// The map stored on the tour document.
  Map<String, dynamic> toMap() => {
        'contributionTaka': contributionTaka,
        'startMonth': startMonth,
        'dueDay': dueDay,
        'payoutOrder': payoutOrder,
      };

  /// Reads the stored map. A value that is not usable reads as its default, so a damaged
  /// field does not break the tour; the rules refuse such values on the way in.
  static SamityConfig fromMap(Object? raw) {
    if (raw is! Map) return const SamityConfig();
    final contribution = raw['contributionTaka'];
    final due = raw['dueDay'];
    final start = raw['startMonth'];
    final order = raw['payoutOrder'];
    final startMonth =
        start is String && parseSamityMonth(start) != null ? start : null;
    return SamityConfig(
      contributionTaka: contribution is int && contribution > 0
          ? (contribution > kSamityMaxContributionTaka
              ? kSamityMaxContributionTaka
              : contribution)
          : 0,
      startMonth: startMonth,
      dueDay: due is int && due >= 1 && due <= kSamityMaxDueDay ? due : 1,
      payoutOrder: order is List
          ? [
              for (final e in order)
                if (e is String && e.trim().isNotEmpty) normalizeEmail(e),
            ].take(kSamityMaxMembers).toList()
          : const [],
    );
  }
}

/// One member's payment for one cycle, stored under
/// tours/{id}/samity_payments/{cycleKey}__{email}. The amount is what has been paid so
/// far for that cycle, so a part payment is recorded and then topped up.
class SamityPayment {
  const SamityPayment({
    required this.cycle,
    required this.email,
    required this.amountTaka,
    this.recordedByEmail = '',
  });

  /// The 0-based cycle the payment is for.
  final int cycle;

  /// The member who paid, in lower case.
  final String email;

  /// Taka paid so far for the cycle.
  final int amountTaka;

  /// Who wrote the record: the member themselves, or an admin.
  final String recordedByEmail;

  String get cycleKey => samityCycleKey(cycle);

  /// The document id: the cycle and the member.
  String get id => paymentId(cycle, email);

  /// The document id a payment is stored under.
  static String paymentId(int cycle, String email) =>
      '${samityCycleKey(cycle)}__$email';

  /// The fields a member or admin writes. The repository adds the time it was written.
  Map<String, dynamic> toFields(String recordedBy) => {
        'cycleKey': cycleKey,
        'email': email,
        'amountTaka': amountTaka,
        'recordedByEmail': recordedBy,
      };

  /// Reads one stored payment. Returns null when it has no valid cycle, member or
  /// amount, so a damaged record is skipped rather than shown.
  static SamityPayment? fromMap(Map<String, dynamic> data) {
    final cycle = samityCycleIndexFromKey(data['cycleKey']);
    final email = data['email'];
    final amount = data['amountTaka'];
    if (cycle == null || email is! String || email.isEmpty) return null;
    if (amount is! int || amount <= 0) return null;
    final by = data['recordedByEmail'];
    return SamityPayment(
      cycle: cycle,
      email: email,
      amountTaka: amount,
      recordedByEmail: by is String ? by : '',
    );
  }
}

/// The pot for one cycle handed to its recipient, stored under
/// tours/{id}/samity_payouts/{cycleKey}. Only an owner or admin records it.
class SamityPayout {
  const SamityPayout({
    required this.cycle,
    required this.recipientEmail,
    required this.amountTaka,
    this.recordedByEmail = '',
    this.receiptUrl,
    this.isVerified = false,
    this.verifiedAt,
  });

  /// The 0-based cycle the pot belongs to.
  final int cycle;

  /// The member who received the pot.
  final String recipientEmail;

  /// Taka handed over.
  final int amountTaka;

  /// The admin who recorded the handover.
  final String recordedByEmail;

  /// Attached image URL of signed receipt or transfer screenshot.
  final String? receiptUrl;

  /// Whether the beneficiary has confirmed receipt of the pot payout.
  final bool isVerified;

  /// When the beneficiary confirmed the payout receipt.
  final DateTime? verifiedAt;

  String get cycleKey => samityCycleKey(cycle);

  /// The fields an admin writes. The repository adds the time it was written.
  Map<String, dynamic> toFields(String recordedBy) => {
        'cycleKey': cycleKey,
        'recipientEmail': recipientEmail,
        'amountTaka': amountTaka,
        'recordedByEmail': recordedBy,
        if (receiptUrl != null && receiptUrl!.isNotEmpty)
          'receiptUrl': receiptUrl,
        if (isVerified) 'isVerified': true,
        if (verifiedAt != null) 'verifiedAt': writeDate(verifiedAt!),
      };

  /// Reads one stored payout, or null when it has no valid cycle, recipient or amount.
  static SamityPayout? fromMap(Map<String, dynamic> data) {
    final cycle = samityCycleIndexFromKey(data['cycleKey']);
    final recipient = data['recipientEmail'];
    final amount = data['amountTaka'];
    if (cycle == null || recipient is! String || recipient.isEmpty) return null;
    if (amount is! int || amount <= 0) return null;
    final by = data['recordedByEmail'];
    final receipt = data['receiptUrl'] as String?;
    final isVerified = data['isVerified'] == true;
    final verifiedAt = readDate(data['verifiedAt']);
    return SamityPayout(
      cycle: cycle,
      recipientEmail: recipient,
      amountTaka: amount,
      recordedByEmail: by is String ? by : '',
      receiptUrl: receipt,
      isVerified: isVerified,
      verifiedAt: verifiedAt,
    );
  }

  SamityPayout copyWith({
    String? receiptUrl,
    bool? isVerified,
    DateTime? verifiedAt,
  }) =>
      SamityPayout(
        cycle: cycle,
        recipientEmail: recipientEmail,
        amountTaka: amountTaka,
        recordedByEmail: recordedByEmail,
        receiptUrl: receiptUrl ?? this.receiptUrl,
        isVerified: isVerified ?? this.isVerified,
        verifiedAt: verifiedAt ?? this.verifiedAt,
      );
}
