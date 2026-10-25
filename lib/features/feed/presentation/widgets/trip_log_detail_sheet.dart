import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/entities/trip_log.dart';
import '../../../../core/entities/trip_block.dart';
import '../../../../core/widgets/voice_note_player.dart';
import 'in_app_youtube_player.dart';
import 'full_screen_image_viewer.dart';
import '../../../../core/theme/colors.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../../../../core/utils/image_sizing.dart';

class TripLogDetailSheet extends StatefulWidget {
  final TripLog log;
  final ScrollController scrollController;

  const TripLogDetailSheet({
    super.key,
    required this.log,
    required this.scrollController,
  });

  static void show(BuildContext context, TripLog log) {
    try {
      FirebaseFirestore.instance
          .collection('trip_logs')
          .doc(log.tripId)
          .update({'views': FieldValue.increment(1)});
    } catch (_) {}

    // Transparent page route (not a modal sheet): Hero images fly from the
    // feed card into the sheet during this push. Drag below the min extent or
    // tap the dimmed area to dismiss, matching the old bottom-sheet behavior.
    Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 340),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (ctx, animation, secondaryAnimation) =>
          _TripLogDetailPage(log: log),
      transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.15),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    ));
  }

  @override
  State<TripLogDetailSheet> createState() => _TripLogDetailSheetState();
}

