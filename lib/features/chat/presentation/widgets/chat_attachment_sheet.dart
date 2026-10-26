import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

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
  final void Function(XFile file, bool isVideo) onMediaPicked;
  final void Function(PlatformFile audioFile) onAudioPicked;
  final void Function(Position position, String title) onLocationPicked;
  final VoidCallback onExpenseSplit;

  const ChatAttachmentSheet({
    super.key,
    required this.onDocumentPicked,
    required this.onMediaPicked,
    required this.onAudioPicked,
    required this.onLocationPicked,
    required this.onExpenseSplit,
  });

  Future<void> _pickDocument(BuildContext context) async {
    Navigator.pop(context);
    try {
      final res = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'doc',
          'docx',
          'xls',
          'xlsx',
          'txt',
          'zip',
          'csv'
        ],
      );
      if (res != null && res.files.isNotEmpty) {
        onDocumentPicked(res.files.first);
      }
    } catch (e) {
      debugPrint('Error picking document: $e');
    }
  }

  Future<void> _pickFromCamera(BuildContext context) async {
    Navigator.pop(context);
    try {
      final picker = ImagePicker();
      final photo =
          await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      if (photo != null) {
        onMediaPicked(photo, false);
      }
    } catch (e) {
      debugPrint('Error capturing photo: $e');
    }
  }

  Future<void> _pickFromGallery(BuildContext context) async {
    Navigator.pop(context);
    try {
      final picker = ImagePicker();
      final media =
          await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (media != null) {
        onMediaPicked(media, false);
      }
    } catch (e) {
      debugPrint('Error picking gallery image: $e');
    }
  }

  Future<void> _pickAudio(BuildContext context) async {
    Navigator.pop(context);
    try {
      final res = await FilePicker.pickFiles(type: FileType.audio);
      if (res != null && res.files.isNotEmpty) {
        onAudioPicked(res.files.first);
      }
    } catch (e) {
      debugPrint('Error picking audio: $e');
    }
  }

  Future<void> _shareLocation(BuildContext context) async {
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
      onLocationPicked(pos, 'Current Location');
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2C34),
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
            label: 'Document',
            onTap: () => _pickDocument(context),
          ),
          _buildItem(
            context,
            icon: Icons.camera_alt,
            color: const Color(0xFFD3396D),
            label: 'Camera',
            onTap: () => _pickFromCamera(context),
          ),
          _buildItem(
            context,
            icon: Icons.photo,
            color: const Color(0xFFAC44CF),
            label: 'Gallery',
            onTap: () => _pickFromGallery(context),
          ),
          _buildItem(
            context,
            icon: Icons.headphones,
            color: const Color(0xFFE36D38),
            label: 'Audio',
            onTap: () => _pickAudio(context),
          ),
          _buildItem(
            context,
            icon: Icons.location_on,
            color: const Color(0xFF1FA855),
            label: 'Location',
            onTap: () => _shareLocation(context),
          ),
          _buildItem(
            context,
            icon: Icons.payments_outlined,
            color: const Color(0xFF00A884),
            label: 'Split Bill',
            onTap: () {
              Navigator.pop(context);
              onExpenseSplit();
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
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
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
