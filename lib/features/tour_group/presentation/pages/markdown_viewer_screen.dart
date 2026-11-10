import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/media/media_access.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../chat/presentation/widgets/chat_rich_text.dart';
import '../widgets/group_back_button.dart';

/// Represents a distinct section or question in a Markdown document.
class _MarkdownSection {
  final String title;
  final String cleanTitle;
  final String rawText;
  final GlobalKey key;
  final bool isQuestion;

  _MarkdownSection({
    required this.title,
    required this.cleanTitle,
    required this.rawText,
    required this.key,
    this.isQuestion = false,
  });
}

/// Fullscreen in-app reader for Markdown documents (.md, .txt, .log)
/// supporting remote URLs, local file paths, and preloaded text content.
/// Includes an interactive Question Navigator (Table of Contents) and
/// instant 1-tap bilingual toggling between English and Bangla solutions.
class MarkdownViewerScreen extends StatefulWidget {
  final String title;
  final String? filePath;
  final String? fileUrl;
  final String? rawContent;
  final String? tourId;
  final String? alternateRawContent;
  final String? alternateTitle;
  final String? alternateLanguageLabel;

  const MarkdownViewerScreen({
    super.key,
    required this.title,
    this.filePath,
    this.fileUrl,
    this.rawContent,
    this.tourId,
    this.alternateRawContent,
    this.alternateTitle,
    this.alternateLanguageLabel,
  });

  /// Helper to push the viewer onto the navigation stack.
  static Future<void> open(
    BuildContext context, {
    required String title,
    String? filePath,
    String? fileUrl,
    String? rawContent,
    String? tourId,
    String? alternateRawContent,
    String? alternateTitle,
    String? alternateLanguageLabel,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MarkdownViewerScreen(
          title: title,
          filePath: filePath,
          fileUrl: fileUrl,
          rawContent: rawContent,
          tourId: tourId,
          alternateRawContent: alternateRawContent,
          alternateTitle: alternateTitle,
          alternateLanguageLabel: alternateLanguageLabel,
        ),
      ),
    );
  }

  @override
  State<MarkdownViewerScreen> createState() => _MarkdownViewerScreenState();
}

class _MarkdownViewerScreenState extends State<MarkdownViewerScreen> {
  String? _primaryContent;
  bool _showingAlternate = false;
  bool _isLoading = true;
  String? _errorMessage;
  List<_MarkdownSection> _sections = const [];

  String get _currentContent => _showingAlternate
      ? (widget.alternateRawContent ?? '')
      : (_primaryContent ?? '');

  String get _currentTitle => _showingAlternate
      ? (widget.alternateTitle ?? widget.title)
      : widget.title;

