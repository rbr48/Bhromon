import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/localization/localized_date.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/forest_palette.dart';
import '../../../core/utils/logger.dart';
import '../data/tour_export_collector.dart';
import '../data/tour_export_images.dart';
import '../data/tour_export_pdf.dart';
import '../data/tour_group_repository.dart';
import '../domain/models/tour_export_data.dart';
import '../domain/models/tour_group.dart';
import '../domain/services/tour_record_plan.dart';
import 'tour_pdf_download.dart';

/// Makes the group's record into one PDF. A progress dialog stays up while the data is read
/// and the pictures are prepared, and it can be cancelled. Once the record is ready, the
/// user confirms before it leaves the app. A failure is reported in a snack bar; the raw
/// error goes to the log only.
Future<void> exportTourPdf(
  BuildContext context, {
  required TourGroup group,
  required TourGroupRepository repository,
}) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  final status = ValueNotifier<String>(l10n.translate('pdf_export_progress'));
  final cancel = TourExportCancel();

  var dialogOpen = true;
  void closeDialog() {
    if (dialogOpen && navigator.canPop()) navigator.pop();
    dialogOpen = false;
  }

  void cancelExport() {
    cancel.cancel();
    closeDialog();
  }

  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ExportProgressDialog(
      status: status,
      onCancel: cancelExport,
    ),
  ));

  final images = TourExportImages();
  try {
    final data = await TourExportCollector(repository).collect(
      group,
      onComments: (done, total) {
        if (cancel.isCancelled) return;
        status.value = l10n.translate(
          'pdf_export_posts',
          args: {'done': l10n.number(done), 'total': l10n.number(total)},
        );
      },
      cancel: cancel,
    );
    if (!cancel.isCancelled) {
      status.value = l10n.translate('pdf_export_building');
    }
    final bytes = await buildTourPdf(
      data: data,
      images: images,
      labels: TourPdfLabels(
        text: (key, {args}) => l10n.translate(key, args: args ?? const {}),
        number: l10n.number,
        date: localizedDateFormat('d MMM y').format,
        dateTime: localizedDateFormat('d MMM y, h:mm a').format,
      ),
      onImages: (done, total) {
        if (cancel.isCancelled) return;
        status.value = l10n.translate(
          'pdf_export_images',
          args: {'done': l10n.number(done), 'total': l10n.number(total)},
        );
      },
      cancel: cancel,
    );
    closeDialog();
    if (!context.mounted) return;
    final confirmed = await _confirmShare(
      context,
      data: data,
      photosMissing: images.failedCount,
    );
    if (!confirmed) return;

    final fileName = recordFileName(group.name);
    if (kIsWeb) {
      await downloadWebFile(bytes, fileName);
    } else {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              bytes,
              mimeType: 'application/pdf',
              name: fileName,
            ),
          ],
          fileNameOverrides: [fileName],
          text: l10n.translate('pdf_export_title', args: {'name': group.name}),
        ),
      );
    }
  } on TourExportCancelled {
    closeDialog();
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.translate('pdf_export_cancelled'))),
      );
    }
  } catch (error, stack) {
    logError('Tour PDF export failed: $error\n$stack');
    closeDialog();
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.translate('pdf_export_failed'))),
      );
    }
  } finally {
    images.close();
  }
}

/// Asks the user to confirm before the record leaves the app, and says which parts are
/// missing from it and how many photos could not be included.
Future<bool> _confirmShare(
  BuildContext context, {
  required TourExportData data,
  required int photosMissing,
}) async {
  final l10n = context.l10n;
  final parts = [
    for (final section in TourRecordSection.values)
      if (data.incomplete.contains(section))
        l10n.translate(recordSectionKey(section)),
  ].join(', ');
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: context.forest.dialog,
      title: Text(
        l10n.translate('pdf_share_confirm_title'),
        style: TextStyle(color: context.forest.text),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.translate('pdf_share_confirm_body'),
            style: TextStyle(color: context.forest.text70),
          ),
          if (parts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              l10n.translate('pdf_incomplete_parts', args: {'parts': parts}),
              style: TextStyle(
                color: context.forest.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (photosMissing > 0) ...[
            const SizedBox(height: 8),
            Text(
              l10n.translate(
                'pdf_share_photos',
                args: {'count': l10n.number(photosMissing)},
              ),
              style: TextStyle(color: context.forest.text70),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(
            l10n.translate('tour_cancel'),
            style: TextStyle(color: context.forest.text54),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.midGreen),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l10n.translate('pdf_share_confirm_action')),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

class _ExportProgressDialog extends StatefulWidget {
  const _ExportProgressDialog({required this.status, required this.onCancel});

  final ValueNotifier<String> status;
  final VoidCallback onCancel;

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
        backgroundColor: context.forest.dialog,
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.midGreen,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: widget.status,
                builder: (context, text, child) => Text(
                  text,
                  style: TextStyle(color: context.forest.text),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: widget.onCancel,
            child: Text(
              context.l10n.translate('tour_cancel'),
              style: TextStyle(color: context.forest.text70),
            ),
          ),
        ],
      ),
    );
  }
}
