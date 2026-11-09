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
        backgroundColor: Colors.redAccent,
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
        backgroundColor: Colors.redAccent,
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
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: Text(l10n.translate('study_glossary_title'),
            style: TextStyle(
                color: palette.text,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
        backgroundColor: palette.card,
        foregroundColor: palette.text,
        iconTheme: IconThemeData(color: palette.text),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addTerm,
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.translate(
            _isAdmin ? 'study_glossary_add_admin' : 'study_glossary_add')),
      ),
      body: _body(),
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
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final approved = approvedTerms(_terms);
    final proposals = [
      for (final term in _terms)
        if (!term.approved) term,
    ];
    if (approved.isEmpty && proposals.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.translate('study_glossary_empty'),
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.text70),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        for (final term in approved) _termCard(term),
        if (proposals.isNotEmpty)
          _heading(l10n.translate('study_glossary_proposals_heading')),
        for (final term in proposals) _termCard(term),
      ],
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
      child: ListTile(
        title: Text(
          term.term,
          style: TextStyle(color: palette.text, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            term.definition,
            if (chapter != null)
              l10n.translate('study_chapter_title_line', args: {
                'number': l10n.number(chapter.number),
                'title': chapter.title,
              }),
            if (!term.approved) l10n.translate('study_material_waiting'),
          ].join('\n'),
          style: TextStyle(color: palette.text70),
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
