// lib/features/tour_group/presentation/itinerary_pdf_export.dart
//
// Exports the tour's complete itinerary, stops schedule, and route roadmap
// as a formatted, printable PDF.

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/logger.dart';
import '../data/itinerary_pdf.dart';
import '../domain/models/tour_activity_models.dart';
import '../domain/models/tour_group.dart';
import 'tour_pdf_download.dart';

Future<void> exportItineraryPdf(
  BuildContext context, {
  required TourGroup group,
  List<RouteCheckpoint> checkpoints = const [],
  String? preparedByName,
}) async {
  final messenger = ScaffoldMessenger.of(context);

  messenger.showSnackBar(
    const SnackBar(
      content: Text('ভ্রমণ পরিকল্পনা PDF তৈরি হচ্ছে...'),
      duration: Duration(seconds: 2),
    ),
  );

  try {
    final generator = ItineraryPdfGenerator();
    final bytes = await generator.generate(
      group: group,
      checkpoints: checkpoints,
      preparedByName: preparedByName,
    );

    final safeName = group.name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final filename =
        '${safeName.isEmpty ? 'tour' : safeName}_itinerary_${group.id}.pdf';

    if (kIsWeb) {
      await downloadWebFile(bytes, filename);
      messenger.showSnackBar(
        const SnackBar(
            content: Text('ভ্রমণ পরিকল্পনা PDF ডাউনলোড সম্পন্ন হয়েছে')),
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
        text: '${group.name} - ভ্রমণ পরিকল্পনা ও রোডম্যাপ',
      ),
    );
  } catch (err, st) {
    logError('Itinerary PDF export failed: $err\n$st');
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'পরিকল্পনা PDF তৈরিতে সমস্যা হয়েছে: ${err.toString().replaceAll("Exception: ", "")}',
        ),
      ),
    );
  }
}
