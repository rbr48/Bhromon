import '../widgets/group_back_button.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/localized_date.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../../core/utils/app_logger.dart';
import '../../data/study_activity_log.dart';
import '../../data/study_flashcard_store.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/study_flashcard_models.dart';
import '../../domain/models/study_models.dart';
import '../../domain/services/study_flashcard_extractor.dart';
import '../../domain/services/study_flashcard_rules.dart';
import '../../domain/services/study_solution_rules.dart';
import '../widgets/study/study_learning_dialogs.dart';
import 'study_flashcard_review_screen.dart';

/// The flashcards of one book, kept on this device. Cards never go to the server; they leave the phone only when
/// the member exports them to a file. A member reviews the cards that are due, adds a card by hand, or imports a
/// deck file another phone exported.
class StudyFlashcardsScreen extends StatefulWidget {
  const StudyFlashcardsScreen({
    super.key,
    required this.book,
    this.tourId = '',
    this.store,
    this.today,
    this.activity,
    this.repository,
  });

  /// Where reviews are counted for the streak and the progress card. Null in the app; tests pass one.
  final StudyActivityLog? activity;

  final StudyBook book;

  final String tourId;

  /// The device's flashcards. Null in the app, where the screen makes its own; tests pass one.
  final StudyFlashcardStore? store;

  /// The day the due dates are judged against. Null in the app, where it is today; tests pass one.
  final DateTime? today;

  /// The repository for reading study materials. Null in the app; tests pass one.
  final TourGroupRepository? repository;

  @override
  State<StudyFlashcardsScreen> createState() => _StudyFlashcardsScreenState();
}

/// The actions of the deck menu.
enum _DeckAction { exportDeck, exportAnki, importDeck, generateFromSolutions }

class _StudyFlashcardsScreenState extends State<StudyFlashcardsScreen> {
  static const Uuid _ids = Uuid();

  late final StudyFlashcardStore _store = widget.store ?? StudyFlashcardStore();
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();

  /// The cards of this book, the soonest due first.
  List<StudyFlashcard> _cards = const [];
  bool _loaded = false;
  bool _failed = false;
  bool _extracting = false;

