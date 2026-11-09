import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/theme/forest_palette.dart';
import '../../../../../core/utils/app_logger.dart';

// The progress card: a picture of a member's streak, chapters read and cards reviewed, which the member chooses and
// shares. It is drawn on the device, the same way the scrapbook's pages are shared. It never shows a score, a private
// record or a name, and it shows only the three numbers the member keeps ticked.

/// Opens the progress card sheet. The member picks what the card shows, sees it, and shares it.
Future<void> showStudyProgressCardSheet(
  BuildContext context, {
  required String bookTitle,
  required int weeks,
  required int chaptersRead,
  required int cardsReviewed,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ProgressCardSheet(
      bookTitle: bookTitle,
      weeks: weeks,
      chaptersRead: chaptersRead,
      cardsReviewed: cardsReviewed,
    ),
  );
}

class _ProgressCardSheet extends StatefulWidget {
  const _ProgressCardSheet({
    required this.bookTitle,
    required this.weeks,
    required this.chaptersRead,
    required this.cardsReviewed,
  });

  final String bookTitle;
  final int weeks;
  final int chaptersRead;
  final int cardsReviewed;

  @override
  State<_ProgressCardSheet> createState() => _ProgressCardSheetState();
}

class _ProgressCardSheetState extends State<_ProgressCardSheet> {
  final _cardKey = GlobalKey();
  bool _showWeeks = true;
  bool _showChapters = true;
  bool _showCards = true;
  bool _sharing = false;

  /// The lines the card shows, for the choices the member has made.
  List<String> _lines(AppLocalizations l10n) => [
        if (_showWeeks)
          l10n.translate('study_card_weeks_line', args: {
            'weeks': l10n.number(widget.weeks),
          }),
        if (_showChapters)
          l10n.translate('study_card_chapters_line', args: {
            'count': l10n.number(widget.chaptersRead),
          }),
        if (_showCards)
          l10n.translate('study_card_cards_line', args: {
            'count': l10n.number(widget.cardsReviewed),
          }),
      ];

  /// Shares the card as a picture. When the picture cannot be drawn, the same words are shared as text.
  Future<void> _share() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final lines = _lines(l10n);
    setState(() => _sharing = true);
    try {
      final boundary = _cardKey.currentContext?.findRenderObject();
      if (boundary is RenderRepaintBoundary) {
        final image = await boundary.toImage(pixelRatio: 2.5);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data != null) {
          await SharePlus.instance.share(
            ShareParams(
              files: [
                XFile.fromData(
                  data.buffer.asUint8List(),
                  mimeType: 'image/png',
                  name: 'bhromon-progress.png',
                ),
              ],
              fileNameOverrides: const ['bhromon-progress.png'],
            ),
          );
          return;
        }
      }
      await SharePlus.instance.share(
        ShareParams(text: '${widget.bookTitle}\n${lines.join('\n')}'),
      );
    } catch (error, stackTrace) {
      logWarning('The progress card could not be shared', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: Colors.redAccent,
      ));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final lines = _lines(l10n);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.translate('study_card_title'),
              style: TextStyle(
                  color: palette.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 18),
            ),
            Text(
              l10n.translate('study_card_choose'),
              style: TextStyle(color: palette.text70),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _showWeeks,
              onChanged: (value) => setState(() => _showWeeks = value ?? true),
              title: Text(l10n.translate('study_card_show_streak'),
                  style: TextStyle(color: palette.text)),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _showChapters,
              onChanged: (value) =>
                  setState(() => _showChapters = value ?? true),
              title: Text(l10n.translate('study_card_show_chapters'),
                  style: TextStyle(color: palette.text)),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _showCards,
              onChanged: (value) => setState(() => _showCards = value ?? true),
              title: Text(l10n.translate('study_card_show_cards'),
                  style: TextStyle(color: palette.text)),
            ),
            const SizedBox(height: 12),
            RepaintBoundary(
              key: _cardKey,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: palette.card,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Bhromon',
                      style: TextStyle(
                          color: palette.accentText,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.bookTitle,
                      style: TextStyle(color: palette.text54, fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    for (final line in lines)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          line,
                          style: TextStyle(
                              color: palette.text,
                              fontSize: 18,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _sharing || lines.isEmpty ? null : _share,
              icon: const Icon(Icons.share_rounded),
              label: Text(l10n.translate('study_card_share')),
            ),
          ],
        ),
      ),
    );
  }
}
