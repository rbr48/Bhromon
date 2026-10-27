import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../domain/models/channel_models.dart';
import '../../domain/services/chat_markdown.dart';
import '../../domain/services/trip_ledger_engine.dart';
import '../../../../core/localization/localized_date.dart';

/// One message in a channel: its sender, quote, media, poll or expense card,
/// formatted text, reactions and time.
class ChannelMessageBubble extends StatefulWidget {
  final ChannelMessage message;
  final bool isMine;
  final bool mentionsMe;
  final String myEmail;

  /// Seat and room of the sender, already formatted. Empty when none.
  final String badge;
  final VoidCallback onLongPress;
  final ValueChanged<String> onReact;
  final ValueChanged<int> onVote;
  final ValueChanged<int> onOpenMedia;
  final VoidCallback onOpenLedger;

  const ChannelMessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.mentionsMe,
    required this.myEmail,
    required this.badge,
    required this.onLongPress,
    required this.onReact,
    required this.onVote,
    required this.onOpenMedia,
    required this.onOpenLedger,
  });

  @override
  State<ChannelMessageBubble> createState() => _ChannelMessageBubbleState();
}

class _ChannelMessageBubbleState extends State<ChannelMessageBubble> {
  /// Spoilers the reader has opened on this message.
  final Set<int> _revealed = {};

  void _toggleSpoiler(int id) {
    setState(() {
      if (!_revealed.remove(id)) _revealed.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final l10n = context.l10n;
    final own = widget.isMine;
    final isExpense = m.kind == ChannelMessageKind.expense;
    final loc = _findLocation(m, l10n);

    return Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: widget.onLongPress,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          constraints:
              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: own ? AppColors.midGreen : const Color(0xFF1E3326),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(own ? 14 : 2),
              bottomRight: Radius.circular(own ? 2 : 14),
            ),
            border: widget.mentionsMe
                ? Border.all(color: AppColors.gold, width: 1.5)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!own) _header(),
              if (m.replyTo != null) _ReplyQuote(reply: m.replyTo!),
              if (m.attachments.isNotEmpty) ...[
                _AttachmentGrid(
                  attachments: m.attachments,
                  onTap: widget.onOpenMedia,
                ),
                const SizedBox(height: 6),
              ],
              if (isExpense)
                _ExpenseCard(message: m, onOpen: widget.onOpenLedger)
              else if (m.text.isNotEmpty)
                ChannelRichText(
                  text: m.text,
                  revealed: _revealed,
                  onSpoiler: _toggleSpoiler,
                ),
              if (loc != null) ...[
                const SizedBox(height: 6),
                _LocationCard(location: loc),
              ],
              if (m.kind == ChannelMessageKind.poll) ...[
                const SizedBox(height: 8),
                _PollBlock(
                  message: m,
                  myEmail: widget.myEmail,
                  onVote: widget.onVote,
                ),
              ],
              const SizedBox(height: 4),
              _footer(l10n),
              if (m.reactions.isNotEmpty)
                _ReactionRow(
                  message: m,
                  myEmail: widget.myEmail,
                  onReact: widget.onReact,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            widget.message.senderName,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: AppColors.gold,
                fontSize: 11,
                fontWeight: FontWeight.bold),
          ),
        ),
        if (widget.badge.isNotEmpty) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.badge,
              style: const TextStyle(color: AppColors.mintGreen, fontSize: 10),
            ),
          ),
        ],
      ],
    );
  }

  Widget _footer(AppLocalizations l10n) {
    final m = widget.message;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (m.isPending) ...[
          const Icon(Icons.schedule, size: 11, color: Colors.white54),
          const SizedBox(width: 4),
        ],
        if (m.isPinned) ...[
          const Icon(Icons.push_pin, size: 11, color: AppColors.gold),
          const SizedBox(width: 4),
        ],
        if (m.editedAt != null) ...[
          Text(
            l10n.translate('chan_edited'),
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
          const SizedBox(width: 4),
        ],
        Text(
          localizedDateFormat('hh:mm a').format(m.timestamp),
          style: const TextStyle(color: Colors.white54, fontSize: 10),
        ),
      ],
    );
  }
}

class _ReplyQuote extends StatelessWidget {
  final ChannelReply reply;

