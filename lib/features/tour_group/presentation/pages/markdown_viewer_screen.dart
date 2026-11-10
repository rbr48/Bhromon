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

/// Fullscreen in-app reader for Markdown documents (.md, .txt, .log)
/// supporting remote URLs, local file paths, and preloaded text content.
class MarkdownViewerScreen extends StatefulWidget {
  final String title;
  final String? filePath;
  final String? fileUrl;
  final String? rawContent;
  final String? tourId;

  const MarkdownViewerScreen({
    super.key,
    required this.title,
    this.filePath,
    this.fileUrl,
    this.rawContent,
    this.tourId,
  });

  /// Helper to push the viewer onto the navigation stack.
  static Future<void> open(
    BuildContext context, {
    required String title,
    String? filePath,
    String? fileUrl,
    String? rawContent,
    String? tourId,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MarkdownViewerScreen(
          title: title,
          filePath: filePath,
          fileUrl: fileUrl,
          rawContent: rawContent,
          tourId: tourId,
        ),
      ),
    );
  }

  @override
  State<MarkdownViewerScreen> createState() => _MarkdownViewerScreenState();
}

class _MarkdownViewerScreenState extends State<MarkdownViewerScreen> {
  String? _content;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    if (widget.rawContent != null) {
      setState(() {
        _content = widget.rawContent;
        _isLoading = false;
        _errorMessage = null;
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
              _content = text;
              _isLoading = false;
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
            _content = response.data ?? '';
            _isLoading = false;
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

  Future<void> _copyContent() async {
    if (_content == null || _content!.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _content!));
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
    // ignore: deprecated_member_use
    if (widget.filePath != null && !kIsWeb) {
      // ignore: deprecated_member_use
      await Share.shareXFiles([XFile(widget.filePath!)], text: widget.title);
    } else if (widget.fileUrl != null) {
      // ignore: deprecated_member_use
      await Share.share(signedMediaUrl(widget.fileUrl!), subject: widget.title);
    } else if (_content != null) {
      // ignore: deprecated_member_use
      await Share.share(_content!, subject: widget.title);
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
    final bgColor = context.forest.surfaceFor(const Color(0xFF0F1713));

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: context.forest.surfaceFor(const Color(0xFF141E18)),
        leading: GroupBackButton(tourId: widget.tourId ?? ''),
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: AppColors.mintGreen.withValues(alpha: 0.4),
                  width: 0.8,
                ),
              ),
              child: const Text(
                'MD',
                style: TextStyle(
                  color: AppColors.mintGreen,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.title.isNotEmpty
                    ? widget.title
                    : l10n.translate('viewer_markdown_title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (_content != null && _content!.isNotEmpty) ...[
            IconButton(
              tooltip: l10n.translate('viewer_copy_content'),
              icon: const Icon(Icons.copy_rounded,
                  color: AppColors.mintGreen, size: 20),
              onPressed: _copyContent,
            ),
            IconButton(
              tooltip: l10n.translate('viewer_share'),
              icon: const Icon(Icons.share_rounded,
                  color: AppColors.mintGreen, size: 20),
              onPressed: _shareDocument,
            ),
          ],
          IconButton(
            tooltip: l10n.translate('viewer_open_external'),
            icon: const Icon(Icons.open_in_new_rounded,
                color: AppColors.mintGreen, size: 20),
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

    final content = _content ?? '';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: SelectionArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
            child: ChatRichText(
              text: content,
              baseStyle: TextStyle(
                color: context.forest.text,
                fontSize: 14.5,
                height: 1.55,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
