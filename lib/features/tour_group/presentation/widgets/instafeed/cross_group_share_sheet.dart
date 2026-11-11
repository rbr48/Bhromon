import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bhromon/core/media/media_access.dart';
import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/utils/logger.dart';
import 'package:bhromon/features/tour_group/data/tour_channel_repository.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/data/tour_media_journal.dart';
import 'package:bhromon/features/tour_group/data/tour_media_uploader.dart';
import 'package:bhromon/features/tour_group/domain/models/channel_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_post_models.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/group_avatar.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/group_type.dart';

/// Modal bottom sheet allowing travelers to share/repost a Moments post
/// across their other tour groups.
class CrossGroupShareSheet extends StatefulWidget {
  final TourGroupRepository repository;
  final String sourceTourId;
  final String sourceTourName;
  final TourPostItem post;

  const CrossGroupShareSheet({
    super.key,
    required this.repository,
    required this.sourceTourId,
    required this.sourceTourName,
    required this.post,
  });

  @override
  State<CrossGroupShareSheet> createState() => _CrossGroupShareSheetState();
}

class _CrossGroupShareSheetState extends State<CrossGroupShareSheet> {
  TourGroup? _selectedGroup;
  bool _isSharing = false;
  bool _showChannels = false;
  final TextEditingController _captionCtrl = TextEditingController();

  static const List<Map<String, dynamic>> _defaultChannels = [
    {
      'id': 'general',
      'icon': Icons.chat_bubble_outline,
      'color': Colors.blueAccent,
    },
    {
      'id': 'food',
      'icon': Icons.restaurant_menu,
      'color': Colors.orangeAccent,
    },
    {
      'id': 'sightseeing',
      'icon': Icons.photo_camera_outlined,
      'color': Colors.greenAccent,
    },
    {
      'id': 'emergency',
      'icon': Icons.warning_amber_rounded,
      'color': Colors.redAccent,
    },
  ];

  late final Stream<List<TourGroup>> _groupsStream;

  @override
  void initState() {
    super.initState();
    _groupsStream = widget.repository.watchMyGroups();
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    super.dispose();
  }

  static String _channelTitle(BuildContext context, String channelId) {
    return switch (channelId) {
      'general' => context.l10n.translate('ig_channel_general'),
      'food' => context.l10n.translate('ig_channel_food'),
      'sightseeing' => context.l10n.translate('ig_channel_sightseeing'),
      _ => context.l10n.translate('ig_channel_emergency'),
    };
  }

  Future<String> _copyMediaForTarget(
      String url, String targetTourId, String folder) async {
    if (!url.startsWith(TourMediaRef.publicBaseUrl)) return url;
    try {
      return await TourMediaUploader.copyMedia(
        tourId: targetTourId,
        sourceUrl: url,
        folder: folder,
      );
    } catch (e, st) {
      logWarning('[CrossGroupShare] copyMedia fallback to source: $e', e, st);
      return url;
    }
  }

  Future<void> _repostToFeed(TourGroup targetGroup) async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    final l10n = context.l10n;

