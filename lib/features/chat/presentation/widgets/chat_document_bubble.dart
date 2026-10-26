import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

/// WhatsApp-style document attachment card.
class ChatDocumentBubble extends StatefulWidget {
  final String documentUrl;
  final String fileName;
  final int fileSizeBytes;
  final bool isMe;
  final String timeStr;
  final Widget? deliveryIcon;

  const ChatDocumentBubble({
    super.key,
    required this.documentUrl,
    required this.fileName,
    required this.fileSizeBytes,
    required this.isMe,
    required this.timeStr,
    this.deliveryIcon,
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
        return const Color(0xFF1E88E5);
      case 'XLS':
      case 'XLSX':
        return const Color(0xFF43A047);
      case 'ZIP':
      case 'RAR':
      case '7Z':
        return const Color(0xFFFB8C00);
      default:
        return const Color(0xFF00A884);
    }
  }

  Future<void> _openOrDownload() async {
    if (widget.documentUrl.isEmpty) return;

    if (kIsWeb) {
      final uri = Uri.parse(widget.documentUrl);
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
          widget.documentUrl,
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
      debugPrint('Error downloading/opening document: $e');
      if (mounted) {
        setState(() => _isDownloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open file: $e'),
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

    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: widget.isMe ? const Color(0xFF005C4B) : const Color(0xFF202C33),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Inner card
          InkWell(
            onTap: _isDownloading ? null : _openOrDownload,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: widget.isMe
                    ? const Color(0xFF024638)
                    : const Color(0xFF182229),
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
                        color: extColor,
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
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${_formatFileSize(widget.fileSizeBytes)} • $ext',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (_isDownloading)
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        value: _downloadProgress > 0 ? _downloadProgress : null,
                        color: const Color(0xFF00A884),
                        strokeWidth: 2.5,
                      ),
                    )
                  else
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.download_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Time and status row
          Align(
            alignment: Alignment.bottomRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.timeStr,
                  style: const TextStyle(color: Colors.white54, fontSize: 9.5),
                ),
                if (widget.isMe && widget.deliveryIcon != null) ...[
                  const SizedBox(width: 4),
                  widget.deliveryIcon!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
