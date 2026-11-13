import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../core/theme/colors.dart';
import '../../../../../core/theme/forest_palette.dart';
import '../../../../../core/theme/theme_context.dart';
import '../../../../chat/presentation/widgets/chat_svg_widget.dart';
import '../../../data/tour_group_repository.dart';
import '../../../domain/models/study_subject_models.dart';
import '../../pages/study_graph_atlas_screen.dart';

/// Modal bottom sheet allowing students and admins to browse, pick, or publish
/// dynamic vector diagrams from the POE Graph Atlas directly into a subject's Charts & Graphs module.
class StudyAtlasPublishSheet extends StatefulWidget {
  final String tourId;
  final String subjectId;
  final bool isPickerOnly;
  final TourGroupRepository? repository;

  const StudyAtlasPublishSheet({
    super.key,
    required this.tourId,
    required this.subjectId,
    this.isPickerOnly = false,
    this.repository,
  });

  /// Opens the sheet in publisher mode.
  static Future<void> showPublisher(
    BuildContext context, {
    required String tourId,
    required String subjectId,
    TourGroupRepository? repository,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StudyAtlasPublishSheet(
        tourId: tourId,
        subjectId: subjectId,
        isPickerOnly: false,
        repository: repository,
      ),
    );
  }

  /// Opens the sheet in picker mode and returns the selected graph item.
  static Future<AtlasGraphItem?> showPicker(BuildContext context) {
    return showModalBottomSheet<AtlasGraphItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const StudyAtlasPublishSheet(
        tourId: '',
        subjectId: '',
        isPickerOnly: true,
      ),
    );
  }

  @override
  State<StudyAtlasPublishSheet> createState() => _StudyAtlasPublishSheetState();
}

class _StudyAtlasPublishSheetState extends State<StudyAtlasPublishSheet> {
  final TextEditingController _search = TextEditingController();
  List<AtlasGraphItem> _all = [];
  List<AtlasGraphItem> _filtered = [];
  bool _isLoading = true;
  String _selectedExam = 'all';
  String _selectedLang = 'all';

  final Set<String> _publishingIds = {};
  final Set<String> _publishedIds = {};
  bool _isPublishingBatch = false;
  double _batchProgress = 0.0;

  late final TourGroupRepository _repo =
      widget.repository ?? TourGroupRepository();

  static const _exams = [
    {'id': 'all', 'label': 'সব পরীক্ষা (All)'},
    {'id': '96th', 'label': '96th BPE'},
    {'id': '97th', 'label': '97th BPE'},
    {'id': '98th', 'label': '98th BPE'},
    {'id': '99th', 'label': '99th BPE'},
    {'id': '5th', 'label': '5th BPE'},
    {'id': '6th', 'label': '6th BPE'},
    {'id': '7th', 'label': '7th BPE'},
    {'id': '8th', 'label': '8th BPE'},
  ];