    try {
      // 1. Duplicate media files for target group storage isolation
      final copiedImages = <String>[];
      for (final img in widget.post.images) {
        final copied = await _copyMediaForTarget(img, targetGroup.id, 'posts');
        copiedImages.add(copied);
      }

      String? copiedVideo;
      if (widget.post.videoUrl != null && widget.post.videoUrl!.isNotEmpty) {
        copiedVideo = await _copyMediaForTarget(
            widget.post.videoUrl!, targetGroup.id, 'posts');
      }

      String? copiedCover;
      if (widget.post.coverUrl != null && widget.post.coverUrl!.isNotEmpty) {
        copiedCover = await _copyMediaForTarget(
            widget.post.coverUrl!, targetGroup.id, 'posts');
      }

      // 2. Compose caption
      final userNote = _captionCtrl.text.trim();
      final finalCaption = userNote.isNotEmpty
          ? (widget.post.caption.isNotEmpty
              ? '$userNote\n\n${widget.post.caption}'
              : userNote)
          : widget.post.caption;

      // 3. Post to target group
      await widget.repository.addPost(
        tourId: targetGroup.id,
        caption: finalCaption,
        images: copiedImages,
        videoUrl: copiedVideo,
        isReel: widget.post.isReel,
        coverUrl: copiedCover,
        aspectRatio: widget.post.aspectRatio,
        resharedFromTourId: widget.sourceTourId,
        resharedFromTourName: widget.sourceTourName,
        resharedFromAuthorName: widget.post.authorName,
        resharedPostId: widget.post.id,
      );

      if (mounted) {
        Navigator.pop(context); // Close cross group sheet
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('ig_share_feed_success',
                args: {'group': targetGroup.name})),
            backgroundColor: AppColors.mintGreen,
          ),
        );
      }
    } catch (e, st) {
      logWarning('[CrossGroupShare] repost failed: $e', e, st);
      if (mounted) {
        setState(() => _isSharing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(l10n.translate('ig_share_failed', args: {'error': e})),
            backgroundColor: AppColors.amber,
          ),
        );
      }
    }
  }

  Future<void> _sendToChannel(
      TourGroup targetGroup, String channelId, String channelTitle) async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    final l10n = context.l10n;

    try {
      final mediaPreview = widget.post.coverUrl ??
          (widget.post.images.isNotEmpty
              ? widget.post.images.first
              : widget.post.videoUrl ?? '');

      final msg =
          '📸 [${l10n.translate('ig_share_group_picker_title')}]\n${widget.post.authorName} (${widget.sourceTourName}): ${widget.post.caption.isNotEmpty ? widget.post.caption : l10n.translate('ig_chat_photo_fallback')}\n$mediaPreview';

      final channelRepo = TourChannelRepository(groups: widget.repository);
      await channelRepo.sendMessage(
        targetGroup.id,
        channelId,
        text: msg,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('ig_share_channel_success', args: {
              'channel': channelTitle,
              'group': targetGroup.name,
            })),
            backgroundColor: AppColors.mintGreen,
          ),
        );
      }
    } catch (e, st) {
      logWarning('[CrossGroupShare] send to channel failed: $e', e, st);
      if (mounted) {
        setState(() => _isSharing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(l10n.translate('ig_share_failed', args: {'error': e})),
            backgroundColor: AppColors.amber,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.forest.feedSurface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.forest.text24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _selectedGroup == null
                    ? _buildGroupPicker(context)
                    : _buildShareOptions(context, _selectedGroup!),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupPicker(BuildContext context) {
    final l10n = context.l10n;
    return StreamBuilder<List<TourGroup>>(
      stream: _groupsStream,
      builder: (context, snapshot) {
        final allGroups = snapshot.data ?? const <TourGroup>[];
        final otherGroups =
            allGroups.where((g) => g.id != widget.sourceTourId).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.swap_horiz_rounded,
                    color: context.forest.accentText, size: 22),
                const SizedBox(width: 8),
                Text(
                  l10n.translate('ig_share_group_picker_title'),
                  style: TextStyle(
                    color: context.forest.text,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.translate('ig_share_to_another_group_sub'),
              style: TextStyle(color: context.forest.text54, fontSize: 13),
            ),
            const SizedBox(height: 12),
            if (otherGroups.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.groups_outlined,
                          size: 48, color: context.forest.text24),
                      const SizedBox(height: 12),
                      Text(
                        l10n.translate('ig_no_other_groups'),
                        style: TextStyle(
                            color: context.forest.text54, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              for (final group in otherGroups)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: GroupAvatar(
                    typeIcon: groupTypeIcon(group),
                    photoUrl: group.photoUrl,
                    size: 40,
                  ),
                  title: Text(
                    group.name,
                    style: TextStyle(
                      color: context.forest.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Text(
                    l10n.translate(groupTypeKey(group)),
                    style:
                        TextStyle(color: context.forest.text54, fontSize: 12),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded,
                      color: context.forest.text54),
                  onTap: () {
                    setState(() {
                      _selectedGroup = group;
                      _showChannels = false;
                    });
                  },
                ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _buildShareOptions(BuildContext context, TourGroup targetGroup) {
    final l10n = context.l10n;
    final mediaThumbnail = widget.post.coverUrl ??
        (widget.post.images.isNotEmpty
            ? widget.post.images.first
            : widget.post.videoUrl);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Back navigation header
        Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: context.forest.text),
              onPressed: () {
                setState(() {
                  _selectedGroup = null;
                  _showChannels = false;
                });
              },
            ),
            GroupAvatar(
              typeIcon: groupTypeIcon(targetGroup),
              photoUrl: targetGroup.photoUrl,
              size: 32,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    targetGroup.name,
                    style: TextStyle(
                      color: context.forest.text,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    l10n.translate(groupTypeKey(targetGroup)),
                    style:
                        TextStyle(color: context.forest.text54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Post thumbnail card
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: context.forest.feedRaised,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.forest.divider10),
          ),
          child: Row(
            children: [
              if (mediaThumbnail != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    signedMediaUrl(mediaThumbnail),
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 50,
                      height: 50,
                      color: context.forest.divider12,
                      child: Icon(Icons.image,
                          size: 20, color: context.forest.text54),
                    ),
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.post.authorName,
                      style: TextStyle(
                        color: context.forest.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    if (widget.post.caption.isNotEmpty)
                      Text(
                        widget.post.caption,
                        style: TextStyle(
                          color: context.forest.text70,
                          fontSize: 12,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Option 1: Moments Feed Repost
        if (targetGroup.momentsOpen) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.forest.feedRaised,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.forest.divider10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor:
                          context.forest.accentText.withValues(alpha: 0.15),
                      child: Icon(Icons.auto_awesome_motion_rounded,
                          size: 18, color: context.forest.accentText),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.translate('ig_share_mode_feed'),
                            style: TextStyle(
                              color: context.forest.text,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            l10n.translate('ig_share_mode_feed_desc'),
                            style: TextStyle(
                                color: context.forest.text54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _captionCtrl,
                  style: TextStyle(color: context.forest.text, fontSize: 13),
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: l10n.translate('ig_share_caption_hint'),
                    hintStyle:
                        TextStyle(color: context.forest.text38, fontSize: 12),
                    filled: true,
                    fillColor: context.forest.feedField,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: context.forest.divider10),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: context.forest.divider10),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.mintGreen,
                      foregroundColor: AppColors.darkGreen,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                    ),
                    icon: _isSharing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.darkGreen))
                        : const Icon(Icons.repeat_rounded, size: 18),
                    label: Text(
                      _isSharing
                          ? l10n.translate('ig_sharing_in_progress')
                          : l10n.translate('ig_repost_button'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed:
                        _isSharing ? null : () => _repostToFeed(targetGroup),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 18, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.translate('ig_moments_disabled_in_group'),
                    style: const TextStyle(color: Colors.orange, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Option 2: Send to Group Channels
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _showChannels = !_showChannels),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.forest.feedRaised,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.forest.divider10),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.blueAccent.withValues(alpha: 0.15),
                  child: const Icon(Icons.forum_outlined,
                      size: 18, color: Colors.blueAccent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.translate('ig_share_mode_channel'),
                        style: TextStyle(
                          color: context.forest.text,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        l10n.translate('ig_share_mode_channel_desc'),
                        style: TextStyle(
                            color: context.forest.text54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _showChannels
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: context.forest.text54,
                ),
              ],
            ),
          ),
        ),

        // Channel list if expanded
        if (_showChannels) ...[
          const SizedBox(height: 8),
          _TargetChannelList(
            repository: widget.repository,
            tourId: targetGroup.id,
            onPick: (channelId, title) =>
                _sendToChannel(targetGroup, channelId, title),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

class _TargetChannelList extends StatefulWidget {
  final TourGroupRepository repository;
  final String tourId;
  final void Function(String channelId, String title) onPick;

  const _TargetChannelList({
    required this.repository,
    required this.tourId,
    required this.onPick,
  });

  @override
  State<_TargetChannelList> createState() => _TargetChannelListState();
}

class _TargetChannelListState extends State<_TargetChannelList> {
  late final Stream<List<TourChannel>> _docs = () {
    try {
      return TourChannelRepository(groups: widget.repository)
          .watchChannels(widget.tourId);
    } catch (e, st) {
      logWarning('[TargetChannelList] watchChannels fallback: $e', e, st);
      return Stream.value(const <TourChannel>[]);
    }
  }();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TourChannel>>(
      stream: _docs,
      builder: (context, snapshot) {
        final docs = snapshot.data ?? const <TourChannel>[];
        final hidden = hiddenBuiltInChannelIds(docs);
        final byId = {for (final c in docs) c.id: c};

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: context.forest.feedRaised,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final ch in _CrossGroupShareSheetState._defaultChannels)
                if (!hidden.contains(ch['id'] as String))
                  _tile(context, ch, byId[ch['id'] as String]),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(
      BuildContext context, Map<String, dynamic> ch, TourChannel? doc) {
    final id = ch['id'] as String;
    final override = doc?.titleOverride ?? '';
    final title = override.isNotEmpty
        ? override
        : _CrossGroupShareSheetState._channelTitle(context, id);
    final color = ch['color'] as Color;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: color.withValues(alpha: 0.2),
        child: Icon(ch['icon'] as IconData,
            size: 14, color: context.forest.readable(color)),
      ),
      title: Text(title,
          style: TextStyle(color: context.forest.text, fontSize: 13)),
      trailing:
          Icon(Icons.send_rounded, size: 14, color: context.forest.text54),
      onTap: () => widget.onPick(id, title),
    );
  }
}
