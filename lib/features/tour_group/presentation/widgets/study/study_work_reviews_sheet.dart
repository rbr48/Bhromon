import 'package:flutter/material.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/theme/forest_palette.dart';
import '../../../../../core/utils/app_logger.dart';
import '../../../data/tour_group_repository.dart';
import '../../../domain/models/study_problem_models.dart';
import 'study_modal.dart';
import 'package:bhromon/core/theme/colors.dart';

/// Opens the reviews of a working for an admin, who sees who reviewed and what they said, and may take any review back.
Future<void> showStudyWorkReviewsSheet(
  BuildContext context, {
  required TourGroupRepository repository,
  required String tourId,
  required String subjectId,
  required String problemId,
  required String solverEmail,
}) {
  return showStudyModal<void>(
    context: context,
    builder: (_) => StudyWorkReviewsSheet(
      repository: repository,
      tourId: tourId,
      subjectId: subjectId,
      problemId: problemId,
      solverEmail: solverEmail,
    ),
  );
}

class StudyWorkReviewsSheet extends StatefulWidget {
  const StudyWorkReviewsSheet({
    super.key,
    required this.repository,
    required this.tourId,
    required this.subjectId,
    required this.problemId,
    required this.solverEmail,
  });

  final TourGroupRepository repository;
  final String tourId;
  final String subjectId;
  final String problemId;
  final String solverEmail;

  @override
  State<StudyWorkReviewsSheet> createState() => _StudyWorkReviewsSheetState();
}

class _StudyWorkReviewsSheetState extends State<StudyWorkReviewsSheet> {
  late Future<List<StudyWorkReview>> _reviews;

  @override
  void initState() {
    super.initState();
    _reviews = _load();
  }

  Future<List<StudyWorkReview>> _load() => widget.repository.loadWorkReviews(
        widget.tourId,
        widget.subjectId,
        widget.problemId,
        widget.solverEmail,
      );

  void _reload() {
    setState(() {
      _reviews = _load();
    });
  }

  /// Asks first, then takes the review back and shows the list again.
  Future<void> _takeBack(StudyWorkReview review) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('study_work_reviews_take_back_title')),
        content: Text(l10n.translate('study_work_reviews_take_back_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.translate('study_cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.translate('study_remove')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.repository.withdrawOtherWorkReview(
        widget.tourId,
        widget.subjectId,
        widget.problemId,
        widget.solverEmail,
        review,
      );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_work_reviews_taken_back')),
      ));
      _reload();
    } catch (error, stackTrace) {
      logWarning('A study review could not be taken back', error, stackTrace);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: AppColors.amber,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.translate('study_work_reviews_title'),
                style: TextStyle(
                    color: palette.text,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<StudyWorkReview>>(
                future: _reviews,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Text(l10n.translate('study_failed'),
                        style: TextStyle(color: palette.text70));
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final reviews = snap.data!;
                  if (reviews.isEmpty) {
                    return Text(l10n.translate('study_work_reviews_none'),
                        style: TextStyle(color: palette.text70));
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final review in reviews)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            l10n.translate(
                              review.verdict == WorkVerdict.right
                                  ? 'study_work_reviewed_right_by'
                                  : 'study_work_reviewed_gap_by',
                              args: {'email': review.reviewerEmail},
                            ),
                            style: TextStyle(color: palette.text),
                          ),
                          subtitle: review.note.isEmpty
                              ? null
                              : Text(review.note,
                                  style: TextStyle(color: palette.text70)),
                          trailing: IconButton(
                            tooltip:
                                l10n.translate('study_work_reviews_take_back'),
                            icon: const Icon(Icons.undo_rounded),
                            onPressed: () => _takeBack(review),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
