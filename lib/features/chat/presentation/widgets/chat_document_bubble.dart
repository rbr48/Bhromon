import 'dart:io';
import 'package:bhromon/features/chat/presentation/chat_palette.dart';
import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/media/media_access.dart';
import '../../../../core/utils/logger.dart';

/// WhatsApp-style document attachment card.
class ChatDocumentBubble extends StatefulWidget {
  final String documentUrl;
  final String fileName;
  final int fileSizeBytes;
  final bool isMe;
  final String timeStr;
  final Widget? deliveryIcon;

  /// Set while the file is still being sent (0 to 1). The bubble then shows the
  /// progress and cannot be opened until the message is saved.
  final double? uploadProgress;

  const ChatDocumentBubble({
    super.key,
    required this.documentUrl,
    required this.fileName,
    required this.fileSizeBytes,
    required this.isMe,
    required this.timeStr,
    this.deliveryIcon,
    this.uploadProgress,
  });

  @override
  State<ChatDocumentBubble> createState() => _ChatDocumentBubbleState();
}

class _ChatDocumentBubbleState extends State<ChatDocumentBubble> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _getFileExtension(String fileName) {
    final parts = fileName.split('.');
    if (parts.length > 1) {
      return parts.last.toUpperCase();
    }
    return 'FILE';
  }

  Color _getExtensionColor(String ext) {
    switch (ext) {
      case 'PDF':
        return const Color(0xFFE53935);
      case 'DOC':
      case 'DOCX':
      case 'ODT':
      case 'RTF':
        return const Color(0xFF1E88E5);
      case 'XLS':
      case 'XLSX':
      case 'ODS':
      case 'CSV':
      case 'TSV':
        return const Color(0xFF43A047);
      case 'PPT':
      case 'PPTX':
      case 'ODP':
        return const Color(0xFFE65100);
      case 'MD':
      case 'TXT':
      case 'LOG':
        return const Color(0xFF00897B);
      case 'JSON':
      case 'YAML':
      case 'YML':
      case 'XML':
      case 'SQL':
        return const Color(0xFF5E35B1);
      case 'EPUB':
        return const Color(0xFF8E24AA);
      case 'ZIP':
      case 'RAR':
      case '7Z':
      case 'TAR':
      case 'GZ':
        return const Color(0xFFFB8C00);
      default:
        return const Color(0xFF00A884);
    }
  }

  Future<void> _openOrDownload() async {
    if (widget.documentUrl.isEmpty) return;

    final signedUrl = signedMediaUrl(widget.documentUrl);
    if (kIsWeb) {
      final uri = Uri.parse(signedUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }

    try {
      setState(() {
        _isDownloading = true;
        _downloadProgress = 0.0;
      });

      final dir = await getApplicationDocumentsDirectory();
      final localFilePath = '${dir.path}/${widget.fileName}';
      final file = File(localFilePath);

      if (!await file.exists()) {
        await Dio().download(
          signedUrl,
          localFilePath,
          onReceiveProgress: (received, total) {
            if (total > 0 && mounted) {
              setState(() {
                _downloadProgress = received / total;
              });
            }
          },
        );
      }

      if (mounted) {
        setState(() => _isDownloading = false);
        await OpenFilex.open(localFilePath);
      }
    } catch (e) {
      logError('Error downloading/opening document: $e');
      if (mounted) {
        setState(() => _isDownloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n
                  .translate('chat_open_file_failed', args: {'error': '$e'}),
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ext = _getFileExtension(widget.fileName);
    final extColor = _getExtensionColor(ext);
    final sending = widget.uploadProgress != null;

    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: widget.isMe ? context.chat.outgoing : context.chat.panel,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Inner card
          InkWell(
            onTap: (_isDownloading || sending) ? null : _openOrDownload,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: widget.isMe
                    ? context.chat.outgoingRecessed
                    : context.chat.recessedDeep,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  // File extension badge
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: extColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: extColor, width: 1.2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      ext,
                      style: TextStyle(
                        color: context.chat.text,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.fileName,
                          style: TextStyle(
                            color: context.chat.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${_formatFileSize(widget.fileSizeBytes)} • $ext',
                          style: TextStyle(
                            color: context.chat.text70,
                            fontSize: 10.5,
                          ),
                        ),
                        if (sending) ...[
                          const SizedBox(height: 3),
                          Text(
                            '${context.l10n.number(((widget.uploadProgress ?? 0) * 100).round())}%',
                            style: TextStyle(
                              color: context.chat.text70,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (_isDownloading || sending)
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        value: sending
                            ? (widget.uploadProgress ?? 0)
                                .clamp(0.0, 1.0)
                                .toDouble()
                            : (_downloadProgress > 0
                                ? _downloadProgress
                                : null),
                        color: const Color(0xFF00A884),
                        strokeWidth: 2.5,
                      ),
                    )
                  else
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: context.chat.text.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.download_rounded,
                        color: context.chat.text,
                        size: 18,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (widget.timeStr.isNotEmpty ||
              (widget.isMe && widget.deliveryIcon != null)) ...[
            const SizedBox(height: 4),
            // Time and status row
            Align(
              alignment: Alignment.bottomRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.timeStr.isNotEmpty)
                    Text(
                      widget.timeStr,
                      style:
                          TextStyle(color: context.chat.text54, fontSize: 9.5),
                    ),
                  if (widget.isMe && widget.deliveryIcon != null) ...[
                    const SizedBox(width: 4),
                    widget.deliveryIcon!,
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
