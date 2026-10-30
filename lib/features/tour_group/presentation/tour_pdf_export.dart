import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/localization/localized_date.dart';
import '../../../core/theme/colors.dart';
import '../../../core/utils/logger.dart';
import '../data/tour_export_collector.dart';
import '../data/tour_export_images.dart';
import '../data/tour_export_pdf.dart';
import '../data/tour_group_repository.dart';
import '../domain/models/tour_group.dart';

/// Makes the tour's whole record into one PDF and opens the share sheet with
/// it. A progress dialog stays up while the data is read and the pictures are
/// prepared, and a failure is reported in a snack bar.
Future<void> exportTourPdf(
  BuildContext context, {
  required TourGroup group,
  required TourGroupRepository repository,
}) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  final status = ValueNotifier<String>(l10n.translate('pdf_export_progress'));
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ExportProgressDialog(status: status),
  ));

  var dialogOpen = true;
  void closeDialog() {
    if (dialogOpen && navigator.canPop()) navigator.pop();
    dialogOpen = false;
  }

  try {
    final data = await TourExportCollector(repository).collect(
      group,
      onPosts: (done, total) {
        status.value = l10n.translate(
          'pdf_export_posts',
          args: {'done': l10n.number(done), 'total': l10n.number(total)},
        );
      },
    );
    final bytes = await buildTourPdf(
      data: data,
      images: TourExportImages(),
      labels: TourPdfLabels(
        text: (key, {args}) => l10n.translate(key, args: args ?? const {}),
        number: l10n.number,
        date: localizedDateFormat('d MMM y').format,
        dateTime: localizedDateFormat('d MMM y, h:mm a').format,
      ),
      onImages: (done, total) {
        status.value = l10n.translate(
          'pdf_export_images',
          args: {'done': l10n.number(done), 'total': l10n.number(total)},
        );
      },
    );
    closeDialog();
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            bytes,
            mimeType: 'application/pdf',
            name: _fileName(group),
          ),
        ],
        text: l10n.translate('pdf_export_title', args: {'name': group.name}),
      ),
    );
  } catch (error) {
    logError('Tour PDF export failed: $error');
    closeDialog();
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.translate('pdf_export_failed'))),
    );
  }
}

/// A file name that is safe on every platform. Bengali names fall back to a
/// plain "tour" name.
String _fileName(TourGroup group) {
  final safe = group.name
      .replaceAll(RegExp(r'\W+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return 'bhromon_${safe.isEmpty ? 'tour' : safe}_record.pdf';
}

class _ExportProgressDialog extends StatefulWidget {
  const _ExportProgressDialog({required this.status});

  final ValueNotifier<String> status;

  @override
  State<_ExportProgressDialog> createState() => _ExportProgressDialogState();
}

class _ExportProgressDialogState extends State<_ExportProgressDialog> {
  @override
  void dispose() {
    widget.status.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: const Color(0xFF122218),
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.mintGreen,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: widget.status,
                builder: (context, text, child) => Text(
                  text,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
