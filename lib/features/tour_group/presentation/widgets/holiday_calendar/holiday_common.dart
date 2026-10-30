import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/localization/localized_date.dart';
import '../../../../../core/theme/colors.dart';
import '../../../domain/models/holiday_models.dart';
import '../../../domain/services/holiday_calendar.dart';

/// Weekday keys, Sunday first, to match the calendar grid.
const List<String> kHolidayWeekdayKeys = [
  'hol_wd_sun',
  'hol_wd_mon',
  'hol_wd_tue',
  'hol_wd_wed',
  'hol_wd_thu',
  'hol_wd_fri',
  'hol_wd_sat',
];

const Color kHolidayCard = Color(0xFF15251B);
const Color kHolidayRed = Color(0xFFF87171);
const Color kHolidayAmber = Color(0xFFFBBF24);
const Color kHolidayBlue = Color(0xFF60A5FA);

bool holidayIsBengali(BuildContext context) =>
    context.l10n.locale.languageCode == 'bn';

/// A day and its month name, such as "14 April" or "১৪ এপ্রিল".
String holidayDateLabel(BuildContext context, DateTime date) =>
    '${context.l10n.number(date.day)} ${localizedDateFormat('MMMM').format(date)}';

/// A Bangla date, such as "17 Poush 1433" or "১৭ পৌষ ১৪৩৩".
String banglaDateLabel(BuildContext context, BanglaDate date) {
  final l10n = context.l10n;
  final name = holidayIsBengali(context) ? date.monthBn : date.monthEn;
  return '${l10n.number(date.day)} $name ${l10n.number(date.year)}';
}

/// A Hijri date, such as "1 Shawwal 1448" or "১ শাওয়াল ১৪৪৮".
String hijriDateLabel(BuildContext context, HijriDate date) {
  final l10n = context.l10n;
  final name = holidayIsBengali(context) ? date.monthBn : date.monthEn;
  return '${l10n.number(date.day)} $name ${l10n.number(date.year)}';
}

String holidayCategoryKey(HolidayCategory category) => switch (category) {
      HolidayCategory.public => 'hol_category_public',
      HolidayCategory.executive => 'hol_category_executive',
      HolidayCategory.bank => 'hol_category_bank',
    };

Color holidayCategoryColor(HolidayCategory category) => switch (category) {
      HolidayCategory.public => AppColors.mintGreen,
      HolidayCategory.executive => kHolidayAmber,
      HolidayCategory.bank => kHolidayBlue,
    };

/// Hands a generated file to the share sheet. Works on mobile and web, the
/// same way the trip ledger exports its CSV.
Future<void> shareHolidayFile({
  required Uint8List bytes,
  required String name,
  required String mimeType,
}) async {
  // ignore: deprecated_member_use
  await Share.shareXFiles(
    [XFile.fromData(bytes, mimeType: mimeType, name: name)],
    subject: name,
  );
}

/// A small pill used for categories, flags and statuses.
class HolidayChip extends StatelessWidget {
  const HolidayChip({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
