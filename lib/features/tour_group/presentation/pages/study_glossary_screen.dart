import 'package:bhromon/core/widgets/empty_state.dart';
import 'package:bhromon/core/widgets/skeleton.dart';
import '../widgets/group_back_button.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../../core/utils/app_logger.dart';
import '../../data/study_flashcard_store.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/study_flashcard_models.dart';
import '../../domain/models/study_glossary_models.dart';
import '../../domain/models/study_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/study_chapter_rules.dart';
import '../../domain/services/study_flashcard_rules.dart';
import '../../domain/services/study_glossary_rules.dart';
import '../widgets/study/study_learning_dialogs.dart';
import '../widgets/study/study_rich_text.dart';
import 'package:bhromon/core/theme/colors.dart';

/// The glossary of one book. A member proposes a term and an admin approves it. An approved term can be made into
/// a flashcard on this device, once: the card keeps its own copy of the words and remembers the term it came from.
class StudyGlossaryScreen extends StatefulWidget {
  const StudyGlossaryScreen({
    super.key,
    required this.tourId,
    required this.book,
    this.repository,
    this.store,
  });

  final String tourId;
  final StudyBook book;

  /// The data source. Null in the app, where the screen makes its own; tests pass one.
  final TourGroupRepository? repository;

  /// The flashcards kept on this device. Null in the app; tests pass one.
  final StudyFlashcardStore? store;

  @override
  State<StudyGlossaryScreen> createState() => _StudyGlossaryScreenState();
}

class _StudyGlossaryScreenState extends State<StudyGlossaryScreen> {
  static const Uuid _ids = Uuid();

  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();
  late final StudyFlashcardStore _store = widget.store ?? StudyFlashcardStore();
  StreamSubscription<List<StudyGlossaryTerm>>? _termSub;
  StreamSubscription<List<StudyChapter>>? _chapterSub;

  TourRole? _myRole;
  List<StudyGlossaryTerm> _terms = const [];
  List<StudyChapter> _chapters = const [];
  bool _loaded = false;
  bool _failed = false;

  bool _searching = false;
  String _query = '';
  String? _selectedChapterId;
  final TextEditingController _searchCtrl = TextEditingController();

  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;
  String get _email => _repository.currentEmail;