  const _ReplyQuote({required this.reply});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: const BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.all(Radius.circular(6)),
        border: Border(left: BorderSide(color: AppColors.gold, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            reply.senderName,
            style: const TextStyle(
                color: AppColors.gold,
                fontSize: 11,
                fontWeight: FontWeight.bold),
          ),
          Text(
            reply.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _AttachmentGrid extends StatelessWidget {
  final List<ChannelAttachment> attachments;
  final ValueChanged<int> onTap;

  const _AttachmentGrid({required this.attachments, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final single = attachments.length == 1;
    final width = single ? 220.0 : 108.0;
    final height = single ? 170.0 : 108.0;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var i = 0; i < attachments.length; i++)
          GestureDetector(
            onTap: () => onTap(i),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: width,
                height: height,
                child: _tile(context, attachments[i]),
              ),
            ),
          ),
      ],
    );
  }

  Widget _tile(BuildContext context, ChannelAttachment attachment) {
    if (attachment.isVideo) {
      return ColoredBox(
        color: Colors.black54,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.play_circle_fill, size: 44, color: Colors.white70),
            const SizedBox(height: 4),
            Text(
              context.l10n.translate('chan_attachment_video_label'),
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      );
    }
    return Image.network(
      attachment.url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const ColoredBox(
        color: Colors.black38,
        child: Center(
          child: Icon(Icons.broken_image_outlined, color: Colors.white54),
        ),
      ),
    );
  }
}

class _ExpenseCard extends StatelessWidget {
  final ChannelMessage message;
  final VoidCallback onOpen;

  const _ExpenseCard({required this.message, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long, color: AppColors.mintGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.translate('chan_expense_card'),
                      style: const TextStyle(
                          color: AppColors.mintGreen, fontSize: 10),
                    ),
                    Text(
                      message.expenseTitle,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold),
                    ),
                    Text(
                      TripLedgerEngine.formatTaka(message.expenseAmountPaisa),
                      style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 13,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onOpen,
              child: Text(
                l10n.translate('chan_expense_view'),
                style:
                    const TextStyle(color: AppColors.mintGreen, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PollBlock extends StatelessWidget {
  final ChannelMessage message;
  final String myEmail;
  final ValueChanged<int> onVote;

  const _PollBlock({
    required this.message,
    required this.myEmail,
    required this.onVote,
  });

  @override
  Widget build(BuildContext context) {
    final counts = message.voteCounts;
    final total = counts.fold<int>(0, (sum, c) => sum + c);
    final mine = message.voteBy(myEmail);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < message.pollOptions.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              onTap: () => onVote(i),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: mine == i
                      ? AppColors.mintGreen.withValues(alpha: 0.25)
                      : Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          mine == i
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 16,
                          color: AppColors.mintGreen,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            message.pollOptions[i],
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
                          ),
                        ),
                        Text(
                          '${counts[i]}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: total == 0 ? 0 : counts[i] / total,
                      backgroundColor: Colors.white10,
                      color: AppColors.mintGreen,
                      minHeight: 4,
                    ),
                  ],
                ),
              ),
            ),
          ),
        Text(
          context.l10n.translate('chan_poll_votes', args: {'count': total}),
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ],
    );
  }
}

class _ReactionRow extends StatelessWidget {
  final ChannelMessage message;
  final String myEmail;
  final ValueChanged<String> onReact;

  const _ReactionRow({
    required this.message,
    required this.myEmail,
    required this.onReact,
  });

