import 'package:flutter/foundation.dart';
import 'package:bhromon/features/chat/presentation/chat_palette.dart';
import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/domain/services/media_rules.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/utils/logger.dart';

enum AttachmentType {
  document,
  camera,
  gallery,
  audio,
  location,
  contact,
  expense,
}

/// WhatsApp-style circular icon grid attachment bottom sheet.
class ChatAttachmentSheet extends StatelessWidget {
  final void Function(PlatformFile file) onDocumentPicked;
  final void Function(XFile file, bool isVideo)? onMediaPicked;
  final void Function(List<XFile> files, bool isVideo)? onMultiMediaPicked;
  final void Function(PlatformFile audioFile) onAudioPicked;
  final void Function(Position position, String title) onLocationPicked;
  final VoidCallback onExpenseSplit;
  final VoidCallback? onEmojiPicked;

  const ChatAttachmentSheet({
    super.key,
    required this.onDocumentPicked,
    this.onMediaPicked,
    this.onMultiMediaPicked,
    required this.onAudioPicked,
    required this.onLocationPicked,
    required this.onExpenseSplit,
    this.onEmojiPicked,
  });

  Future<void> _pickDocument(BuildContext context) async {
    Navigator.pop(context);
    try {
      final res = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: kSupportedDocExtensions,
        // On web the picker returns no path, only bytes, so the bytes are asked for here.
        withData: kIsWeb,
      );
      if (res != null && res.files.isNotEmpty) {
        onDocumentPicked(res.files.first);
      }
    } catch (e) {
      logError('Error picking document: $e');
    }
  }

  Future<void> _pickFromCamera(BuildContext context) async {
    Navigator.pop(context);
    try {
      final picker = ImagePicker();
      final photo =
          await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      if (photo != null) {
        if (onMultiMediaPicked != null) {
          onMultiMediaPicked!([photo], false);
        } else if (onMediaPicked != null) {
          onMediaPicked!(photo, false);
        }
      }
    } catch (e) {
      logError('Error capturing photo: $e');
    }
  }

  Future<void> _pickFromGallery(BuildContext context) async {
    Navigator.pop(context);
    try {
      final picker = ImagePicker();
      final images = await picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (images.isNotEmpty) {
        if (onMultiMediaPicked != null) {
          onMultiMediaPicked!(images, false);
        } else if (onMediaPicked != null) {
          onMediaPicked!(images.first, false);
        }
      }
    } catch (e) {
      logError('Error picking gallery images: $e');
    }
  }

  Future<void> _pickVideo(BuildContext context) async {
    Navigator.pop(context);
    try {
      final picker = ImagePicker();
      final video = await picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 120),
      );
      if (video != null) {
        if (onMultiMediaPicked != null) {
          onMultiMediaPicked!([video], true);
        } else if (onMediaPicked != null) {
          onMediaPicked!(video, true);
        }
      }
    } catch (e) {
      logError('Error picking video: $e');
    }
  }

  Future<void> _pickAudio(BuildContext context) async {
    Navigator.pop(context);
    try {
      final res = await FilePicker.pickFiles(
        type: FileType.audio,
        // On web the picker returns no path, only bytes, so the bytes are asked for here.
        withData: kIsWeb,
      );
      if (res != null && res.files.isNotEmpty) {
        onAudioPicked(res.files.first);
      }
    } catch (e) {
      logError('Error picking audio: $e');
    }
  }

  Future<void> _shareLocation(BuildContext context) async {
    final l10n = context.l10n;
    Navigator.pop(context);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      onLocationPicked(pos, l10n.translate('chat_attach_current_location'));
    } catch (e) {
      logError('Error getting location: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: context.chat.bar,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Wrap(
        spacing: 24,
        runSpacing: 20,
        alignment: WrapAlignment.center,
        children: [
          _buildItem(
            context,
            icon: Icons.insert_drive_file,
            color: const Color(0xFF7F66FF),
            label: context.l10n.translate('chat_attach_document'),
            onTap: () => _pickDocument(context),
          ),
          _buildItem(
            context,
            icon: Icons.camera_alt,
            color: const Color(0xFFD3396D),
            label: context.l10n.translate('chat_open_camera'),
            onTap: () => _pickFromCamera(context),
          ),
          _buildItem(
            context,
            icon: Icons.photo,
            color: const Color(0xFFAC44CF),
            label: context.l10n.translate('chat_attach_gallery'),
            onTap: () => _pickFromGallery(context),
          ),
          _buildItem(
            context,
            icon: Icons.videocam_rounded,
            color: const Color(0xFFE4175B),
            label: context.l10n.translate('chat_video_label'),
            onTap: () => _pickVideo(context),
          ),
          _buildItem(
            context,
            icon: Icons.headphones,
            color: const Color(0xFFE36D38),
            label: context.l10n.translate('chat_attach_audio'),
            onTap: () => _pickAudio(context),
          ),
          _buildItem(
            context,
            icon: Icons.location_on,
            color: const Color(0xFF1FA855),
            label: context.l10n.translate('chat_attach_location'),
            onTap: () => _shareLocation(context),
          ),
          _buildItem(
            context,
            icon: Icons.payments_outlined,
            color: const Color(0xFF00A884),
            label: context.l10n.translate('chat_split_bill'),
            onTap: () {
              Navigator.pop(context);
              onExpenseSplit();
            },
          ),
          if (onEmojiPicked != null)
            _buildItem(
              context,
              icon: Icons.sentiment_satisfied_alt_outlined,
              color: const Color(0xFFF59E0B),
              label: context.l10n.translate('chat_open_emoji'),
              onTap: () {
                Navigator.pop(context);
                onEmojiPicked!();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildItem(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: color,
              child: Icon(icon, color: context.chat.text, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: context.chat.text70,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
