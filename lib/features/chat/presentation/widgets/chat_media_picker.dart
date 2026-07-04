import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

/// Result of a media pick operation.
class MediaPickResult {
  final File file;
  final String type; // 'image' | 'video'

  const MediaPickResult({required this.file, required this.type});
}

/// Shows a WhatsApp-style bottom sheet to pick an image or video.
/// Returns a [MediaPickResult] or null if the user cancels.
Future<MediaPickResult?> showChatMediaPicker(BuildContext context) {
  return showModalBottomSheet<MediaPickResult>(
    context: context,
    backgroundColor: const Color(0xFF1F2C34),
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
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Share Media',
              style: TextStyle(
                color: Colors.white,
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
                  label: 'Camera',
                  color: const Color(0xFF00A884),
                  onTap: () => _pick(context, _PickMode.camera),
                ),
                _MediaOption(
                  icon: Icons.photo_library_rounded,
                  label: 'Gallery',
                  color: const Color(0xFF34B7F1),
                  onTap: () => _pick(context, _PickMode.gallery),
                ),
                _MediaOption(
                  icon: Icons.videocam_rounded,
                  label: 'Video',
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
    // Request relevant permission
    final Permission perm =
        (mode == _PickMode.camera) ? Permission.camera : Permission.photos;

    final status = await perm.request();
    if (!context.mounted) return;

    if (status.isDenied || status.isPermanentlyDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Permission denied. Please enable it in Settings.'),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: openAppSettings,
          ),
          backgroundColor: Color(0xFF1F2C34),
        ),
      );
      Navigator.of(context).pop();
      return;
    }

    final picker = ImagePicker();
    XFile? xfile;

    try {
      if (mode == _PickMode.camera) {
        xfile = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
          maxWidth: 1920,
          maxHeight: 1920,
        );
      } else if (mode == _PickMode.gallery) {
        xfile = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 85,
          maxWidth: 1920,
          maxHeight: 1920,
        );
      } else {
        xfile = await picker.pickVideo(
          source: ImageSource.gallery,
          maxDuration: const Duration(seconds: 60),
        );
      }
    } catch (e) {
      debugPrint('Media picker error: $e');
    }

    if (!context.mounted) return;

    if (xfile == null) {
      Navigator.of(context).pop(null);
      return;
    }

    final result = MediaPickResult(
      file: File(xfile.path),
      type: (mode == _PickMode.video) ? 'video' : 'image',
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
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
