import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/colors.dart';
import '../../data/news_tts_service.dart';
import '../../data/newspaper_service.dart';
import '../../domain/models/newspaper_models.dart';
import 'adblock_browser_screen.dart';

enum ReaderTheme { light, sepia, dark }

class AdFreeArticleReaderScreen extends StatefulWidget {
  final String articleUrl;
  final String? initialTitle;
  final String? initialSourceName;
  final String? initialImageUrl;

  const AdFreeArticleReaderScreen({
    super.key,
    required this.articleUrl,
    this.initialTitle,
    this.initialSourceName,
    this.initialImageUrl,
  });

  @override
  State<AdFreeArticleReaderScreen> createState() => _AdFreeArticleReaderScreenState();
}

class _AdFreeArticleReaderScreenState extends State<AdFreeArticleReaderScreen> {
  final NewspaperService _service = NewspaperService();
  final NewsTtsService _ttsService = NewsTtsService();

  CleanArticle? _article;
  bool _isLoading = true;
  String? _errorMessage;

  double _fontSize = 17.0;
  ReaderTheme _readerTheme = ReaderTheme.dark;
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
    _loadArticle();
    _ttsService.isPlayingNotifier.addListener(_onTtsStateChanged);
  }

  @override
  void dispose() {
    _ttsService.isPlayingNotifier.removeListener(_onTtsStateChanged);
    _ttsService.stop();
    super.dispose();
  }

  void _onTtsStateChanged() {
    if (mounted) {
      setState(() {
        _isSpeaking = _ttsService.isPlayingNotifier.value;
      });
    }
  }

  Future<void> _loadArticle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final article = await _service.fetchCleanArticle(widget.articleUrl);
      if (mounted) {
        setState(() {
          _article = article;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _toggleTts() {
    if (_article == null) return;
    if (_isSpeaking) {
      _ttsService.stop();
      setState(() => _isSpeaking = false);
    } else {
      // Build reading narration: title + paragraphs
      final StringBuffer narration = StringBuffer();
      narration.writeln(_article!.title);
      narration.writeln('. ');
      for (final p in _article!.paragraphs) {
        narration.writeln(p);
        narration.writeln('. ');
      }
      _ttsService.speak(
        id: 'article_${widget.articleUrl.hashCode}',
        text: narration.toString(),
      );
    }
  }

  void _increaseFont() {
    if (_fontSize < 28.0) {
      setState(() => _fontSize += 1.5);
    }
  }

  void _decreaseFont() {
    if (_fontSize > 13.0) {
      setState(() => _fontSize -= 1.5);
    }
  }

  Color get _backgroundColor {
    switch (_readerTheme) {
      case ReaderTheme.light:
        return const Color(0xFFFAFAFA);
      case ReaderTheme.sepia:
        return const Color(0xFFFBF0D9);
      case ReaderTheme.dark:
        return const Color(0xFF121417);
    }
  }

  Color get _textColor {
    switch (_readerTheme) {
      case ReaderTheme.light:
        return const Color(0xFF1E293B);
      case ReaderTheme.sepia:
        return const Color(0xFF4A3B2C);
      case ReaderTheme.dark:
        return const Color(0xFFE2E8F0);
      }
  }

  Color get _subTextColor {
    switch (_readerTheme) {
      case ReaderTheme.light:
        return const Color(0xFF64748B);
      case ReaderTheme.sepia:
        return const Color(0xFF7D6752);
      case ReaderTheme.dark:
        return const Color(0xFF94A3B8);
    }
  }

  Color get _barColor {
    switch (_readerTheme) {
      case ReaderTheme.light:
        return Colors.white;
      case ReaderTheme.sepia:
        return const Color(0xFFF4E5C7);
      case ReaderTheme.dark:
        return const Color(0xFF1B1F24);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _article?.title ?? widget.initialTitle ?? 'News Article';
    final sourceName = _article?.sourceName ?? widget.initialSourceName ?? 'Newspaper';
    final heroImage = _article?.heroImageUrl ?? widget.initialImageUrl;

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _barColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: _textColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.mintGreen.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.shield_outlined, size: 14, color: AppColors.mintGreen),
              const SizedBox(width: 4),
              Text(
                sourceName,
                style: const TextStyle(
                  color: AppColors.mintGreen,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                '• Ad-Free',
                style: TextStyle(
                  color: AppColors.mintGreen,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        actions: [
          // TTS Audio narration toggle
          IconButton(
            tooltip: _isSpeaking ? 'Stop Audio' : 'Listen Article (TTS)',
            icon: Icon(
              _isSpeaking ? Icons.volume_up_rounded : Icons.volume_down_rounded,
              color: _isSpeaking ? AppColors.mintGreen : _textColor,
            ),
            onPressed: _toggleTts,
          ),
          // Font size decrease
          IconButton(
            tooltip: 'Decrease font size',
            icon: Text(
              'A-',
              style: TextStyle(
                color: _textColor,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: _decreaseFont,
          ),
          // Font size increase
          IconButton(
            tooltip: 'Increase font size',
            icon: Text(
              'A+',
              style: TextStyle(
                color: _textColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: _increaseFont,
          ),
          // Reader theme menu
          PopupMenuButton<ReaderTheme>(
            tooltip: 'Reader appearance',
            icon: Icon(Icons.palette_outlined, color: _textColor),
            color: _barColor,
            onSelected: (t) => setState(() => _readerTheme = t),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: ReaderTheme.light,
                child: Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAFAFA),
                        border: Border.all(color: Colors.grey.shade400),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text('Light (সাদা)', style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: ReaderTheme.sepia,
                child: Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFBF0D9),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text('Sepia (কাগজ)', style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: ReaderTheme.dark,
                child: Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        color: Color(0xFF121417),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text('Dark (ডার্ক)', style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
          // AdBlock Browser switcher
          IconButton(
            tooltip: 'Open in AdBlock Browser',
            icon: const Icon(Icons.public_rounded, color: AppColors.mintGreen),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AdBlockBrowserScreen(
                    initialUrl: widget.articleUrl,
                    initialTitle: title,
                  ),
                ),
              );
            },
          ),
          // Share
          IconButton(
            tooltip: 'Share',
            icon: Icon(Icons.share_rounded, color: _textColor),
            onPressed: () {
              // ignore: deprecated_member_use
              Share.share(
                '$title\n\nRead ad-free on Bhromon Newspaper Hub: ${widget.articleUrl}',
              );
            },
          ),
        ],
      ),
      body: _buildBody(title, sourceName, heroImage),
    );
  }

  Widget _buildBody(String title, String sourceName, String? heroImage) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppColors.mintGreen),
            const SizedBox(height: 16),
            Text(
              'বিজ্ঞাপনমুক্ত রিডার মোড তৈরি হচ্ছে...',
              style: TextStyle(color: _subTextColor, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: Colors.amber),
              const SizedBox(height: 12),
              Text(
                'নিবন্ধটি রিডার মোডে লোড করা যায়নি',
                style: TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'আপনি মূল ব্রাউজারে সংবাদটি পড়তে পারেন।',
                style: TextStyle(color: _subTextColor, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.mintGreen,
                  foregroundColor: Colors.black,
                ),
                icon: const Icon(Icons.open_in_browser_rounded),
                label: const Text('মূল ওয়েবসাইটে পড়ুন'),
                onPressed: () => launchUrl(Uri.parse(widget.articleUrl), mode: LaunchMode.externalApplication),
              ),
            ],
          ),
        ),
      );
    }

    final article = _article!;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Audio Playing Notification Bar
              if (_isSpeaking)
                Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.mintGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.mintGreen.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.graphic_eq_rounded, color: AppColors.mintGreen, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'নিবন্ধটি অডিওর মাধ্যমে পড়া হচ্ছে...',
                          style: TextStyle(
                            color: _textColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _toggleTts,
                        child: const Text('থামান', style: TextStyle(color: AppColors.mintGreen)),
                      ),
                    ],
                  ),
                ),

              // Title
              Text(
                article.title,
                style: TextStyle(
                  color: _textColor,
                  fontSize: _fontSize + 8,
                  fontWeight: FontWeight.w800,
                  height: 1.35,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 14),

              // Meta row
              Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: AppColors.mintGreen.withValues(alpha: 0.2),
                    child: Text(
                      sourceName.isNotEmpty ? sourceName[0].toUpperCase() : 'N',
                      style: const TextStyle(
                        color: AppColors.mintGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    sourceName,
                    style: TextStyle(
                      color: _textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (article.author.isNotEmpty) ...[
                    Text(' • ', style: TextStyle(color: _subTextColor)),
                    Expanded(
                      child: Text(
                        article.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _subTextColor, fontSize: 13),
                      ),
                    ),
                  ],
                  Text(' • ', style: TextStyle(color: _subTextColor)),
                  Text(
                    '${article.readingTimeMinutes} মিনিট পড়া',
                    style: TextStyle(color: _subTextColor, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Hero Image
              if (heroImage != null && heroImage.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: heroImage,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      height: 220,
                      color: Colors.black12,
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.mintGreen),
                      ),
                    ),
                    errorWidget: (context, url, error) => const SizedBox.shrink(),
                  ),
                ),
              if (heroImage != null && heroImage.isNotEmpty) const SizedBox(height: 24),

              // Divider
              Divider(color: _textColor.withValues(alpha: 0.08), height: 1),
              const SizedBox(height: 24),

              // Article Paragraphs
              if (article.paragraphs.isEmpty)
                Text(
                  'সংবাদটির মূল বিষয়বস্তু নিচে দেওয়া লিঙ্কে গিয়ে দেখা যাবে।',
                  style: TextStyle(color: _subTextColor, fontSize: _fontSize),
                )
              else
                ...article.paragraphs.map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Text(
                      p,
                      style: TextStyle(
                        color: _textColor,
                        fontSize: _fontSize,
                        height: 1.75,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 32),
              Divider(color: _textColor.withValues(alpha: 0.08), height: 1),
              const SizedBox(height: 24),

              // Footer: Open original web & Ad-free notice
              Center(
                child: Column(
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _textColor,
                        side: BorderSide(color: _textColor.withValues(alpha: 0.2)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      icon: const Icon(Icons.launch_rounded, size: 16),
                      label: const Text('মূল ওয়েবসাইট থেকে পড়ুন'),
                      onPressed: () => launchUrl(
                        Uri.parse(widget.articleUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.verified_user_outlined, size: 14, color: AppColors.mintGreen),
                        const SizedBox(width: 6),
                        Text(
                          'সম্পূর্ণ বিজ্ঞাপনমুক্ত ও ডেটা-সাশ্রয়ী মোড • Bhromon',
                          style: TextStyle(color: _subTextColor, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
