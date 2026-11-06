import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/colors.dart';

/// A styled container for multiline code blocks in chat messages.
///
/// Features:
/// - Dark monospace editor look with rounded borders.
/// - Top bar displaying the detected programming language.
/// - One-tap "Copy" button with haptic feedback and confirmation state.
/// - Horizontal scrolling for long code lines to prevent overflow.
class ChatCodeBlockWidget extends StatefulWidget {
  final String code;
  final String? language;

  const ChatCodeBlockWidget({
    super.key,
    required this.code,
    this.language,
  });

  @override
  State<ChatCodeBlockWidget> createState() => _ChatCodeBlockWidgetState();
}

class _ChatCodeBlockWidgetState extends State<ChatCodeBlockWidget> {
  bool _copied = false;

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    HapticFeedback.lightImpact();
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.language?.trim().toUpperCase();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF151D18),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Code block header bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              color: Colors.black.withValues(alpha: 0.35),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    lang != null && lang.isNotEmpty ? lang : 'CODE',
                    style: const TextStyle(
                      color: AppColors.mintGreen,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: _copyCode,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _copied ? Icons.check_rounded : Icons.copy_rounded,
                            size: 13,
                            color: _copied ? AppColors.mintGreen : Colors.white70,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _copied ? 'Copied' : 'Copy',
                            style: TextStyle(
                              color:
                                  _copied ? AppColors.mintGreen : Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Code text content with horizontal scroll
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(10),
              child: SelectableText(
                widget.code,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  color: Color(0xFFE2E8F0),
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
