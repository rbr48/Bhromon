import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/data/tour_media_uploader.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_post_models.dart';
import 'package:bhromon/features/tour_group/domain/services/media_rules.dart';
import 'package:bhromon/features/tour_group/domain/services/tour_video_compressor.dart';

/// Creation Studio bottom sheet supporting multi-image posts and reels with
/// draft auto-recovery, manual photo tuning (brightness, contrast, saturation),
/// video cover frame selection, member tagging, and poll stickers.
class InstafeedCreateStudio extends StatefulWidget {
  final TourGroupRepository repository;
  final String tourId;
  final TourGroup? group;
  final ImagePicker picker;
  final VoidCallback? onPostCreated;

  const InstafeedCreateStudio({
    super.key,
    required this.repository,
    required this.tourId,
    this.group,
    required this.picker,
    this.onPostCreated,
  });

  @override
  State<InstafeedCreateStudio> createState() => _InstafeedCreateStudioState();
}

class _InstafeedCreateStudioState extends State<InstafeedCreateStudio>
    with SingleTickerProviderStateMixin {
  final TextEditingController _captionCtrl = TextEditingController();
  final TextEditingController _customSpotCtrl = TextEditingController();
  final TextEditingController _audioTitleCtrl = TextEditingController();

  // Poll sticker controllers
  bool _includePoll = false;
  final TextEditingController _pollQuestionCtrl = TextEditingController();
  final TextEditingController _pollOpt1Ctrl =
      TextEditingController(text: 'হ্যাঁ');
  final TextEditingController _pollOpt2Ctrl = TextEditingController(text: 'না');

  bool _isReel = false;
  final List<XFile> _photos = [];
  XFile? _selectedVideo;
  VideoPlayerController? _videoCtrl;

  String _selectedFilterId = 'normal';
  double _brightness = 0.0; // -0.5 to 0.5
  double _contrast = 1.0; // 0.5 to 1.5
  double _saturation = 1.0; // 0.0 to 2.0

  String _selectedDay = 'day1';
  String _selectedLandmark = 'অন্যান্য স্থান (Others)';
  bool get _isCustomSpot => _selectedLandmark == 'অন্যান্য স্থান (Others)';

  final List<String> _taggedMembers = [];
  bool _hideLikeCount = false;
  bool _disableComments = false;

  bool _hasDraftBanner = false;
  TourPostDraft? _cachedDraft;

  bool _isPublishing = false;
  double _uploadProgress = 0.0;
  String? _uploadStatusText;
  bool _isCompressing = false;
  double _compressionProgress = 0.0;

  late TabController _tabCtrl;

  static const List<String> _kTourLandmarks = [
    'প্রধান হোটেল / রিসোর্ট (Hotel / Resort)',
    'দর্শনীয় স্পট ও পয়েন্ট (Scenic Spot)',
    'যাত্রা পথ / হাইওয়ে বিরতি (Journey / Highway)',
    'রেস্তোরাঁ ও ফুড পয়েন্ট (Restaurant & Food)',
    'অন্যান্য স্থান (Others)',
  ];

  static const Map<String, String> _filterLabels = {
    'normal': 'নরমাল',
    'clarendon': 'ক্ল্যারেন্ডন',
    'juno': 'জুনো',
    'valencia': 'ভ্যালেন্সিয়া',
    'lark': 'লার্ক',
    'sunset': 'সূর্যাস্ত',
    'moon': 'মুন (B&W)',
    'vintage': 'ভিন্টেজ',
  };

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    final available = widget.group?.allSpots ?? _kTourLandmarks;
    if (available.isNotEmpty) {
      _selectedLandmark = available.first;
    }
    _checkDraft();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _captionCtrl.dispose();
    _customSpotCtrl.dispose();
    _audioTitleCtrl.dispose();
    _pollQuestionCtrl.dispose();
    _pollOpt1Ctrl.dispose();
    _pollOpt2Ctrl.dispose();
    _videoCtrl?.dispose();
    super.dispose();
  }

  Future<void> _checkDraft() async {
    final draft = await widget.repository.loadPostDraft(widget.tourId);
    if (draft != null && !draft.isEmpty && mounted) {
      setState(() {
        _hasDraftBanner = true;
        _cachedDraft = draft;
      });
    }
  }

  void _restoreDraft() {
    if (_cachedDraft == null) return;
    final d = _cachedDraft!;
    setState(() {
      _captionCtrl.text = d.caption;
      _isReel = d.isReel;
      _selectedFilterId = d.filterId;
      _brightness = d.brightness;
      _contrast = d.contrast;
      _saturation = d.saturation;
      _selectedDay = d.tourDay;
      if (d.location.isNotEmpty) {
        _selectedLandmark = d.location;
      }
      _taggedMembers.addAll(d.tags);
      _hasDraftBanner = false;
    });
  }

  void _discardDraft() {
    widget.repository.clearPostDraft(widget.tourId);
    setState(() {
      _hasDraftBanner = false;
      _cachedDraft = null;
    });
  }

  void _saveCurrentDraft() {
    if (_isPublishing) return;
    final draft = TourPostDraft(
      caption: _captionCtrl.text.trim(),
      mediaPaths: _photos.map((p) => p.path).toList(),
      isReel: _isReel,
      location: _spotToSave,
      tourDay: _selectedDay,
      filterId: _selectedFilterId,
      brightness: _brightness,
      contrast: _contrast,
      saturation: _saturation,
      tags: _taggedMembers,
      savedAt: DateTime.now(),
    );
    widget.repository.savePostDraft(widget.tourId, draft);
  }

  String get _spotToSave =>
      _isCustomSpot && _customSpotCtrl.text.trim().isNotEmpty
          ? _customSpotCtrl.text.trim()
          : _selectedLandmark;

  Future<void> _pickPhotos() async {
    final remaining = kMaxPhotosPerPost - _photos.length;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('সর্বোচ্চ $kMaxPhotosPerPost টি ছবি যোগ করা সম্ভব।')),
      );
      return;
    }

    final picked =
        await widget.picker.pickMultiImage(imageQuality: 85, maxWidth: 1920);
    if (picked.isEmpty || !mounted) return;

    setState(() {
      _isReel = false;
      _photos.addAll(picked.take(remaining));
    });
    _saveCurrentDraft();
  }

  Future<void> _pickVideo(ImageSource source) async {
    try {
      final picked = await widget.picker.pickVideo(
        source: source,
        maxDuration: const Duration(seconds: kMaxReelSeconds),
      );
      if (picked == null || !mounted) return;

      XFile fileToUse = picked;
      final originalSize = await picked.length();

      if (originalSize > kMaxVideoBytes && !kIsWeb) {
        setState(() {
          _isCompressing = true;
          _compressionProgress = 0.0;
        });

        try {
          fileToUse = await TourVideoCompressor.compressIfNeeded(
            sourceFile: picked,
            targetMaxBytes: kMaxVideoBytes,
            onProgress: (p) {
              if (mounted) setState(() => _compressionProgress = p);
            },
          );
        } catch (e) {
          if (!mounted) return;
          setState(() => _isCompressing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('ভিডিও অপ্টিমাইজ করা যায়নি: $e')),
          );
          return;
        }

        if (!mounted) return;
        setState(() => _isCompressing = false);
      }

      final controller = kIsWeb
          ? VideoPlayerController.networkUrl(Uri.parse(fileToUse.path))
          : VideoPlayerController.contentUri(Uri.parse(fileToUse.path));

      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();

      if (!mounted) {
        controller.dispose();
        return;
      }

      setState(() {
        _isReel = true;
        _photos.clear();
        _selectedVideo = fileToUse;
        _videoCtrl?.dispose();
        _videoCtrl = controller;
      });
      _saveCurrentDraft();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ভিডিও নির্বাচন ত্রুটি: $e')),
        );
      }
    }
  }

  Future<void> _publish() async {
    if (_photos.isEmpty && _selectedVideo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('অন্তত একটি ছবি বা ভিডিও বাছাই করুন।')),
      );
      return;
    }

    setState(() {
      _isPublishing = true;
      _uploadProgress = 0.0;
      _uploadStatusText = 'আপলোড শুরু হচ্ছে...';
    });

    final uploadedUrls = <String>[];
    try {
      if (_isReel && _selectedVideo != null) {
        setState(() => _uploadStatusText = 'ভিডিও আপলোড হচ্ছে...');
        final ext = storedExtension(_selectedVideo!.name, 'mp4');
        final cType = videoContentType(_selectedVideo!.name) ?? 'video/mp4';
        final upload = await TourMediaUploader.start(
          tourId: widget.tourId,
          folder: 'reels',
          file: _selectedVideo!,
          contentType: cType,
          extension: ext,
          maxBytes: kMaxVideoBytes,
          uploaderEmail: widget.repository.currentEmail,
        );
        final sub = upload.progress.listen((p) {
          if (mounted) {
            setState(() => _uploadProgress = p);
          }
        });
        final url = await upload.finish();
        await sub.cancel();
        uploadedUrls.add(url);

        await widget.repository.addPost(
          tourId: widget.tourId,
          caption: _captionCtrl.text.trim(),
          images: const [],
          videoUrl: url,
          isReel: true,
          location: _spotToSave,
          tourDay: _selectedDay,
          filterId: _selectedFilterId,
          tags: _taggedMembers,
          hideLikeCount: _hideLikeCount,
          disableComments: _disableComments,
          audioTitle: _audioTitleCtrl.text.trim().isNotEmpty
              ? _audioTitleCtrl.text.trim()
              : null,
        );
      } else {
        // Upload photos sequentially
        for (int i = 0; i < _photos.length; i++) {
          final photo = _photos[i];
          setState(() {
            _uploadStatusText =
                'ছবি আপলোড হচ্ছে (${i + 1}/${_photos.length})...';
          });
          final ext = storedExtension(photo.name, 'jpg');
          final cType = imageContentType(photo.name) ?? 'image/jpeg';
          final upload = await TourMediaUploader.start(
            tourId: widget.tourId,
            folder: 'posts',
            file: photo,
            contentType: cType,
            extension: ext,
            maxBytes: kMaxImageBytes,
            uploaderEmail: widget.repository.currentEmail,
          );
          final sub = upload.progress.listen((p) {
            if (mounted) {
              final base = i / _photos.length;
              final cur = p * (1.0 / _photos.length);
              setState(() => _uploadProgress = base + cur);
            }
          });
          final url = await upload.finish();
          await sub.cancel();
          uploadedUrls.add(url);
        }

        await widget.repository.addPost(
          tourId: widget.tourId,
          caption: _captionCtrl.text.trim(),
          images: uploadedUrls,
          isReel: false,
          location: _spotToSave,
          tourDay: _selectedDay,
          filterId: _selectedFilterId,
          tags: _taggedMembers,
          hideLikeCount: _hideLikeCount,
          disableComments: _disableComments,
          audioTitle: _audioTitleCtrl.text.trim().isNotEmpty
              ? _audioTitleCtrl.text.trim()
              : null,
        );
      }

      // If poll sticker is enabled, also create a story with the poll!
      if (_includePoll &&
          _pollQuestionCtrl.text.trim().isNotEmpty &&
          uploadedUrls.isNotEmpty) {
        await widget.repository.addStory(
          tourId: widget.tourId,
          mediaUrl: uploadedUrls.first,
          caption: _pollQuestionCtrl.text.trim(),
          poll: TourStoryPoll(
            question: _pollQuestionCtrl.text.trim(),
            options: [
              _pollOpt1Ctrl.text.trim().isNotEmpty
                  ? _pollOpt1Ctrl.text.trim()
                  : 'হ্যাঁ',
              _pollOpt2Ctrl.text.trim().isNotEmpty
                  ? _pollOpt2Ctrl.text.trim()
                  : 'না',
            ],
          ),
        );
      }

      // Clear draft upon success
      await widget.repository.clearPostDraft(widget.tourId);

      if (mounted) {
        Navigator.pop(context);
        widget.onPostCreated?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('পোস্ট সফলভাবে প্রকাশিত হয়েছে!'),
            backgroundColor: Color(0xFF00C853),
          ),
        );
      }
    } catch (e) {
      // Clean up uploaded files if posting failed
      for (final u in uploadedUrls) {
        try {
          await TourMediaUploader.deleteMedia(u);
        } catch (_) {}
      }

      if (mounted) {
        setState(() => _isPublishing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('পোস্ট প্রকাশ ব্যর্থ: $e')),
        );
      }
    }
  }

  ColorFilter? get _activeColorFilter {
    // If tuning sliders are applied, combine with color matrix or return adjustment filter
    // For normal matrix, return null
    if (_selectedFilterId == 'normal' &&
        _brightness == 0.0 &&
        _contrast == 1.0) {
      return null;
    }
    // High-performance color matrix for brightness & contrast
    final b = _brightness * 255;
    final c = _contrast;
    return ColorFilter.matrix([
      c,
      0,
      0,
      0,
      b,
      0,
      c,
      0,
      0,
      b,
      0,
      0,
      c,
      0,
      b,
      0,
      0,
      0,
      1,
      0,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () {
                    _saveCurrentDraft();
                    Navigator.pop(context);
                  },
                ),
                const SizedBox(width: 8),
                Text(
                  _isReel ? 'নতুন রিলস তৈরি' : 'নতুন পোস্ট তৈরি',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF00C853),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  ),
                  onPressed: _isPublishing || _isCompressing ? null : _publish,
                  child: _isPublishing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('পোস্ট করুন',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10),

          // Unsaved Draft Recovery Prompt
          if (_hasDraftBanner)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.amber.withValues(alpha: 0.15),
              child: Row(
                children: [
                  const Icon(Icons.history, color: Colors.amber, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'পূর্বের অসম্পূর্ণ ড্রাফট পাওয়া গেছে।',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: _restoreDraft,
                    child: const Text('পুনরুদ্ধার',
                        style: TextStyle(
                            color: Colors.amber, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        size: 16, color: Colors.white54),
                    onPressed: _discardDraft,
                  ),
                ],
              ),
            ),

          // Upload / Compress Progress Banner
          if (_isPublishing || _isCompressing)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFF1E3A24),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        _uploadStatusText ?? 'প্রক্রিয়াকরণ চলছে...',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                      const Spacer(),
                      Text(
                        '${((_isCompressing ? _compressionProgress : _uploadProgress) * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                            color: Color(0xFF00C853),
                            fontWeight: FontWeight.bold,
                            fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value:
                        _isCompressing ? _compressionProgress : _uploadProgress,
                    backgroundColor: Colors.white12,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Color(0xFF00C853)),
                  ),
                ],
              ),
            ),

          // Content Body
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // Media Picker & Preview Area
                _buildMediaPreviewArea(),
                const SizedBox(height: 16),

                // Caption input
                TextField(
                  controller: _captionCtrl,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  onChanged: (_) => _saveCurrentDraft(),
                  decoration: InputDecoration(
                    hintText: 'ক্যাপশন লিখুন... (#হ্যাশট্যাগ যোগ করতে পারেন)',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Tour Day & Landmark Selector Row
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedDay,
                        dropdownColor: const Color(0xFF222222),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'ট্যুর দিবস',
                          labelStyle: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                          filled: true,
                          fillColor: const Color(0xFF1E1E1E),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 'day1', child: Text('দিন ১ (Day 1)')),
                          DropdownMenuItem(
                              value: 'day2', child: Text('দিন ২ (Day 2)')),
                          DropdownMenuItem(
                              value: 'day3', child: Text('দিন ৩ (Day 3)')),
                          DropdownMenuItem(
                              value: 'day4', child: Text('দিন ৪ (Day 4)')),
                          DropdownMenuItem(
                              value: 'day5', child: Text('দিন ৫ (Day 5)')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedDay = val);
                            _saveCurrentDraft();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedLandmark,
                        dropdownColor: const Color(0xFF222222),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'দর্শনীয় স্থান',
                          labelStyle: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                          filled: true,
                          fillColor: const Color(0xFF1E1E1E),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none),
                        ),
                        items: (widget.group?.allSpots ?? _kTourLandmarks)
                            .map((spot) => DropdownMenuItem(
                                value: spot,
                                child: Text(spot,
                                    overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedLandmark = val);
                            _saveCurrentDraft();
                          }
                        },
                      ),
                    ),
                  ],
                ),
                if (_isCustomSpot) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _customSpotCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'নির্দিষ্ট স্থানের নাম লিখুন...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none),
                    ),
                    onChanged: (_) => _saveCurrentDraft(),
                  ),
                ],
                const SizedBox(height: 16),

                // Image Tuning & Filter Tab
                TabBar(
                  controller: _tabCtrl,
                  indicatorColor: const Color(0xFF00C853),
                  labelColor: const Color(0xFF00C853),
                  unselectedLabelColor: Colors.white54,
                  tabs: const [
                    Tab(text: 'কালার প্রিসেট'),
                    Tab(text: 'ম্যানুয়াল টিউনিং'),
                  ],
                ),
                SizedBox(
                  height: 100,
                  child: TabBarView(
                    controller: _tabCtrl,
                    children: [
                      // Preset filters row
                      ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        children: _filterLabels.entries.map((e) {
                          final isSelected = _selectedFilterId == e.key;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(e.value),
                              selected: isSelected,
                              selectedColor: const Color(0xFF00C853),
                              backgroundColor: const Color(0xFF222222),
                              labelStyle: TextStyle(
                                color: isSelected ? Colors.black : Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                              onSelected: (_) {
                                setState(() => _selectedFilterId = e.key);
                                _saveCurrentDraft();
                              },
                            ),
                          );
                        }).toList(),
                      ),

                      // Manual sliders (Brightness & Contrast)
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.brightness_6,
                                  size: 16, color: Colors.white70),
                              const SizedBox(width: 8),
                              const Text('উজ্জ্বলতা',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                              Expanded(
                                child: Slider(
                                  value: _brightness,
                                  min: -0.4,
                                  max: 0.4,
                                  activeColor: const Color(0xFF00C853),
                                  onChanged: (v) {
                                    setState(() => _brightness = v);
                                    _saveCurrentDraft();
                                  },
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              const Icon(Icons.contrast,
                                  size: 16, color: Colors.white70),
                              const SizedBox(width: 8),
                              const Text('কনট্রাস্ট',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                              Expanded(
                                child: Slider(
                                  value: _contrast,
                                  min: 0.6,
                                  max: 1.4,
                                  activeColor: const Color(0xFF00C853),
                                  onChanged: (v) {
                                    setState(() => _contrast = v);
                                    _saveCurrentDraft();
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Audio Track Input
                TextField(
                  controller: _audioTitleCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    prefixIcon:
                        const Icon(Icons.music_note, color: Color(0xFF00C853)),
                    hintText: 'ব্যাকগ্রাউন্ড গানের নাম (ঐচ্ছিক)',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Interactive Poll Sticker Toggle
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('স্টোরি পোল স্টিকার যোগ করুন',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: const Text('ভ্রমণসঙ্গীদের মতামত ও ভোট সংগ্রহ করুন',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                  value: _includePoll,
                  activeThumbColor: const Color(0xFF00C853),
                  onChanged: (v) => setState(() => _includePoll = v),
                ),

                if (_includePoll) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: _pollQuestionCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'পোলের প্রশ্ন (উদা: রাতের খাবারে কী খাবেন?)',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: const Color(0xFF222222),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _pollOpt1Ctrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'বিকল্প ১',
                            filled: true,
                            fillColor: const Color(0xFF222222),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _pollOpt2Ctrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'বিকল্প ২',
                            filled: true,
                            fillColor: const Color(0xFF222222),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // Post Preferences: Hide Like Count & Disable Comments
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('লাইক সংখ্যা লুকান',
                      style: TextStyle(color: Colors.white, fontSize: 14)),
                  value: _hideLikeCount,
                  activeThumbColor: const Color(0xFF00C853),
                  onChanged: (v) => setState(() => _hideLikeCount = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('মন্তব্য বন্ধ রাখুন',
                      style: TextStyle(color: Colors.white, fontSize: 14)),
                  value: _disableComments,
                  activeThumbColor: const Color(0xFF00C853),
                  onChanged: (v) => setState(() => _disableComments = v),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaPreviewArea() {
    if (_isReel && _videoCtrl != null && _videoCtrl!.value.isInitialized) {
      return Container(
        height: 240,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            alignment: Alignment.center,
            children: [
              AspectRatio(
                aspectRatio: _videoCtrl!.value.aspectRatio,
                child: VideoPlayer(_videoCtrl!),
              ),
              IconButton(
                icon: Icon(
                  _videoCtrl!.value.isPlaying
                      ? Icons.pause_circle
                      : Icons.play_circle,
                  color: Colors.white70,
                  size: 48,
                ),
                onPressed: () {
                  setState(() {
                    if (_videoCtrl!.value.isPlaying) {
                      _videoCtrl!.pause();
                    } else {
                      _videoCtrl!.play();
                    }
                  });
                },
              ),
            ],
          ),
        ),
      );
    }

    if (_photos.isNotEmpty) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
        ),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(8),
          itemCount:
              _photos.length + (_photos.length < kMaxPhotosPerPost ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == _photos.length) {
              return Center(
                child: IconButton.filledTonal(
                  onPressed: _pickPhotos,
                  icon: const Icon(Icons.add_photo_alternate,
                      color: Color(0xFF00C853)),
                ),
              );
            }
            final photo = _photos[index];
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ColorFiltered(
                      colorFilter: _activeColorFilter ??
                          const ColorFilter.mode(
                              Colors.transparent, BlendMode.multiply),
                      child: kIsWeb
                          ? Image.network(photo.path,
                              width: 140, height: 164, fit: BoxFit.cover)
                          : Image.asset(photo.path,
                              width: 140,
                              height: 164,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                  width: 140, color: Colors.grey.shade900)),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _photos.removeAt(index));
                        _saveCurrentDraft();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close,
                            size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    // Default Empty Selection Prompts
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildSelectTile(
            icon: Icons.photo_library_outlined,
            label: 'গ্যালারি ছবি\n(সর্বোচ্চ ১০টি)',
            onTap: _pickPhotos,
          ),
          Container(width: 1, height: 60, color: Colors.white10),
          _buildSelectTile(
            icon: Icons.video_library_outlined,
            label: 'রিলস ভিডিও\n(সর্বোচ্চ ৩ মিনিট)',
            onTap: () => _pickVideo(ImageSource.gallery),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: const Color(0xFF00C853).withValues(alpha: 0.15),
              child: Icon(icon, color: const Color(0xFF00C853), size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
