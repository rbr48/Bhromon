import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/theme/forest_palette.dart';
import '../../../../../core/utils/app_logger.dart';
import '../../../data/tour_group_repository.dart';
import '../../../domain/models/study_models.dart';
import 'package:bhromon/core/theme/colors.dart';

/// The "I would read this" vote on a proposed book: how many members would read it, and a
/// button for the signed-in member to say so or take it back. Its stream is opened once, when
/// the row is first shown.
class StudyVoteRow extends StatefulWidget {
  const StudyVoteRow({
    super.key,
    required this.tourId,
    required this.bookId,
    required this.repository,
  });

  final String tourId;
  final String bookId;
  final TourGroupRepository repository;

  @override
  State<StudyVoteRow> createState() => _StudyVoteRowState();
}

class _StudyVoteRowState extends State<StudyVoteRow> {
  StudyVoteTally _tally = StudyVoteTally.none;
  bool _loaded = false;
  bool _busy = false;
  StreamSubscription<StudyVoteTally>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.repository
        .watchStudyBookVotes(widget.tourId, widget.bookId)
        .listen(
      (tally) {
        if (!mounted) return;
        setState(() {
          _tally = tally;
          _loaded = true;
        });
      },
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      await widget.repository.setStudyBookVote(
        widget.tourId,
        widget.bookId,
        voted: !_tally.mine,
      );
    } catch (error, stackTrace) {
      logWarning('A study book vote failed', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: AppColors.amber,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    return Row(
      children: [
        Expanded(
          child: Text(
            _loaded
                ? l10n.translate('study_book_vote_count',
                    args: {'count': l10n.number(_tally.count)})
                : '',
            style: TextStyle(color: palette.text70),
          ),
        ),
        TextButton.icon(
          onPressed: _loaded && !_busy ? _toggle : null,
          icon: Icon(
            _tally.mine
                ? Icons.thumb_up_alt_rounded
                : Icons.thumb_up_alt_outlined,
            size: 18,
            color: palette.accentText,
          ),
          label: Text(l10n.translate(
              _tally.mine ? 'study_book_vote_undo' : 'study_book_vote_add')),
        ),
      ],
    );
  }
}
