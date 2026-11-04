import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/localization/localized_date.dart';
import '../../../core/utils/logger.dart';
import '../data/samity_statement_pdf.dart';
import '../data/tour_export_pdf.dart' show TourPdfLabels;
import '../domain/models/samity_models.dart';
import '../domain/models/tour_group.dart';
import 'tour_pdf_download.dart';

/// Exports a samity's schedule, collection records and member standings as a
/// formatted PDF statement.
Future<void> exportSamityPdf(
  BuildContext context, {
  required TourGroup group,
  required List<TourMember> members,
  required List<SamityPayment> payments,
  required List<SamityPayout> payouts,
}) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);

  messenger.showSnackBar(
    SnackBar(
      content: Text(l10n.translate('samity_pdf_exporting')),
      duration: const Duration(seconds: 2),
    ),
  );

  try {
    final now = DateTime.now();
    final data = SamityStatementData(
      group: group,
      members: members,
      payments: payments,
      payouts: payouts,
      generatedAt: now,
    );

    final labels = TourPdfLabels(
      text: (key, {args}) => l10n.translate(key, args: args ?? const {}),
      number: l10n.number,
      date: localizedDateFormat('d MMM y').format,
      dateTime: localizedDateFormat('d MMM y, h:mm a').format,
    );

    final bytes = await buildSamityStatementPdf(data: data, labels: labels);
    final safeName = group.name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final filename = '${safeName.isEmpty ? 'samity' : safeName}_statement.pdf';

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
        text: '${group.name} - ${l10n.translate('samity_pdf_title')}',
      ),
    );
  } catch (err, stack) {
    logError('Failed to export samity statement PDF: $err\n$stack');
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n
            .translate('samity_save_failed', args: {'error': err.toString()})),
        backgroundColor: Colors.redAccent,
      ),
    );
  }
}
