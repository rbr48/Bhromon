import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../domain/models/tour_group.dart';
import '../../../domain/models/tour_post_models.dart';
import '../../../domain/services/scrapbook_engine.dart';
import '../instafeed/reel_thumbnail_preview.dart';

const _paper = Color(0xFF15110D);
const _ink = Color(0xFFF5EEDC);
const _gold = Color(0xFFE8B04B);
const _muted = Color(0xFFB9AE98);

/// The tour magazine: a set of pages the family flips through, built from
/// [issue]. Pages without data behind them are left out.
class ScrapbookMagazine extends StatefulWidget {
  const ScrapbookMagazine({
    super.key,
    required this.issue,
    required this.posts,
    required this.group,
    required this.travellers,
    required this.myEmail,
    required this.onShareText,
  });

  final ScrapbookIssue issue;

  /// The posts the issue was built from, for the reader's own page.
  final List<TourPostItem> posts;

  final TourGroup? group;
  final int travellers;

  /// The signed-in member, for their own page. Empty when signed out.
  final String myEmail;

  /// Shares the magazine as text, used when an image cannot be made.
  final VoidCallback onShareText;

  /// How long each page stays up while the magazine plays.
  static const pageDuration = Duration(seconds: 5);

  @override
  State<ScrapbookMagazine> createState() => _ScrapbookMagazineState();
}

class _ScrapbookMagazineState extends State<ScrapbookMagazine> {
  final _controller = PageController();
  final _pageKeys = <GlobalKey>[];
  Timer? _player;
  int _page = 0;
  bool _sharing = false;

  @override
  void dispose() {
    _player?.cancel();
    _controller.dispose();
    super.dispose();
  }

  List<Widget> _pages(AppLocalizations l10n) {
    final issue = widget.issue;
    final recap = widget.myEmail.isEmpty
        ? null
        : issue.recapFor(widget.myEmail, widget.posts);
    return [
      _CoverPage(
          issue: issue, group: widget.group, travellers: widget.travellers),
      if (!issue.isEmpty) _NumbersPage(stats: issue.stats),
      if (recap != null && !recap.isEmpty) _YourPage(recap: recap),
      for (var i = 0; i < issue.chapters.length; i++)
        _ChapterPage(chapter: issue.chapters[i], number: i + 1),
      if (issue.topMoments.isNotEmpty) _MomentsPage(posts: issue.topMoments),
      if (issue.quotes.isNotEmpty) _QuotesPage(quotes: issue.quotes),
      if (issue.awards.isNotEmpty) _AwardsPage(awards: issue.awards),
      if (issue.places.isNotEmpty) _PlacesPage(places: issue.places),
      _BackCoverPage(
          travellers: widget.travellers, onShare: widget.onShareText),
    ];
  }

  void _go(int page, int total) {
    if (page < 0 || page >= total) return;
    unawaited(_controller.animateToPage(page,
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeInOutCubic));
  }

  void _togglePlay(int total) {
    if (_player != null) {
      _stopPlaying();
      return;
    }
    if (_page >= total - 1) _go(0, total);
    setState(() {
      _player = Timer.periodic(ScrapbookMagazine.pageDuration, (_) {
        if (!mounted) return;
        if (_page >= total - 1) {
          _stopPlaying();
        } else {
          _go(_page + 1, total);
        }
      });
    });
  }

  void _stopPlaying() {
    _player?.cancel();
    if (mounted) setState(() => _player = null);
  }

