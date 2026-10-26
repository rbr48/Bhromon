import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class MediaCaptionResult {
  final XFile file;
  final String caption;
  final bool isViewOnce;

  MediaCaptionResult({
    required this.file,
    required this.caption,
    this.isViewOnce = false,
  });
}

/// WhatsApp-style full screen media preview with caption composer before sending.
class ChatMediaCaptionScreen extends StatefulWidget {
  final XFile file;
  final bool isVideo;

  const ChatMediaCaptionScreen({
    super.key,
    required this.file,
    this.isVideo = false,
  });

  @override
  State<ChatMediaCaptionScreen> createState() => _ChatMediaCaptionScreenState();
}

class _ChatMediaCaptionScreenState extends State<ChatMediaCaptionScreen> {
  final TextEditingController _captionController = TextEditingController();
  int _rotationQuarterTurns = 0;
  bool _isViewOnce = false;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  void _rotateImage() {
    setState(() {
      _rotationQuarterTurns = (_rotationQuarterTurns + 1) % 4;
    });
  }

  void _submit() {
    Navigator.of(context).pop(
      MediaCaptionResult(
        file: widget.file,
        caption: _captionController.text.trim(),
        isViewOnce: _isViewOnce,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Center Image/Media with InteractiveViewer (pinch to zoom)
            Center(
              child: RotatedBox(
                quarterTurns: _rotationQuarterTurns,
                child: InteractiveViewer(
                  maxScale: 4.0,
                  child: kIsWeb
                      ? Image.network(
                          widget.file.path,
                          fit: BoxFit.contain,
                        )
                      : Image.file(
                          File(widget.file.path),
                          fit: BoxFit.contain,
                        ),
                ),
              ),
            ),

            // Top action buttons
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.rotate_right, color: Colors.white, size: 26),
                    tooltip: 'Rotate',
                    onPressed: _rotateImage,
                  ),
                ],
              ),
            ),

            // Bottom Caption Composer Bar (WhatsApp styled)
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F2C34),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _captionController,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        decoration: const InputDecoration(
                          hintText: 'Add a caption...',
                          hintStyle: TextStyle(color: Colors.white54, fontSize: 14),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                        maxLines: 3,
                        minLines: 1,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _submit(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // WhatsApp View Once (1) toggle button
                  GestureDetector(
                    onTap: () {
                      setState(() => _isViewOnce = !_isViewOnce);
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            _isViewOnce
                                ? 'Photo set to view once'
                                : 'View once turned off',
                            style: const TextStyle(fontSize: 13),
                          ),
                          duration: const Duration(seconds: 2),
                          backgroundColor: const Color(0xFF1F2C34),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isViewOnce
                            ? const Color(0xFF00A884).withValues(alpha: 0.25)
                            : const Color(0xFF1F2C34),
                        border: Border.all(
                          color: _isViewOnce
                              ? const Color(0xFF00A884)
                              : Colors.white54,
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '1',
                          style: TextStyle(
                            color: _isViewOnce
                                ? const Color(0xFF00A884)
                                : Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _submit,
                    child: const CircleAvatar(
                      radius: 24,
                      backgroundColor: Color(0xFF00A884),
                      child: Icon(Icons.send, color: Colors.white, size: 20),
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
}
