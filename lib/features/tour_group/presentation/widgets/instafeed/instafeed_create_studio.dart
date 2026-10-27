import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/data/tour_media_upload.dart';
import 'package:bhromon/features/tour_group/data/tour_media_uploader.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_post_models.dart';
import 'package:bhromon/features/tour_group/domain/services/media_rules.dart';
import 'package:bhromon/features/tour_group/domain/services/tour_video_compressor.dart';
import 'package:video_compress/video_compress.dart';
import '../../../../../core/theme/colors.dart';
import '../../../../../core/localization/app_localizations.dart';

/// Creation Studio bottom sheet supporting multi-image posts and reels with
/// draft auto-recovery, manual photo tuning (brightness, contrast, saturation),
/// video cover frame selection, member tagging, and poll stickers.
class InstafeedCreateStudio extends StatefulWidget {
  final TourGroupRepository repository;
  final String tourId;
  final TourGroup? group;
  final ImagePicker picker;
  final VoidCallback? onPostCreated;
  final bool isStory;

  const InstafeedCreateStudio({
    super.key,
    required this.repository,
    required this.tourId,
    this.group,
    required this.picker,
    this.onPostCreated,
    this.isStory = false,
  });

  @override
  State<InstafeedCreateStudio> createState() => _InstafeedCreateStudioState();
}

