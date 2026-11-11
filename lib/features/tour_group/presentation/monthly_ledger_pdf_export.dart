import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/utils/logger.dart';
import '../data/monthly_ledger_pdf.dart';
import '../domain/models/expense_models.dart';
import '../domain/models/tour_group.dart';
import '../domain/services/trip_ledger_engine.dart';
import 'tour_pdf_download.dart';
import 'package:bhromon/core/theme/colors.dart';

/// Exports a circle's monthly financial statement and MFS audit log as a
/// formatted Bangla PDF using [MonthlyLedgerPdfGenerator].
Future<void> exportMonthlyLedgerPdf(
  BuildContext context, {
  required TourGroup group,
  required int year,
  required int month,
  required List<LedgerMember> members,
  required List<ExpenseItem> allExpenses,
  required List<SettlementRecord> allSettlements,
  DateTime? customStart,
  DateTime? customEnd,
  String? preparedByName,
}) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);

  messenger.showSnackBar(
    SnackBar(
      content: Text(l10n.translate('fund_exporting_pdf')),
      duration: const Duration(seconds: 2),
    ),
  );

  try {
    final statement = const TripLedgerEngine().computeMonthlyStatement(
      tourId: group.id,
      groupTitle: group.name,
      groupArchetype: group.preset ?? group.kind.name,
      year: year,
      month: month,
      members: members,
      allExpenses: allExpenses,
      allSettlements: allSettlements,
      customStart: customStart,
      customEnd: customEnd,
    );

    final generator = MonthlyLedgerPdfGenerator();
    final bytes = await generator.generate(
      statement,
      preparedByName: preparedByName ?? group.name,
    );

    final safeName = group.name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final monthStr = month.toString().padLeft(2, '0');
    final filename = customStart != null && customEnd != null
        ? '${safeName.isEmpty ? 'group' : safeName}_statement_${customStart.year}${customStart.month.toString().padLeft(2, '0')}${customStart.day.toString().padLeft(2, '0')}.pdf'
        : '${safeName.isEmpty ? 'group' : safeName}_ledger_${year}_$monthStr.pdf';

    if (kIsWeb) {
      await downloadWebFile(bytes, filename);
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
        text: customStart != null && customEnd != null
            ? '${group.name} - ${BanglaLedgerFormatter.formatShortDateBangla(customStart)} — ${BanglaLedgerFormatter.formatShortDateBangla(customEnd)} Statement'
            : '${group.name} - ${BanglaLedgerFormatter.formatMonthYearBangla(year, month)} Statement',
      ),
    );
  } catch (err, stack) {
    logError('Failed to export monthly ledger PDF: $err\n$stack');
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.translate('fund_export_pdf_error',
            args: {'error': err.toString()})),
        backgroundColor: AppColors.amber,
      ),
    );
  }
}