  @override
  Widget build(BuildContext context) {
    final mine = message.reactionBy(myEmail);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final entry in message.reactionCounts.entries)
            InkWell(
              onTap: () => onReact(entry.key),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: mine == entry.key
                      ? AppColors.mintGreen.withValues(alpha: 0.35)
                      : Colors.black26,
                  borderRadius: BorderRadius.circular(12),
                  border: mine == entry.key
                      ? Border.all(color: AppColors.mintGreen)
                      : null,
                ),
                child: Text(
                  '${entry.key} ${entry.value}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Text with the chat formatting applied: bold, italic, strike-through, code,
/// quotes, links and spoilers.
class ChannelRichText extends StatefulWidget {
  final String text;

  /// Spoiler ids the reader has opened.
  final Set<int> revealed;
  final ValueChanged<int> onSpoiler;

  const ChannelRichText({
    super.key,
    required this.text,
    required this.revealed,
    required this.onSpoiler,
  });

  @override
  State<ChannelRichText> createState() => _ChannelRichTextState();
}

class _ChannelRichTextState extends State<ChannelRichText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    // The recognizers belong to the spans built below, so the previous set is
    // released first.
    _disposeRecognizers();
    const base = TextStyle(color: Colors.white, fontSize: 14, height: 1.35);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final line in parseChatMarkdown(widget.text)) _line(line, base),
      ],
    );
  }

  Widget _line(ChatLine line, TextStyle base) {
    final text = Text.rich(
      TextSpan(children: [for (final span in line.spans) _span(span, base)]),
    );
    if (!line.quote) return text;
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.only(left: 8),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.gold, width: 3)),
      ),
      child: text,
    );
  }

  InlineSpan _span(ChatSpan span, TextStyle base) {
    var style = base.copyWith(
      fontWeight: span.bold ? FontWeight.bold : null,
      fontStyle: span.italic ? FontStyle.italic : null,
      decoration: span.strike
          ? TextDecoration.lineThrough
          : span.link != null
              ? TextDecoration.underline
              : null,
      fontFamily: span.code ? 'monospace' : null,
      backgroundColor: span.code ? Colors.black38 : null,
      color: span.link != null ? AppColors.mintGreen : null,
    );

    final spoilerId = span.spoilerId;
    if (spoilerId != null && !widget.revealed.contains(spoilerId)) {
      style = style.copyWith(
        color: Colors.transparent,
        backgroundColor: const Color(0xFF0B1410),
      );
    }

    TapGestureRecognizer? recognizer;
    final link = span.link;
    if (link != null) {
      recognizer = TapGestureRecognizer()..onTap = () => _openLink(link);
    } else if (spoilerId != null) {
      recognizer = TapGestureRecognizer()
        ..onTap = () => widget.onSpoiler(spoilerId);
    }
    if (recognizer != null) _recognizers.add(recognizer);

    return TextSpan(text: span.text, style: style, recognizer: recognizer);
  }

  void _openLink(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
  }
}

class _LocationInfo {
  final String title;
  final String url;
  const _LocationInfo({required this.title, required this.url});
}

_LocationInfo? _findLocation(ChannelMessage m, [AppLocalizations? l10n]) {
  if (m.hasLocation) {
    final title = (m.locationTitle != null && m.locationTitle!.isNotEmpty)
        ? m.locationTitle!
        : (l10n?.translate('chan_location_title') ??
            'Shared location / Meetup point');
    final url =
        'https://maps.google.com/?q=${m.locationLatitude},${m.locationLongitude}';
    return _LocationInfo(title: title, url: url);
  }
  return _findLocationFromText(m.text, l10n);
}

_LocationInfo? _findLocationFromText(String text, [AppLocalizations? l10n]) {
  // Check for markdown [Title](https://...maps...)
  final mdMatch = RegExp(
          r'\[([^\]]+)\]\((https?://(?:maps\.google\.|goo\.gl/maps|maps\.app\.goo\.gl)[^\)]+)\)',
          caseSensitive: false)
      .firstMatch(text);
  if (mdMatch != null) {
    return _LocationInfo(title: mdMatch.group(1)!, url: mdMatch.group(2)!);
  }
  // Check for plain maps URL
  final urlMatch = RegExp(
          r'(https?://(?:maps\.google\.|goo\.gl/maps|maps\.app\.goo\.gl)[^\s\)]+)',
          caseSensitive: false)
      .firstMatch(text);
  if (urlMatch != null) {
    final url = urlMatch.group(1)!;
    final prefix = text.substring(0, urlMatch.start).trim();
    String title = '';
    if (prefix.isNotEmpty) {
      final clean = prefix.replaceAll(RegExp(r'[📍:,\-\n]'), '').trim();
      if (clean.isNotEmpty && clean.length < 50) {
        title = clean;
      }
    }
    final defaultTitle = l10n?.translate('chan_location_title') ??
        'Shared location / Meetup point';
    return _LocationInfo(
        title: title.isNotEmpty ? title : defaultTitle, url: url);
  }
  return null;
}

class _LocationCard extends StatelessWidget {
  final _LocationInfo location;

  const _LocationCard({required this.location});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 2),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.mintGreen.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.mintGreen.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.location_on_rounded,
                color: AppColors.mintGreen, size: 20),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  location.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12),
                ),
                Text(
                  l10n.translate('chan_location_open_maps'),
                  style: const TextStyle(
                      color: AppColors.mintGreen,
                      fontSize: 10,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: l10n.translate('chan_location_open_maps'),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.mintGreen,
              foregroundColor: AppColors.darkGreen,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(6),
            ),
            icon: const Icon(Icons.map_rounded, size: 16),
            onPressed: () {
              final uri = Uri.tryParse(location.url);
              if (uri != null) {
                unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
              }
            },
          ),
        ],
      ),
    );
  }
}
