import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/study_flashcard_store.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/study_flashcard_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_glossary_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/study_glossary_rules.dart';
import 'package:bhromon/features/tour_group/presentation/pages/study_glossary_screen.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/study/study_rich_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGlossaryRepo extends TourGroupRepository {
  _FakeGlossaryRepo({required this.terms, this.chapters = const []});

  final List<StudyGlossaryTerm> terms;
  final List<StudyChapter> chapters;

  @override
  String get currentEmail => 'student@bhromon.fun';

  @override
  Future<TourRole?> myRole(String tourId) async => TourRole.member;

  @override
  Stream<List<StudyGlossaryTerm>> watchGlossary(String tourId, String bookId) =>
      Stream.value(terms);

  @override
  Stream<List<StudyChapter>> watchStudyChapters(String tourId, String bookId) =>
      Stream.value(chapters);
}

class _MemoryStore extends StudyFlashcardStore {
  final Map<String, StudyFlashcard> cards = {};

  @override
  Future<List<StudyFlashcard>> loadAll() async => cards.values.toList();

  @override
  Future<void> putAll(Iterable<StudyFlashcard> items) async {
    for (final c in items) {
      cards[c.id] = c;
    }
  }
}

const _book = StudyBook(
  id: 'book1',
  title: 'Principles of Economics (POE)',
  createdByEmail: 'admin@bhromon.fun',
);

const _terms = [
  StudyGlossaryTerm(
    id: 't1',
    term: 'Absolute Advantage (চরম ব্যয় সুবিধা)',
    definition: 'একটি দেশ যখন কম খরচে পণ্য উৎপাদন করতে পারে।',
    approved: true,
    createdByEmail: 'admin@bhromon.fun',
    chapterId: 'ch1',
  ),
  StudyGlossaryTerm(
    id: 't2',
    term: 'Aggregate Demand — AD (সামগ্রিক চাহিদা)',
    definition: 'মোট চাহিদা (`AD = C + I + G + [X - M]`)।',
    approved: true,
    createdByEmail: 'admin@bhromon.fun',
    chapterId: 'ch2',
  ),
  StudyGlossaryTerm(
    id: 't3',
    term: 'Accounting Cost vs. Economic Cost',
    definition:
        'কেবল নগদে প্রদত্ত ব্যয় হলো হিসাবরক্ষণ ব্যয়; আর `প্রকাশ্য ব্যয় + অপ্রকাশ্য সুযোগ ব্যয়` হলো অর্থনৈতিক ব্যয়।',
    approved: true,
    createdByEmail: 'admin@bhromon.fun',
    chapterId: 'ch2',
  ),
];

const List<StudyChapter> _chapters = [
  StudyChapter(
    id: 'ch1',
    number: 1,
    title: 'ভূমিকা ও মৌলিক ধারণা',
  ),
  StudyChapter(
    id: 'ch2',
    number: 2,
    title: 'সামষ্টিক অর্থনীতি ও সামগ্রিক চাহিদা',
  ),
];

Future<void> _pumpGlossary(
  WidgetTester tester, {
  List<StudyGlossaryTerm> terms = _terms,
  List<StudyChapter> chapters = _chapters,
}) async {
  final repo = _FakeGlossaryRepo(terms: terms, chapters: chapters);
  final store = _MemoryStore();

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('bn'),
      supportedLocales: const [Locale('en'), Locale('bn')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: StudyGlossaryScreen(
        tourId: 'tour1',
        book: _book,
        repository: repo,
        store: store,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('searchGlossaryTerms domain rules', () {
    test('returns all terms when query is empty', () {
      final res = searchGlossaryTerms(_terms, query: '');
      expect(res.length, 3);
    });

    test('matches term title case-insensitively in English & Bengali', () {
      final resEn = searchGlossaryTerms(_terms, query: 'absolute');
      expect(resEn.length, 1);
      expect(resEn.first.id, 't1');

      final resBn = searchGlossaryTerms(_terms, query: 'সামগ্রিক চাহিদা');
      expect(resBn.length, 1);
      expect(resBn.first.id, 't2');
    });

    test('matches definition and strips markdown backticks for matching', () {
      final res = searchGlossaryTerms(_terms, query: 'AD = C + I');
      expect(res.length, 1);
      expect(res.first.id, 't2');

      final resCost =
          searchGlossaryTerms(_terms, query: 'অপ্রকাশ্য সুযোগ ব্যয়');
      expect(resCost.length, 1);
      expect(resCost.first.id, 't3');
    });

    test('filters by chapterId correctly', () {
      final ch1 = searchGlossaryTerms(_terms, chapterId: 'ch1');
      expect(ch1.length, 1);
      expect(ch1.first.id, 't1');

      final ch2 = searchGlossaryTerms(_terms, chapterId: 'ch2');
      expect(ch2.length, 2);
    });
  });

  group('StudyGlossaryScreen Widget Tests', () {
    testWidgets('renders search header, terms count badge and StudyRichText',
        (tester) async {
      await _pumpGlossary(tester);

      expect(find.byType(StudyGlossaryScreen), findsOneWidget);
      expect(find.byType(StudyRichText), findsWidgets);
      expect(find.textContaining('৩টি শব্দ'), findsOneWidget);
      expect(
          find.text('Absolute Advantage (চরম ব্যয় সুবিধা)'), findsOneWidget);
    });

    testWidgets('typing in search bar filters terms in real-time',
        (tester) async {
      await _pumpGlossary(tester);

      // Find the TextField in search header
      final searchField = find.byType(TextField).first;
      await tester.enterText(searchField, 'Economic Cost');
      await tester.pumpAndSettle();

      expect(find.text('Accounting Cost vs. Economic Cost'), findsOneWidget);
      expect(find.text('Absolute Advantage (চরম ব্যয় সুবিধা)'), findsNothing);
      expect(find.textContaining('১টি ফলাফল'), findsOneWidget);
    });

    testWidgets('shows empty state when no search results match',
        (tester) async {
      await _pumpGlossary(tester);

      final searchField = find.byType(TextField).first;
      await tester.enterText(searchField, 'NonExistentTermXYZ');
      await tester.pumpAndSettle();

      expect(find.text('কোনো শব্দ খুঁজে পাওয়া যায়নি।'), findsOneWidget);
      expect(find.byIcon(Icons.search_off_rounded), findsOneWidget);
    });

    testWidgets('selecting chapter chip filters terms by chapter',
        (tester) async {
      await _pumpGlossary(tester);

      // Tap on Chapter 1 chip
      final ch1Chip =
          find.widgetWithText(ChoiceChip, '১: ভূমিকা ও মৌলিক ধারণা');
      expect(ch1Chip, findsOneWidget);
      await tester.tap(ch1Chip);
      await tester.pumpAndSettle();

      expect(
          find.text('Absolute Advantage (চরম ব্যয় সুবিধা)'), findsOneWidget);
      expect(
          find.text('Aggregate Demand — AD (সামগ্রিক চাহিদা)'), findsNothing);
      expect(find.textContaining('১টি ফলাফল'), findsOneWidget);
    });
  });
}
