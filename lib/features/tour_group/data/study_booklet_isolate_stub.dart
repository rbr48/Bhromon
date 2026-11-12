import 'dart:typed_data';

import '../domain/services/study_booklet_pdf_generator.dart';

/// Lays [job] out on this thread. The web has no isolates, so the layout runs where it always has,
/// with a pause after each chapter so the page stays responsive.
Future<Uint8List> layoutBookletJob(
  StudyBookletJob job, {
  bool Function()? isCancelled,
  void Function(int done, int total)? onProgress,
}) =>
    StudyBookletPdfGenerator.layoutJob(
      job,
      isCancelled: isCancelled,
      onProgress: onProgress,
    );
