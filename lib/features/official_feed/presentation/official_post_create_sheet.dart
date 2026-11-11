import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/colors.dart';
import '../../../core/utils/app_logger.dart';
import '../data/official_feed_repository.dart';

/// Modal sheet for platform admins to create and publish official feed posts (reels or photos).
class OfficialPostCreateSheet extends StatefulWidget {
  const OfficialPostCreateSheet({
    super.key,
    this.repository,
  });

  final OfficialFeedRepository? repository;

  static Future<bool?> show(BuildContext context,
      {OfficialFeedRepository? repository}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => OfficialPostCreateSheet(repository: repository),
    );
  }

  @override
  State<OfficialPostCreateSheet> createState() =>
      _OfficialPostCreateSheetState();
}

class _OfficialPostCreateSheetState extends State<OfficialPostCreateSheet> {
  final _picker = ImagePicker();
  final _captionController = TextEditingController();

  bool _isVideo = true;
  Uint8List? _fileBytes;
  String? _fileName;

  Uint8List? _coverBytes;
  String? _coverName;

  bool _isUploading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    setState(() {
      _errorMessage = null;
    });

    try {
      if (_isVideo) {
        final video = await _picker.pickVideo(source: ImageSource.gallery);
        if (video == null) return;
        final bytes = await video.readAsBytes();
        setState(() {
          _fileBytes = bytes;
          _fileName = video.name;
        });
      } else {
        final image = await _picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1080,
          maxHeight: 1920,
          imageQuality: 88,
        );
        if (image == null) return;
        final bytes = await image.readAsBytes();
        setState(() {
          _fileBytes = bytes;
          _fileName = image.name;
        });
      }
    } catch (e, stack) {
      logWarning('[OfficialPostCreateSheet] Error picking media', e, stack);
      setState(() {
        _errorMessage = 'মিডিয়া ফাইল লোড করা যায়নি: $e';
      });
    }
  }

  Future<void> _pickCover() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1080,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      setState(() {
        _coverBytes = bytes;
        _coverName = image.name;
      });
    } catch (e, stack) {
      logWarning('[OfficialPostCreateSheet] Error picking cover', e, stack);
    }
  }

  Future<void> _publish() async {
    if (_fileBytes == null || _fileName == null) {
      setState(
          () => _errorMessage = 'অনুগ্রহ করে একটি ছবি বা ভিডিও সিলেক্ট করুন');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(
          () => _errorMessage = 'পাবলিশ করার জন্য অ্যাডমিন সাইন-ইন প্রয়োজন');
      return;
    }

    setState(() {
      _isUploading = true;
      _errorMessage = null;
    });

    try {
      final token = await user.getIdToken(true);
      if (token == null) throw Exception('Auth token could not be retrieved.');

      final repo = widget.repository ?? OfficialFeedRepository();
      await repo.publishOfficialPost(
        fileBytes: _fileBytes!,
        fileName: _fileName!,
        caption: _captionController.text.trim(),
        coverBytes: _coverBytes,
        coverName: _coverName,
        idToken: token,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e, stack) {
      logWarning('[OfficialPostCreateSheet] Publish failed', e, stack);
      if (mounted) {
        setState(() {
          _isUploading = false;
          _errorMessage = 'পাবলিশ করা সম্ভব হয়নি: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: 20 + bottomInset,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF131F1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.campaign_rounded,
                        color: AppColors.mintGreen, size: 26),
                    SizedBox(width: 10),
                    Text(
                      'অফিসিয়াল পোস্ট পাবলিশ করুন',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Mode Selector: Video Reel vs Photo
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _isUploading
                        ? null
                        : () => setState(() {
                              _isVideo = true;
                              _fileBytes = null;
                              _fileName = null;
                            }),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _isVideo ? AppColors.midGreen : Colors.white10,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isVideo
                              ? AppColors.mintGreen
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.video_library_rounded,
                            color: _isVideo ? Colors.white : Colors.white70,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'রিল ভিডিও',
                            style: TextStyle(
                              color: _isVideo ? Colors.white : Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: _isUploading
                        ? null
                        : () => setState(() {
                              _isVideo = false;
                              _fileBytes = null;
                              _fileName = null;
                              _coverBytes = null;
                              _coverName = null;
                            }),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: !_isVideo ? AppColors.midGreen : Colors.white10,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: !_isVideo
                              ? AppColors.mintGreen
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.image_rounded,
                            color: !_isVideo ? Colors.white : Colors.white70,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'ছবি / ব্যানার',
                            style: TextStyle(
                              color: !_isVideo ? Colors.white : Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Pick file preview box
            InkWell(
              onTap: _isUploading ? null : _pickMedia,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 160,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _fileBytes != null
                        ? AppColors.mintGreen
                        : Colors.white24,
                    width: 1.5,
                  ),
                ),
                child: _fileBytes != null
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          if (!_isVideo)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.memory(
                                _fileBytes!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                              ),
                            )
                          else
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: AppColors.mintGreen,
                                  size: 48,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _fileName ?? 'ভিডিও সিলেক্টেড',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: CircleAvatar(
                              radius: 16,
                              backgroundColor: Colors.black87,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.edit,
                                    size: 16, color: Colors.white),
                                onPressed: _pickMedia,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isVideo
                                ? Icons.upload_file_rounded
                                : Icons.add_photo_alternate_rounded,
                            color: AppColors.mintGreen,
                            size: 44,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isVideo
                                ? 'গ্যালারি থেকে ভিডিও নির্বাচন করুন'
                                : 'ছবি নির্বাচন করুন (৯:১৬ রেশিও সেরা)',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 14),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 12),

            // Optional cover for video
            if (_isVideo && _fileBytes != null) ...[
              OutlinedButton.icon(
                onPressed: _isUploading ? null : _pickCover,
                icon: Icon(
                  _coverBytes != null
                      ? Icons.check_circle
                      : Icons.add_photo_alternate_outlined,
                  color: AppColors.mintGreen,
                ),
                label: Text(
                  _coverBytes != null
                      ? 'কভার ছবি সিলেক্টেড ($_coverName)'
                      : 'ঐচ্ছিক কভার ছবি নির্বাচন করুন',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Caption Field
            TextField(
              controller: _captionController,
              enabled: !_isUploading,
              maxLines: 3,
              maxLength: 300,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.black26,
                hintText: 'ক্যাপশন লিখুন (সর্বোচ্চ ৩০০ অক্ষর)...',
                hintStyle: const TextStyle(color: Colors.white38),
                counterStyle: const TextStyle(color: Colors.white54),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.mintGreen),
                ),
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ],
            const SizedBox(height: 16),

            // Publish Button
            ElevatedButton(
              onPressed: _isUploading ? null : _publish,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.midGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isUploading
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('পাবলিশ হচ্ছে...',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    )
                  : const Text(
                      'পাবলিশ করুন',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
