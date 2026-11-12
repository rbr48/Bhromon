import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/forest_palette.dart';
import '../../../../core/theme/theme_context.dart';
import '../../../chat/presentation/widgets/chat_svg_widget.dart';
import '../widgets/group_back_button.dart';

/// Represents a single economic vector diagram from the POE Exam Dynamic SVG Atlas.
class AtlasGraphItem {
  final String id;
  final int index;
  final String exam;
  final String examLabel;
  final String language;
  final String title;
  final String subtitle;
  final String headerText;
  final String svg;

  const AtlasGraphItem({
    required this.id,
    required this.index,
    required this.exam,
    required this.examLabel,
    required this.language,
    required this.title,
    required this.subtitle,
    required this.headerText,
    required this.svg,
  });

  factory AtlasGraphItem.fromJson(Map<String, dynamic> json) {
    return AtlasGraphItem(
      id: json['id'] as String? ?? '',
      index: (json['index'] as num?)?.toInt() ?? 0,
      exam: json['exam'] as String? ?? '',
      examLabel: json['examLabel'] as String? ?? '',
      language: json['language'] as String? ?? '',
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      headerText: json['headerText'] as String? ?? '',
      svg: json['svg'] as String? ?? '',
    );
  }
}

/// Dedicated interactive viewer and catalog for all 95 dynamic economics SVG graphs
/// from the 96th to 8th BPE exams (Principles of Economics — POE).
///
/// Features:
/// - Real-time filtering by exam session (96th, 97th, 98th, 99th, 5th, 6th, 7th, 8th BPE).
/// - Bilingual language switching (All, English, বাংলা).
/// - Instant keyword search across graph titles, subtitles, and concepts.
/// - Full interactive inspection with pinch-to-zoom and SVG code inspection.
/// - Direct link to open the standalone interactive HTML Atlas.
class StudyGraphAtlasScreen extends StatefulWidget {
  final String? tourId;
  final String? initialExam;
  final String? initialLanguage;

  const StudyGraphAtlasScreen({
    super.key,
    this.tourId,
    this.initialExam,
    this.initialLanguage,
  });

  static Future<void> open(
    BuildContext context, {
    String? tourId,
    String? initialExam,
    String? initialLanguage,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StudyGraphAtlasScreen(
          tourId: tourId,
          initialExam: initialExam,
          initialLanguage: initialLanguage,
        ),
      ),
    );
  }

  @override
  State<StudyGraphAtlasScreen> createState() => _StudyGraphAtlasScreenState();
}

class _StudyGraphAtlasScreenState extends State<StudyGraphAtlasScreen> {
  List<AtlasGraphItem> _allGraphs = const [];
  bool _isLoading = true;
  String? _errorMessage;

  String _selectedExam = 'all';
  String _selectedLang = 'all';
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  static const _exams = <Map<String, String>>[
    {'id': 'all', 'label': 'All Exams (সব পরীক্ষা)'},
    {'id': '96th', 'label': '96th BPE'},
    {'id': '97th', 'label': '97th BPE'},
    {'id': '98th', 'label': '98th BPE'},
    {'id': '99th', 'label': '99th BPE'},
    {'id': '5th', 'label': '5th New BPE'},
    {'id': '6th', 'label': '6th New BPE'},
    {'id': '7th', 'label': '7th New BPE'},
    {'id': '8th', 'label': '8th New BPE'},
  ];

  static const _languages = <Map<String, String>>[
    {'id': 'all', 'label': 'All (সব)'},
    {'id': 'English', 'label': 'English'},
    {'id': 'Bangla', 'label': 'বাংলা'},
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialExam != null && widget.initialExam!.isNotEmpty) {
      _selectedExam = widget.initialExam!;
    }
    if (widget.initialLanguage != null && widget.initialLanguage!.isNotEmpty) {
      _selectedLang = widget.initialLanguage!;
    }
    _loadAtlas();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAtlas() async {
    try {
      final jsonStr =
          await rootBundle.loadString('assets/study/poe_graph_atlas.json');
      final list = jsonDecode(jsonStr) as List<dynamic>;
      final items = list
          .map((e) => AtlasGraphItem.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() {
        _allGraphs = items;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load graph atlas: $e';
        _isLoading = false;
      });
    }
  }