  @override
  void initState() {
    super.initState();
    _repository.myRole(widget.tourId).then((role) {
      if (mounted) setState(() => _myRole = role);
    }, onError: (Object _) {});
    _termSub = _repository.watchGlossary(widget.tourId, widget.book.id).listen(
      (terms) {
        if (!mounted) return;
        setState(() {
          _terms = terms;
          _loaded = true;
          _failed = false;
        });
      },
      onError: (Object _) {
        if (mounted) setState(() => _failed = true);
      },
    );
    _chapterSub =
        _repository.watchStudyChapters(widget.tourId, widget.book.id).listen(
      (chapters) {
        if (mounted) setState(() => _chapters = sortStudyChapters(chapters));
      },
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    _termSub?.cancel();
    _chapterSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Runs one change and says how it went. A failure is logged and shown.
  Future<void> _run(Future<void> Function() change, String doneKey) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await change();
      messenger.showSnackBar(SnackBar(content: Text(l10n.translate(doneKey))));
    } catch (error, stackTrace) {
      logWarning('A glossary change failed', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: AppColors.amber,
      ));
    }
  }

  /// A member proposes a term; an admin's is added already approved.
  Future<void> _addTerm() async {
    final draft = await showStudyGlossaryEditor(context, chapters: _chapters);
    if (draft == null || !mounted) return;
    await _run(
      () => _repository.addGlossaryTerm(
        widget.tourId,
        widget.book.id,
        term: draft.term,
        definition: draft.definition,
        chapterId: draft.chapterId,
        approved: _isAdmin,
      ),
      _isAdmin ? 'study_glossary_added' : 'study_glossary_proposed',
    );
  }

  Future<void> _approve(StudyGlossaryTerm term) {
    return _run(
      () => _repository.approveGlossaryTerm(
          widget.tourId, widget.book.id, term.id),
      'study_glossary_approved',
    );
  }

  Future<void> _remove(StudyGlossaryTerm term) async {
    final sure = await confirmStudyRemoval(context);
    if (!sure || !mounted) return;
    await _run(
      () => _repository.deleteGlossaryTerm(
          widget.tourId, widget.book.id, term.id),
      'study_glossary_removed',
    );
  }

  /// Makes a flashcard of an approved term on this device. A term gives one card per book.
  Future<void> _makeCard(StudyGlossaryTerm term) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      final existing = await _store.loadAll();
      final made = existing.any(
        (card) => card.deckId == widget.book.id && card.termId == term.id,
      );
      if (made) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.translate('study_glossary_card_exists'))),
        );
        return;
      }
      await _store.putAll([
        StudyFlashcard(
          id: _ids.v4(),
          deckId: widget.book.id,
          front: term.term,
          back: term.definition,
          dueOn: dayKey(DateTime.now()),
          termId: term.id,
        ),
      ]);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.translate('study_glossary_card_made'))),
      );
    } catch (error, stackTrace) {
      logWarning(
          'A flashcard could not be made from a term', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: AppColors.amber,
      ));
    }
  }

  StudyChapter? _chapterFor(String? chapterId) {
    if (chapterId == null) return null;
    for (final chapter in _chapters) {
      if (chapter.id == chapterId) return chapter;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    return GroupPopScope(
      tourId: widget.tourId,
      child: Scaffold(
        backgroundColor: palette.background,
        appBar: AppBar(
          leading: _searching
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => setState(() {
                    _searching = false;
                    _searchCtrl.clear();
                    _query = '';
                  }),
                )
              : GroupBackButton(tourId: widget.tourId),
          title: _searching
              ? TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 16,
                  ),
                  decoration: InputDecoration(
                    hintText: l10n.translate('study_glossary_search_hint'),
                    hintStyle: TextStyle(
                      color: palette.text54,
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                  ),
                  onChanged: (value) => setState(() => _query = value),
                )
              : Text(
                  l10n.translate('study_glossary_title'),
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
          backgroundColor: palette.card,
          foregroundColor: palette.text,
          iconTheme: IconThemeData(color: palette.text),
          elevation: 0,
          actions: [
            if (_searching) ...[
              if (_query.isNotEmpty)
                IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.clear_rounded),
                  onPressed: () => setState(() {
                    _searchCtrl.clear();
                    _query = '';
                  }),
                ),
            ] else ...[
              IconButton(
                tooltip: l10n.translate('study_glossary_search'),
                icon: const Icon(Icons.search_rounded),
                onPressed: () => setState(() => _searching = true),
              ),
            ],
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addTerm,
          icon: const Icon(Icons.add_rounded),
          label: Text(l10n.translate(
              _isAdmin ? 'study_glossary_add_admin' : 'study_glossary_add')),
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    final l10n = context.l10n;
    final palette = context.forest;
    if (_failed) {
      return Center(
        child: Text(l10n.translate('study_failed'),
            style: TextStyle(color: palette.text70)),
      );
    }
    if (!_loaded) return const ListRowsSkeleton();
    final approved = approvedTerms(_terms);
    final proposals = [
      for (final term in _terms)
        if (!term.approved) term,
    ];
    if (approved.isEmpty && proposals.isEmpty) {
      return EmptyState(
        icon: Icons.translate_rounded,
        message: l10n.translate('study_glossary_empty'),
      );
    }

    final filteredApproved = searchGlossaryTerms(
      approved,
      query: _query,
      chapterId: _selectedChapterId,
    );
    final filteredProposals = searchGlossaryTerms(
      proposals,
      query: _query,
      chapterId: _selectedChapterId,
    );

    return Column(
      children: [
        _searchHeader(
          totalApproved: approved.length,
          filteredCount: filteredApproved.length,
        ),
        if (_chapters.isNotEmpty) _chapterFilterBar(),
        Expanded(
          child: filteredApproved.isEmpty && filteredProposals.isEmpty
              ? EmptyState(
                  icon: Icons.search_off_rounded,
                  message: l10n.translate('study_glossary_search_empty'),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  children: [
                    for (final term in filteredApproved) _termCard(term),
                    if (filteredProposals.isNotEmpty)
                      _heading(
                          l10n.translate('study_glossary_proposals_heading')),
                    for (final term in filteredProposals) _termCard(term),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _searchHeader({
    required int totalApproved,
    required int filteredCount,
  }) {
    final l10n = context.l10n;
    final palette = context.forest;
    final hasFilter = _query.isNotEmpty || _selectedChapterId != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: palette.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: palette.divider10,
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: palette.accentText,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      style: TextStyle(color: palette.text, fontSize: 14),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: l10n.translate('study_glossary_search_hint'),
                        hintStyle: TextStyle(
                          color: palette.text54,
                          fontSize: 13,
                        ),
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onChanged: (val) => setState(() => _query = val),
                    ),
                  ),
                  if (_query.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      color: palette.text54,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: palette.accentText.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              hasFilter
                  ? l10n.translate('study_glossary_results_count',
                      args: {'count': l10n.number(filteredCount)})
                  : l10n.translate('study_glossary_terms_count',
                      args: {'count': l10n.number(totalApproved)}),
              style: TextStyle(
                color: palette.accentText,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chapterFilterBar() {
    final l10n = context.l10n;
    final palette = context.forest;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Row(
        children: [
          ChoiceChip(
            label: Text(l10n.translate('study_glossary_all_chapters')),
            selected: _selectedChapterId == null,
            onSelected: (_) => setState(() => _selectedChapterId = null),
            selectedColor: palette.accentText.withValues(alpha: 0.2),
            labelStyle: TextStyle(
              fontSize: 12,
              fontWeight: _selectedChapterId == null
                  ? FontWeight.bold
                  : FontWeight.normal,
              color: _selectedChapterId == null
                  ? palette.accentText
                  : palette.text70,
            ),
          ),
          for (final ch in _chapters) ...[
            const SizedBox(width: 6),
            ChoiceChip(
              label: Text('${l10n.number(ch.number)}: ${ch.title}'),
              selected: _selectedChapterId == ch.id,
              onSelected: (selected) => setState(() {
                _selectedChapterId = selected ? ch.id : null;
              }),
              selectedColor: palette.accentText.withValues(alpha: 0.2),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: _selectedChapterId == ch.id
                    ? FontWeight.bold
                    : FontWeight.normal,
                color: _selectedChapterId == ch.id
                    ? palette.accentText
                    : palette.text70,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _heading(String text) {
    final palette = context.forest;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Text(
        text,
        style:
            TextStyle(color: palette.accentText, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _termCard(StudyGlossaryTerm term) {
    final l10n = context.l10n;
    final palette = context.forest;
    final chapter = _chapterFor(term.chapterId);
    final canApprove = !term.approved && canApproveTerm(isAdmin: _isAdmin);
    final canRemove = canRemoveTerm(
      term,
      viewerEmail: _email,
      isAdmin: _isAdmin,
    );
    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: palette.divider10, width: 0.8),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        title: StudyRichText(
          term.term,
          style: TextStyle(
            color: palette.text,
            fontWeight: FontWeight.bold,
            fontSize: 15.5,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StudyRichText(
                term.definition,
                style: TextStyle(
                  color: palette.text70,
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
              if (chapter != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: palette.accentText.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    l10n.translate('study_chapter_title_line', args: {
                      'number': l10n.number(chapter.number),
                      'title': chapter.title,
                    }),
                    style: TextStyle(
                      color: palette.accentText,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              if (!term.approved) ...[
                const SizedBox(height: 4),
                Text(
                  l10n.translate('study_material_waiting'),
                  style: TextStyle(
                    color: palette.text54,
                    fontStyle: FontStyle.italic,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canApprove)
              TextButton(
                onPressed: () => _approve(term),
                child: Text(l10n.translate('study_approve')),
              ),
            if (term.approved)
              IconButton(
                tooltip: l10n.translate('study_glossary_to_flashcard'),
                icon: Icon(Icons.style_outlined, color: palette.accentText),
                onPressed: () => _makeCard(term),
              ),
            if (canRemove)
              IconButton(
                tooltip: l10n.translate(term.approved || _isAdmin
                    ? 'study_remove'
                    : 'study_withdraw'),
                icon: Icon(Icons.delete_outline_rounded, color: palette.text54),
                onPressed: () => _remove(term),
              ),
          ],
        ),
      ),
    );
  }
}
