import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/colors.dart';
import '../../data/news_tts_service.dart';
import '../../data/newspaper_service.dart';
import '../../domain/models/newspaper_models.dart';
import 'adfree_article_reader_screen.dart';
import 'adblock_browser_screen.dart';

class NewspaperHubScreen extends StatefulWidget {
  final String? initialCategory;
  final String? initialPaperId;

  const NewspaperHubScreen({
    super.key,
    this.initialCategory,
    this.initialPaperId,
  });

  @override
  State<NewspaperHubScreen> createState() => _NewspaperHubScreenState();
}

class _NewspaperHubScreenState extends State<NewspaperHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final NewspaperService _service = NewspaperService();
  final NewsTtsService _ttsService = NewsTtsService();

  final TextEditingController _headlineSearchCtrl = TextEditingController();
  final TextEditingController _paperSearchCtrl = TextEditingController();

  List<NewsHeadline> _headlines = [];
  List<StoryCluster> _clusters = [];
  List<Newspaper> _allPapers = [];
  Set<String> _favoritePaperIds = {};
  List<String> _continueReadingIds = [];
  Map<String, NewsHeadline> _bookmarks = {};

  bool _isLoadingHeadlines = true;
  bool _isLoadingPapers = true;
  bool _isRefreshing = false;
  String _selectedCategory = 'all';
  String? _selectedPaperId;
  String? _currentlySpeakingId;

  final List<Map<String, String>> _categories = const [
    {'id': 'all', 'label': 'All', 'labelBn': 'সব'},
    {'id': 'bangla_dailies', 'label': 'Bangla dailies', 'labelBn': 'বাংলা পত্রিকা'},
    {'id': 'english_dailies', 'label': 'English dailies', 'labelBn': 'ইংরেজি পত্রিকা'},
    {'id': 'online_portals', 'label': 'Online portals', 'labelBn': 'অনলাইন পোর্টাল'},
    {'id': 'world_tech', 'label': 'World & Tech', 'labelBn': 'আন্তর্জাতিক ও প্রযুক্তি'},
    {'id': 'sports', 'label': 'Sports', 'labelBn': 'খেলাধুলা'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _selectedCategory = widget.initialCategory ?? 'all';
    _selectedPaperId = widget.initialPaperId;

    _loadUserData();
    _loadHeadlines();
    _loadPapers();

    _ttsService.currentPlayingIdNotifier.addListener(_onTtsChange);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _headlineSearchCtrl.dispose();
    _paperSearchCtrl.dispose();
    _ttsService.currentPlayingIdNotifier.removeListener(_onTtsChange);
    super.dispose();
  }

  void _onTtsChange() {
    if (mounted) {
      setState(() {
        _currentlySpeakingId = _ttsService.currentPlayingIdNotifier.value;
      });
    }
  }

  Future<void> _loadUserData() async {
    final favs = await _service.getFavoritePaperIds();
    final cont = await _service.getContinueReadingIds();
    final bmarks = await _service.getBookmarkedHeadlines();
    if (mounted) {
      setState(() {
        _favoritePaperIds = favs;
        _continueReadingIds = cont;
        _bookmarks = bmarks;
      });
    }
  }

  Future<void> _loadHeadlines({bool refresh = false}) async {
    setState(() {
      if (refresh) {
        _isRefreshing = true;
      } else {
        _isLoadingHeadlines = true;
      }
    });

    final res = await _service.fetchHeadlines(
      category: _selectedCategory,
      paperId: _selectedPaperId,
      query: _headlineSearchCtrl.text,
      refresh: refresh,
    );

    if (mounted) {
      setState(() {
        _headlines = res.items;
        _clusters = res.clusters;
        _isLoadingHeadlines = false;
        _isRefreshing = false;
      });
    }
  }

  Future<void> _loadPapers() async {
    setState(() => _isLoadingPapers = true);
    final papers = await _service.fetchNewspapers();
    if (mounted) {
      setState(() {
        _allPapers = papers;
        _isLoadingPapers = false;
      });
    }
  }

  void _onCategorySelected(String categoryId) {
    if (_selectedCategory == categoryId) return;
    setState(() {
      _selectedCategory = categoryId;
      _selectedPaperId = null;
    });
    _loadHeadlines();
  }

  void _onPaperFilterSelected(String? paperId) {
    setState(() {
      _selectedPaperId = paperId;
    });
    _loadHeadlines();
  }

  void _toggleFavorite(String paperId) async {
    await _service.toggleFavoritePaper(paperId);
    final favs = await _service.getFavoritePaperIds();
    if (mounted) {
      setState(() => _favoritePaperIds = favs);
    }
  }

  void _toggleBookmark(NewsHeadline headline) async {
    await _service.toggleBookmarkHeadline(headline);
    final bmarks = await _service.getBookmarkedHeadlines();
    if (mounted) {
      setState(() => _bookmarks = bmarks);
    }
  }

  void _openArticleReader(NewsHeadline headline) {
    _service.recordPaperRead(headline.paperId);
    _loadUserData();

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdFreeArticleReaderScreen(
          articleUrl: headline.articleUrl,
          initialTitle: headline.title,
          initialSourceName: headline.paperName,
          initialImageUrl: headline.imageUrl,
        ),
      ),
    );
  }

  void _openAdBlockBrowser({required String url, required String title, Newspaper? paper}) {
    if (paper != null) {
      _service.recordPaperRead(paper.id);
      _loadUserData();
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdBlockBrowserScreen(
          initialUrl: url,
          initialTitle: title,
          paper: paper,
        ),
      ),
    );
  }

  void _speakHeadline(NewsHeadline headline) {
    final textToSpeak = '${headline.paperName}. ${headline.title}. ${headline.snippet}';
    _ttsService.speak(id: headline.id, text: textToSpeak);
  }

  void _showClusterDetailsModal(StoryCluster cluster) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1B1F24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.layers_rounded, color: AppColors.mintGreen, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Same story, different papers',
                    style: TextStyle(
                      color: AppColors.mintGreen,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                cluster.topic,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${cluster.papers.length} publications covering this story • Tap to read ad-free',
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Divider(color: Colors.white.withOpacity(0.1)),
              Expanded(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: cluster.items.length,
                  separatorBuilder: (_, __) => Divider(color: Colors.white.withOpacity(0.08)),
                  itemBuilder: (context, idx) {
                    final item = cluster.items[idx];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: AppColors.mintGreen.withOpacity(0.15),
                        child: Text(
                          item.paperName.isNotEmpty ? item.paperName[0].toUpperCase() : 'N',
                          style: const TextStyle(
                            color: AppColors.mintGreen,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        item.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${item.paperName} • ${item.relativeTime}',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.white38),
                      onTap: () {
                        Navigator.pop(context);
                        _openArticleReader(item);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      appBar: AppBar(
        backgroundColor: const Color(0xFF14181E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Newspaper Hub',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.mintGreen,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Ad-Free Live Headlines & Directory',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.mintGreen),
                  )
                : const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: () => _loadHeadlines(refresh: true),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.mintGreen,
          indicatorWeight: 3,
          labelColor: AppColors.mintGreen,
          unselectedLabelColor: Colors.white54,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: const [
            Tab(text: 'Live headlines'),
            Tab(text: 'All newspapers'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLiveHeadlinesTab(),
          _buildAllNewspapersTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.mintGreen,
        foregroundColor: Colors.black,
        tooltip: 'Quick Refresh & Pulse',
        child: const Icon(Icons.bolt_rounded, size: 26),
        onPressed: () => _loadHeadlines(refresh: true),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Tab 1: Live Headlines
  // -------------------------------------------------------------------------

  Widget _buildLiveHeadlinesTab() {
    return RefreshIndicator(
      color: AppColors.mintGreen,
      backgroundColor: const Color(0xFF1B1F24),
      onRefresh: () => _loadHeadlines(refresh: true),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        children: [
          // Search Bar across all papers
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1B1F24),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: TextField(
              controller: _headlineSearchCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search headlines across all papers',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54, size: 20),
                suffixIcon: _headlineSearchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 18),
                        onPressed: () {
                          _headlineSearchCtrl.clear();
                          _loadHeadlines();
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
              onSubmitted: (_) => _loadHeadlines(),
            ),
          ),
          const SizedBox(height: 14),

          // Categories horizontal chips
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, idx) {
                final cat = _categories[idx];
                final isSelected = _selectedCategory == cat['id'];
                return ChoiceChip(
                  label: Text(cat['label']!),
                  selected: isSelected,
                  selectedColor: AppColors.mintGreen,
                  backgroundColor: const Color(0xFF1B1F24),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.black : Colors.white70,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isSelected ? AppColors.mintGreen : Colors.white.withOpacity(0.1),
                    ),
                  ),
                  onSelected: (_) => _onCategorySelected(cat['id']!),
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // Status Indicator Row (Matching reference screen)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.mintGreen,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Updated Just now',
                  style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                const Text('•', style: TextStyle(color: Colors.white38)),
                const SizedBox(width: 8),
                Text(
                  '${_headlines.length} live stories',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Topic Clustering Feature Card ("Same story, different papers")
          if (_clusters.isNotEmpty && _selectedPaperId == null) ...[
            _buildStoryClusterCard(_clusters.first),
            const SizedBox(height: 20),
          ],

          // Active Paper Filter Chip (if selected)
          if (_selectedPaperId != null) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  const Text('Filtering by: ', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  Chip(
                    backgroundColor: AppColors.mintGreen.withOpacity(0.15),
                    label: Text(
                      _selectedPaperId!,
                      style: const TextStyle(color: AppColors.mintGreen, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    deleteIcon: const Icon(Icons.close_rounded, size: 16, color: AppColors.mintGreen),
                    onDeleted: () => _onPaperFilterSelected(null),
                  ),
                ],
              ),
            ),
          ],

          // Latest Headlines Section Header
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text(
              'Latest headlines',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Headlines List
          if (_isLoadingHeadlines && !_isRefreshing)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(color: AppColors.mintGreen),
              ),
            )
          else if (_headlines.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    const Icon(Icons.article_rounded, size: 48, color: Colors.white24),
                    const SizedBox(height: 12),
                    const Text(
                      'কোনো শিরোনাম পাওয়া যায়নি',
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: AppColors.mintGreen),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('পুনরায় লোড করুন'),
                      onPressed: () => _loadHeadlines(refresh: true),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._headlines.map((item) => _buildHeadlineCard(item)),

          const SizedBox(height: 60),
        ],
      ),
    );
  }

  Widget _buildStoryClusterCard(StoryCluster cluster) {
    return InkWell(
      onTap: () => _showClusterDetailsModal(cluster),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1B222C),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.mintGreen.withOpacity(0.25)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.layers_rounded, color: AppColors.mintGreen, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Same story, different papers',
                  style: TextStyle(
                    color: AppColors.mintGreen,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.mintGreen.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_clusters.length} stories',
                    style: const TextStyle(color: AppColors.mintGreen, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              cluster.topic,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.compare_arrows_rounded, size: 14, color: Colors.white70),
                      const SizedBox(width: 6),
                      Text(
                        '${cluster.papers.length} papers • Tap to compare coverage',
                        style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeadlineCard(NewsHeadline item) {
    final isSpeakingThis = _currentlySpeakingId == item.id;
    final isBookmarked = _bookmarks.containsKey(item.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF14181E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openArticleReader(item),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: Source badge, Relative time, TTS speaker icon
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.paperName,
                        style: const TextStyle(
                          color: AppColors.mintGreen,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item.relativeTime,
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    const Spacer(),
                    // TTS Audio Speaker Button
                    IconButton(
                      iconSize: 18,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      tooltip: isSpeakingThis ? 'Stop Audio' : 'Listen Headline (TTS)',
                      icon: Icon(
                        isSpeakingThis ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                        color: isSpeakingThis ? AppColors.mintGreen : Colors.white54,
                      ),
                      onPressed: () => _speakHeadline(item),
                    ),
                    // Bookmark toggle
                    IconButton(
                      iconSize: 18,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      tooltip: isBookmarked ? 'Remove Bookmark' : 'Bookmark Story',
                      icon: Icon(
                        isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                        color: isBookmarked ? AppColors.mintGreen : Colors.white54,
                      ),
                      onPressed: () => _toggleBookmark(item),
                    ),
                    // Open in Ad-Blocker Web Browser
                    IconButton(
                      iconSize: 18,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      tooltip: 'Open in AdBlock Browser',
                      icon: const Icon(
                        Icons.public_rounded,
                        color: Colors.white54,
                      ),
                      onPressed: () => _openAdBlockBrowser(
                        url: item.articleUrl,
                        title: item.title,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Main Content: Title + optional Thumbnail
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              height: 1.35,
                            ),
                          ),
                          if (item.snippet.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              item.snippet,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12.5,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (item.imageUrl != null && item.imageUrl!.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: CachedNetworkImage(
                          imageUrl: item.imageUrl!,
                          width: 84,
                          height: 72,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            width: 84,
                            height: 72,
                            color: Colors.white10,
                          ),
                          errorWidget: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Tab 2: All Newspapers Directory & Bookmarks
  // -------------------------------------------------------------------------

  Widget _buildAllNewspapersTab() {
    final query = _paperSearchCtrl.text.trim().toLowerCase();
    final filteredPapers = _allPapers.where((p) {
      if (query.isEmpty) return true;
      return p.name.toLowerCase().contains(query) ||
          p.nameBn.toLowerCase().contains(query) ||
          p.domain.toLowerCase().contains(query);
    }).toList();

    // Group by category
    final Map<String, List<Newspaper>> grouped = {};
    for (final p in filteredPapers) {
      grouped.putIfAbsent(p.category, () => []).add(p);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      children: [
        // Continue Reading Section (Matching reference screen 2)
        if (_continueReadingIds.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              'Continue reading',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _continueReadingIds.map((paperId) {
              final paper = _allPapers.firstWhere(
                (p) => p.id == paperId,
                orElse: () => Newspaper(
                  id: paperId,
                  name: paperId.replaceAll('_', ' ').toUpperCase(),
                  nameBn: '',
                  domain: '',
                  category: '',
                  websiteUrl: '',
                ),
              );

              return ActionChip(
                avatar: const Icon(Icons.bookmark_rounded, size: 14, color: AppColors.mintGreen),
                label: Text(paper.name),
                backgroundColor: const Color(0xFF1B1F24),
                labelStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
                onPressed: () {
                  if (paper.websiteUrl.isNotEmpty) {
                    _openAdBlockBrowser(
                      url: paper.websiteUrl,
                      title: paper.name,
                      paper: paper,
                    );
                  } else {
                    _onPaperFilterSelected(paper.id);
                    _tabController.animateTo(0);
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
        ],

        // Search Newspapers Input
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1B1F24),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: TextField(
            controller: _paperSearchCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search newspapers',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54, size: 20),
              suffixIcon: _paperSearchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 18),
                      onPressed: () {
                        setState(() => _paperSearchCtrl.clear());
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 18),

        // Directory Sections
        if (_isLoadingPapers)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(color: AppColors.mintGreen),
            ),
          )
        else ...[
          _buildCategorySection('BANGLA DAILIES', grouped['bangla_dailies'] ?? []),
          _buildCategorySection('ENGLISH DAILIES', grouped['english_dailies'] ?? []),
          _buildCategorySection('ONLINE PORTALS', grouped['online_portals'] ?? []),
          _buildCategorySection('WORLD & TECH', grouped['world_tech'] ?? []),
          _buildCategorySection('SPORTS & OTHERS', grouped['sports'] ?? []),
        ],

        const SizedBox(height: 60),
      ],
    );
  }

  Widget _buildCategorySection(String title, List<Newspaper> papers) {
    if (papers.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
        ),
        ...papers.map((p) => _buildNewspaperTile(p)),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildNewspaperTile(Newspaper paper) {
    final isFav = _favoritePaperIds.contains(paper.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF14181E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            _openAdBlockBrowser(
              url: paper.websiteUrl,
              title: paper.name,
              paper: paper,
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.mintGreen.withOpacity(0.25),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      paper.name.isNotEmpty ? paper.name[0].toUpperCase() : 'N',
                      style: const TextStyle(
                        color: AppColors.mintGreen,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              paper.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: AppColors.mintGreen.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.shield_rounded,
                                    size: 10, color: AppColors.mintGreen),
                                SizedBox(width: 3),
                                Text(
                                  'AD-FREE',
                                  style: TextStyle(
                                    color: AppColors.mintGreen,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        paper.nameBn.isNotEmpty
                            ? '${paper.nameBn} • ${paper.domain}'
                            : paper.domain,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                // Action: Filter headlines
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    _onPaperFilterSelected(paper.id);
                    _tabController.animateTo(0);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.feed_outlined,
                            size: 13, color: Colors.white70),
                        SizedBox(width: 4),
                        Text(
                          'খবর',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Favorite toggle
                IconButton(
                  iconSize: 20,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: isFav ? Colors.amber : Colors.white38,
                  ),
                  onPressed: () => _toggleFavorite(paper.id),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