  List<AtlasGraphItem> get _filteredGraphs {
    return _allGraphs.where((g) {
      if (_selectedExam != 'all' && g.exam != _selectedExam) {
        return false;
      }
      if (_selectedLang != 'all' && g.language != _selectedLang) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final inTitle = g.title.toLowerCase().contains(q);
        final inSubtitle = g.subtitle.toLowerCase().contains(q);
        final inExam = g.examLabel.toLowerCase().contains(q);
        if (!inTitle && !inSubtitle && !inExam) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  Future<void> _openWebAtlas() async {
    final uri = Uri.parse(
      kIsWeb
          ? '/media/atlas/poe_atlas.html'
          : 'https://bhromon.fun/media/atlas/poe_atlas.html',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final forest = context.forest;
    final filtered = _filteredGraphs;

    return Scaffold(
      backgroundColor: forest.background,
      appBar: AppBar(
        leading: GroupBackButton(tourId: widget.tourId ?? ''),
        backgroundColor: forest.feedRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Dynamic SVG Graph Atlas',
              style: TextStyle(
                color: forest.text,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '95 Vector Graphs · 96th to 8th BPE (POE)',
              style: TextStyle(
                color: forest.text54,
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser_rounded),
            tooltip: 'Open Web Edition (ওয়েব সংস্করণ)',
            color: forest.accentText,
            onPressed: _openWebAtlas,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: forest.text70),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Column(
                  children: [
                    _buildFilters(forest),
                    _buildCountBar(forest, filtered.length),
                    Expanded(
                      child: filtered.isEmpty
                          ? _buildEmptyState(forest)
                          : _buildGraphList(forest, filtered),
                    ),
                  ],
                ),
    );
  }

  Widget _buildFilters(ForestPalette forest) {
    return Container(
      decoration: BoxDecoration(
        color: forest.feedRaised,
        border: Border(bottom: BorderSide(color: context.borderFaint)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Search Box
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
              style: TextStyle(color: forest.text, fontSize: 13),
              decoration: InputDecoration(
                hintText:
                    'Search graph, curve or concept (e.g. PPC, IC, AC, MC)...',
                hintStyle: TextStyle(color: forest.text54, fontSize: 13),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: forest.text54,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        color: forest.text54,
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: forest.feedSurface,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.borderFaint),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.borderFaint),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: forest.accentText),
                ),
              ),
            ),
          ),

          // Exam Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: _exams.map((ex) {
                final isSelected = _selectedExam == ex['id'];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    selected: isSelected,
                    label: Text(
                      ex['label']!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? forest.accentText : forest.text70,
                      ),
                    ),
                    backgroundColor: forest.feedSurface,
                    selectedColor: forest.accentText.withValues(alpha: 0.15),
                    checkmarkColor: forest.accentText,
                    side: BorderSide(
                      color:
                          isSelected ? forest.accentText : context.borderFaint,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    onSelected: (val) {
                      setState(() {
                        _selectedExam = ex['id']!;
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          // Language Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
            child: Row(
              children: [
                Text(
                  'Language: ',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: forest.text54,
                  ),
                ),
                const SizedBox(width: 4),
                ..._languages.map((ln) {
                  final isSelected = _selectedLang == ln['id'];
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      selected: isSelected,
                      label: Text(
                        ln['label']!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? forest.accentText : forest.text70,
                        ),
                      ),
                      backgroundColor: forest.feedSurface,
                      selectedColor: forest.accentText.withValues(alpha: 0.15),
                      side: BorderSide(
                        color: isSelected
                            ? forest.accentText
                            : context.borderFaint,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      onSelected: (val) {
                        setState(() {
                          _selectedLang = ln['id']!;
                        });
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountBar(ForestPalette forest, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: forest.background,
      child: Row(
        children: [
          Icon(
            Icons.auto_graph_rounded,
            size: 14,
            color: forest.accentText,
          ),
          const SizedBox(width: 6),
          Text(
            'Showing $count of ${_allGraphs.length} Dynamic Vector Graphs',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: forest.text70,
            ),
          ),
          const Spacer(),
          if (_searchQuery.isNotEmpty ||
              _selectedExam != 'all' ||
              _selectedLang != 'all')
            GestureDetector(
              onTap: () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                  _selectedExam = 'all';
                  _selectedLang = 'all';
                });
              },
              child: Text(
                'Reset Filters',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: forest.accentText,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ForestPalette forest) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: forest.text54,
            ),
            const SizedBox(height: 12),
            Text(
              'No matching vector graphs found',
              style: TextStyle(
                color: forest.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Try clearing search filters or selecting another exam session.',
              style: TextStyle(color: forest.text54, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGraphList(ForestPalette forest, List<AtlasGraphItem> graphs) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: graphs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 14),
          itemBuilder: (context, index) =>
              _buildGraphCard(forest, graphs[index]),
        ),
      ),
    );
  }

  Widget _buildGraphCard(ForestPalette forest, AtlasGraphItem item) {
    return Container(
      decoration: BoxDecoration(
        color: forest.feedSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderFaint),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header info bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: forest.feedRaised,
              border: Border(bottom: BorderSide(color: context.borderFaint)),
            ),
            child: Row(
              children: [
                // Exam Badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: forest.accentText.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item.examLabel,
                    style: TextStyle(
                      color: forest.accentText,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Language Badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: item.language == 'Bangla'
                        ? Colors.teal.withValues(alpha: 0.15)
                        : Colors.indigo.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item.language == 'Bangla' ? 'বাংলা' : 'EN',
                    style: TextStyle(
                      color: item.language == 'Bangla'
                          ? Colors.teal
                          : Colors.indigoAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '#${item.index}',
                  style: TextStyle(
                    color: forest.text54,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Text(
              item.title,
              style: TextStyle(
                color: forest.text,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // Subtitle / Concept note
          if (item.subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Text(
                item.subtitle,
                style: TextStyle(
                  color: forest.text54,
                  fontSize: 11.5,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),

          // Vector SVG Graphic
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: ChatSvgWidget(svg: item.svg),
          ),
        ],
      ),
    );
  }
}