class _InstafeedCreateStudioState extends State<InstafeedCreateStudio>
    with SingleTickerProviderStateMixin {
  final TextEditingController _captionCtrl = TextEditingController();
  final TextEditingController _customSpotCtrl = TextEditingController();
  final TextEditingController _audioTitleCtrl = TextEditingController();

  late bool _shareToStory;
  late bool _shareToFeed;

  // Poll sticker controllers
  bool _includePoll = false;
  final TextEditingController _pollQuestionCtrl = TextEditingController();
  final TextEditingController _pollOpt1Ctrl = TextEditingController();
  final TextEditingController _pollOpt2Ctrl = TextEditingController();

  bool _isReel = false;
  final List<XFile> _photos = [];
  XFile? _selectedVideo;
  VideoPlayerController? _videoCtrl;
  XFile? _coverImage;
  Uint8List? _coverBytes;
  bool _isFirstFrameCover = false;
  double _videoPosition = 0.0;
  double _videoDuration = 1.0;

  String _selectedFilterId = 'normal';
  double _brightness = 0.0; // -0.5 to 0.5
  double _contrast = 1.0; // 0.5 to 1.5
  double _saturation = 1.0; // 0.0 to 2.0
  double _warmth = 0.0; // -0.4 to 0.4
  double _vignette = 0.0; // 0.0 to 1.0
  double?
      _selectedAspectRatio; // null = original, 1.0 = 1:1, 0.8 = 4:5, 16/9 = 16:9

  String _selectedDay = 'day1';
  late String _selectedLandmark;
  bool _defaultsReady = false;
  bool get _isCustomSpot =>
      _selectedLandmark == context.l10n.translate('ig_place_others');

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

  List<String> get _kTourLandmarks => [
        context.l10n.translate('ig_place_hotel'),
        context.l10n.translate('ig_place_spot'),
        context.l10n.translate('ig_place_journey'),
        context.l10n.translate('ig_place_food'),
        context.l10n.translate('ig_place_others'),
      ];

  Map<String, String> get _filterLabels => {
        'normal': context.l10n.translate('ig_filter_normal'),
        'clarendon': context.l10n.translate('ig_filter_clarendon'),
        'juno': context.l10n.translate('ig_filter_juno'),
        'valencia': context.l10n.translate('ig_filter_valencia'),
        'lark': context.l10n.translate('ig_filter_lark'),
        'sunset': context.l10n.translate('ig_filter_sunset'),
        'moon': context.l10n.translate('ig_filter_moon'),
        'vintage': context.l10n.translate('ig_filter_vintage'),
      };

  @override
  void initState() {
    super.initState();
    _shareToStory = widget.isStory;
    _shareToFeed = !widget.isStory;
    _tabCtrl = TabController(length: 2, vsync: this);
    _checkDraft();
  }

  /// Language-dependent defaults. They need the inherited localizations, so
  /// they are set here rather than in a field initializer or initState.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_defaultsReady) return;
    _defaultsReady = true;
    _pollOpt1Ctrl.text = context.l10n.translate('ig_yes');
    _pollOpt2Ctrl.text = context.l10n.translate('ig_no');
    final available = widget.group?.allSpots ?? _kTourLandmarks;
    _selectedLandmark = available.isNotEmpty
        ? available.first
        : context.l10n.translate('ig_place_others');
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
    // Leaving the sheet mid-compression stops the transcode too.
    if (_isCompressing) TourVideoCompressor.cancel();
    _releaseVideoPreview();
    // A compressed copy is only needed while its post is uploading.
    if (!_isCompressing && !_isPublishing) TourVideoCompressor.clearCache();
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
        SnackBar(
            content: Text(context.l10n
                .translate('ig_max_photos', args: {'max': kMaxPhotosPerPost}))),
      );
      return;
    }

    final picked =
        await widget.picker.pickMultiImage(imageQuality: 85, maxWidth: 1920);
    if (picked.isEmpty || !mounted) return;

    // Photos replace the reel, so its preview stops playing and is freed.
    _releaseVideoPreview();
    setState(() {
      _isReel = false;
      _selectedVideo = null;
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
        } on TourVideoCompressionCancelled {
          if (mounted) setState(() => _isCompressing = false);
          return;
        } catch (e) {
          if (!mounted) return;
          setState(() => _isCompressing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(context.l10n.translate('ig_video_optimize_failed',
                    args: {'error': e}))),
          );
          return;
        }

        if (!mounted) return;
        setState(() => _isCompressing = false);
      }

      final controller = createLocalVideoController(fileToUse);
      try {
        await controller.initialize();
        await controller.setLooping(true);
        await controller.play();
      } catch (_) {
        controller.dispose();
        rethrow;
      }

      if (!mounted) {
        controller.dispose();
        return;
      }

      controller.addListener(_onVideoTick);

      setState(() {
        _isReel = true;
        _photos.clear();
        _selectedVideo = fileToUse;
        _videoPosition = 0.0;
        _videoDuration = controller.value.duration.inMilliseconds.toDouble();
        _releaseVideoPreview();
        _videoCtrl = controller;
      });

      // Automatically extract first frame as reel thumbnail by default
      if (_coverImage == null && !kIsWeb) {
        _extractFirstFrameCover(fileToUse);
      }

      _saveCurrentDraft();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.l10n
                  .translate('ig_video_pick_failed', args: {'error': e}))),
        );
      }
    }
  }

  /// Stops and frees the reel preview, if one is loaded.
  void _releaseVideoPreview() {
    _videoCtrl?.removeListener(_onVideoTick);
    _videoCtrl?.dispose();
    _videoCtrl = null;
  }

  void _onVideoTick() {
    if (!mounted || _videoCtrl == null) return;
    final pos = _videoCtrl!.value.position.inMilliseconds.toDouble();
    final dur = _videoCtrl!.value.duration.inMilliseconds.toDouble();
    if (dur > 0 && (_videoPosition != pos || _videoDuration != dur)) {
      setState(() {
        _videoPosition = pos;
        _videoDuration = dur;
      });
    }
  }

  String _formatMs(double ms) {
    final s = (ms / 1000).floor();
    final mins = (s ~/ 60).toString().padLeft(2, '0');
    final secs = (s % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  Future<void> _extractFirstFrameCover(XFile videoFile) async {
    if (kIsWeb) return;
    try {
      final thumbFile = await VideoCompress.getFileThumbnail(
        videoFile.path,
        quality: 85,
        position: 1, // First frame in milliseconds
      );
      final bytes = await thumbFile.readAsBytes();
      if (mounted && _selectedVideo?.path == videoFile.path) {
        setState(() {
          _coverImage = XFile(thumbFile.path, name: 'first_frame.jpg');
          _coverBytes = bytes;
          _isFirstFrameCover = true;
        });
      }
    } catch (e) {
      debugPrint('Auto-extract first frame thumbnail error: $e');
    }
  }

  Future<void> _pickCoverImage() async {
    try {
      final picked = await widget.picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1440,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      setState(() {
        _coverImage = picked;
        _coverBytes = bytes;
        _isFirstFrameCover = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.l10n
                  .translate('ig_cover_pick_failed', args: {'error': e}))),
        );
      }
    }
  }

  void _clearCoverImage() {
    setState(() {
      _coverImage = null;
      _coverBytes = null;
      _isFirstFrameCover = false;
    });
    // Re-extract first frame as default if a video is selected
    if (_selectedVideo != null && !kIsWeb) {
      _extractFirstFrameCover(_selectedVideo!);
    }
  }

  Future<void> _publish() async {
    final l10n = context.l10n;
    if (_photos.isEmpty && _selectedVideo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.translate('ig_pick_one_media'))),
      );
      return;
    }

    setState(() {
      _isPublishing = true;
      _uploadProgress = 0.0;
      _uploadStatusText = context.l10n.translate('ig_upload_starting');
    });

    final uploads = <TourMediaUpload>[];
    final uploadedUrls = <String>[];
    var postSaved = false;
    String? coverUrl;
    try {
      if (_isReel && _selectedVideo != null) {
        setState(() =>
            _uploadStatusText = context.l10n.translate('ig_uploading_video'));
        final ext = storedExtension(_selectedVideo!.name, 'mp4');
        final cType = videoContentType(_selectedVideo!.name) ?? 'video/mp4';
        final upload = await TourMediaUploader.start(
          tourId: widget.tourId,
          folder: 'reels',
          file: _selectedVideo!,
          contentType: cType,
          extension: ext,
          maxBytes: kMaxVideoBytes,
        );
        uploads.add(upload);
        final sub = upload.progress.listen((p) {
          if (mounted) {
            final scale = _coverImage != null ? 0.8 : 1.0;
            setState(() => _uploadProgress = p * scale);
          }
        });
        final url = await upload.finish();
        await sub.cancel();
        uploadedUrls.add(url);

        if (_coverImage == null && _selectedVideo != null && !kIsWeb) {
          try {
            final thumbFile = await VideoCompress.getFileThumbnail(
              _selectedVideo!.path,
              quality: 85,
              position: 1,
            );
            _coverImage = XFile(thumbFile.path, name: 'first_frame.jpg');
          } catch (e) {
            debugPrint(
                'Auto-extract first frame on publish fallback failed: $e');
          }
        }
        if (_coverImage != null) {
          setState(() {
            _uploadStatusText = context.l10n.translate('ig_uploading_cover');
            _uploadProgress = 0.8;
          });
          final cExt = storedExtension(_coverImage!.name, 'jpg');
          final cContentType =
              imageContentType(_coverImage!.name) ?? 'image/jpeg';
          final coverUpload = await TourMediaUploader.start(
            tourId: widget.tourId,
            folder: 'covers',
            file: _coverImage!,
            contentType: cContentType,
            extension: cExt,
            maxBytes: kMaxImageBytes,
          );
          uploads.add(coverUpload);
          final coverSub = coverUpload.progress.listen((p) {
            if (mounted) {
              setState(() => _uploadProgress = 0.8 + (p * 0.2));
            }
          });
          coverUrl = await coverUpload.finish();
          await coverSub.cancel();
          uploadedUrls.add(coverUrl);
        }

        if (_shareToFeed) {
          await widget.repository.addPost(
            tourId: widget.tourId,
            caption: _captionCtrl.text.trim(),
            images: const [],
            videoUrl: url,
            coverUrl: coverUrl,
            aspectRatio: _videoCtrl?.value.aspectRatio,
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
        }
      } else {
        // Upload photos sequentially
        for (int i = 0; i < _photos.length; i++) {
          final photo = _photos[i];
          setState(() {
            _uploadStatusText = context.l10n.translate('ig_uploading_photo',
                args: {'current': i + 1, 'total': _photos.length});
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
          );
          uploads.add(upload);
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

        if (_shareToFeed) {
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
            aspectRatio: _selectedAspectRatio,
          );
        }
      }

      // If share to story is enabled, create the story!
      if (_shareToStory && uploadedUrls.isNotEmpty) {
        final mediaUrl =
            _isReel ? (coverUrl ?? uploadedUrls.first) : uploadedUrls.first;
        final poll = (_includePoll &&
                _pollQuestionCtrl.text.trim().isNotEmpty)
            ? TourStoryPoll(
                question: _pollQuestionCtrl.text.trim(),
                options: [
                  _pollOpt1Ctrl.text.trim().isNotEmpty
                      ? _pollOpt1Ctrl.text.trim()
                      : l10n.translate('ig_yes'),
                  _pollOpt2Ctrl.text.trim().isNotEmpty
                      ? _pollOpt2Ctrl.text.trim()
                      : l10n.translate('ig_no'),
                ],
              )
            : null;

        await widget.repository.addStory(
          tourId: widget.tourId,
          mediaUrl: mediaUrl,
          caption: _captionCtrl.text.trim().isNotEmpty
              ? _captionCtrl.text.trim()
              : (_includePoll && _pollQuestionCtrl.text.trim().isNotEmpty
                  ? _pollQuestionCtrl.text.trim()
                  : null),
          isVideo: _isReel,
          videoUrl: _isReel ? uploadedUrls.first : null,
          poll: poll,
        );
      }

      // The post/story is saved, so its files are no longer orphans.
      postSaved = true;
      for (final upload in uploads) {
        await upload.commit();
      }

      // Clear draft upon success
      await widget.repository.clearPostDraft(widget.tourId);

      // The reel is saved, so its compressed copy is no longer needed.
      _releaseVideoPreview();
      TourVideoCompressor.clearCache();

      if (mounted) {
        Navigator.pop(context);
        widget.onPostCreated?.call();
        final successMsg = _shareToStory && !_shareToFeed
            ? context.l10n.translate('ig_shared_to_story')
            : context.l10n.translate('ig_post_published');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMsg),
            backgroundColor: AppColors.mintGreen,
          ),
        );
      }
    } catch (e) {
      // The post is not saved, so the files it would have used are removed.
      if (!postSaved) {
        for (final upload in uploads) {
          await upload.discard();
        }
      }

      if (mounted) {
        setState(() => _isPublishing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.l10n
                  .translate('ig_publish_failed', args: {'error': e}))),
        );
      }
    }
  }

  ColorFilter? get _activeColorFilter {
    // If tuning sliders are applied, combine with color matrix or return adjustment filter
    // For normal matrix, return null
    if (_selectedFilterId == 'normal' &&
        _brightness == 0.0 &&
        _contrast == 1.0 &&
        _warmth == 0.0) {
      return null;
    }
    // High-performance color matrix for brightness, contrast & warmth
    final b = _brightness * 255;
    final c = _contrast;
    final wR = 1.0 + (_warmth * 0.35);
    final wB = 1.0 - (_warmth * 0.35);
    return ColorFilter.matrix([
      c * wR,
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
      c * wB,
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
    final media = MediaQuery.of(context);
    // The keyboard takes room from the sheet, so its bottom controls stay above
    // it while the caption is being typed.
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        height: (media.size.height - media.viewInsets.bottom) * 0.90,
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
                    tooltip: context.l10n.translate('ig_close'),
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () {
                      _saveCurrentDraft();
                      Navigator.pop(context);
                    },
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isReel
                        ? context.l10n.translate('ig_new_reel')
                        : (_shareToStory && !_shareToFeed
                            ? context.l10n.translate('ig_create_story')
                            : context.l10n.translate('ig_new_post_title')),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.mintGreen,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 8),
                    ),
                    onPressed:
                        _isPublishing || _isCompressing ? null : _publish,
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
                        : Text(
                            _shareToStory && !_shareToFeed
                                ? context.l10n.translate('ig_share_to_story_btn')
                                : context.l10n.translate('ig_publish'),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.darkGreen)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white10),

            // Share Destination Selector (Feed Post vs Story)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _shareToFeed = true;
                          _shareToStory = false;
                        });
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _shareToFeed && !_shareToStory
                              ? AppColors.mintGreen
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.grid_on_rounded,
                              size: 16,
                              color: _shareToFeed && !_shareToStory
                                  ? AppColors.darkGreen
                                  : Colors.white70,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              context.l10n.translate('ig_destination_feed'),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: _shareToFeed && !_shareToStory
                                    ? AppColors.darkGreen
                                    : Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _shareToStory = true;
                          _shareToFeed = false;
                        });
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _shareToStory && !_shareToFeed
                              ? AppColors.mintGreen
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.auto_stories_rounded,
                              size: 16,
                              color: _shareToStory && !_shareToFeed
                                  ? AppColors.darkGreen
                                  : Colors.white70,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              context.l10n.translate('ig_destination_story'),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: _shareToStory && !_shareToFeed
                                    ? AppColors.darkGreen
                                    : Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Unsaved Draft Recovery Prompt
            if (_hasDraftBanner)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.amber.withValues(alpha: 0.15),
                child: Row(
                  children: [
                    const Icon(Icons.history, color: Colors.amber, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.l10n.translate('ig_draft_found'),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: _restoreDraft,
                      child: Text(context.l10n.translate('ig_restore'),
                          style: const TextStyle(
                              color: Colors.amber,
                              fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      tooltip: context.l10n.translate('ig_close'),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: const Color(0xFF1E3A24),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          _uploadStatusText ??
                              context.l10n.translate('ig_processing'),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                        const Spacer(),
                        Text(
                          '${((_isCompressing ? _compressionProgress : _uploadProgress) * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                              color: AppColors.mintGreen,
                              fontWeight: FontWeight.bold,
                              fontSize: 12),
                        ),
                        if (_isCompressing)
                          IconButton(
                            tooltip: context.l10n.translate('ig_cancel'),
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close,
                                color: Colors.white70, size: 18),
                            onPressed: () => TourVideoCompressor.cancel(),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: _isCompressing
                          ? _compressionProgress
                          : _uploadProgress,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.mintGreen),
                    ),
                  ],
                ),
              ),

            // Content Body
            Expanded(
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                children: [
                  // Media Picker & Preview Area
                  _buildMediaPreviewArea(),
                  if (_photos.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.aspect_ratio,
                            size: 16, color: Colors.white70),
                        const SizedBox(width: 8),
                        Text(context.l10n.translate('ig_frame_label'),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildRatioChip(
                                    context.l10n.translate('ig_original_frame'),
                                    null),
                                const SizedBox(width: 6),
                                _buildRatioChip(
                                    context.l10n.translate('ig_ratio_square'),
                                    1.0),
                                const SizedBox(width: 6),
                                _buildRatioChip(
                                    context.l10n.translate('ig_ratio_portrait'),
                                    4.0 / 5.0),
                                const SizedBox(width: 6),
                                _buildRatioChip(
                                    context.l10n
                                        .translate('ig_ratio_landscape'),
                                    16.0 / 9.0),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Caption input
                  TextField(
                    controller: _captionCtrl,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white),
                    onChanged: (_) => _saveCurrentDraft(),
                    decoration: InputDecoration(
                      hintText: context.l10n.translate('ig_caption_hint'),
                      hintStyle: const TextStyle(color: Colors.white54),
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
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: context.l10n.translate('ig_tour_day'),
                            labelStyle: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                            filled: true,
                            fillColor: const Color(0xFF1E1E1E),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none),
                          ),
                          items: [
                            DropdownMenuItem(
                                value: 'day1',
                                child:
                                    Text(context.l10n.translate('ig_day_one'))),
                            DropdownMenuItem(
                                value: 'day2',
                                child:
                                    Text(context.l10n.translate('ig_day_two'))),
                            DropdownMenuItem(
                                value: 'day3',
                                child: Text(
                                    context.l10n.translate('ig_day_three'))),
                            DropdownMenuItem(
                                value: 'day4',
                                child: Text(
                                    context.l10n.translate('ig_day_four'))),
                            DropdownMenuItem(
                                value: 'day5',
                                child: Text(
                                    context.l10n.translate('ig_day_five'))),
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
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            labelText:
                                context.l10n.translate('ig_sightseeing_place'),
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
                        hintText: context.l10n.translate('ig_enter_place_name'),
                        hintStyle: const TextStyle(color: Colors.white54),
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
                    indicatorColor: AppColors.mintGreen,
                    labelColor: AppColors.mintGreen,
                    unselectedLabelColor: Colors.white54,
                    tabs: [
                      Tab(text: context.l10n.translate('ig_color_preset')),
                      Tab(text: context.l10n.translate('ig_manual_tuning')),
                    ],
                  ),
                  SizedBox(
                    height: 185,
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
                                selectedColor: AppColors.mintGreen,
                                backgroundColor: const Color(0xFF222222),
                                labelStyle: TextStyle(
                                  color:
                                      isSelected ? Colors.black : Colors.white,
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

                        // Manual sliders (Brightness, Contrast, Warmth, Vignette)
                        SingleChildScrollView(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.brightness_6,
                                      size: 16, color: Colors.white70),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 55,
                                    child: Text(
                                        context.l10n.translate('ig_brightness'),
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12)),
                                  ),
                                  Expanded(
                                    child: Slider(
                                      value: _brightness,
                                      min: -0.4,
                                      max: 0.4,
                                      activeColor: AppColors.mintGreen,
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
                                  SizedBox(
                                    width: 55,
                                    child: Text(
                                        context.l10n.translate('ig_contrast'),
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12)),
                                  ),
                                  Expanded(
                                    child: Slider(
                                      value: _contrast,
                                      min: 0.6,
                                      max: 1.4,
                                      activeColor: AppColors.mintGreen,
                                      onChanged: (v) {
                                        setState(() => _contrast = v);
                                        _saveCurrentDraft();
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  const Icon(Icons.wb_sunny_outlined,
                                      size: 16, color: Colors.amber),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 55,
                                    child: Text(
                                        context.l10n.translate('ig_warmth'),
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12)),
                                  ),
                                  Expanded(
                                    child: Slider(
                                      value: _warmth,
                                      min: -0.4,
                                      max: 0.4,
                                      activeColor: Colors.amber,
                                      onChanged: (v) {
                                        setState(() => _warmth = v);
                                        _saveCurrentDraft();
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  const Icon(Icons.vignette,
                                      size: 16, color: Colors.white70),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 55,
                                    child: Text(
                                        context.l10n.translate('ig_vignette'),
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12)),
                                  ),
                                  Expanded(
                                    child: Slider(
                                      value: _vignette,
                                      min: 0.0,
                                      max: 1.0,
                                      activeColor: AppColors.mintGreen,
                                      onChanged: (v) {
                                        setState(() => _vignette = v);
                                        _saveCurrentDraft();
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
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
                      prefixIcon: const Icon(Icons.music_note,
                          color: AppColors.mintGreen),
                      hintText: context.l10n.translate('ig_music_name_hint'),
                      hintStyle: const TextStyle(color: Colors.white54),
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
                    title: Text(context.l10n.translate('ig_add_poll_sticker'),
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Text(context.l10n.translate('ig_poll_hint'),
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                    value: _includePoll,
                    activeThumbColor: AppColors.mintGreen,
                    onChanged: (v) => setState(() => _includePoll = v),
                  ),

                  if (_includePoll) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        controller: _pollQuestionCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText:
                              context.l10n.translate('ig_poll_question_hint'),
                          hintStyle: const TextStyle(color: Colors.white54),
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
                              hintText: context.l10n.translate('ig_option_one'),
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
                              hintText: context.l10n.translate('ig_option_two'),
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
                    title: Text(context.l10n.translate('ig_hide_like_count'),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14)),
                    value: _hideLikeCount,
                    activeThumbColor: AppColors.mintGreen,
                    onChanged: (v) => setState(() => _hideLikeCount = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.l10n.translate('ig_keep_comments_off'),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14)),
                    value: _disableComments,
                    activeThumbColor: AppColors.mintGreen,
                    onChanged: (v) => setState(() => _disableComments = v),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaPreviewArea() {
    if (_isReel && _videoCtrl != null && _videoCtrl!.value.isInitialized) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 220,
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
                    tooltip: _videoCtrl!.value.isPlaying
                        ? context.l10n.translate('ig_pause')
                        : context.l10n.translate('ig_play'),
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
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 2),
            child: Row(
              children: [
                Text(
                  _formatMs(_videoPosition),
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 10),
                      activeTrackColor: AppColors.mintGreen,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: AppColors.mintGreen,
                    ),
                    child: Slider(
                      value: _videoPosition.clamp(
                          0.0, _videoDuration > 0 ? _videoDuration : 1.0),
                      min: 0.0,
                      max: _videoDuration > 0 ? _videoDuration : 1.0,
                      onChanged: (val) {
                        _videoCtrl?.seekTo(Duration(milliseconds: val.toInt()));
                      },
                    ),
                  ),
                ),
                Text(
                  _formatMs(_videoDuration),
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white54,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  onPressed: () => _pickVideo(ImageSource.gallery),
                  icon: const Icon(Icons.sync, size: 14),
                  label: Text(context.l10n.translate('ig_change_video'),
                      style: const TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
          _buildReelCoverSelector(),
        ],
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
                      color: AppColors.mintGreen),
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
                    child: AspectRatio(
                      aspectRatio: _selectedAspectRatio ?? 1.0,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _LocalPhotoThumbnail(
                            photo: photo,
                            colorFilter: _activeColorFilter,
                          ),
                          if (_vignette > 0)
                            Container(
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  colors: [
                                    Colors.transparent,
                                    Colors.black
                                        .withValues(alpha: _vignette * 0.85),
                                  ],
                                  radius: 0.85,
                                ),
                              ),
                            ),
                        ],
                      ),
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
            label: context.l10n.translate('ig_gallery_photos'),
            onTap: _pickPhotos,
          ),
          Container(width: 1, height: 60, color: Colors.white10),
          _buildSelectTile(
            icon: Icons.video_library_outlined,
            label: context.l10n.translate('ig_reel_video'),
            onTap: () => _pickVideo(ImageSource.gallery),
          ),
        ],
      ),
    );
  }

  Widget _buildReelCoverSelector() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _coverImage != null
              ? AppColors.mintGreen.withValues(alpha: 0.5)
              : Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.image_outlined,
                size: 18,
                color:
                    _coverImage != null ? AppColors.mintGreen : Colors.white70,
              ),
              const SizedBox(width: 8),
              Text(
                context.l10n.translate('ig_reel_cover'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              if (_coverImage != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.mintGreen.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _isFirstFrameCover
                        ? context.l10n.translate('ig_default_first_frame')
                        : context.l10n.translate('ig_custom_photo'),
                    style: const TextStyle(
                      color: AppColors.mintGreen,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _isFirstFrameCover
                ? context.l10n.translate('ig_first_frame_set')
                : context.l10n.translate('ig_pick_feed_frame'),
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 10),
          if (_coverImage != null && _coverBytes != null) ...[
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    _coverBytes!,
                    width: 60,
                    height: 80,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isFirstFrameCover
                            ? context.l10n.translate('ig_first_frame_cover')
                            : _coverImage!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Colors.white24),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: _pickCoverImage,
                            icon: const Icon(Icons.edit, size: 14),
                            label: Text(context.l10n.translate('ig_change'),
                                style: const TextStyle(fontSize: 11)),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: _clearCoverImage,
                            icon: const Icon(Icons.delete_outline, size: 14),
                            label: Text(context.l10n.translate('ig_delete'),
                                style: const TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.mintGreen,
                      side: const BorderSide(color: AppColors.mintGreen),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: _pickCoverImage,
                    icon: const Icon(Icons.add_photo_alternate_outlined,
                        size: 18),
                    label: Text(
                      context.l10n.translate('ig_pick_cover_gallery'),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRatioChip(String label, double? ratio) {
    final isSelected = _selectedAspectRatio == ratio;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: AppColors.mintGreen,
      backgroundColor: const Color(0xFF222222),
      labelStyle: TextStyle(
        color: isSelected ? Colors.black : Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.bold,
      ),
      onSelected: (_) => setState(() => _selectedAspectRatio = ratio),
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
              backgroundColor: AppColors.mintGreen.withValues(alpha: 0.15),
              child: Icon(icon, color: AppColors.mintGreen, size: 26),
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

/// Robust local photo thumbnail builder that safely loads bytes from picked XFile
/// across all platforms (Android, iOS, Web, Desktop) without asset errors.
class _LocalPhotoThumbnail extends StatelessWidget {
  final XFile photo;
  final ColorFilter? colorFilter;

  const _LocalPhotoThumbnail({
    required this.photo,
    this.colorFilter,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: photo.readAsBytes(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            width: 140,
            height: 164,
            color: Colors.grey.shade900,
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.mintGreen),
                ),
              ),
            ),
          );
        }
        return ColorFiltered(
          colorFilter: colorFilter ??
              const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
          child: Image.memory(
            snapshot.data!,
            width: 140,
            height: 164,
            fit: BoxFit.cover,
          ),
        );
      },
    );
  }
}