  DateTime get _now => widget.today ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await _store.loadAll();
      if (!mounted) return;
      final deck = [
        for (final card in all)
          if (card.deckId == widget.book.id) card,
      ]..sort((a, b) => a.dueOn.compareTo(b.dueOn));
      setState(() {
        _cards = deck;
        _loaded = true;
        _failed = false;
      });
    } catch (error, stackTrace) {
      logWarning('The flashcards could not be read', error, stackTrace);
      if (mounted) {
        setState(() {
          _loaded = true;
          _failed = true;
        });
      }
    }
  }

  void _say(String key,
      {Map<String, Object> args = const {}, bool error = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(
      content: Text(context.l10n.translate(key, args: args)),
      backgroundColor: error ? Colors.redAccent : null,
    ));
  }

  /// Saves one change to the cards, then reloads them. A failure is logged and shown.
  Future<void> _change(Future<void> Function() change, String doneKey) async {
    try {
      await change();
      await _load();
      if (mounted) _say(doneKey);
    } catch (error, stackTrace) {
      logWarning('A flashcard change failed', error, stackTrace);
      if (mounted) _say('study_failed', error: true);
    }
  }

  Future<void> _addCard() async {
    final draft = await showStudyFlashcardEditor(context);
    if (draft == null || !mounted) return;
    await _change(
      () => _store.putAll([
        StudyFlashcard(
          id: _ids.v4(),
          deckId: widget.book.id,
          front: draft.front,
          back: draft.back,
          dueOn: dayKey(_now),
        ),
      ]),
      'study_flashcard_added',
    );
  }

  Future<void> _removeCard(StudyFlashcard card) async {
    final sure = await confirmStudyRemoval(context);
    if (!sure || !mounted) return;
    await _change(() => _store.delete(card.id), 'study_flashcard_removed');
  }

  Future<void> _review(List<StudyFlashcard> due) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StudyFlashcardReviewScreen(
        cards: due,
        tourId: widget.tourId,
        store: _store,
        today: widget.today,
        activity: widget.activity,
      ),
    ));
    if (mounted) await _load();
  }

  String get _fileStem {
    final cleaned = widget.book.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return cleaned.isEmpty ? 'deck' : cleaned;
  }

  Future<void> _onAction(_DeckAction action) async {
    switch (action) {
      case _DeckAction.exportDeck:
        await _exportDeck();
      case _DeckAction.exportAnki:
        await _exportAnki();
      case _DeckAction.importDeck:
        await _importDeck();
      case _DeckAction.generateFromSolutions:
        await _generateFromSolutions();
    }
  }

  Future<void> _generateFromSolutions() async {
    if (_extracting || widget.tourId.isEmpty) return;
    setState(() => _extracting = true);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;

    try {
      final materials = await _repository
          .watchStudyMaterials(widget.tourId, widget.book.id)
          .first;

      final solutions = materials
          .where((m) => m.isPublished && isReadableSolution(m))
          .toList();

      if (solutions.isEmpty) {
        if (mounted) {
          messenger.showSnackBar(SnackBar(
            content: Text(l10n.translate('study_flashcards_none_found')),
          ));
        }
        return;
      }

      final generated = <StudyFlashcard>[];
      for (final sol in solutions) {
        final content = sol.body ?? '';
        if (content.trim().isEmpty) continue;
        final cards = StudyFlashcardExtractor.extractFromMarkdown(
          deckId: widget.book.id,
          subjectTitle: widget.book.title,
          markdownContent: content,
          today: _now,
        );
        generated.addAll(cards);
      }

      if (generated.isEmpty) {
        if (mounted) {
          messenger.showSnackBar(SnackBar(
            content: Text(l10n.translate('study_flashcards_none_found')),
          ));
        }
        return;
      }

      await _store.putAll(generated);
      await _load();
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text(l10n.translate(
            'study_flashcards_generated_count',
            args: {'count': l10n.number(generated.length)},
          )),
        ));
      }
    } catch (error, stackTrace) {
      logWarning(
          'Failed to generate flashcards from solutions', error, stackTrace);
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text(l10n.translate('study_failed')),
          backgroundColor: Colors.redAccent,
        ));
      }
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }

  Future<void> _exportDeck() async {
    if (_cards.isEmpty) {
      _say('study_flashcard_export_empty');
      return;
    }
    final bytes = Uint8List.fromList(
      utf8.encode(jsonEncode(deckToJson(_cards))),
    );
    await _share(bytes,
        mimeType: 'application/json', name: '$_fileStem.bhromon-deck.json');
  }

  Future<void> _exportAnki() async {
    if (_cards.isEmpty) {
      _say('study_flashcard_export_empty');
      return;
    }
    final bytes = Uint8List.fromList(utf8.encode(toAnkiCsv(_cards)));
    await _share(bytes, mimeType: 'text/csv', name: '$_fileStem-anki.csv');
  }

  Future<void> _share(
    Uint8List bytes, {
    required String mimeType,
    required String name,
  }) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: mimeType, name: name)],
          fileNameOverrides: [name],
        ),
      );
    } catch (error, stackTrace) {
      logWarning('The flashcards could not be shared', error, stackTrace);
      if (mounted) _say('study_failed', error: true);
    }
  }

  Future<void> _importDeck() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    final picked =
        result != null && result.files.isNotEmpty ? result.files.first : null;
    final bytes = picked?.bytes;
    if (bytes == null || !mounted) return;
    final imported = deckFromJson(
      _decodeDeck(bytes),
      deckId: widget.book.id,
      newId: () => _ids.v4(),
    );
    if (imported == null || imported.isEmpty) {
      _say('study_flashcard_import_bad', error: true);
      return;
    }
    try {
      await _store.putAll(imported);
      await _load();
      if (mounted) {
        _say('study_flashcard_import_done', args: {
          'count': context.l10n.number(imported.length),
        });
      }
    } catch (error, stackTrace) {
      logWarning('The flashcard deck could not be imported', error, stackTrace);
      if (mounted) _say('study_failed', error: true);
    }
  }

  /// The file as JSON, or null when it is not JSON at all.
  Object? _decodeDeck(Uint8List bytes) {
    try {
      return jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return null;
    }
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
          leading: GroupBackButton(tourId: widget.tourId),
          title: Text(l10n.translate('study_flashcards_title'),
              style: TextStyle(
                  color: palette.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
          backgroundColor: palette.card,
          foregroundColor: palette.text,
          iconTheme: IconThemeData(color: palette.text),
          elevation: 0,
          actions: [
            PopupMenuButton<_DeckAction>(
              tooltip: l10n.translate('study_flashcard_menu'),
              icon: Icon(Icons.more_vert_rounded, color: palette.text),
              onSelected: _onAction,
              itemBuilder: (_) => [
                if (widget.tourId.isNotEmpty)
                  PopupMenuItem<_DeckAction>(
                    value: _DeckAction.generateFromSolutions,
                    child: Text(l10n
                        .translate('study_flashcards_generate_from_solutions')),
                  ),
                PopupMenuItem<_DeckAction>(
                  value: _DeckAction.exportDeck,
                  child: Text(l10n.translate('study_flashcard_export_json')),
                ),
                PopupMenuItem<_DeckAction>(
                  value: _DeckAction.exportAnki,
                  child: Text(l10n.translate('study_flashcard_export_anki')),
                ),
                PopupMenuItem<_DeckAction>(
                  value: _DeckAction.importDeck,
                  child: Text(l10n.translate('study_flashcard_import')),
                ),
              ],
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addCard,
          icon: const Icon(Icons.add_rounded),
          label: Text(l10n.translate('study_flashcard_add')),
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
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final due = dueCards(_cards, _now);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        Card(
          color: palette.card,
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.translate('study_flashcards_summary', args: {
                    'due': l10n.number(due.length),
                    'total': l10n.number(_cards.length),
                  }),
                  style: TextStyle(
                      color: palette.text, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.translate('study_flashcard_device_note'),
                  style: TextStyle(color: palette.text54, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (due.isNotEmpty)
                      FilledButton.icon(
                        onPressed: () => _review(due),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(l10n.translate('study_flashcards_review')),
                      ),
                    if (widget.tourId.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: _extracting ? null : _generateFromSolutions,
                        icon: _extracting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.auto_awesome_rounded, size: 16),
                        label: Text(
                          l10n.translate(
                              'study_flashcards_generate_from_solutions'),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    if (due.isEmpty && _cards.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          l10n.translate('study_flashcards_nothing_due'),
                          style: TextStyle(color: palette.text70),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_cards.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.translate('study_flashcards_none'),
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.text70),
            ),
          ),
        for (final card in _cards) _cardTile(card),
      ],
    );
  }

  Widget _cardTile(StudyFlashcard card) {
    final l10n = context.l10n;
    final palette = context.forest;
    final due = DateTime.tryParse(card.dueOn);
    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Row(
          children: [
            if (card.moduleCode != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: palette.accentText.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: palette.accentText.withValues(alpha: 0.4),
                    width: 0.6,
                  ),
                ),
                child: Text(
                  'Mod ${card.moduleCode}',
                  style: TextStyle(
                    color: palette.accentText,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                card.front,
                style:
                    TextStyle(color: palette.text, fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Text(
          [
            card.back,
            l10n.translate('study_flashcard_box', args: {
              'box': l10n.number(card.box),
              'date': due == null
                  ? card.dueOn
                  : localizedDateFormat('d MMM yyyy').format(due),
            }),
          ].join('\n'),
          style: TextStyle(color: palette.text54),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          tooltip: l10n.translate('study_remove'),
          icon: Icon(Icons.delete_outline_rounded, color: palette.text54),
          onPressed: () => _removeCard(card),
        ),
      ),
    );
  }
}