  @override
  void initState() {
    super.initState();
    _loadAtlas();
    _search.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _search.dispose();
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
      if (mounted) {
        setState(() {
          _all = items;
          _filtered = items;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applyFilters() {
    final query = _search.text.trim().toLowerCase();
    setState(() {
      _filtered = _all.where((g) {
        final matchExam = _selectedExam == 'all' || g.exam == _selectedExam;
        final matchLang = _selectedLang == 'all' ||
            g.language.toLowerCase() == _selectedLang.toLowerCase();
        final matchQuery = query.isEmpty ||
            g.title.toLowerCase().contains(query) ||
            g.subtitle.toLowerCase().contains(query) ||
            g.examLabel.toLowerCase().contains(query);
        return matchExam && matchLang && matchQuery;
      }).toList();
    });
  }

  String _formatPostText(AtlasGraphItem item) {
    final sub = item.subtitle.trim();
    final subtitleBlock = sub.isNotEmpty ? '> $sub\n\n' : '';
    final sanitizedSvg = ChatSvgWidget.sanitizeSvgXml(item.svg);
    return '*${item.examLabel} • ${item.language}*\n\n'
        '$subtitleBlock'
        '```svg\n$sanitizedSvg\n```';
  }

  Future<void> _publishSingle(AtlasGraphItem item) async {
    if (_publishingIds.contains(item.id) || _publishedIds.contains(item.id)) {
      return;
    }
    setState(() => _publishingIds.add(item.id));
    final title = '${item.title} (${item.examLabel})';
    final text = _formatPostText(item);
    try {
      await _repo.addStudyPost(
        widget.tourId,
        widget.subjectId,
        StudyModuleKey.charts,
        title: title,
        text: text,
        shown: true,
      );
      if (mounted) {
        setState(() {
          _publishingIds.remove(item.id);
          _publishedIds.add(item.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('চার্ট ও গ্রাফে প্রকাশ করা হয়েছে: ${item.title}'),
            backgroundColor: AppColors.darkGreen,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _publishingIds.remove(item.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('প্রকাশ করতে সমস্যা হয়েছে: $e'),
            backgroundColor: AppColors.amber,
          ),
        );
      }
    }
  }

  Future<void> _publishBatch() async {
    final targets =
        _filtered.where((g) => !_publishedIds.contains(g.id)).toList();
    if (targets.isEmpty) return;

    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('সবগুলো গ্রাফ প্রকাশ করবেন?'),
        content: Text(
          'নির্বাচিত ${targets.length}টি ভেক্টর গ্রাফ এই বিষয়ের "চার্ট ও গ্রাফ" সেকশনে প্রকাশ করা হবে।',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.darkGreen),
            child: const Text('প্রকাশ করুন'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;

    setState(() {
      _isPublishingBatch = true;
      _batchProgress = 0.0;
    });

    int published = 0;
    for (int i = 0; i < targets.length; i++) {
      final item = targets[i];
      final title = '${item.title} (${item.examLabel})';
      final text = _formatPostText(item);
      try {
        await _repo.addStudyPost(
          widget.tourId,
          widget.subjectId,
          StudyModuleKey.charts,
          title: title,
          text: text,
          shown: true,
        );
        published++;
        if (mounted) {
          setState(() {
            _publishedIds.add(item.id);
            _batchProgress = (i + 1) / targets.length;
          });
        }
      } catch (_) {
        // continue best-effort
      }
    }

    if (mounted) {
      setState(() => _isPublishingBatch = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$publishedটি চার্ট সফলভাবে প্রকাশ করা হয়েছে!'),
          backgroundColor: AppColors.darkGreen,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.forest;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      height: MediaQuery.sizeOf(context).height * 0.88,
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: palette.feedSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _handle(palette),
          _header(palette),
          _filterBar(palette),
          if (_isPublishingBatch)
            LinearProgressIndicator(
              value: _batchProgress,
              backgroundColor: palette.card,
              color: palette.accentText,
            ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child:
                        CircularProgressIndicator(color: AppColors.mintGreen),
                  )
                : _filtered.isEmpty
                    ? Center(
                        child: Text(
                          'কোন গ্রাফ খুঁজে পাওয়া যায়নি',
                          style: TextStyle(color: palette.text54),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: _filtered.length,
                        itemBuilder: (context, index) {
                          final item = _filtered[index];
                          return _itemCard(item, palette);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _handle(ForestPalette palette) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(top: 10, bottom: 6),
        decoration: BoxDecoration(
          color: palette.text54.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _header(ForestPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 12, 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: palette.accentText.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.auto_graph_rounded,
              size: 20,
              color: palette.accentText,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.isPickerOnly
                      ? 'অ্যাটলাস থেকে গ্রাফ বেছে নিন'
                      : 'অ্যাটলাস থেকে চার্ট প্রকাশ করুন',
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '৯৫টি ডাইনামিক অর্থনীতি ভেক্টর চিত্র (POE)',
                  style: TextStyle(color: palette.text70, fontSize: 12),
                ),
              ],
            ),
          ),
          if (!widget.isPickerOnly)
            FilledButton.tonalIcon(
              onPressed: _isPublishingBatch ? null : _publishBatch,
              icon: const Icon(Icons.cloud_upload_outlined, size: 16),
              label: Text('সবগুলো (${_filtered.length})'),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
          IconButton(
            icon: Icon(Icons.close_rounded, color: palette.text70),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _filterBar(ForestPalette palette) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: palette.feedRaised,
        border: Border(
          top: BorderSide(color: context.borderFaint),
          bottom: BorderSide(color: context.borderFaint),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _search,
            style: TextStyle(color: palette.text, fontSize: 13.5),
            decoration: InputDecoration(
              isDense: true,
              hintText:
                  'গ্রাফ, কার্ভ বা শিরোনাম অনুসন্ধান করুন (e.g. PPC, IC, MC)...',
              hintStyle: TextStyle(color: palette.text54, fontSize: 12.5),
              prefixIcon:
                  Icon(Icons.search_rounded, size: 18, color: palette.text54),
              suffixIcon: _search.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 16),
                      onPressed: () => _search.clear(),
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: context.borderFaint),
              ),
              filled: true,
              fillColor: palette.feedSurface,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final e in _exams)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(e['label']!),
                      selected: _selectedExam == e['id'],
                      onSelected: (_) {
                        setState(() => _selectedExam = e['id']!);
                        _applyFilters();
                      },
                      labelStyle: TextStyle(
                        fontSize: 11,
                        fontWeight: _selectedExam == e['id']
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('সব ভাষা'),
                  selected: _selectedLang == 'all',
                  onSelected: (_) {
                    setState(() => _selectedLang = 'all');
                    _applyFilters();
                  },
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 4),
                ChoiceChip(
                  label: const Text('English'),
                  selected: _selectedLang == 'English',
                  onSelected: (_) {
                    setState(() => _selectedLang = 'English');
                    _applyFilters();
                  },
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 4),
                ChoiceChip(
                  label: const Text('বাংলা'),
                  selected: _selectedLang == 'Bangla',
                  onSelected: (_) {
                    setState(() => _selectedLang = 'Bangla');
                    _applyFilters();
                  },
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemCard(AtlasGraphItem item, ForestPalette palette) {
    final isPublishing = _publishingIds.contains(item.id);
    final isPublished = _publishedIds.contains(item.id);

    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.borderFaint),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap:
            widget.isPickerOnly ? () => Navigator.of(context).pop(item) : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: palette.accentText.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.examLabel,
                      style: TextStyle(
                        color: palette.accentText,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: palette.text54.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.language,
                      style: TextStyle(
                        color: palette.text70,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (widget.isPickerOnly)
                    Icon(
                      Icons.check_circle_outline_rounded,
                      color: palette.accentText,
                      size: 20,
                    )
                  else if (isPublished)
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_rounded,
                            size: 14, color: AppColors.mintGreen),
                        SizedBox(width: 4),
                        Text(
                          'প্রকাশিত',
                          style: TextStyle(
                            color: AppColors.mintGreen,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    )
                  else
                    FilledButton.icon(
                      onPressed:
                          isPublishing ? null : () => _publishSingle(item),
                      icon: isPublishing
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_rounded, size: 14),
                      label: const Text('প্রকাশ'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        backgroundColor: palette.accentText,
                        foregroundColor: Colors.white,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item.title,
                style: TextStyle(
                  color: palette.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              if (item.subtitle.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  item.subtitle,
                  style: TextStyle(
                    color: palette.text70,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
