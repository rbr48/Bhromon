import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/utils/app_logger.dart';
import '../../data/study_pack_pdf.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/study_models.dart';
import '../../domain/services/study_pack_rules.dart';

/// Gathers a book's study pack from what the group shares, makes the PDF on the device, and opens the share sheet.
/// A book with nothing to put in the pack yet says so instead.
Future<void> shareStudyPack({
  required BuildContext context,
  required TourGroupRepository repository,
  required String tourId,
  required StudyBook book,
}) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final labels = StudyPackLabels(
    summaries: l10n.translate('study_pack_heading_summaries'),
    answers: l10n.translate('study_pack_heading_answers'),
    glossary: l10n.translate('study_pack_heading_glossary'),
    recaps: l10n.translate('study_pack_heading_recaps'),
    materials: l10n.translate('study_pack_heading_materials'),
    covered: l10n.translate('study_pack_covered'),
    hard: l10n.translate('study_pack_hard'),
    openQuestions: l10n.translate('study_pack_open_questions'),
    link: l10n.translate('study_pack_link'),
    footer: l10n.translate('study_pack_footer'),
  );
  messenger.showSnackBar(
    SnackBar(content: Text(l10n.translate('study_pack_building'))),
  );
  try {
    final chapters = await repository.watchStudyChapters(tourId, book.id).first;
    final revisions = await repository.loadSummaryRevisions(
      tourId,
      book.id,
      [for (final chapter in chapters) chapter.id],
    );
    final threads = await repository.watchStudyThreads(tourId, book.id).first;
    final answers =
        await repository.loadAcceptedAnswers(tourId, book.id, threads);
    final glossary = await repository.watchGlossary(tourId, book.id).first;
    final sessions = await repository.watchReadingSessions(tourId).first;
    final materials =
        await repository.watchStudyMaterials(tourId, book.id).first;

    final pack = buildStudyPack(
      book: book,
      chapters: chapters,
      revisionsByChapter: revisions,
      acceptedAnswers: answers,
      glossary: glossary,
      sessions: sessions,
      materials: materials,
    );
    if (pack.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.translate('study_pack_empty'))),
      );
      return;
    }
    final bytes = await buildStudyPackPdf(pack, labels);
    const name = 'bhromon-study-pack.pdf';
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(bytes, mimeType: 'application/pdf', name: name),
        ],
        fileNameOverrides: const [name],
      ),
    );
  } catch (error, stackTrace) {
    logWarning('The study pack could not be made', error, stackTrace);
    messenger.showSnackBar(SnackBar(
      content: Text(l10n.translate('study_pack_failed')),
      backgroundColor: Colors.redAccent,
    ));
  }
}