  /// Renders the page on screen to a picture and shares it. Falls back to the
  /// text summary when the picture cannot be made (for example, a photo that
  /// another site will not let the browser read).
  Future<void> _sharePage(int index) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sharing = true);
    try {
      final boundary = _pageKeys[index].currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('page not on screen');
      final image = await boundary.toImage(pixelRatio: 2.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('no image data');
      final name =
          'bhromon_${(widget.group?.name ?? 'tour').replaceAll(RegExp(r'\W+'), '_')}_${index + 1}.png';
      // ignore: deprecated_member_use
      await Share.shareXFiles([
        XFile.fromData(data.buffer.asUint8List(),
            mimeType: 'image/png', name: name),
      ], text: widget.group?.name);
    } catch (_) {
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.translate('mag_share_failed'))));
      widget.onShareText();
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pages = _pages(l10n);
    while (_pageKeys.length < pages.length) {
      _pageKeys.add(GlobalKey());
    }
    final total = pages.length;
    final page = _page.clamp(0, total - 1);

    return Column(
      children: [
        LinearProgressIndicator(
          value: (page + 1) / total,
          minHeight: 3,
          backgroundColor: Colors.white10,
          valueColor: const AlwaysStoppedAnimation(_gold),
        ),
        Expanded(
          child: PageView.builder(
            controller: _controller,
            itemCount: total,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) => _FlipTransform(
              controller: _controller,
              index: i,
              child: RepaintBoundary(
                key: _pageKeys[i],
                child: ColoredBox(color: _paper, child: pages[i]),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: l10n.translate('mag_prev'),
                  onPressed: page > 0
                      ? () {
                          _stopPlaying();
                          _go(page - 1, total);
                        }
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded, color: _ink),
                ),
                IconButton(
                  tooltip: l10n
                      .translate(_player == null ? 'mag_play' : 'mag_pause'),
                  onPressed: total > 1 ? () => _togglePlay(total) : null,
                  icon: Icon(
                    _player == null
                        ? Icons.play_circle_outline_rounded
                        : Icons.pause_circle_outline_rounded,
                    color: _gold,
                  ),
                ),
                Expanded(
                  child: Text(
                    l10n.translate('mag_page_of', args: {
                      'page': l10n.number(page + 1),
                      'total': l10n.number(total),
                    }),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
                IconButton(
                  tooltip: l10n.translate('mag_share_page'),
                  onPressed: _sharing ? null : () => _sharePage(page),
                  icon: _sharing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _gold))
                      : const Icon(Icons.ios_share_rounded, color: _ink),
                ),
                IconButton(
                  tooltip: l10n.translate('mag_next'),
                  onPressed: page < total - 1
                      ? () {
                          _stopPlaying();
                          _go(page + 1, total);
                        }
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded, color: _ink),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Turns each page a little around its spine as it moves, like a magazine.
class _FlipTransform extends StatelessWidget {
  const _FlipTransform({
    required this.controller,
    required this.index,
    required this.child,
  });

  final PageController controller;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        var offset = 0.0;
        if (controller.hasClients && controller.position.haveDimensions) {
          offset = (controller.page ?? index.toDouble()) - index;
        }
        final angle = offset.clamp(-1.0, 1.0) * math.pi / 5;
        return Transform(
          alignment: offset > 0 ? Alignment.centerRight : Alignment.centerLeft,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(-angle),
          child: child,
        );
      },
    );
  }
}

// ── Shared pieces ────────────────────────────────────────────────────────────

/// A page's heading: a small kicker over a large title.
class _PageHeading extends StatelessWidget {
  const _PageHeading({required this.kicker, required this.title});

  final String kicker;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(kicker.toUpperCase(),
            style: const TextStyle(
                color: _gold,
                fontSize: 11,
                letterSpacing: 2.4,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(title,
            style: const TextStyle(
                color: _ink,
                fontSize: 28,
                height: 1.15,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Container(width: 48, height: 3, color: _gold),
        const SizedBox(height: 18),
      ],
    );
  }
}

class _PageBody extends StatelessWidget {
  const _PageBody({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// A post's picture: its first photo, or the reel's cover, or a reel tile.
class _PostPicture extends StatelessWidget {
  const _PostPicture({required this.post, this.radius = 14});

  final TourPostItem post;
  final double radius;

  String? get _url {
    if (!post.isReel && post.images.isNotEmpty) return post.images.first;
    final cover = post.coverUrl;
    if (cover != null && isRemoteMediaUrl(cover)) return cover;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    final picture = url == null
        ? (post.isReel && post.videoUrl != null && isRemoteMediaUrl(post.videoUrl!)
            ? ReelThumbnailPreview(videoUrl: post.videoUrl!)
            : const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF5B2A86), Color(0xFFB4452F)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                    child: Icon(Icons.play_circle_fill_rounded,
                        color: Colors.white70, size: 40)),
              ))
        : CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            placeholder: (_, __) => const ColoredBox(color: Color(0xFF2A231C)),
            errorWidget: (_, __, ___) => const ColoredBox(
              color: Color(0xFF2A231C),
              child: Center(
                  child: Icon(Icons.broken_image_outlined, color: _muted)),
            ),
          );

