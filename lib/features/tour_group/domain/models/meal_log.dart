// One member's meals on one day of a mess, stored under
// tours/{id}/meals/{dateKey}__{email}. Breakfast, lunch and dinner are counted
// separately, and a guest adds to a count rather than to a new record.

/// The most one member can log for one meal in a day, so a guest or two fits and a
/// typo does not.
const int kMaxMealsPerSlot = 5;

class MealLog {
  const MealLog({
    required this.dateKey,
    required this.email,
    this.breakfast = 0,
    this.lunch = 0,
    this.dinner = 0,
  });

  /// The day as yyyy-MM-dd, which sorts in the same order as the date.
  final String dateKey;

  /// The member the meals belong to, in lower case.
  final String email;

  final int breakfast;
  final int lunch;
  final int dinner;

  /// The document id: the day and the member.
  String get id => '${dateKey}__$email';

  /// All the meals in the day.
  int get total => breakfast + lunch + dinner;

  MealLog copyWith({int? breakfast, int? lunch, int? dinner}) => MealLog(
        dateKey: dateKey,
        email: email,
        breakfast: breakfast ?? this.breakfast,
        lunch: lunch ?? this.lunch,
        dinner: dinner ?? this.dinner,
      );

  /// The fields a member writes. The repository adds the time it was written.
  Map<String, dynamic> toFields(String updatedByEmail) => {
        'dateKey': dateKey,
        'email': email,
        'breakfast': breakfast,
        'lunch': lunch,
        'dinner': dinner,
        'updatedByEmail': updatedByEmail,
      };

  /// Reads one stored day. Returns null when it has no day or no member, so a
  /// damaged record is skipped rather than shown. A count that is not a whole number
  /// reads as none, and a count above the limit reads as the limit.
  static MealLog? fromMap(Map<String, dynamic> data) {
    final dateKey = data['dateKey'];
    final email = data['email'];
    if (dateKey is! String || email is! String) return null;
    if (dateKey.isEmpty || email.isEmpty) return null;
    return MealLog(
      dateKey: dateKey,
      email: email,
      breakfast: _slot(data['breakfast']),
      lunch: _slot(data['lunch']),
      dinner: _slot(data['dinner']),
    );
  }

  static int _slot(Object? raw) {
    if (raw is! int || raw < 0) return 0;
    return raw > kMaxMealsPerSlot ? kMaxMealsPerSlot : raw;
  }
}
