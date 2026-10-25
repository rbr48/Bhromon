// Domain models for Trip Expenses and Deposits

class ExpenseItem {
  final String id;
  final String tourId;
  final String title;
  final int amountPaisa; // Integer paisa: 100 paisa = 1 BDT
  final String?
      paidById; // Member ID/email, or null if paid directly from the shared fund
  final String? paidByName;
  final String category; // e.g. Food, Transport, Hotel, Tickets, Miscellaneous
  final DateTime date;
  final String? notes;

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
  });

  double get amountTaka => amountPaisa / 100.0;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tourId': tourId,
      'title': title,
      'amountPaisa': amountPaisa,
      'paidById': paidById,
      'paidByName': paidByName,
      'category': category,
      'date': date.toIso8601String(),
      'notes': notes,
    };
  }

  factory ExpenseItem.fromMap(String id, Map<String, dynamic> map) {
    int parsedPaisa = 0;
    if (map['amountPaisa'] != null) {
      parsedPaisa = (map['amountPaisa'] as num).toInt();
    } else if (map['amount'] != null) {
      parsedPaisa = ((map['amount'] as num).toDouble() * 100).round();
    }

    return ExpenseItem(
      id: id,
      tourId: map['tourId'] as String? ?? '',
      title: map['title'] as String? ?? 'Expense',
      amountPaisa: parsedPaisa,
      paidById: map['paidById'] as String?,
      paidByName: map['paidByName'] as String? ?? map['paidBy'] as String?,
      category: map['category'] as String? ?? 'Others',
      date: map['date'] != null
          ? DateTime.tryParse(map['date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      notes: map['notes'] as String?,
    );
  }
}

class DepositItem {
  final String id;
  final String tourId;
  final String memberId; // Member email or unique id
  final String memberName;
  final int amountPaisa;
  final DateTime date;
  final String? notes;

  const DepositItem({
    required this.id,
    required this.tourId,
    required this.memberId,
    required this.memberName,
    required this.amountPaisa,
    required this.date,
    this.notes,
  });

  double get amountTaka => amountPaisa / 100.0;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tourId': tourId,
      'memberId': memberId,
      'memberName': memberName,
      'amountPaisa': amountPaisa,
      'date': date.toIso8601String(),
      'notes': notes,
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
      memberId: map['memberId'] as String? ?? '',
      memberName: map['memberName'] as String? ?? 'Member',
      amountPaisa: parsedPaisa,
      date: map['date'] != null
          ? DateTime.tryParse(map['date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      notes: map['notes'] as String?,
    );
  }
}