    return GestureDetector(
      onTap: url == null ? null : () => _openPhoto(context, url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            picture,
            if (post.isReel && url != null)
              const Center(
                  child: Icon(Icons.play_circle_fill_rounded,
                      color: Colors.white70, size: 40)),
          ],
        ),
      ),
    );
  }
}

void _openPhoto(BuildContext context, String url) {
  final l10n = context.l10n;
  showDialog<void>(
    context: context,
    barrierColor: Colors.black,
    builder: (ctx) => Stack(
      children: [
        Positioned.fill(
          child: InteractiveViewer(
            maxScale: 5,
            child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: SafeArea(
            child: IconButton(
              tooltip: l10n.translate('mag_close'),
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
          ),
        ),
      ],
    ),
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.photo, this.size = 44});

  final String name;
  final String? photo;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = photo;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: _gold,
      backgroundImage: url != null && isRemoteMediaUrl(url)
          ? CachedNetworkImageProvider(url)
          : null,
      child: url != null && isRemoteMediaUrl(url)
          ? null
          : Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style:
                  const TextStyle(color: _paper, fontWeight: FontWeight.w800)),
    );
  }
}

String _taka(AppLocalizations l10n, int paisa) =>
    l10n.translate('mag_taka', args: {'amount': l10n.number(paisa ~/ 100)});

// ── Pages ────────────────────────────────────────────────────────────────────

class _CoverPage extends StatelessWidget {
  const _CoverPage({
    required this.issue,
    required this.group,
    required this.travellers,
  });

  final ScrapbookIssue issue;
  final TourGroup? group;
  final int travellers;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final g = group;
    final cover = issue.coverPost;
    final year = (g?.startDate ?? DateTime.now()).year;
    final dates = g == null
        ? l10n.translate('scrap_cover_subtitle')
        : '${DateFormat('d MMM').format(g.startDate)} – ${DateFormat('d MMM yyyy').format(g.endDate)} · ${g.durationText}';

    return Stack(
      fit: StackFit.expand,
      children: [
        if (cover != null)
          _PostPicture(post: cover, radius: 0)
        else
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF8D4B00), Color(0xFF3E1F00), _paper],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        // Darkens the photo top and bottom so the cover lines stay readable.
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, 0.3, 0.55, 1],
                colors: [
                  Color(0xCC000000),
                  Color(0x22000000),
                  Color(0x33000000),
                  Color(0xF0000000),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('BHROMON',
                  style: TextStyle(
                      color: _ink,
                      fontSize: 44,
                      height: 1,
                      letterSpacing: 6,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(
                l10n.translate('mag_issue', args: {
                  'year': l10n.number(year),
                  'destination': g?.destination ??
                      l10n.translate('scrap_destination_unknown'),
                }).toUpperCase(),
                style: const TextStyle(
                    color: _gold,
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                g?.name ?? l10n.translate('scrap_default_name'),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    height: 1.1,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(dates, style: const TextStyle(color: _ink, fontSize: 13)),
              const SizedBox(height: 14),
              Text(
                issue.isEmpty
                    ? l10n.translate('mag_empty_cover')
                    : l10n.translate('mag_cover_line', args: {
                        'photos': l10n.number(issue.stats.photos),
                        'places': l10n.number(issue.stats.places),
                        'travellers': l10n.number(travellers),
                      }),
                style: const TextStyle(
                    color: _gold, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NumbersPage extends StatelessWidget {
  const _NumbersPage({required this.stats});

  final ScrapbookStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tiles = <(String, String, IconData)>[
      (
        l10n.number(stats.photos),
        l10n.translate('mag_stat_photos'),
        Icons.photo_camera_rounded
      ),
      (
        l10n.number(stats.reels),
        l10n.translate('mag_stat_reels'),
        Icons.movie_rounded
      ),
      (
        l10n.number(stats.likes),
        l10n.translate('mag_stat_likes'),
        Icons.favorite_rounded
      ),
      (
        l10n.number(stats.comments),
        l10n.translate('mag_stat_comments'),
        Icons.chat_bubble_rounded
      ),
      (
        l10n.number(stats.places),
        l10n.translate('mag_stat_places'),
        Icons.place_rounded
      ),
      (
        l10n.number(stats.contributors),
        l10n.translate('mag_stat_contributors'),
        Icons.edit_note_rounded
      ),
      if (stats.days > 0)
        (
          l10n.number(stats.days),
          l10n.translate('mag_stat_days'),
          Icons.calendar_month_rounded
        ),
    ];

    return _PageBody(children: [
      _PageHeading(
          kicker: l10n.translate('mag_kicker_numbers'),
          title: l10n.translate('mag_in_numbers')),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final t in tiles)
            SizedBox(
              width: 150,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _gold.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(t.$3, color: _gold, size: 20),
                    const SizedBox(height: 8),
                    Text(t.$1,
                        style: const TextStyle(
                            color: _ink,
                            fontSize: 30,
                            fontWeight: FontWeight.w900)),
                    Text(t.$2,
                        style: const TextStyle(color: _muted, fontSize: 12)),
                  ],
                ),
              ),
            ),
        ],
      ),
      if (stats.spentPaisa > 0) ...[
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF3E2A10), Color(0xFF1E160C)]),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.translate('mag_stat_spent'),
                  style: const TextStyle(color: _muted, fontSize: 12)),
              const SizedBox(height: 4),
              Text(_taka(l10n, stats.spentPaisa),
                  style: const TextStyle(
                      color: _gold, fontSize: 34, fontWeight: FontWeight.w900)),
              if (stats.topSpendCategory != null)
                Text(
                    l10n.translate('mag_spent_top',
                        args: {'category': stats.topSpendCategory!}),
                    style: const TextStyle(color: _ink, fontSize: 13)),
            ],
          ),
        ),
      ],
    ]);
  }
}

