import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/forest_palette.dart';
import '../../../../core/theme/theme_context.dart';
import 'chat_code_block_widget.dart';

/// The font a diagram's labels are drawn in: the app's bundled Bengali face, so a label reads the same in Bengali
/// and in English in a note, a solution and a chat.
const kDiagramFontFamily = 'NotoSansBengali';

/// The diagram with the app's font set on its root element. SVG text inherits `font-family` from its parents, so
/// this one attribute covers every label. A diagram that names a font itself is returned unchanged, and so is a
/// string with no `<svg>` start tag.
String svgWithDiagramFont(String svg) {
  final start = RegExp(r'<svg\b([^>]*)>', caseSensitive: false).firstMatch(svg);
  if (start == null || start.group(1)!.contains('font-family')) return svg;
  final insertAt = start.start + '<svg'.length;
  return '${svg.substring(0, insertAt)} font-family="$kDiagramFontFamily"'
      '${svg.substring(insertAt)}';
}

/// The title a diagram is shown under. Its `<title>` element comes first. Without one, the title is the label that
/// is boldest and then largest, so a heading beats an axis name, and ties go to the label that comes first. Null
/// when the diagram has no words to show.
String? svgDiagramTitle(String svg) {
  final titled =
      RegExp(r'<title\b[^>]*>(.*?)</title>', caseSensitive: false, dotAll: true)
          .firstMatch(svg);
  final fromTitle = _plainLabel(titled?.group(1));
  if (fromTitle != null) return fromTitle;

  String? best;
  var bestScore = double.negativeInfinity;
  final labels =
      RegExp(r'<text\b([^>]*)>(.*?)</text>', caseSensitive: false, dotAll: true)
          .allMatches(svg);
  for (final label in labels) {
    final text = _plainLabel(label.group(2));
    if (text == null || text.length > 90) continue;
    final attributes = label.group(1)!;
    final sizeText =
        RegExp(r'font-size\s*[=:]\s*"?\s*([\d.]+)', caseSensitive: false)
            .firstMatch(attributes)
            ?.group(1);
    final size = double.tryParse(sizeText ?? '') ?? 12;
    final bold = RegExp(r'font-weight\s*[=:]\s*"?\s*(bold|[6-9]00)',
            caseSensitive: false)
        .hasMatch(attributes);
    final score = (bold ? 1000 : 0) + size;
    if (score > bestScore) {
      bestScore = score;
      best = text;
    }
  }
  return best;
}

/// The width-to-height ratio of a diagram, from its viewBox, or from its width and height when it has no usable
/// viewBox. Null when the diagram gives neither, so it is drawn in a fixed box.
double? svgAspectRatio(String svg) {
  final start = RegExp(r'<svg\b([^>]*)>', caseSensitive: false).firstMatch(svg);
  if (start == null) return null;
  final attributes = start.group(1)!;

  final viewBox =
      RegExp(r'viewBox\s*=\s*"([^"]*)"').firstMatch(attributes)?.group(1);
  if (viewBox != null) {
    final box =
        viewBox.trim().split(RegExp(r'[\s,]+')).map(double.tryParse).toList();
    if (box.length == 4 &&
        box[2] != null &&
        box[3] != null &&
        box[2]! > 0 &&
        box[3]! > 0) {
      return box[2]! / box[3]!;
    }
  }

  double? length(String name) {
    final match = RegExp('(?<![\\w-])$name\\s*=\\s*"([\\d.]+)(?:px)?"')
        .firstMatch(attributes);
    return match == null ? null : double.tryParse(match.group(1)!);
  }

  final width = length('width');
  final height = length('height');
  if (width != null && height != null && width > 0 && height > 0) {
    return width / height;
  }
  return null;
}

/// The words of a label, with its tags removed and its common entities decoded. Null when nothing is left.
String? _plainLabel(String? raw) {
  if (raw == null) return null;
  final text = raw
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&')
      .trim();
  return text.isEmpty ? null : text;
}

/// The white page a diagram is drawn on. Diagrams use black lines and grey, so on this page they keep their
/// contrast in dark mode too, as a printed figure does.
class _DiagramPaper extends StatelessWidget {
  const _DiagramPaper({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Padding(padding: const EdgeInsets.all(8), child: child),
      ),
    );
  }
}

/// A styled responsive container for vector SVG graphics embedded in markdown.
///
/// Features:
/// - Theme-adaptive card container matching the app's study & chat design system.
/// - The diagram is drawn on a white page in both themes, in the app's font.
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

  /// The diagram itself, in the app's font. A diagram that cannot be drawn is shown as its code.
  Widget _picture() {
    return SvgPicture.string(
      svgWithDiagramFont(widget.svg),
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => ChatCodeBlockWidget(
        code: widget.svg,
        language: 'svg',
      ),
    );
  }

  /// The diagram in the card: at its own proportions and no taller than 380 pixels, so the page fits the drawing
  /// instead of floating in an empty box. A diagram with no size to read keeps a fixed box.
  Widget _cardDiagram() {
    final ratio = svgAspectRatio(widget.svg);
    final fixedBox = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 140, maxHeight: 380),
      child: Center(child: _picture()),
    );
    if (ratio == null) return fixedBox;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth) return fixedBox;
        final width = constraints.maxWidth;
        final height = (width / ratio).clamp(120.0, 380.0).toDouble();
        return SizedBox(width: width, height: height, child: _picture());
      },
    );
  }

  void _openFullscreen(BuildContext context, String title) {
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
                  child: _DiagramPaper(
                    child: InteractiveViewer(
                      maxScale: 5.0,
                      minScale: 0.5,
                      child: Center(child: _picture()),
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
    final title = svgDiagramTitle(widget.svg) ?? 'Vector Graphic';

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
              child: _DiagramPaper(child: _cardDiagram()),
            ),
          ),
        ],
      ),
    );
  }
}
