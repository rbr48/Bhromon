// Domain models for Trip Expenses and Deposits

import 'date_codec.dart';

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
  });

  double get amountTaka => amountPaisa / 100.0;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tourId': tourId,
      'title': title,
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