  bool get _hasAlternate =>
      widget.alternateRawContent != null &&
      widget.alternateRawContent!.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    if (widget.rawContent != null) {
      setState(() {
        _primaryContent = widget.rawContent;
        _isLoading = false;
        _errorMessage = null;
        _parseSections();
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Try local file path first if available and not on web
      if (!kIsWeb && widget.filePath != null && widget.filePath!.isNotEmpty) {
        try {
          final text = await XFile(widget.filePath!).readAsString();
          if (mounted) {
            setState(() {
              _primaryContent = text;
              _isLoading = false;
              _parseSections();
            });
            return;
          }
        } catch (e) {
          logWarning(
            '[MarkdownViewer] Could not read local file, falling back to URL',
            e,
          );
        }
      }

      // 2. Fetch from remote URL
      if (widget.fileUrl != null && widget.fileUrl!.isNotEmpty) {
        final targetUrl = signedMediaUrl(widget.fileUrl!);
        final response = await Dio().get<String>(
          targetUrl,
          options: Options(responseType: ResponseType.plain),
        );
        if (mounted) {
          setState(() {
            _primaryContent = response.data ?? '';
            _isLoading = false;
            _parseSections();
          });
          return;
        }
      }

      throw Exception('No document source available to load.');
    } catch (e, st) {
      logWarning('[MarkdownViewer] Failed to load markdown content', e, st);
      if (mounted) {
        setState(() {
          _errorMessage = '$e';
          _isLoading = false;
        });
      }
    }
  }

  void _parseSections() {
    final text = _currentContent;
    if (text.isEmpty) {
      _sections = const [];
      return;
    }

    // Pattern to detect Question headings or Exam section headers:
    // ### Question 1 [Marks: 5 + 5 = 10]
    // ### প্রশ্ন ১ [মান: ১০ + ১০ = ২০]
    // ## PART A: BROAD QUESTIONS
    // ## ক বিভাগ
    // ## GROUP A
    final questionPattern = RegExp(
      r'^(#{1,3})\s+(.*?(?:Question|প্রশ্ন|PART|GROUP|বিভাগ).*?)$',
      multiLine: true,
      caseSensitive: false,
    );

    var matches = questionPattern.allMatches(text).toList();

    // If no exam questions matched, fall back to general markdown headings (## or ###)
    if (matches.isEmpty) {
      final generalPattern = RegExp(
        r'^(#{1,3})\s+(.+)$',
        multiLine: true,
      );
      final generalMatches = generalPattern.allMatches(text).toList();
      if (generalMatches.length >= 2) {
        matches = generalMatches;
      }
    }

    if (matches.isEmpty) {
      _sections = [
        _MarkdownSection(
          title: '',
          cleanTitle: '',
          rawText: text,
          key: GlobalKey(),
          isQuestion: false,
        ),
      ];
      return;
    }

    final sections = <_MarkdownSection>[];

    // Text before the first heading (preamble / exam metadata)
    final firstStart = matches.first.start;
    if (firstStart > 0) {
      final preamble = text.substring(0, firstStart).trim();
      if (preamble.isNotEmpty) {
        sections.add(
          _MarkdownSection(
            title: '',
            cleanTitle: '',
            rawText: preamble,
            key: GlobalKey(),
            isQuestion: false,
          ),
        );
      }
    }

    for (int i = 0; i < matches.length; i++) {
      final match = matches[i];
      final headingText = match.group(2)?.trim() ?? '';
      final start = match.start;
      final end = (i + 1 < matches.length) ? matches[i + 1].start : text.length;
      final sectionText = text.substring(start, end).trim();

      final isQ =
          RegExp(r'(?:Question|প্রশ্ন)\s*[\d০-৯]+', caseSensitive: false)
              .hasMatch(headingText);

      // Clean title from backslash escaped brackets like \[Marks: ...\]
      final clean = headingText
          .replaceAll(r'\[', '[')
          .replaceAll(r'\]', ']')
          .replaceAll('**', '');

      sections.add(
        _MarkdownSection(
          title: headingText,
          cleanTitle: clean,
          rawText: sectionText,
          key: GlobalKey(),
          isQuestion: isQ,
        ),
      );
    }

    _sections = sections;
  }

  void _openQuestionNavigator() {
    final navSections =
        _sections.where((s) => s.cleanTitle.isNotEmpty).toList();
    if (navSections.isEmpty) return;
    final palette = context.forest;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.surfaceFor(const Color(0xFF141E18)),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (bottomSheetContext) {
        final l10n = context.l10n;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.text54.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.format_list_bulleted_rounded,
                        color: palette.accentText, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.translate('viewer_question_navigator'),
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      l10n.translate('viewer_questions_count',
                          args: {'count': '${navSections.length}'}),
                      style: TextStyle(
                        color: palette.text54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: palette.divider12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: navSections.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, indent: 56, color: palette.divider10),
                  itemBuilder: (context, index) {
                    final section = navSections[index];
                    final isQ = section.isQuestion;

                    return ListTile(
                      dense: true,
                      leading: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: isQ
                              ? palette.accentText.withValues(alpha: 0.15)
                              : palette.divider10,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isQ
                                ? palette.accentText.withValues(alpha: 0.45)
                                : palette.divider12,
                            width: 0.8,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          isQ
                              ? Icons.quiz_outlined
                              : Icons.bookmark_outline_rounded,
                          color: isQ ? palette.accentText : palette.text70,
                          size: 18,
                        ),
                      ),
                      title: Text(
                        section.cleanTitle,
                        style: TextStyle(
                          color: isQ ? palette.text : palette.text70,
                          fontSize: 13.5,
                          fontWeight: isQ ? FontWeight.w600 : FontWeight.normal,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        Navigator.of(bottomSheetContext).pop();
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          final targetCtx = section.key.currentContext;
                          if (targetCtx != null) {
                            Scrollable.ensureVisible(
                              targetCtx,
                              duration: const Duration(milliseconds: 350),
                              curve: Curves.easeInOut,
                              alignment: 0.05,
                            );
                          }
                        });
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _targetLanguageLabel() {
    final targetText = _showingAlternate
        ? (widget.rawContent ?? _primaryContent ?? '')
        : (widget.alternateRawContent ?? '');
    final isBangla = targetText.contains('বাংলা') ||
        targetText.contains('সমাধান') ||
        RegExp(r'[\u0980-\u09FF]').hasMatch(targetText);
    return isBangla ? '🇧🇩 বাংলা' : '🇬🇧 English';
  }

  Future<void> _copyContent() async {
    final content = _currentContent;
    if (content.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: content));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.translate('viewer_copied')),
          backgroundColor: AppColors.darkGreen,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _shareDocument() async {
    final title = _currentTitle;
    final content = _currentContent;
    if (widget.filePath != null && !kIsWeb) {
      // ignore: deprecated_member_use
      await Share.shareXFiles([XFile(widget.filePath!)], text: title);
    } else if (widget.fileUrl != null && !_showingAlternate) {
      // ignore: deprecated_member_use
      await Share.share(signedMediaUrl(widget.fileUrl!), subject: title);
    } else if (content.isNotEmpty) {
      // ignore: deprecated_member_use
      await Share.share(content, subject: title);
    }
  }

  Future<void> _openExternally() async {
    try {
      if (!kIsWeb && widget.filePath != null) {
        await OpenFilex.open(widget.filePath!);
        return;
      }
      if (widget.fileUrl != null) {
        final uri = Uri.parse(signedMediaUrl(widget.fileUrl!));
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e, st) {
      logWarning('[MarkdownViewer] External launch error', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final bgColor = palette.surfaceFor(const Color(0xFF0F1713));
    final hasContent = _currentContent.isNotEmpty;
    final hasNavSections = _sections.any((s) => s.cleanTitle.isNotEmpty);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: palette.surfaceFor(const Color(0xFF141E18)),
        leading: GroupBackButton(tourId: widget.tourId ?? ''),
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: palette.accentText.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: palette.accentText.withValues(alpha: 0.5),
                  width: 0.8,
                ),
              ),
              child: Text(
                'MD',
                style: TextStyle(
                  color: palette.accentText,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _currentTitle.isNotEmpty
                    ? _currentTitle
                    : l10n.translate('viewer_markdown_title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (_hasAlternate)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _showingAlternate = !_showingAlternate;
                      _parseSections();
                    });
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: palette.accentText.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: palette.accentText.withValues(alpha: 0.5),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      _targetLanguageLabel(),
                      style: TextStyle(
                        color: palette.accentText,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (hasNavSections)
            IconButton(
              tooltip: l10n.translate('viewer_question_navigator'),
              icon: Icon(Icons.format_list_bulleted_rounded,
                  color: palette.accentText, size: 21),
              onPressed: _openQuestionNavigator,
            ),
          if (hasContent) ...[
            IconButton(
              tooltip: l10n.translate('viewer_copy_content'),
              icon:
                  Icon(Icons.copy_rounded, color: palette.accentText, size: 20),
              onPressed: _copyContent,
            ),
            IconButton(
              tooltip: l10n.translate('viewer_share'),
              icon: Icon(Icons.share_rounded,
                  color: palette.accentText, size: 20),
              onPressed: _shareDocument,
            ),
          ],
          IconButton(
            tooltip: l10n.translate('viewer_open_external'),
            icon: Icon(Icons.open_in_new_rounded,
                color: palette.accentText, size: 20),
            onPressed: _openExternally,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.mintGreen),
            const SizedBox(height: 16),
            Text(
              context.l10n.translate('viewer_loading'),
              style: TextStyle(
                color: context.forest.text54,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.redAccent, size: 48),
              const SizedBox(height: 12),
              Text(
                context.l10n.translate('viewer_load_failed',
                    args: {'error': _errorMessage!}),
                textAlign: TextAlign.center,
                style: TextStyle(color: context.forest.text70, fontSize: 13.5),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadContent,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(context.l10n.translate('viewer_retry')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.darkGreen,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: SelectionArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final section in _sections)
                  Container(
                    key: section.key,
                    child: ChatRichText(
                      text: section.rawText,
                      baseStyle: TextStyle(
                        color: context.forest.text,
                        fontSize: 14.5,
                        height: 1.55,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
