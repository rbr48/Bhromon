import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdfx/pdfx.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/media/media_access.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../../core/utils/app_logger.dart';
import '../tour_pdf_download.dart';
import '../viewer_file_helper.dart';
import '../widgets/group_back_button.dart';

/// Fullscreen in-app viewer for PDF documents (.pdf) with pinch-to-zoom,
/// multi-page swipe navigation, jump controls, and system fallback launcher.
class PdfViewerScreen extends StatefulWidget {
  final String title;
  final String? filePath;
  final String? fileUrl;
  final Uint8List? bytes;
  final String? tourId;

  const PdfViewerScreen({
    super.key,
    required this.title,
    this.filePath,
    this.fileUrl,
    this.bytes,
    this.tourId,
  });

  /// Helper to push the PDF viewer onto the navigation stack.
  static Future<void> open(
    BuildContext context, {
    required String title,
    String? filePath,
    String? fileUrl,
    Uint8List? bytes,
    String? tourId,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PdfViewerScreen(
          title: title,
          filePath: filePath,
          fileUrl: fileUrl,
          bytes: bytes,
          tourId: tourId,
        ),
      ),
    );
  }

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  PdfControllerPinch? _pdfController;
  int _pageCount = 0;
  int _currentPage = 1;
  bool _isLoading = true;
  String? _errorMessage;
  Uint8List? _activeBytes;
  String? _activeFilePath;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  Future<void> _loadPdf() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      Future<PdfDocument> docFuture;

      if (widget.bytes != null && widget.bytes!.isNotEmpty) {
        _activeBytes = widget.bytes;
        docFuture = PdfDocument.openData(widget.bytes!);
      } else if (!kIsWeb &&
          widget.filePath != null &&
          widget.filePath!.isNotEmpty) {
        _activeFilePath = widget.filePath;
        docFuture = PdfDocument.openFile(widget.filePath!);
      } else if (widget.fileUrl != null && widget.fileUrl!.isNotEmpty) {
        final targetUrl = signedMediaUrl(widget.fileUrl!);
        final response = await Dio().get<List<int>>(
          targetUrl,
          options: Options(responseType: ResponseType.bytes),
        );
        final data = Uint8List.fromList(response.data!);
        _activeBytes = data;
        docFuture = PdfDocument.openData(data);
      } else {
        throw Exception('No valid PDF source provided.');
      }

      _pdfController = PdfControllerPinch(document: docFuture);

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e, st) {
      logWarning('[PdfViewerScreen] Failed to load PDF document', e, st);
      if (mounted) {
        setState(() {
          _errorMessage = '$e';
          _isLoading = false;
        });
      }
    }
  }

  String _safeFileName(String title,
      {String fallback = 'document', String ext = 'pdf'}) {
    final clean = title
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final base = clean.isEmpty ? fallback : clean;
    return base.toLowerCase().endsWith('.$ext') ? base : '$base.$ext';
  }

  Future<Uint8List?> _ensureBytes() async {
    if (_activeBytes != null && _activeBytes!.isNotEmpty) {
      return _activeBytes;
    }
    if (!kIsWeb && _activeFilePath != null) {
      final read = await readLocalBytes(_activeFilePath!);
      if (read != null && read.isNotEmpty) {
        _activeBytes = read;
        return read;
      }
    }
    if (widget.fileUrl != null && widget.fileUrl!.isNotEmpty) {
      try {
        final targetUrl = signedMediaUrl(widget.fileUrl!);
        final response = await Dio().get<List<int>>(
          targetUrl,
          options: Options(responseType: ResponseType.bytes),
        );
        if (response.data != null) {
          final read = Uint8List.fromList(response.data!);
          _activeBytes = read;
          return read;
        }
      } catch (e, st) {
        logWarning('[PdfViewerScreen] Failed to fetch bytes from url', e, st);
      }
    }
    return null;
  }

  Future<String?> _ensureLocalFilePath() async {
    if (kIsWeb) return null;
    if (_activeFilePath != null && fileExists(_activeFilePath!)) {
      return _activeFilePath;
    }
    final bytes = await _ensureBytes();
    if (bytes == null || bytes.isEmpty) return null;
    final name = _safeFileName(widget.title, ext: 'pdf');
    final savedPath = await saveTempBytes(bytes, name);
    if (savedPath != null) {
      _activeFilePath = savedPath;
    }
    return savedPath;
  }

  Future<void> _shareDocument() async {
    final fileName = _safeFileName(widget.title, ext: 'pdf');
    try {
      if (kIsWeb) {
        final bytes = await _ensureBytes();
        if (bytes != null) {
          try {
            await SharePlus.instance.share(
              ShareParams(
                files: [
                  XFile.fromData(
                    bytes,
                    mimeType: 'application/pdf',
                    name: fileName,
                  ),
                ],
                fileNameOverrides: [fileName],
                text: widget.title,
              ),
            );
          } catch (e) {
            // Web Share API may not support files on this browser; download as fallback
            await downloadWebFile(bytes, fileName, mimeType: 'application/pdf');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(context.l10n.translate('viewer_downloaded')),
                ),
              );
            }
          }
        } else if (widget.fileUrl != null) {
          await SharePlus.instance.share(
            ShareParams(
              text: signedMediaUrl(widget.fileUrl!),
              subject: widget.title,
            ),
          );
        }
        return;
      }

      // Mobile & Desktop platforms
      final localPath = await _ensureLocalFilePath();
      if (localPath != null) {
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile(
                localPath,
                mimeType: 'application/pdf',
                name: fileName,
              ),
            ],
            fileNameOverrides: [fileName],
            text: widget.title,
          ),
        );
      } else if (widget.fileUrl != null) {
        await SharePlus.instance.share(
          ShareParams(
            text: signedMediaUrl(widget.fileUrl!),
            subject: widget.title,
          ),
        );
      }
    } catch (e, st) {
      logWarning('[PdfViewerScreen] Share document failed', e, st);
    }
  }

  Future<void> _openExternally() async {
    final fileName = _safeFileName(widget.title, ext: 'pdf');
    try {
      if (kIsWeb) {
        final bytes = await _ensureBytes();
        if (bytes != null) {
          await openWebBlob(bytes,
              mimeType: 'application/pdf', filename: fileName);
        } else if (widget.fileUrl != null) {
          final uri = Uri.parse(signedMediaUrl(widget.fileUrl!));
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, webOnlyWindowName: '_blank');
          }
        }
        return;
      }

      // Mobile & Desktop
      final localPath = await _ensureLocalFilePath();
      if (localPath != null) {
        final result = await OpenFilex.open(localPath, type: 'application/pdf');
        if (result.type != ResultType.done && mounted) {
          logWarning(
              '[PdfViewerScreen] OpenFilex error: ${result.type} - ${result.message}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.type == ResultType.noAppToOpen
                    ? context.l10n.translate('viewer_no_external_app')
                    : context.l10n.translate('viewer_open_failed'),
              ),
              action: SnackBarAction(
                label: context.l10n.translate('viewer_share'),
                onPressed: _shareDocument,
              ),
            ),
          );
        }
        return;
      }

      if (widget.fileUrl != null) {
        final uri = Uri.parse(signedMediaUrl(widget.fileUrl!));
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e, st) {
      logWarning('[PdfViewerScreen] External launch error', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('${context.l10n.translate('viewer_open_failed')}: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final bgColor = palette.surfaceFor(const Color(0xFF0F1713));

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
                color: const Color(0xFFD32F2F).withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: Colors.redAccent.withValues(alpha: 0.4),
                  width: 0.8,
                ),
              ),
              child: const Text(
                'PDF',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 11,
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
                    : l10n.translate('viewer_pdf_title'),
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
          IconButton(
            tooltip: l10n.translate('viewer_share'),
            icon:
                Icon(Icons.share_rounded, color: palette.accentText, size: 20),
            onPressed: _shareDocument,
          ),
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
    final palette = context.forest;
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: palette.accentText),
            const SizedBox(height: 16),
            Text(
              context.l10n.translate('viewer_loading'),
              style: TextStyle(
                color: palette.text54,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null || _pdfController == null) {
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
                    args: {'error': _errorMessage ?? ''}),
                textAlign: TextAlign.center,
                style: TextStyle(color: context.forest.text70, fontSize: 14),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadPdf,
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

    return Stack(
      children: [
        PdfViewPinch(
          controller: _pdfController!,
          onDocumentLoaded: (doc) {
            if (mounted) {
              setState(() {
                _pageCount = doc.pagesCount;
              });
            }
          },
          onPageChanged: (page) {
            if (mounted) {
              setState(() {
                _currentPage = page;
              });
            }
          },
        ),
        if (_pageCount > 0)
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.mintGreen.withValues(alpha: 0.35),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_currentPage > 1) ...[
                      InkWell(
                        onTap: () => _pdfController?.previousPage(
                          curve: Curves.ease,
                          duration: const Duration(milliseconds: 200),
                        ),
                        child: const Icon(
                          Icons.chevron_left_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      context.l10n.translate('viewer_page_indicator', args: {
                        'current': '$_currentPage',
                        'total': '$_pageCount',
                      }),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_currentPage < _pageCount) ...[
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () => _pdfController?.nextPage(
                          curve: Curves.ease,
                          duration: const Duration(milliseconds: 200),
                        ),
                        child: const Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
