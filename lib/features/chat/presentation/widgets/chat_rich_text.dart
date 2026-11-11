import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/colors.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../tour_group/domain/services/chat_markdown.dart';
import 'chat_code_block_widget.dart';
import 'chat_svg_widget.dart';
import 'chat_table_widget.dart';
import 'ppc_chart_widget.dart';

/// A rich markdown renderer for both 1-on-1 direct chats and group channels.
///
/// Supports:
/// - Tables with responsive horizontal scrolling, headers, alignments, and zebra stripes.
/// - Multiline fenced code blocks with language indicators and copy button.
/// - Section headings (H1, H2, H3).
/// - Bullet lists, numbered lists, and task checklists ([ ] / [x]).
/// - Blockquotes with accent vertical bar.
/// - Dividers / horizontal rules.
/// - Inline styling: bold, italic, underline, strikethrough, highlight, inline code,
///   named links, bare URLs, and tap-to-reveal spoilers.
class ChatRichText extends StatefulWidget {
  final String text;
  final TextStyle? baseStyle;
  final Set<int>? revealed;
  final ValueChanged<int>? onSpoiler;
  final bool isMine;
  final String? tableTitle;
  final VoidCallback? onPinNotice;
  final VoidCallback? onImportLedger;
  final bool collapsible;
  final int collapseThreshold;
  final VoidCallback? onExpandFullScreen;

  const ChatRichText({
    super.key,
    required this.text,
    this.baseStyle,
    this.revealed,
    this.onSpoiler,
    this.isMine = false,
    this.tableTitle,
    this.onPinNotice,
    this.onImportLedger,
    this.collapsible = false,
    this.collapseThreshold = 1400,
    this.onExpandFullScreen,
  });

  @override
  State<ChatRichText> createState() => _ChatRichTextState();
}

