import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/forest_palette.dart';
import '../../../../core/theme/theme_context.dart';
import 'chat_code_block_widget.dart';

/// A styled responsive container for vector SVG graphics embedded in markdown.
///
/// Features:
/// - Theme-adaptive card container matching the app's study & chat design system.
/// - Top action bar with title extraction, SVG badge, view code toggle, and tap-to-expand.
/// - Pinch-to-zoom full screen interactive inspection for complex charts and diagrams.
/// - Safe error boundary fallback to monospace code viewer on malformed XML.
class ChatSvgWidget extends StatefulWidget {
  final String svg;

  const ChatSvgWidget({super.key, required this.svg});

  @override
  State<ChatSvgWidget> createState() => _ChatSvgWidgetState();
}

class _ChatSvgWidgetState extends State<ChatSvgWidget> {
  bool _showCode = false;

  /// Sanitizes raw SVG XML to guarantee valid XML tag and attribute casing
  /// (e.g. converting lowercased 'viewbox' to 'viewBox', 'lineargradient' to
  /// 'linearGradient', etc.) which strict SVG XML parsers require to render properly.
  static String sanitizeSvgXml(String raw) {
    var s = raw.trim();
    // Normalize viewBox attribute
    s = s.replaceAll(RegExp(r'\bviewbox=', caseSensitive: false), 'viewBox=');
    // Normalize gradient elements
    s = s.replaceAll(
      RegExp(r'<\s*lineargradient\b', caseSensitive: false),
      '<linearGradient',
    );
    s = s.replaceAll(
      RegExp(r'<\/\s*lineargradient>', caseSensitive: false),
      '</linearGradient>',
    );
    s = s.replaceAll(
      RegExp(r'<\s*radialgradient\b', caseSensitive: false),
      '<radialGradient',
    );
    s = s.replaceAll(
      RegExp(r'<\/\s*radialgradient>', caseSensitive: false),
      '</radialGradient>',
    );
    // Normalize clipPath elements
    s = s.replaceAll(
      RegExp(r'<\s*clippath\b', caseSensitive: false),
      '<clipPath',
    );
    s = s.replaceAll(
      RegExp(r'<\/\s*clippath>', caseSensitive: false),
      '</clipPath>',
    );
    // Normalize marker & pattern attributes
    s = s.replaceAll(
      RegExp(r'\bmarkerheight=', caseSensitive: false),
      'markerHeight=',
    );
    s = s.replaceAll(
      RegExp(r'\bmarkerwidth=', caseSensitive: false),
      'markerWidth=',
    );
    s = s.replaceAll(RegExp(r'\brefx=', caseSensitive: false), 'refX=');
    s = s.replaceAll(RegExp(r'\brefy=', caseSensitive: false), 'refY=');
    s = s.replaceAll(
      RegExp(r'\bgradientunits=', caseSensitive: false),
      'gradientUnits=',
    );
    s = s.replaceAll(
      RegExp(r'\bgradienttransform=', caseSensitive: false),
      'gradientTransform=',
    );
    s = s.replaceAll(
      RegExp(r'\bpatternunits=', caseSensitive: false),
      'patternUnits=',
    );
    s = s.replaceAll(
      RegExp(r'\bpatterncontentunits=', caseSensitive: false),
      'patternContentUnits=',
    );
    s = s.replaceAll(
      RegExp(r'\bpreserveaspectratio=', caseSensitive: false),
      'preserveAspectRatio=',
    );
    return s;
  }

  String? _extractTitle(String svg) {
    final match =
        RegExp(r'<title>(.*?)</title>', caseSensitive: false).firstMatch(svg);
    if (match != null && match.group(1) != null) {
      final title = match.group(1)!.trim();
      if (title.isNotEmpty) return title;
    }
    final textMatch = RegExp(r'<text[^>]*>(.*?)</text>', caseSensitive: false)
        .firstMatch(svg);
    if (textMatch != null && textMatch.group(1) != null) {
      final text = textMatch
          .group(1)!
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll('&amp;', '&')
          .trim();
      if (text.isNotEmpty && text.length <= 90) return text;
    }
    return null;
  }

  void _openFullscreen(BuildContext context, String title) {
    final cleanSvg = sanitizeSvgXml(widget.svg);
    HapticFeedback.selectionClick();
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final forest = ctx.forest;
        return Dialog(
          backgroundColor: forest.feedSurface,
          insetPadding: const EdgeInsets.all(12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: ctx.borderFaint),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.image_outlined,
                      size: 18,
                      color: forest.accentText,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: forest.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: forest.text70),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: InteractiveViewer(
                    maxScale: 5.0,
                    minScale: 0.5,
                    child: Center(
                      child: SvgPicture.string(
                        cleanSvg,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            ChatCodeBlockWidget(
                          code: widget.svg,
                          language: 'svg',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final forest = context.forest;
    final cleanSvg = sanitizeSvgXml(widget.svg);
    final title = _extractTitle(cleanSvg) ?? 'Vector Graphic';

    if (_showCode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChatCodeBlockWidget(
            code: widget.svg,
            language: 'svg',
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() => _showCode = false),
              icon: const Icon(Icons.visibility_outlined, size: 14),
              label: const Text('Show Diagram', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: forest.feedSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderFaint),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: forest.feedRaised,
              border: Border(bottom: BorderSide(color: context.borderFaint)),
            ),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: forest.accentText.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'SVG',
                    style: TextStyle(
                      color: forest.accentText,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: forest.text70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.fullscreen_rounded, size: 18),
                  color: forest.text54,
                  tooltip: 'Fullscreen & Zoom',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () => _openFullscreen(context, title),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.code_rounded, size: 16),
                  color: forest.text54,
                  tooltip: 'View SVG Code',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () => setState(() => _showCode = true),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () => _openFullscreen(context, title),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: 140,
                  maxHeight: 380,
                ),
                child: Center(
                  child: SvgPicture.string(
                    cleanSvg,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        ChatCodeBlockWidget(
                      code: widget.svg,
                      language: 'svg',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
