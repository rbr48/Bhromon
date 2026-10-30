/// What kind of closing a holiday is, as the gazette lists it.
enum HolidayCategory { public, executive, bank }

/// A government, executive-order or bank holiday. A moon-dependent holiday
/// moves by the moon-sighting shift; the others stay on their date.
class Holiday {
  const Holiday({
    required this.baseDate,
    required this.nameBn,
    required this.nameEn,
    required this.category,
    required this.religion,
    required this.isMoon,
    required this.descBn,
    required this.descEn,
  });

  /// The date before any moon-sighting shift, as yyyy-MM-dd.
  final String baseDate;
  final String nameBn;
  final String nameEn;
  final HolidayCategory category;
  final String religion;
  final bool isMoon;
  final String descBn;
  final String descEn;

  String name({required bool bengali}) => bengali ? nameBn : nameEn;

  String description({required bool bengali}) => bengali ? descBn : descEn;
}

/// A holiday on a particular date, after the moon-sighting shift.
class HolidayOccurrence {
  const HolidayOccurrence({required this.date, required this.holiday});

  final DateTime date;
  final Holiday holiday;
}