class _TripLogDetailPage extends StatelessWidget {
  final TripLog log;
  const _TripLogDetailPage({required this.log});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Tapping the dimmed area above the sheet dismisses, like a modal.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: const SizedBox.expand(),
            ),
          ),
          NotificationListener<DraggableScrollableNotification>(
            onNotification: (notification) {
              if (notification.extent <= notification.minExtent + 0.005) {
                Navigator.of(context).maybePop();
              }
              return false;
            },
            child: DraggableScrollableSheet(
              initialChildSize: 0.92,
              minChildSize: 0.45,
              maxChildSize: 1.0,
              builder: (ctx, scrollController) {
                return TripLogDetailSheet(
                  log: log,
                  scrollController: scrollController,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TripLogDetailSheetState extends State<TripLogDetailSheet> {
  static final Map<String, Map<String, String>> _profileCache = {};
  late final Future<Map<String, String>> _authorProfileFuture;
  late final List<Widget> _cachedBlocks;

  @override
  void initState() {
    super.initState();
    _authorProfileFuture = _fetchAuthorProfile(widget.log.authorId);
    final blocks = <Widget>[];
    bool firstImageSeen = false;
    for (final block in widget.log.blocks) {
      final bool isFirstImage = !firstImageSeen && block is ImageBlock;
      if (isFirstImage) firstImageSeen = true;
      blocks.add(_buildTripBlockWidget(block, isFirstImage: isFirstImage));
    }
    _cachedBlocks = blocks;
  }

  Future<Map<String, String>> _fetchAuthorProfile(String authorId) async {
    if (_profileCache.containsKey(authorId)) {
      return _profileCache[authorId]!;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('explorer_profiles')
          .doc(authorId)
          .get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final profile = {
          'displayName':
              (data['displayName'] as String?)?.trim().isNotEmpty == true
                  ? data['displayName'] as String
                  : 'Explorer',
          'avatarUrl': (data['avatarUrl'] as String?) ?? '',
        };
        _profileCache[authorId] = profile;
        return profile;
      }
    } catch (_) {}
    final fallback = {'displayName': 'Explorer', 'avatarUrl': ''};
    _profileCache[authorId] = fallback;
    return fallback;
  }

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays}d ago';
  }

  Widget _detailChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildLinkifiedText(String text, TextStyle baseStyle) {
    final RegExp urlRegex = RegExp(
      r'(https?:\/\/[^\s]+)',
      caseSensitive: false,
    );

    final matches = urlRegex.allMatches(text);
    if (matches.isEmpty) {
      return Text(text, style: baseStyle);
    }

    final List<InlineSpan> spans = [];
    int lastMatchEnd = 0;

    for (final match in matches) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: baseStyle,
        ));
      }

      final urlString = match.group(0)!;
      final isYoutube =
          urlString.contains('youtube.com') || urlString.contains('youtu.be');

      spans.add(
        TextSpan(
          text: urlString,
          style: baseStyle.copyWith(
            color: Colors.blue.shade700,
            decoration: TextDecoration.underline,
            fontWeight: FontWeight.w600,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              final Uri url = Uri.parse(urlString);
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
        ),
      );

      if (isYoutube) {
        spans.add(
          const WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.0),
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.red,
                size: 16,
              ),
            ),
          ),
        );
      }

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastMatchEnd),
        style: baseStyle,
      ));
    }

    return RichText(
      text: TextSpan(children: spans),
    );
  }

  Widget _buildTripBlockWidget(TripBlock block, {bool isFirstImage = false}) {
    switch (block) {
      case TextBlock textBlock:
        return Padding(
          padding: const EdgeInsets.only(bottom: 6.0),
          child: _buildLinkifiedText(
            textBlock.content,
            TextStyle(
              fontSize: 13.5,
              fontWeight:
                  textBlock.isBold ? FontWeight.bold : FontWeight.normal,
              color: Colors.black87,
              height: 1.35,
            ),
          ),
        );
      case VideoBlock videoBlock:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: InAppYoutubePlayer(
            videoUrl: videoBlock.storageUrl,
            caption: videoBlock.caption,
            previewMode: true,
          ),
        );
      case ImageBlock imageBlock:
        final bool hasLocalFile = !kIsWeb &&
            imageBlock.localPath != null &&
            imageBlock.localPath!.isNotEmpty &&
            File(imageBlock.localPath!).existsSync();
        // The first image shares the feed card's tag so it hero-flies from
        // the card into this sheet; the rest keep sheet-local tags.
        final String heroTag = isFirstImage
            ? 'feed_${widget.log.tripId}_${imageBlock.storageUrl}'
            : 'sheet_${widget.log.tripId}_${imageBlock.storageUrl}';
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => FullScreenImageViewer(
                        imageUrl: imageBlock.storageUrl,
                        heroTag: heroTag,
                        localPath: imageBlock.localPath,
                        caption: imageBlock.caption,
                      ),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Hero(
                    tag: heroTag,
                    child: hasLocalFile
                        ? Image.file(
                            File(imageBlock.localPath!),
                            cacheWidth: context.decodeWidth(),
                            fit: BoxFit.cover,
                            height: 180,
                          )
                        : CachedNetworkImage(
                            memCacheWidth: context.decodeWidth(),
                            imageUrl: imageBlock.storageUrl,
                            fit: BoxFit.cover,
                            height: 180,
                            placeholder: (context, url) => Container(
                              height: 180,
                              color: Colors.grey.shade100,
                              child: const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.midGreen),
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              height: 180,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFE2EBE2),
                                    Color(0xFFECEAE4)
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Center(
                                child: Icon(Icons.image,
                                    color: Colors.black26, size: 36),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              if (imageBlock.caption.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  imageBlock.caption,
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontStyle: FontStyle.italic,
                      color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        );
      case CostEntryBlock costBlock:
        return Container(
          margin: const EdgeInsets.only(bottom: 6.0),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE9ECEF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.receipt_long, color: Color(0xFF2D6A4F), size: 14),
                  SizedBox(width: 6),
                  Text(
                    'Itemized Cost Details',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1B4332)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ...costBlock.items.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1.5),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(item.category,
                            style: const TextStyle(
                                fontSize: 11.5, color: Colors.black87)),
                        Text('${costBlock.currency} ${item.amountBDT}',
                            style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87)),
                      ],
                    ),
                  )),
            ],
          ),
        );
      case RouteBlock routeBlock:
        return Container(
          margin: const EdgeInsets.only(bottom: 6.0),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF9F5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFCE8DB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.route_outlined,
                      color: Color(0xFFE76F51), size: 14),
                  SizedBox(width: 6),
                  Text(
                    'Route Stops Mapped',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF9E3A25)),
                  ),
                ],
              ),
              if (routeBlock.description != null &&
                  routeBlock.description!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  routeBlock.description!,
                  style: const TextStyle(fontSize: 11.5, color: Colors.black87),
                ),
              ],
              const SizedBox(height: 2),
              Text(
                'Includes ${routeBlock.points.length} coordinates on map',
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ],
          ),
        );
      case SafetyNoteBlock safetyBlock:
        final isDanger = safetyBlock.level == 'danger';
        final isWarning = safetyBlock.level == 'warning';
        return Container(
          margin: const EdgeInsets.only(bottom: 6.0),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDanger
                ? const Color(0xFFFFF2F2)
                : isWarning
                    ? const Color(0xFFFFFBEA)
                    : const Color(0xFFEDF8FF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDanger
                  ? const Color(0xFFFAD1D1)
                  : isWarning
                      ? const Color(0xFFF9E7B9)
                      : const Color(0xFFCCE4FF),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isDanger
                    ? Icons.report_gmailerrorred_rounded
                    : isWarning
                        ? Icons.warning_amber_rounded
                        : Icons.info_outline,
                color: isDanger
                    ? Colors.red
                    : isWarning
                        ? Colors.orange
                        : Colors.blue,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  safetyBlock.text,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: isDanger
                        ? Colors.red.shade900
                        : isWarning
                            ? Colors.orange.shade900
                            : Colors.blue.shade900,
                  ),
                ),
              ),
            ],
          ),
        );
      case VoiceNoteBlock voiceNoteBlock:
        return VoiceNotePlayerWidget(
          storageUrl: voiceNoteBlock.storageUrl,
          localPath: voiceNoteBlock.localPath,
          durationSeconds: voiceNoteBlock.durationSeconds,
          transcript: voiceNoteBlock.transcript,
          isDarkTheme: false,
        );
    }
  }

  void _showCommentsBottomSheet(BuildContext context, TripLog log) {
    final TextEditingController commentController = TextEditingController();
    final authState = context.read<AuthCubit>().state;
    final String currentUserId =
        authState is Authenticated ? authState.profile.uid : '';
    final String currentUserName = authState is Authenticated
        ? authState.profile.displayName
        : 'Guest User';

    // Created once per sheet, not on every sheet rebuild.
    final commentsStream = FirebaseFirestore.instance
        .collection(log.isArchived ? 'archived_trip_logs' : 'trip_logs')
        .doc(log.tripId)
        .collection('comments')
        .orderBy('createdAt', descending: false)
        .snapshots();

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.92,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Comments',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const Divider(),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: commentsStream,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                                'Error loading comments: ${snapshot.error}',
                                style: const TextStyle(color: Colors.red)),
                          );
                        }
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.midGreen));
                        }

                        final docs = snapshot.data?.docs ?? [];
                        if (docs.isEmpty) {
                          return const Center(
                            child: Text(
                              'No comments yet. Be the first to comment!',
                              style: TextStyle(color: Colors.grey),
                            ),
                          );
                        }

                        return ListView.builder(
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final doc = docs[index];
                            final data = doc.data() as Map<String, dynamic>;
                            final String commentId = doc.id;
                            final String authorId =
                                (data['authorId'] as String?) ?? '';
                            final String authorName =
                                (data['authorName'] as String?) ?? 'Anonymous';
                            final String content =
                                (data['content'] as String?) ?? '';
                            final Timestamp? timestamp =
                                data['createdAt'] as Timestamp?;
                            final DateTime time =
                                timestamp?.toDate() ?? DateTime.now();

                            final isCommentOwner = currentUserId.isNotEmpty &&
                                authorId == currentUserId;

                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: AppColors.mintGreen
                                        .withValues(alpha: 0.2),
                                    child: Text(
                                      authorName.isNotEmpty
                                          ? authorName[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        color: AppColors.midGreen,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              authorName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12.5,
                                                color: Colors.black87,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              _formatCommentTime(time),
                                              style: TextStyle(
                                                color: Colors.grey.shade500,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          content,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isCommentOwner)
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          size: 16, color: Colors.redAccent),
                                      padding: EdgeInsets.zero,
                                      onPressed: () async {
                                        await FirebaseFirestore.instance
                                            .collection(log.isArchived
                                                ? 'archived_trip_logs'
                                                : 'trip_logs')
                                            .doc(log.tripId)
                                            .collection('comments')
                                            .doc(commentId)
                                            .delete();
                                      },
                                    ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const Divider(),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: TextField(
                            controller: commentController,
                            style: const TextStyle(
                                color: Colors.black87, fontSize: 13.5),
                            decoration: const InputDecoration(
                              hintText: 'Write a comment...',
                              hintStyle:
                                  TextStyle(color: Colors.grey, fontSize: 12.5),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.send, color: AppColors.midGreen),
                        onPressed: () async {
                          final commentText = commentController.text.trim();
                          if (commentText.isEmpty) return;

                          if (currentUserId.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('Please log in to post comments.')),
                            );
                            return;
                          }

                          commentController.clear();
                          await FirebaseFirestore.instance
                              .collection(log.isArchived
                                  ? 'archived_trip_logs'
                                  : 'trip_logs')
                              .doc(log.tripId)
                              .collection('comments')
                              .add({
                            'authorId': currentUserId,
                            'authorName': currentUserName,
                            'content': commentText,
                            'createdAt': FieldValue.serverTimestamp(),
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatCommentTime(DateTime dateTime) {
    final duration = DateTime.now().difference(dateTime);
    if (duration.inMinutes < 1) {
      return 'just now';
    } else if (duration.inMinutes < 60) {
      return '${duration.inMinutes}m ago';
    } else if (duration.inHours < 24) {
      return '${duration.inHours}h ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final authState = context.read<AuthCubit>().state;
    final String currentUserId =
        authState is Authenticated ? authState.profile.uid : '';
    final totalCost =
        log.costItems.fold<int>(0, (acc, item) => acc + item.amountBDT);
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF6F5F1),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: widget.scrollController,
              padding: EdgeInsets.fromLTRB(
                  16, 8, 16, 32 + MediaQuery.of(context).padding.bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FutureBuilder<Map<String, String>>(
                    future: _authorProfileFuture,
                    builder: (context, snapshot) {
                      final name = snapshot.data?['displayName'] ?? 'Explorer';
                      final avatarUrl = snapshot.data?['avatarUrl'] ?? '';
                      final initials = name
                          .split(' ')
                          .map((e) => e.isNotEmpty ? e[0] : '')
                          .take(2)
                          .join()
                          .toUpperCase();
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFECEAE4)),
                        ),
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: () {
                                Navigator.pop(context);
                                if (log.authorId.isNotEmpty) {
                                  context.push('/profile/${log.authorId}');
                                }
                              },
                              child: CircleAvatar(
                                radius: 24,
                                backgroundColor: const Color(0xFF40916C),
                                backgroundImage: avatarUrl.isNotEmpty
                                    ? sizedImage(
                                        CachedNetworkImageProvider(
                                          avatarUrl,
                                          errorListener: (dynamic error) {},
                                        ),
                                        context.decodeWidth(48))
                                    : null,
                                child: avatarUrl.isEmpty
                                    ? Text(initials,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold))
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.pop(context);
                                      if (log.authorId.isNotEmpty) {
                                        context
                                            .push('/profile/${log.authorId}');
                                      }
                                    },
                                    child: Text(
                                      name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: Color(0xFF181818),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Text(
                                        _timeAgo(log.publishedAt ??
                                            log.lastConfirmed),
                                        style: const TextStyle(
                                            color: Colors.black38,
                                            fontSize: 11),
                                      ),
                                      const Text(' · ',
                                          style: TextStyle(
                                              color: Colors.black38,
                                              fontSize: 11)),
                                      Text(
                                        log.district.isNotEmpty
                                            ? log.district
                                            : log.division,
                                        style: const TextStyle(
                                            color: Color(0xFF40916C),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEAF5EE),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${log.trustScore} XP',
                                style: const TextStyle(
                                    color: Color(0xFF1B4332),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            if (currentUserId.isNotEmpty &&
                                currentUserId != log.authorId) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                padding: EdgeInsets.zero,
                                icon: const Icon(
                                    Icons.report_gmailerrorred_rounded,
                                    color: Colors.redAccent,
                                    size: 20),
                                tooltip: 'Report Travel Log',
                                onPressed: () =>
                                    TravelLogReportDialog.show(context, log),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFECEAE4)),
                    ),
                    child: Text(
                      log.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF181818),
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _detailChip(
                          Icons.location_on,
                          log.district.isNotEmpty ? log.district : '—',
                          const Color(0xFF40916C)),
                      const SizedBox(width: 8),
                      _detailChip(
                          Icons.map_outlined,
                          log.division.isNotEmpty ? log.division : '—',
                          const Color(0xFF4361EE)),
                      if (totalCost > 0) ...[
                        const SizedBox(width: 8),
                        _detailChip(Icons.attach_money_rounded,
                            'BDT $totalCost', const Color(0xFFE76F51)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFECEAE4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Trip Details',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFF1B4332)),
                        ),
                        const SizedBox(height: 10),
                        if (log.blocks.isEmpty)
                          const Text('No content blocks.',
                              style: TextStyle(
                                  color: Colors.black45, fontSize: 13))
                        else
                          ..._cachedBlocks,
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (log.costItems.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFD8EFE2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.receipt_long_outlined,
                                  color: Color(0xFF2D6A4F), size: 16),
                              SizedBox(width: 6),
                              Text('Cost Breakdown',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Color(0xFF1B4332))),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ...log.costItems.map((item) => Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 3),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(item.category,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            color: Colors.black87)),
                                    Text('BDT ${item.amountBDT}',
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1B4332))),
                                  ],
                                ),
                              )),
                          const Divider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Color(0xFF181818))),
                              Text('BDT $totalCost',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Color(0xFF1B4332))),
                            ],
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFECEAE4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.thumb_up,
                            color: Color(0xFF40916C), size: 18),
                        const SizedBox(width: 8),
                        Text(
                          '${log.helpfulVotes} people found this helpful',
                          style: const TextStyle(
                              color: Colors.black54, fontSize: 13),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => _showCommentsBottomSheet(context, log),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF5EE),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Comments',
                              style: TextStyle(
                                  color: Color(0xFF1B4332),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TravelLogReportDialog extends StatefulWidget {
  final TripLog log;
  const TravelLogReportDialog({super.key, required this.log});

  static Future<void> show(BuildContext context, TripLog log) {
    return showDialog(
      context: context,
      builder: (_) => TravelLogReportDialog(log: log),
    );
  }

  @override
  State<TravelLogReportDialog> createState() => _TravelLogReportDialogState();
}

class _TravelLogReportDialogState extends State<TravelLogReportDialog> {
  String _selectedReason = 'Spam';
  final TextEditingController _detailCtrl = TextEditingController();
  bool _submitting = false;

  static const List<String> _reasons = [
    'Spam',
    'Harassment or hate speech',
    'Inaccurate safety information',
    'Inappropriate/Adult content',
    'Dangerous activity',
    'Plagiarism or fake log',
    'Other',
  ];

  @override
  void dispose() {
    _detailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.report_gmailerrorred_rounded,
              color: Colors.redAccent, size: 22),
          SizedBox(width: 8),
          Expanded(
            child: Text('Report Travel Log',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('📖 ${widget.log.title}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 14),
          const Text('Reason:',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _selectedReason,
            dropdownColor: const Color(0xFF2A2A3E),
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: _reasons
                .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                .toList(),
            onChanged: (v) =>
                setState(() => _selectedReason = v ?? _selectedReason),
          ),
          const SizedBox(height: 12),
          const Text('Additional details (optional):',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _detailCtrl,
            maxLines: 3,
            maxLength: 300,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: InputDecoration(
              hintText: 'Describe why you are reporting this log...',
              hintStyle: const TextStyle(color: Colors.white54, fontSize: 12),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              counterStyle: const TextStyle(color: Colors.white54, fontSize: 9),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Text('Submit Report',
                  style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final auth = context.read<AuthCubit>().state;
      final uid = auth is Authenticated ? auth.profile.uid : 'anonymous';
      await FirebaseFirestore.instance.collection('travel_log_reports').add({
        'tripId': widget.log.tripId,
        'tripTitle': widget.log.title,
        'authorId': widget.log.authorId,
        'reason': _selectedReason,
        'detail': _detailCtrl.text.trim(),
        'reportedBy': uid,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });
      // Increment report count on travel log doc
      await FirebaseFirestore.instance
          .collection('trip_logs')
          .doc(widget.log.tripId)
          .update({'reportCount': FieldValue.increment(1)});

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  '🛡️ Travel log report submitted. Thank you for maintaining community guidelines!')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}
