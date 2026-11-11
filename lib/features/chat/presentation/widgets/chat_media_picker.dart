import 'package:bhromon/core/theme/colors.dart';
import 'dart:io';
import 'package:bhromon/features/chat/presentation/chat_palette.dart';
import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/utils/logger.dart';

/// Result of a media pick operation.
class MediaPickResult {
  final XFile xFile;
  final File? file;
  final String type; // 'image' | 'video'
  final List<XFile>? xFiles;

  const MediaPickResult({
    required this.xFile,
    this.file,
    required this.type,
    this.xFiles,
  });

  /// All files picked (returns [xFiles] if present, otherwise [xFile] as a single-element list).
  List<XFile> get allFiles =>
      xFiles != null && xFiles!.isNotEmpty ? xFiles! : [xFile];
}

/// Shows a WhatsApp-style bottom sheet to pick an image or video.
/// Returns a [MediaPickResult] or null if the user cancels.
Future<MediaPickResult?> showChatMediaPicker(BuildContext context) {
  return showModalBottomSheet<MediaPickResult>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.75),
    backgroundColor: context.chat.bar,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => const _ChatMediaPickerSheet(),
  );
}

class _ChatMediaPickerSheet extends StatelessWidget {
  const _ChatMediaPickerSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: context.chat.text24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              context.l10n.translate('chat_media_picker_title'),
              style: TextStyle(
                color: context.chat.text,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _MediaOption(
                  icon: Icons.camera_alt_rounded,
                  label: context.l10n.translate('chat_open_camera'),
                  color: AppColors.chatGreen,
                  onTap: () => _pick(context, _PickMode.camera),
                ),
                _MediaOption(
                  icon: Icons.photo_library_rounded,
                  label: context.l10n.translate('chat_attach_gallery'),
                  color: const Color(0xFF34B7F1),
                  onTap: () => _pick(context, _PickMode.gallery),
                ),
                _MediaOption(
                  icon: Icons.videocam_rounded,
                  label: context.l10n.translate('chat_video_label'),
                  color: const Color(0xFFE4175B),
                  onTap: () => _pick(context, _PickMode.video),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context, _PickMode mode) async {
    // Only request Camera permission when capturing from camera.
    // Gallery image/video picking uses system pickers which require no runtime permissions.
    if (mode == _PickMode.camera) {
      final status = await Permission.camera.request();
      if (!context.mounted) return;

      if (status.isDenied || status.isPermanentlyDenied) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.translate('chat_camera_denied')),
            action: SnackBarAction(
              label: context.l10n.translate('chat_open_settings'),
              onPressed: openAppSettings,
            ),
            backgroundColor: AppColors.chatPanel,
          ),
        );
        Navigator.of(context).pop();
        return;
      }
    }

    final picker = ImagePicker();
    XFile? xfile;
    List<XFile>? multiFiles;

    try {
      if (mode == _PickMode.camera) {
        xfile = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
          maxWidth: 1920,
          maxHeight: 1920,
        );
      } else if (mode == _PickMode.gallery) {
        multiFiles = await picker.pickMultiImage(
          imageQuality: 85,
          maxWidth: 1920,
          maxHeight: 1920,
        );
        if (multiFiles.isNotEmpty) {
          xfile = multiFiles.first;
        }
      } else {
        xfile = await picker.pickVideo(
          source: ImageSource.gallery,
          maxDuration: const Duration(seconds: 120),
        );
      }
    } catch (e) {
      logError('Media picker error: $e');
    }

    if (!context.mounted) return;

    if (xfile == null) {
      Navigator.of(context).pop(null);
      return;
    }

    final result = MediaPickResult(
      xFile: xfile,
      file: !kIsWeb ? File(xfile.path) : null,
      type: (mode == _PickMode.video) ? 'video' : 'image',
      xFiles: multiFiles,
    );

    Navigator.of(context).pop(result);
  }
}

enum _PickMode { camera, gallery, video }

class _MediaOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MediaOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border:
                  Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(color: context.chat.text70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
