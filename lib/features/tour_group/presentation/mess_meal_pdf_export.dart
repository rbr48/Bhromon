import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/logger.dart';
import '../data/mess_meal_sheet_pdf.dart';
import '../domain/models/meal_log.dart';
import '../domain/models/tour_group.dart';
import '../domain/services/meal_engine.dart';
import 'tour_pdf_download.dart';

/// Exports a mess's 31-day meal sheet and monthly balance statement as a
/// formatted, downloadable PDF.
Future<void> exportMessMealPdf(
  BuildContext context, {
  required TourGroup group,
  required DateTime month,
  required MessMonthlyBalance balance,
  List<MealLog> dailyLogs = const [],
}) async {
  final messenger = ScaffoldMessenger.of(context);

  messenger.showSnackBar(
    const SnackBar(
      content: Text('মেস মিল শিট PDF তৈরি হচ্ছে...'),
      duration: Duration(seconds: 2),
    ),
  );

  try {
    final now = DateTime.now();
    final data = MessMealSheetData(
      group: group,
      month: month,
      balance: balance,
      dailyLogs: dailyLogs,
      generatedAt: now,
    );

    final bytes = await buildMessMealSheetPdf(data: data);
    final safeName = group.name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final filename =
        '${safeName.isEmpty ? 'mess' : safeName}_meals_${month.year}_${month.month}.pdf';

    if (kIsWeb) {
      await downloadWebFile(bytes, filename);
      messenger.showSnackBar(
        const SnackBar(content: Text('মেস মিল শিট ডাউনলোড সম্পন্ন হয়েছে')),
      );
      return;
    }

    final file = XFile.fromData(
      bytes,
      mimeType: 'application/pdf',
      name: filename,
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [file],
        fileNameOverrides: [filename],
        text:
            '${group.name} - মেস মিল হিসাব বিবরণী (${month.year}-${month.month})',
      ),
    );
  } catch (err, st) {
    logError('Mess PDF export failed: $err\n$st');
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'মেস মিল শিট তৈরিতে সমস্যা হয়েছে: ${err.toString().replaceAll("Exception: ", "")}',
        ),
      ),
    );
  }
}