class _YourPage extends StatelessWidget {
  const _YourPage({required this.recap});

  final ScrapbookRecap recap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final best = recap.bestPost;
    return _PageBody(children: [
      _PageHeading(
          kicker: l10n.translate('mag_kicker_you'),
          title: l10n.translate('mag_your_page')),
      Text(
        l10n.translate('mag_your_line', args: {
          'posts': l10n.number(recap.posts),
          'likes': l10n.number(recap.likesReceived),
          'comments': l10n.number(recap.commentsReceived),
        }),
        style: const TextStyle(color: _ink, fontSize: 16, height: 1.4),
      ),
      if (recap.places > 0) ...[
        const SizedBox(height: 6),
        Text(
            l10n.translate('mag_your_places',
                args: {'count': l10n.number(recap.places)}),
            style: const TextStyle(color: _muted, fontSize: 13)),
      ],
      if (best != null && best.hasRemoteMedia) ...[
        const SizedBox(height: 20),
        Text(l10n.translate('mag_your_best'),
            style: const TextStyle(
                color: _gold, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        AspectRatio(aspectRatio: 4 / 3, child: _PostPicture(post: best)),
      ],
      if (recap.awards.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text(l10n.translate('mag_your_awards'),
            style: const TextStyle(
                color: _gold, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final kind in recap.awards)
              Chip(
                avatar: const Icon(Icons.emoji_events_rounded,
                    color: _paper, size: 18),
                backgroundColor: _gold,
                label: Text(l10n.translate(_awardTitleKey(kind)),
                    style: const TextStyle(
                        color: _paper, fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      ],
      const SizedBox(height: 20),
      Text(l10n.translate('mag_your_nudge'),
          style: const TextStyle(
              color: _muted, fontSize: 12, fontStyle: FontStyle.italic)),
    ]);
  }
}

class _ChapterPage extends StatelessWidget {
  const _ChapterPage({required this.chapter, required this.number});

  final ScrapbookChapter chapter;
  final int number;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hero = chapter.hero;
    final title = chapter.day?.label ??
        '${l10n.translate('mag_chapter_extra')} · ${DateFormat('d MMM').format(chapter.date)}';
    final quote = chapter.posts
        .map((p) => p.caption.replaceAll(RegExp(r'#\S+'), '').trim())
        .firstWhere((c) => c.length >= 20, orElse: () => '');

    return _PageBody(children: [
      _PageHeading(
          kicker:
              l10n.translate('mag_chapter', args: {'n': l10n.number(number)}),
          title: title),
      Text(
        l10n.translate('mag_chapter_line', args: {
          'posts': l10n.number(chapter.posts.length),
          'likes': l10n.number(chapter.likes),
        }),
        style: const TextStyle(color: _muted, fontSize: 12),
      ),
      const SizedBox(height: 14),
      if (hero == null)
        Text(l10n.translate('mag_chapter_no_media'),
            style: const TextStyle(color: _muted, fontSize: 13))
      else ...[
        AspectRatio(aspectRatio: 4 / 3, child: _PostPicture(post: hero)),
        if (hero.caption.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(hero.caption,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _ink, fontSize: 13, height: 1.4)),
        ],
        Text('— ${hero.authorName}',
            style: const TextStyle(color: _gold, fontSize: 12)),
      ],
      if (chapter.gallery.isNotEmpty) ...[
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: chapter.gallery.length == 1 ? 1 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: chapter.gallery.length == 1 ? 16 / 9 : 1,
          children: [
            for (final p in chapter.gallery) _PostPicture(post: p, radius: 10),
          ],
        ),
      ],
      if (quote.isNotEmpty && quote != hero?.caption.trim()) ...[
        const SizedBox(height: 18),
        _PullQuote(text: quote),
      ],
      if (chapter.places.isNotEmpty) ...[
        const SizedBox(height: 16),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final place in chapter.places)
              Chip(
                avatar: const Icon(Icons.place_rounded, color: _gold, size: 16),
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                side: BorderSide(color: _gold.withValues(alpha: 0.3)),
                label: Text(place,
                    style: const TextStyle(color: _ink, fontSize: 12)),
              ),
          ],
        ),
      ],
    ]);
  }
}

