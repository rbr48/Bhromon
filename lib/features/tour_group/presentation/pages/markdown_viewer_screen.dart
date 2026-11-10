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
import '../../domain/models/study_syllabus_models.dart';
import '../../domain/services/study_tts_controller.dart';
import '../widgets/group_back_button.dart';
import '../widgets/study/study_commute_audio_bar.dart';

/// Represents a distinct section or question in a Markdown document.
class _MarkdownSection {
  final String title;
  final String cleanTitle;
  final String? topic;
  final String rawText;
  final GlobalKey key;
  final bool isQuestion;
  final SyllabusModule? module;

  _MarkdownSection({
    required this.title,
    required this.cleanTitle,
    this.topic,
    required this.rawText,
    required this.key,
    this.isQuestion = false,
    this.module,
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
  final String? subjectTitle;
  final String? chapterTitle;

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
    this.subjectTitle,
    this.chapterTitle,
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
    String? subjectTitle,
    String? chapterTitle,
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
          subjectTitle: subjectTitle,
          chapterTitle: chapterTitle,
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
  bool? _userSplitOverride;
  late final ScrollController _primaryScrollController;
  late final ScrollController _alternateScrollController;
  bool _isSyncingScroll = false;
  StudyTtsController? _ttsController;
  bool _isAudioBarVisible = false;

  List<_MarkdownSection> _primarySections = const [];
  List<_MarkdownSection> _alternateSections = const [];

  String get _currentContent => _showingAlternate
      ? (widget.alternateRawContent ?? '')
      : (_primaryContent ?? '');

  String get _currentTitle {
    final base = _showingAlternate
        ? (widget.alternateTitle ?? widget.title)
        : widget.title;
    if (widget.chapterTitle != null && widget.chapterTitle!.trim().isNotEmpty) {
      if (base.isEmpty || base == widget.chapterTitle) {
        return widget.chapterTitle!;
      }
      return '${widget.chapterTitle} · $base';
    }
    return base;
  }

  bool get _hasAlternate =>
      widget.alternateRawContent != null &&
      widget.alternateRawContent!.trim().isNotEmpty;

  bool _isSplit(BuildContext context) {
    if (!_hasAlternate) return false;
    if (_userSplitOverride != null) return _userSplitOverride!;
    return MediaQuery.sizeOf(context).width >= 720;
  }

  List<_MarkdownSection> get _sections =>
      _showingAlternate ? _alternateSections : _primarySections;

  @override
  void initState() {
    super.initState();
    _primaryScrollController = ScrollController();
    _alternateScrollController = ScrollController();

    _primaryScrollController.addListener(() {
      if (!mounted || _isSyncingScroll) return;
      if (!_isSplit(context)) return;
      if (!_primaryScrollController.hasClients ||
          !_alternateScrollController.hasClients) {
        return;
      }
      final maxP = _primaryScrollController.position.maxScrollExtent;
      final maxA = _alternateScrollController.position.maxScrollExtent;
      if (maxP <= 0 || maxA <= 0) return;
      _isSyncingScroll = true;
      final ratio = _primaryScrollController.offset / maxP;
      _alternateScrollController.jumpTo((ratio * maxA).clamp(0, maxA));
      _isSyncingScroll = false;
    });

    _alternateScrollController.addListener(() {
      if (!mounted || _isSyncingScroll) return;
      if (!_isSplit(context)) return;
      if (!_primaryScrollController.hasClients ||
          !_alternateScrollController.hasClients) {
        return;
      }
      final maxP = _primaryScrollController.position.maxScrollExtent;
      final maxA = _alternateScrollController.position.maxScrollExtent;
      if (maxP <= 0 || maxA <= 0) return;
      _isSyncingScroll = true;
      final ratio = _alternateScrollController.offset / maxA;
      _primaryScrollController.jumpTo((ratio * maxP).clamp(0, maxP));
      _isSyncingScroll = false;
    });

    _loadContent();
  }

  @override
  void dispose() {
    _ttsController?.dispose();
    _primaryScrollController.dispose();
    _alternateScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadContent() async {
    if (widget.rawContent != null) {
      setState(() {
        _primaryContent = widget.rawContent;
        _isLoading = false;
        _errorMessage = null;
        _parseAllSections();
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
              _parseAllSections();
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
            _parseAllSections();
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

  void _parseAllSections() {
    _primarySections = _parseSectionsForText(_primaryContent ?? '');
    _alternateSections =
        _parseSectionsForText(widget.alternateRawContent ?? '');
  }

  List<_MarkdownSection> _parseSectionsForText(String text) {
    if (text.isEmpty) {
      return const [];
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
      return [
        _MarkdownSection(
          title: '',
          cleanTitle: '',
          rawText: text,
          key: GlobalKey(),
          isQuestion: false,
        ),
      ];
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

      final matchSubject =
          widget.subjectTitle ?? widget.chapterTitle ?? widget.title;
      final mod = isQ
          ? StudySyllabusCatalog.identifyModule(matchSubject, sectionText)
          : null;

      String? topic;
      if (isQ) {
        final lines = sectionText.split('\n');
        for (int j = 1; j < lines.length; j++) {
          final line = lines[j].trim();
          if (line.isEmpty || line.startsWith('#')) continue;
          var cleaned = line
              .replaceAll(RegExp(r'\*\*|__|`'), '')
              .replaceAll(r'\[', '[')
              .replaceAll(r'\]', ']');
          cleaned = cleaned
              .replaceFirst(
                RegExp(
                    r'^(?:[০-৯\d]+[\.\(\)a-zA-Zক-হ]+\s*|\([০-৯\d\wক-হ]+\)\s*)'),
                '',
              )
              .trim();
          if (cleaned.length > 3) {
            topic = cleaned.length > 90
                ? '${cleaned.substring(0, 87)}...'
                : cleaned;
            break;
          }
        }
      }

      sections.add(
        _MarkdownSection(
          title: headingText,
          cleanTitle: clean,
          topic: topic,
          rawText: sectionText,
          key: GlobalKey(),
          isQuestion: isQ,
          module: mod,
        ),
      );
    }

    return sections;
  }

  int? _extractQuestionNumber(String text) {
    final match =
        RegExp(r'(?:Question|প্রশ্ন)\s*([\d০-৯]+)', caseSensitive: false)
            .firstMatch(text);
    if (match == null) return null;
    final digits = match.group(1)!;
    final normalized = digits
        .replaceAll('০', '0')
        .replaceAll('১', '1')
        .replaceAll('২', '2')
        .replaceAll('৩', '3')
        .replaceAll('৪', '4')
        .replaceAll('৫', '5')
        .replaceAll('৬', '6')
        .replaceAll('৭', '7')
        .replaceAll('৮', '8')
        .replaceAll('৯', '9');
    return int.tryParse(normalized);
  }

  void _scrollToSection(_MarkdownSection section, {required bool isSplit}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final qNum = _extractQuestionNumber(section.title);
      if (qNum != null && isSplit) {
        _isSyncingScroll = true;
        // Find in primary sections
        final pSec = _primarySections.firstWhere(
          (s) => _extractQuestionNumber(s.title) == qNum,
          orElse: () => section,
        );
        final pCtx = pSec.key.currentContext;
        if (pCtx != null) {
          Scrollable.ensureVisible(
            pCtx,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
            alignment: 0.05,
          );
        }

        // Find in alternate sections
        final aSec = _alternateSections.firstWhere(
          (s) => _extractQuestionNumber(s.title) == qNum,
          orElse: () => section,
        );
        final aCtx = aSec.key.currentContext;
        if (aCtx != null) {
          Scrollable.ensureVisible(
            aCtx,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
            alignment: 0.05,
          );
        }

        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) _isSyncingScroll = false;
        });
      } else {
        final targetCtx = section.key.currentContext;
        if (targetCtx != null) {
          Scrollable.ensureVisible(
            targetCtx,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
            alignment: 0.05,
          );
        }
      }
    });
  }

  void _openQuestionNavigator() {
    final isSplit = _isSplit(context);
    final navSections =
        (isSplit && _primarySections.isNotEmpty ? _primarySections : _sections)
            .where((s) => s.cleanTitle.isNotEmpty)
            .toList();
    if (navSections.isEmpty) return;
    final palette = context.forest;
    final modules = StudySyllabusCatalog.modulesFor(
      widget.subjectTitle ?? widget.chapterTitle ?? widget.title,
    );
    String? selectedModuleCode;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.surfaceFor(const Color(0xFF141E18)),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (bottomSheetContext) {
        final l10n = context.l10n;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filteredSections = selectedModuleCode == null
                ? navSections
                : navSections
                    .where((s) => s.module?.code == selectedModuleCode)
                    .toList();

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
                              color: palette.isDark
                                  ? Colors.white
                                  : AppColors.darkText,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Text(
                          l10n.translate('viewer_questions_count',
                              args: {'count': '${filteredSections.length}'}),
                          style: TextStyle(
                            color: palette.isDark
                                ? Colors.white70
                                : AppColors.grayText,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Syllabus Module Filter Chips (shown only when subject has syllabus modules)
                  if (modules.isNotEmpty) ...[
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(
                                l10n.translate('viewer_filter_all_modules'),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: selectedModuleCode == null
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: selectedModuleCode == null
                                      ? palette.accentText
                                      : palette.text70,
                                ),
                              ),
                              selected: selectedModuleCode == null,
                              selectedColor:
                                  palette.accentText.withValues(alpha: 0.2),
                              backgroundColor: palette.divider10,
                              side: BorderSide(
                                color: selectedModuleCode == null
                                    ? palette.accentText.withValues(alpha: 0.6)
                                    : palette.divider12,
                                width: 0.8,
                              ),
                              onSelected: (_) {
                                setSheetState(() {
                                  selectedModuleCode = null;
                                });
                              },
                            ),
                          ),
                          for (final mod in modules)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(
                                  'Module ${mod.code}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: selectedModuleCode == mod.code
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: selectedModuleCode == mod.code
                                        ? palette.accentText
                                        : palette.text70,
                                  ),
                                ),
                                selected: selectedModuleCode == mod.code,
                                selectedColor:
                                    palette.accentText.withValues(alpha: 0.2),
                                backgroundColor: palette.divider10,
                                side: BorderSide(
                                  color: selectedModuleCode == mod.code
                                      ? palette.accentText
                                          .withValues(alpha: 0.6)
                                      : palette.divider12,
                                  width: 0.8,
                                ),
                                onSelected: (selected) {
                                  setSheetState(() {
                                    selectedModuleCode =
                                        selected ? mod.code : null;
                                  });
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    Divider(height: 8, color: palette.divider12),
                  ],
                  Flexible(
                    child: filteredSections.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'No questions mapped to this module.',
                              style: TextStyle(
                                  color: palette.text54, fontSize: 13),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: filteredSections.length,
                            separatorBuilder: (_, __) => Divider(
                                height: 1,
                                indent: 56,
                                color: palette.divider10),
                            itemBuilder: (context, index) {
                              final section = filteredSections[index];
                              final isQ = section.isQuestion;
                              final mod = section.module;

                              return ListTile(
                                dense: true,
                                leading: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: isQ
                                        ? palette.accentText
                                            .withValues(alpha: 0.15)
                                        : palette.divider10,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isQ
                                          ? palette.accentText
                                              .withValues(alpha: 0.45)
                                          : palette.divider12,
                                      width: 0.8,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    isQ
                                        ? Icons.quiz_outlined
                                        : Icons.bookmark_outline_rounded,
                                    color: isQ
                                        ? palette.accentText
                                        : palette.text70,
                                    size: 18,
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    if (mod != null) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: palette.accentText
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                            color: palette.accentText
                                                .withValues(alpha: 0.4),
                                            width: 0.6,
                                          ),
                                        ),
                                        child: Text(
                                          'Mod ${mod.code}',
                                          style: TextStyle(
                                            color: palette.accentText,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    Expanded(
                                      child: Text(
                                        section.cleanTitle,
                                        style: TextStyle(
                                          color: palette.isDark
                                              ? Colors.white
                                              : AppColors.darkText,
                                          fontSize: 13.5,
                                          fontWeight: isQ
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: (section.topic?.isNotEmpty == true ||
                                        mod != null)
                                    ? Text(
                                        section.topic ?? mod!.title,
                                        style: TextStyle(
                                          color: palette.isDark
                                              ? Colors.white70
                                              : AppColors.grayText,
                                          fontSize: 11.5,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    : null,
                                onTap: () {
                                  Navigator.of(bottomSheetContext).pop();
                                  _scrollToSection(section, isSplit: isSplit);
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

  void _toggleAudioPlayer() {
    if (_isAudioBarVisible) {
      setState(() => _isAudioBarVisible = false);
      return;
    }

    _ttsController ??= StudyTtsController();
    final activeSections = _sections;
    final tracks = StudyTtsController.buildTracksFromSections([
      for (final s in activeSections)
        {'title': s.cleanTitle, 'rawText': s.rawText},
    ]);
    _ttsController!.setTracks(tracks);
    setState(() => _isAudioBarVisible = true);
    _ttsController!.play();
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
        title: LayoutBuilder(
          builder: (context, constraints) {
            final showBadge = constraints.maxWidth > 140;
            return Row(
              children: [
                if (showBadge) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                ],
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
            );
          },
        ),
        actions: [
          if (_hasAlternate) ...[
            if (MediaQuery.sizeOf(context).width >= 720 || _isSplit(context))
              IconButton(
                tooltip: _isSplit(context)
                    ? l10n.translate('viewer_single_view')
                    : l10n.translate('viewer_split_view'),
                icon: Icon(
                  _isSplit(context)
                      ? Icons.view_agenda_outlined
                      : Icons.vertical_split_rounded,
                  color: palette.accentText,
                  size: 21,
                ),
                onPressed: () {
                  setState(() {
                    _userSplitOverride = !_isSplit(context);
                  });
                },
              ),
            if (!_isSplit(context))
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _showingAlternate = !_showingAlternate;
                        if (_isAudioBarVisible && _ttsController != null) {
                          final tracks =
                              StudyTtsController.buildTracksFromSections([
                            for (final s in _sections)
                              {'title': s.cleanTitle, 'rawText': s.rawText},
                          ]);
                          _ttsController!.setTracks(tracks);
                          _ttsController!.play();
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
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
          ],
          if (hasNavSections) ...[
            IconButton(
              tooltip: l10n.translate('study_audio_listen'),
              icon: Icon(
                _isAudioBarVisible
                    ? Icons.headphones_rounded
                    : Icons.headphones_outlined,
                color: _isAudioBarVisible
                    ? AppColors.mintGreen
                    : palette.accentText,
                size: 21,
              ),
              onPressed: _toggleAudioPlayer,
            ),
            IconButton(
              tooltip: l10n.translate('viewer_question_navigator'),
              icon: Icon(Icons.format_list_bulleted_rounded,
                  color: palette.accentText, size: 21),
              onPressed: _openQuestionNavigator,
            ),
          ],
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
      body: _buildBody(_isSplit(context)),
      bottomNavigationBar: _isAudioBarVisible && _ttsController != null
          ? SafeArea(
              child: StudyCommuteAudioBar(
                controller: _ttsController!,
                onClose: () => setState(() => _isAudioBarVisible = false),
                onTrackChanged: (trackIndex) {
                  final active = _sections;
                  if (trackIndex >= 0 && trackIndex < active.length) {
                    _scrollToSection(active[trackIndex],
                        isSplit: _isSplit(context));
                  }
                },
              ),
            )
          : null,
    );
  }

  Widget _buildBody(bool isSplit) {
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

    if (isSplit && _hasAlternate) {
      return _buildSplitBody();
    }

    return _buildSingleBody();
  }

  Widget _buildSplitBody() {
    final palette = context.forest;
    final primaryBnCount =
        RegExp(r'[\u0980-\u09FF]').allMatches(_primaryContent ?? '').length;
    final primaryEnCount =
        RegExp(r'[a-zA-Z]').allMatches(_primaryContent ?? '').length;
    final primaryIsBangla = primaryBnCount > primaryEnCount;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1600),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left Column: Primary solution
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildPaneHeader(
                    primaryIsBangla
                        ? '🇧🇩 বাংলা সমাধান'
                        : '🇬🇧 English Solution',
                    widget.title,
                  ),
                  Divider(height: 1, color: palette.divider12),
                  Expanded(
                    child: SelectionArea(
                      child: SingleChildScrollView(
                        controller: _primaryScrollController,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final section in _primarySections)
                              Container(
                                key: section.key,
                                child: ChatRichText(
                                  text: section.rawText,
                                  baseStyle: TextStyle(
                                    color: palette.text,
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
                ],
              ),
            ),
            VerticalDivider(width: 1, thickness: 1, color: palette.divider12),
            // Right Column: Alternate solution
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildPaneHeader(
                    primaryIsBangla
                        ? '🇬🇧 English Solution'
                        : '🇧🇩 বাংলা সমাধান',
                    widget.alternateTitle ??
                        (primaryIsBangla ? 'English' : 'বাংলা সমাধান'),
                  ),
                  Divider(height: 1, color: palette.divider12),
                  Expanded(
                    child: SelectionArea(
                      child: SingleChildScrollView(
                        controller: _alternateScrollController,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final section in _alternateSections)
                              Container(
                                key: section.key,
                                child: ChatRichText(
                                  text: section.rawText,
                                  baseStyle: TextStyle(
                                    color: palette.text,
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaneHeader(String badge, String title) {
    final palette = context.forest;
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: palette.surfaceFor(const Color(0xFF141E18)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: palette.accentText.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: palette.accentText.withValues(alpha: 0.5),
                width: 0.8,
              ),
            ),
            child: Text(
              badge,
              style: TextStyle(
                color: palette.accentText,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.text70,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Tooltip(
            message: l10n.translate('viewer_sync_scroll'),
            child: Icon(
              Icons.sync_alt_rounded,
              size: 16,
              color: palette.accentText.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleBody() {
    final palette = context.forest;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: SelectionArea(
          child: SingleChildScrollView(
            controller: _primaryScrollController,
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
                        color: palette.text,
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