class _ChatRichTextState extends State<ChatRichText> {
  final List<TapGestureRecognizer> _recognizers = [];
  late Set<int> _internalRevealed;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _internalRevealed =
        widget.revealed != null ? Set.from(widget.revealed!) : {};
  }

  @override
  void didUpdateWidget(covariant ChatRichText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.revealed != null) {
      _internalRevealed = widget.revealed!;
    }
  }

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

  void _handleSpoiler(int id) {
    if (widget.onSpoiler != null) {
      widget.onSpoiler!(id);
    } else {
      setState(() {
        if (!_internalRevealed.remove(id)) {
          _internalRevealed.add(id);
        }
      });
    }
  }

  void _openLink(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
    }
  }

  InlineSpan _span(ChatSpan span, TextStyle base) {
    var style = base.copyWith(
      fontWeight: span.bold ? FontWeight.bold : null,
      fontStyle: span.italic ? FontStyle.italic : null,
      decoration: TextDecoration.combine([
        if (span.strike) TextDecoration.lineThrough,
        if (span.underline || span.link != null) TextDecoration.underline,
      ]),
      fontFamily: span.code ? 'monospace' : null,
      backgroundColor: span.code
          ? Colors.black38
          : (span.highlight ? AppColors.gold.withValues(alpha: 0.35) : null),
      color: span.link != null
          ? (widget.isMine ? const Color(0xFF0D47A1) : AppColors.mintGreen)
          : null,
    );

    final spoilerId = span.spoilerId;
    final isHidden =
        spoilerId != null && !_internalRevealed.contains(spoilerId);
    if (isHidden) {
      style = style.copyWith(
        color: Colors.transparent,
        backgroundColor: context.forest.surfaceFor(const Color(0xFF0B1410)),
      );
    }

    if (span.math) {
      if (RegExp(r'[\u0980-\u09FF]').hasMatch(span.text)) {
        return TextSpan(
          text: cleanBengaliMath(span.text),
          style: base.copyWith(
            fontWeight: FontWeight.w600,
            fontFamily: 'NotoSansBengali',
            fontFamilyFallback: const ['HindSiliguri', 'Roboto', 'sans-serif'],
          ),
        );
      }
      return WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Math.tex(
              span.text,
              textStyle: base,
              onErrorFallback: (_) => Text(
                '\$${span.text}\$',
                style: base.copyWith(fontFamily: 'monospace'),
              ),
            ),
          ),
        ),
      );
    }

    TapGestureRecognizer? recognizer;
    final link = span.link;
    if (link != null) {
      recognizer = TapGestureRecognizer()..onTap = () => _openLink(link);
    } else if (spoilerId != null) {
      recognizer = TapGestureRecognizer()
        ..onTap = () => _handleSpoiler(spoilerId);
    }
    if (recognizer != null) _recognizers.add(recognizer);

    return TextSpan(text: span.text, style: style, recognizer: recognizer);
  }

  Widget _buildLine(ChatLine line, TextStyle base) {
    final textWidget = Text.rich(
      TextSpan(children: [for (final span in line.spans) _span(span, base)]),
    );
    if (!line.quote) return textWidget;
    return Container(
      margin: const EdgeInsets.only(bottom: 3, top: 1),
      padding: const EdgeInsets.only(left: 8),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.gold, width: 3)),
      ),
      child: textWidget,
    );
  }

  Widget _buildHeading(ChatHeadingBlock block, TextStyle base) {
    final double fontSize = switch (block.level) {
      1 => 18.5,
      2 => 17.0,
      3 => 15.5,
      4 => 14.5,
      5 => 13.5,
      _ => 13.0,
    };
    final headingStyle = base.copyWith(
      fontSize: fontSize,
      fontWeight: FontWeight.bold,
      height: 1.35,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 3),
      child: Text.rich(
        TextSpan(
          children: [for (final span in block.spans) _span(span, headingStyle)],
        ),
      ),
    );
  }

  Widget _buildList(ChatListBlock block, TextStyle base) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in block.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.isChecked != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 1.5, right: 6),
                      child: Icon(
                        item.isChecked!
                            ? Icons.check_box_rounded
                            : Icons.check_box_outline_blank_rounded,
                        size: 15,
                        color: item.isChecked!
                            ? AppColors.mintGreen
                            : context.forest.text54,
                      ),
                    ),
                  ] else if (item.number != null) ...[
                    SizedBox(
                      width: 22,
                      child: Text(
                        '${item.number}.',
                        style: base.copyWith(
                          fontWeight: FontWeight.bold,
                          color: context.forest.text70,
                        ),
                      ),
                    ),
                  ] else ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: 6, left: 2),
                      child: Text(
                        '•',
                        style: base.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppColors.mintGreen,
                        ),
                      ),
                    ),
                  ],
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          for (final span in item.spans) _span(span, base),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBlock(ChatBlock block, TextStyle base) {
    if (block is ChatParagraphBlock) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final line in block.lines) _buildLine(line, base),
        ],
      );
    } else if (block is ChatHeadingBlock) {
      return _buildHeading(block, base);
    } else if (block is ChatListBlock) {
      return _buildList(block, base);
    } else if (block is ChatQuoteBlock) {
      return _buildQuote(block, base);
    } else if (block is ChatTableBlock) {
      return ChatTableWidget(
        table: block,
        baseStyle: base,
        revealed: _internalRevealed,
        onSpoiler: _handleSpoiler,
        isMine: widget.isMine,
        title: widget.tableTitle,
        onPinNotice: widget.onPinNotice,
        onImportLedger: widget.onImportLedger,
      );
    } else if (block is ChatCodeBlock) {
      return ChatCodeBlockWidget(
        code: block.code,
        language: block.language,
      );
    } else if (block is ChatChartBlock) {
      return PpcChartWidget(spec: block.spec);
    } else if (block is ChatSvgBlock) {
      return ChatSvgWidget(svg: block.svg);
    } else if (block is ChatMathBlock) {
      if (RegExp(r'[\u0980-\u09FF]').hasMatch(block.latex)) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            cleanBengaliMath(block.latex),
            style: base.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              fontFamily: 'NotoSansBengali',
              fontFamilyFallback: const [
                'HindSiliguri',
                'Roboto',
                'sans-serif'
              ],
            ),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Math.tex(
            block.latex,
            mathStyle: MathStyle.display,
            textStyle: base,
            onErrorFallback: (_) => Text(
              r'$$' + block.latex + r'$$',
              style: base.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ),
      );
    } else if (block is ChatDividerBlock) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Divider(
          height: 1,
          thickness: 1,
          color: context.forest.divider12,
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildQuote(ChatQuoteBlock block, TextStyle base) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.gold, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (block.blocks.isNotEmpty)
            for (final inner in block.blocks) _buildBlock(inner, base)
          else
            for (final line in block.lines)
              Text.rich(
                TextSpan(
                  children: [for (final span in line.spans) _span(span, base)],
                ),
              ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final defaultStyle = TextStyle(
      color: context.forest.text,
      fontSize: 16,
      height: 1.4,
      letterSpacing: 0.05,
      fontFamily: 'NotoSansBengali',
      fontFamilyFallback: const ['HindSiliguri', 'Roboto', 'sans-serif'],
    );
    final base = widget.baseStyle != null
        ? defaultStyle.merge(widget.baseStyle)
        : defaultStyle;

    final blocks = parseChatBlocks(widget.text);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final block in blocks) _buildBlock(block, base),
      ],
    );

    final isLong =
        widget.collapsible && widget.text.length > widget.collapseThreshold;
    if (!isLong) return content;

    final isBn = Localizations.maybeLocaleOf(context)?.languageCode == 'bn';
    final countLabel = _formatCharCount(widget.text.length);

    if (!_expanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ShaderMask(
              shaderCallback: (Rect bounds) {
                return const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black,
                    Colors.black,
                    Color(0x33000000),
                    Colors.transparent,
                  ],
                  stops: [0.0, 0.65, 0.88, 1.0],
                ).createShader(bounds);
              },
              blendMode: BlendMode.dstIn,
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: content,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              InkWell(
                onTap: () => setState(() => _expanded = true),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.expand_more_rounded,
                        size: 18,
                        color: widget.isMine
                            ? AppColors.mintGreen
                            : AppColors.midGreen,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isBn
                            ? 'পুরো বার্তাটি পড়ুন ($countLabel অক্ষর)'
                            : 'Read more ($countLabel chars)',
                        style: TextStyle(
                          color: widget.isMine
                              ? AppColors.mintGreen
                              : AppColors.midGreen,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.onExpandFullScreen != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  icon: Icon(
                    Icons.open_in_full_rounded,
                    size: 15,
                    color: context.forest.text54,
                  ),
                  tooltip: isBn ? 'ফুলস্ক্রিন দেখুন' : 'Full screen',
                  onPressed: widget.onExpandFullScreen,
                ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        content,
        const SizedBox(height: 6),
        InkWell(
          onTap: () => setState(() => _expanded = false),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.expand_less_rounded,
                  size: 18,
                  color:
                      widget.isMine ? AppColors.mintGreen : AppColors.midGreen,
                ),
                const SizedBox(width: 4),
                Text(
                  isBn ? 'সংক্ষেপ করুন' : 'Show less',
                  style: TextStyle(
                    color: widget.isMine
                        ? AppColors.mintGreen
                        : AppColors.midGreen,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _formatCharCount(int len) {
    if (len >= 1000) {
      return '${(len / 1000).toStringAsFixed(1)}k';
    }
    return '$len';
  }
}
