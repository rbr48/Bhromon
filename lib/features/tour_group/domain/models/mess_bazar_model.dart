import 'date_codec.dart';

/// One day's bazar duty assignment in a mess tour circle.
/// Stored under `tours/{tourId}/mess_bazar_schedule/{dateKey}`.
class MessBazarSchedule {
  const MessBazarSchedule({
    required this.dateKey,
    required this.assignedEmails,
    this.assignedNames = const [],
    this.note,
    this.estimatedBudgetPaisa,
    this.isCompleted = false,
    this.actualExpensePaisa,
    this.expenseId,
    this.updatedByEmail = '',
    this.updatedAt,
  });

  /// The date of duty in yyyy-MM-dd format.
  final String dateKey;

  /// Member emails assigned for bazar duty on this day.
  final List<String> assignedEmails;

  /// Display names of assigned members.
  final List<String> assignedNames;

  /// Optional shopping list or items note (e.g. 'Fish, potatoes, lentils').
  final String? note;

  /// Estimated budget allocated for this bazar trip in integer paisa.
  final int? estimatedBudgetPaisa;

  /// Whether the assigned member has completed the bazar.
  final bool isCompleted;

  /// Total amount spent in integer paisa if booked.
  final int? actualExpensePaisa;

  /// Linked expense document ID if booked to the tour ledger.
  final String? expenseId;

  /// Email of the user who last updated the schedule.
  final String updatedByEmail;

  /// Last modification timestamp.
  final DateTime? updatedAt;

  String get id => dateKey;

  bool isAssigned(String email) =>
      assignedEmails.map(normalizeEmail).contains(normalizeEmail(email));

  MessBazarSchedule copyWith({
    String? dateKey,
    List<String>? assignedEmails,
    List<String>? assignedNames,
    String? note,
    int? estimatedBudgetPaisa,
    bool? isCompleted,
    int? actualExpensePaisa,
    String? expenseId,
    String? updatedByEmail,
    DateTime? updatedAt,
  }) {
    return MessBazarSchedule(
      dateKey: dateKey ?? this.dateKey,
      assignedEmails: assignedEmails ?? this.assignedEmails,
      assignedNames: assignedNames ?? this.assignedNames,
      note: note ?? this.note,
      estimatedBudgetPaisa: estimatedBudgetPaisa ?? this.estimatedBudgetPaisa,
      isCompleted: isCompleted ?? this.isCompleted,
      actualExpensePaisa: actualExpensePaisa ?? this.actualExpensePaisa,
      expenseId: expenseId ?? this.expenseId,
      updatedByEmail: updatedByEmail ?? this.updatedByEmail,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'dateKey': dateKey,
      'assignedEmails': assignedEmails.map(normalizeEmail).toList(),
      'assignedNames': assignedNames,
      if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
      if (estimatedBudgetPaisa != null)
        'estimatedBudgetPaisa': estimatedBudgetPaisa,
      'isCompleted': isCompleted,
      if (actualExpensePaisa != null)
        'actualExpensePaisa': actualExpensePaisa,
      if (expenseId != null && expenseId!.isNotEmpty) 'expenseId': expenseId,
      'updatedByEmail': normalizeEmail(updatedByEmail),
      if (updatedAt != null) 'updatedAt': writeDate(updatedAt!),
    };
  }

  static MessBazarSchedule? fromDoc(String dateKey, Map<String, dynamic>? data) {
    if (data == null) return null;
    final emailsRaw = data['assignedEmails'];
    final assignedEmails = emailsRaw is List
        ? emailsRaw.map((e) => normalizeEmail(e.toString())).toList()
        : <String>[];

    final namesRaw = data['assignedNames'];
    final assignedNames = namesRaw is List
        ? namesRaw.map((e) => e.toString()).toList()
        : <String>[];

    return MessBazarSchedule(
      dateKey: (data['dateKey'] as String?) ?? dateKey,
      assignedEmails: assignedEmails,
      assignedNames: assignedNames,
      note: data['note'] as String?,
      estimatedBudgetPaisa: data['estimatedBudgetPaisa'] as int?,
      isCompleted: (data['isCompleted'] as bool?) ?? false,
      actualExpensePaisa: data['actualExpensePaisa'] as int?,
      expenseId: data['expenseId'] as String?,
      updatedByEmail: normalizeEmail((data['updatedByEmail'] as String?) ?? ''),
      updatedAt: readDate(data['updatedAt']),
    );
  }
}
