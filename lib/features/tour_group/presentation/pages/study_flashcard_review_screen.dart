import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../../core/utils/app_logger.dart';
import '../../data/study_flashcard_store.dart';
import '../../domain/models/study_flashcard_models.dart';
import '../../data/study_activity_log.dart';
import '../../domain/services/study_flashcard_rules.dart';

/// Reviews the cards that are due. The member sees the question, shows the answer, and says whether they knew it.
/// Each answer moves the card's Leitner box and is saved before the next card is shown, so a review that is cut
/// short loses nothing it already marked.
class StudyFlashcardReviewScreen extends StatefulWidget {
  const StudyFlashcardReviewScreen({
    super.key,
    required this.cards,
    required this.store,
    this.today,
    this.activity,
  });

  /// Where each review is counted for the streak and the progress card. Null in the app; tests pass one.
  final StudyActivityLog? activity;

  /// The cards due, in the order they are shown.
  final List<StudyFlashcard> cards;

  final StudyFlashcardStore store;

  /// The day the cards are judged against. Null in the app, where it is today; tests pass one.
  final DateTime? today;

  @override
  State<StudyFlashcardReviewScreen> createState() =>
      _StudyFlashcardReviewScreenState();
}

class _StudyFlashcardReviewScreenState
    extends State<StudyFlashcardReviewScreen> {
  /// The card on screen. It also counts the cards already answered.
  int _index = 0;
  bool _shown = false;
  bool _busy = false;
  bool _failed = false;

  late final StudyActivityLog _activity = widget.activity ?? StudyActivityLog();

  StudyFlashcard get _card => widget.cards[_index];

  /// Counts the review for the day. Best effort: the review is already saved, so a failure here only logs.
  Future<void> _countReview() async {
    try {
      await _activity.recordReview(DateTime.now());
    } catch (error, stackTrace) {
      logWarning('A card review could not be counted', error, stackTrace);
    }
  }

  bool get _finished => _index >= widget.cards.length;

  Future<void> _answer({required bool recalled}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final updated = reviewCard(
      _card,
      recalled: recalled,
      today: widget.today ?? DateTime.now(),
    );
    try {
      await widget.store.putAll([updated]);
    } catch (error, stackTrace) {
      logWarning('A flashcard review could not be saved', error, stackTrace);
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
      return;
    }
    await _countReview();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _index++;
      _shown = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: Text(l10n.translate('study_flashcards_review'),
            style: TextStyle(
                color: palette.text,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
        backgroundColor: palette.card,
        foregroundColor: palette.text,
        iconTheme: IconThemeData(color: palette.text),
        elevation: 0,
      ),
      body: SafeArea(child: _finished ? _doneView() : _cardView()),
    );
  }

  Widget _doneView() {
    final l10n = context.l10n;
    final palette = context.forest;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.translate('study_flashcard_review_done', args: {
                'count': l10n.number(_index),
              }),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: palette.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.translate('study_done')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardView() {
    final l10n = context.l10n;
    final palette = context.forest;
    final card = _card;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        LinearProgressIndicator(
          value: _index / widget.cards.length,
          color: palette.accentText,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.translate('study_flashcard_review_progress', args: {
            'number': l10n.number(_index + 1),
            'total': l10n.number(widget.cards.length),
          }),
          style: TextStyle(color: palette.text54),
        ),
        const SizedBox(height: 12),
        Card(
          color: palette.card,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  card.front,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: palette.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w600),
                ),
                if (_shown) ...[
                  const Divider(height: 32),
                  Text(
                    card.back,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: palette.text, fontSize: 17),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (!_shown)
          FilledButton(
            onPressed: () => setState(() => _shown = true),
            child: Text(l10n.translate('study_flashcard_show_answer')),
          )
        else
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _answer(recalled: false),
                  child: Text(l10n.translate('study_flashcard_missed')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : () => _answer(recalled: true),
                  child: Text(l10n.translate('study_flashcard_got_it')),
                ),
              ),
            ],
          ),
        if (_failed)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              l10n.translate('study_failed'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
      ],
    );
  }
}