class _PullQuote extends StatelessWidget {
  const _PullQuote({required this.text, this.author});

  final String text;
  final String? author;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 14),
      decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: _gold, width: 3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('“$text”',
              style: const TextStyle(
                  color: _ink,
                  fontSize: 18,
                  height: 1.4,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w600)),
          if (author != null) ...[
            const SizedBox(height: 6),
            Text('— $author',
                style: const TextStyle(color: _gold, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class _MomentsPage extends StatelessWidget {
  const _MomentsPage({required this.posts});

  final List<TourPostItem> posts;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _PageBody(children: [
      _PageHeading(
          kicker: l10n.translate('mag_kicker_moments'),
          title: l10n.translate('mag_top_moments')),
      for (var i = 0; i < posts.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 34,
                child: Text(l10n.number(i + 1),
                    style: const TextStyle(
                        color: _gold,
                        fontSize: 28,
                        fontWeight: FontWeight.w900)),
              ),
              SizedBox(
                  width: 96,
                  height: 96,
                  child: _PostPicture(post: posts[i], radius: 10)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      posts[i].caption.trim().isEmpty
                          ? posts[i].authorName
                          : posts[i].caption,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(posts[i].authorName,
                        style: const TextStyle(color: _muted, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      l10n.translate('mag_moment_line', args: {
                        'likes': l10n.number(posts[i].likes.length),
                        'comments': l10n.number(posts[i].commentCount),
                      }),
                      style: const TextStyle(color: _gold, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    ]);
  }
}

class _QuotesPage extends StatelessWidget {
  const _QuotesPage({required this.quotes});

  final List<ScrapbookQuote> quotes;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _PageBody(children: [
      _PageHeading(
          kicker: l10n.translate('mag_kicker_quotes'),
          title: l10n.translate('mag_quotes')),
      for (final q in quotes) ...[
        _PullQuote(text: q.text, author: q.authorName),
        const SizedBox(height: 26),
      ],
    ]);
  }
}

String _awardTitleKey(ScrapbookAwardKind kind) => switch (kind) {
      ScrapbookAwardKind.photographer => 'mag_award_photographer',
      ScrapbookAwardKind.reelStar => 'mag_award_reel_star',
      ScrapbookAwardKind.crowdFavourite => 'mag_award_crowd_favourite',
      ScrapbookAwardKind.storyteller => 'mag_award_storyteller',
      ScrapbookAwardKind.conversationStarter => 'mag_award_conversation',
      ScrapbookAwardKind.explorer => 'mag_award_explorer',
      ScrapbookAwardKind.mostTagged => 'mag_award_most_tagged',
    };

String _awardDetailKey(ScrapbookAwardKind kind) =>
    '${_awardTitleKey(kind)}_detail';

IconData _awardIcon(ScrapbookAwardKind kind) => switch (kind) {
      ScrapbookAwardKind.photographer => Icons.photo_camera_rounded,
      ScrapbookAwardKind.reelStar => Icons.movie_filter_rounded,
      ScrapbookAwardKind.crowdFavourite => Icons.favorite_rounded,
      ScrapbookAwardKind.storyteller => Icons.auto_stories_rounded,
      ScrapbookAwardKind.conversationStarter => Icons.forum_rounded,
      ScrapbookAwardKind.explorer => Icons.explore_rounded,
      ScrapbookAwardKind.mostTagged => Icons.people_alt_rounded,
    };

/// Every key the awards read, for the translation test.
@visibleForTesting
List<String> scrapbookAwardKeys() => [
      for (final kind in ScrapbookAwardKind.values) ...[
        _awardTitleKey(kind),
        _awardDetailKey(kind),
      ],
    ];

class _AwardsPage extends StatelessWidget {
  const _AwardsPage({required this.awards});

  final List<ScrapbookAward> awards;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _PageBody(children: [
      _PageHeading(
          kicker: l10n.translate('mag_kicker_awards'),
          title: l10n.translate('mag_awards')),
      for (final a in awards)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _gold.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _Avatar(name: a.winnerName, photo: a.winnerPhoto, size: 52),
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: CircleAvatar(
                      radius: 12,
                      backgroundColor: _gold,
                      child: Icon(_awardIcon(a.kind), size: 14, color: _paper),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.translate(_awardTitleKey(a.kind)).toUpperCase(),
                        style: const TextStyle(
                            color: _gold,
                            fontSize: 11,
                            letterSpacing: 1.6,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(a.winnerName,
                        style: const TextStyle(
                            color: _ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w800)),
                    Text(
                        l10n.translate(_awardDetailKey(a.kind),
                            args: {'value': l10n.number(a.value)}),
                        style: const TextStyle(color: _muted, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
    ]);
  }
}

class _PlacesPage extends StatelessWidget {
  const _PlacesPage({required this.places});

  final List<ScrapbookPlace> places;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _PageBody(children: [
      _PageHeading(
          kicker: l10n.translate('mag_kicker_route'),
          title: l10n.translate('mag_places')),
      for (var i = 0; i < places.length; i++)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 28,
                child: Column(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      margin: const EdgeInsets.only(top: 3),
                      decoration: BoxDecoration(
                        color:
                            i == 0 || i == places.length - 1 ? _gold : _paper,
                        shape: BoxShape.circle,
                        border: Border.all(color: _gold, width: 2),
                      ),
                    ),
                    if (i < places.length - 1)
                      Expanded(
                          child: Container(
                              width: 2, color: _gold.withValues(alpha: 0.4))),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(places[i].name,
                          style: const TextStyle(
                              color: _ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      Text(
                        '${DateFormat('d MMM, h:mm a').format(places[i].firstVisit)} · ${l10n.translate('mag_place_line', args: {
                              'count': l10n.number(places[i].posts)
                            })}',
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
    ]);
  }
}

class _BackCoverPage extends StatelessWidget {
  const _BackCoverPage({required this.travellers, required this.onShare});

  final int travellers;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _PageBody(children: [
      _PageHeading(
          kicker: l10n.translate('mag_kicker_thanks'),
          title: l10n.translate('scrap_honor_roll')),
      Text(l10n.translate('scrap_honor_text'),
          style: const TextStyle(color: _ink, fontSize: 14, height: 1.6)),
      const SizedBox(height: 22),
      Text(
          l10n.translate('mag_made_by',
              args: {'travellers': l10n.number(travellers)}),
          style: const TextStyle(
              color: _gold, fontSize: 13, fontWeight: FontWeight.w700)),
      const SizedBox(height: 22),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: _gold,
            foregroundColor: _paper,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: onShare,
          icon: const Icon(Icons.share_rounded),
          label: Text(l10n.translate('scrap_share_button'),
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ),
    ]);
  }
}
