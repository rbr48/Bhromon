import 'package:flutter/material.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/forest_palette.dart';
import '../../../core/utils/logger.dart';
import '../data/tour_group_repository.dart';
import '../domain/models/study_models.dart';
import '../domain/models/tour_group.dart';
import '../domain/services/meal_engine.dart';
import 'mess_meal_pdf_export.dart';
import 'pages/study_pack_share.dart';
import 'samity_pdf_export.dart';

/// The samity's own statement: its schedule, payments and payouts, as the samity holds them
/// now. The group menu offers it for a samity that has been set up.
Future<void> exportSamityStatementFor(
  BuildContext context, {
  required TourGroup group,
  required TourGroupRepository repository,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final members = await repository.watchMembers(group.id).first;
    final payments = await repository.watchSamityPayments(group.id).first;
    final payouts = await repository.watchSamityPayouts(group.id).first;
    if (!context.mounted) return;
    await exportSamityPdf(
      context,
      group: group,
      members: members,
      payments: payments,
      payouts: payouts,
    );
  } catch (error, stack) {
    logError('Samity statement export failed: $error\n$stack');
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.translate('pdf_export_failed'))),
      );
    }
  }
}

/// The mess's meal sheet for the current month: its meals day by day and each member's
/// balance, worked out the same way the mess balance sheet works it out.
Future<void> exportMealSheetFor(
  BuildContext context, {
  required TourGroup group,
  required TourGroupRepository repository,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final now = DateTime.now();
  final month = DateTime(now.year, now.month);
  try {
    final members = await repository.watchMembers(group.id).first;
    final logs = await repository.watchMealsForMonth(group.id, month).first;
    final expenses = await repository.watchExpenses(group.id).first;
    final deposits = await repository.watchDeposits(group.id).first;
    final transfers = await repository.watchTransfers(group.id).first;
    final balance = calculateMessMonthlyBalance(
      month: month,
      members: members,
      logs: logs,
      expenses: expenses,
      deposits: deposits,
      transfers: transfers,
    );
    if (!context.mounted) return;
    await exportMessMealPdf(
      context,
      group: group,
      month: month,
      balance: balance,
      dailyLogs: logs,
    );
  } catch (error, stack) {
    logError('Meal sheet export failed: $error\n$stack');
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.translate('pdf_export_failed'))),
      );
    }
  }
}

/// The study pack of a listed book. A group with several listed books asks which one first.
Future<void> exportStudyPackFor(
  BuildContext context, {
  required TourGroup group,
  required TourGroupRepository repository,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final all = await repository.watchStudyBooks(group.id).first;
    final books = [
      for (final book in all)
        if (book.isListed) book,
    ];
    if (!context.mounted) return;
    if (books.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.translate('study_pack_empty'))),
      );
      return;
    }
    final book =
        books.length == 1 ? books.first : await _pickStudyBook(context, books);
    if (book == null || !context.mounted) return;
    await shareStudyPack(
      context: context,
      repository: repository,
      tourId: group.id,
      book: book,
    );
  } catch (error, stack) {
    logError('Study pack export failed: $error\n$stack');
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.translate('pdf_export_failed'))),
      );
    }
  }
}

/// A card in the middle of the screen that lists the listed books, for the user to pick one.
Future<StudyBook?> _pickStudyBook(BuildContext context, List<StudyBook> books) {
  return showDialog<StudyBook>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      backgroundColor: context.forest.dialog,
      title: Text(
        context.l10n.translate('study_pack_action'),
        style: TextStyle(color: context.forest.text),
      ),
      children: [
        for (final book in books)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, book),
            child: Text(
              book.title,
              style: TextStyle(color: context.forest.text),
            ),
          ),
      ],
    ),
  );
}
