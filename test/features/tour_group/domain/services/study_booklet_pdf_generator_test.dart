import 'package:bhromon/features/tour_group/domain/models/study_material_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_models.dart';
import 'package:bhromon/features/tour_group/domain/services/study_booklet_pdf_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const generator = StudyBookletPdfGenerator();

  group('StudyBookletPdfGenerator', () {
    test('extractContent extracts chapters, questions, and module tags', () {
      final chapters = [
        const StudyChapter(id: 'c1', number: 1, title: '96th BPE (May 2023)'),
        const StudyChapter(id: 'c2', number: 2, title: '97th BPE (Nov 2023)'),
      ];

      final materials = [
        StudyMaterial(
          id: 'm1',
          bookId: 'b1',
          chapterId: 'c1',
          title: 'বাংলা সমাধান',
          kind: StudyMaterialKind.note,
          status: StudyMaterialStatus.published,
          createdByEmail: 'test@bhromon.fun',
          createdAt: DateTime(2026, 1, 1),
        ),
        StudyMaterial(
          id: 'm2',
          bookId: 'b1',
          chapterId: 'c2',
          title: 'English Solution',
          kind: StudyMaterialKind.note,
          status: StudyMaterialStatus.published,
          createdByEmail: 'test@bhromon.fun',
          createdAt: DateTime(2026, 1, 1),
        ),
      ];

      final solutionTexts = {
        'm1': '''
### প্রশ্ন ১ [মান: ১০]
ব্যাংক কাকে বলে? তফসিলি ব্যাংকের কার্যাবলী আলোচনা করুন।
ব্যাংক হলো এমন একটি আর্থিক প্রতিষ্ঠান যা অর্থ জমা রাখে এবং ঋণ প্রদান করে।

### প্রশ্ন ২ [মান: ১০]
কেওয়াইসি (KYC) ও অ্যান্টি-মানি লন্ডারিং (AML) এর মূল উপাদানসমূহ কী কী?
গ্রাহককে সনাক্তকরণ এবং মানি লন্ডারিং প্রতিরোধ করা ব্যাংকের অন্যতম প্রধান দায়িত্ব।
''',
        'm2': '''
### Question 1 [Marks: 10]
Define Banker-Customer relationship under general banking law.
The relationship is primarily that of debtor and creditor.
''',
      };

      final content = StudyBookletPdfGenerator.extractContent(
        subjectTitle: 'Laws and Practice of General Banking',
        subjectCode: 'JAIBB',
        tourName: 'Sonali Bank JAIBB Circle',
        inviteCode: 'SB2026JA',
        chapters: chapters,
        materials: materials,
        solutionTexts: solutionTexts,
        isBengali: true,
      );

      expect(content.subjectTitle, 'Laws and Practice of General Banking');
      expect(content.tourName, 'Sonali Bank JAIBB Circle');
      expect(content.inviteCode, 'SB2026JA');
      expect(content.chapters.length, 2);

      // Chapter 1
      final ch1 = content.chapters[0];
      expect(ch1.number, 1);
      expect(ch1.title, '96th BPE (May 2023)');
      expect(ch1.questions.length, 2);
      expect(ch1.questions[0].title, contains('প্রশ্ন ১'));
      expect(ch1.questions[0].solutionText, contains('ব্যাংক কাকে বলে?'));
      expect(ch1.questions[1].title, contains('প্রশ্ন ২'));

      // Chapter 2
      final ch2 = content.chapters[1];
      expect(ch2.number, 2);
      expect(ch2.title, '97th BPE (Nov 2023)');
      expect(ch2.questions.length, 1);
      expect(ch2.questions[0].title, contains('Question 1'));
    });

    test('generateBookletPdf builds a valid multi-page A4 PDF document',
        () async {
      const sampleQuestion = StudyBookletQuestionItem(
        questionNumber: '1',
        title: 'প্রশ্ন ১ [মান: ১০ + ১০ = ২০]',
        moduleCode: 'A',
        pieces: [
          StudyBookletText(
            'ব্যাংক কোম্পানি আইন ১৯৯১ এবং বাংলাদেশ ব্যাংকের নির্দেশনাবলী অনুসারে তফসিলি ব্যাংকের লাইসেন্সিং প্রক্রিয়া সম্পন্ন হয়।',
          ),
        ],
      );

      const content = StudyBookletContent(
        subjectTitle: 'Laws & Practice of General Banking',
        subjectCode: 'LPGB',
        tourName: 'JAIBB Diploma Study Circle',
        inviteCode: 'TEST1234',
        chapters: [
          StudyBookletChapterItem(
            number: 1,
            title: '96th BPE (May 2023)',
            questions: [sampleQuestion],
          ),
        ],
      );

      final pdfBytes =
          await generator.generateBookletPdf(content, isBengali: true);

      expect(pdfBytes, isNotEmpty);
      expect(String.fromCharCodes(pdfBytes.sublist(0, 5)), '%PDF-');
      expect(pdfBytes.length, greaterThan(2000));
    });

    test('the booklet is set in Noto Sans Bengali, Regular and Bold', () async {
      const content = StudyBookletContent(
        subjectTitle: 'Laws & Practice of General Banking',
        subjectCode: 'LPGB',
        tourName: 'JAIBB Diploma Study Circle',
        chapters: [
          StudyBookletChapterItem(
            number: 1,
            title: '96th BPE (May 2023)',
            questions: [
              StudyBookletQuestionItem(
                questionNumber: '1',
                title: 'প্রশ্ন ১ [মান: ১০]',
                moduleCode: 'A',
                pieces: [
                  StudyBookletText(
                    '**ব্যাংক** কাকে বলে? Define a bank under the Bank Company Act.',
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final pdfBytes =
          await generator.generateBookletPdf(content, isBengali: true);
      final text = String.fromCharCodes(pdfBytes);

      expect(text, contains('NotoSansBengali-Regular'));
      expect(text, contains('NotoSansBengali-Bold'));
      expect(text, isNot(contains('HindSiliguri')));
    });

    StudyBookletContent twoChapters() => const StudyBookletContent(
          subjectTitle: 'LPGB',
          tourName: 'Circle',
          chapters: [
            StudyBookletChapterItem(number: 1, title: 'One', questions: []),
            StudyBookletChapterItem(number: 2, title: 'Two', questions: []),
          ],
        );

    test('reports each chapter as it is laid out', () async {
      final seen = <String>[];
      await generator.generateBookletPdf(
        twoChapters(),
        onProgress: (done, total) => seen.add('$done/$total'),
      );
      expect(seen, ['0/2', '1/2', '2/2']);
    });

    test('stops at the next chapter once it is cancelled', () async {
      var cancelled = false;
      final seen = <int>[];
      await expectLater(
        generator.generateBookletPdf(
          twoChapters(),
          isCancelled: () => cancelled,
          onProgress: (done, _) {
            seen.add(done);
            if (done == 1) cancelled = true;
          },
        ),
        throwsA(isA<StudyBookletCancelled>()),
      );
      expect(seen, [0, 1]);
    });

    test('generateBranchNoticePoster builds a valid A4 notice poster with QR',
        () async {
      const content = StudyBookletContent(
        subjectTitle: 'Laws & Practice of General Banking',
        subjectCode: 'LPGB',
        tourName: 'Sonali Bank Principal Office JAIBB Circle',
        tourDescription: 'Daily 30-min preparation group for banking diploma',
        inviteCode: 'JOINBANK',
        chapters: [],
      );

      final posterBytes = await generator.generateBranchNoticePoster(content);

      expect(posterBytes, isNotEmpty);
      expect(String.fromCharCodes(posterBytes.sublist(0, 5)), '%PDF-');
      expect(posterBytes.length, greaterThan(2000));
    });

    test(
        'isBankingContent distinguishes banking groups from generic study circles',
        () {
      const bankingContent1 = StudyBookletContent(
        subjectTitle: 'Basic Accounting (BA)',
        subjectCode: 'JAIBB',
        tourName: 'dhh',
        chapters: [],
      );
      expect(
          StudyBookletPdfGenerator.isBankingContent(bankingContent1), isTrue);

      const bankingContent2 = StudyBookletContent(
        subjectTitle: 'Banking Laws',
        tourName: 'Sonali Bank Circle',
        chapters: [],
      );
      expect(
          StudyBookletPdfGenerator.isBankingContent(bankingContent2), isTrue);

      const genericContent = StudyBookletContent(
        subjectTitle: 'gyg',
        tourName: 'dhh',
        chapters: [
          StudyBookletChapterItem(number: 1, title: 'fh', questions: []),
        ],
      );
      expect(
          StudyBookletPdfGenerator.isBankingContent(genericContent), isFalse);
    });

    test(
        'generateBookletPdf and generateBranchNoticePoster work for generic non-banking circle',
        () async {
      const genericContent = StudyBookletContent(
        subjectTitle: 'gyg',
        tourName: 'dhh',
        inviteCode: 'KHLDFFV4',
        chapters: [
          StudyBookletChapterItem(number: 1, title: 'fh', questions: []),
        ],
      );

      final bookletBytes =
          await generator.generateBookletPdf(genericContent, isBengali: true);
      expect(bookletBytes, isNotEmpty);
      expect(String.fromCharCodes(bookletBytes.sublist(0, 5)), '%PDF-');

      final posterBytes =
          await generator.generateBranchNoticePoster(genericContent);
      expect(posterBytes, isNotEmpty);
      expect(String.fromCharCodes(posterBytes.sublist(0, 5)), '%PDF-');
    });
  });

  group('a booklet for one chapter', () {
    // One chapter whose solution note has two questions.
    StudyBookletContent chapterContent({required bool scoped}) {
      final material = StudyMaterial(
        id: 'm1',
        bookId: 'b1',
        chapterId: 'c1',
        title: 'বাংলা সমাধান',
        kind: StudyMaterialKind.note,
        status: StudyMaterialStatus.published,
        createdByEmail: 'test@bhromon.fun',
        createdAt: DateTime(2026, 1, 1),
      );
      return StudyBookletPdfGenerator.extractContent(
        subjectTitle: 'Laws and Practice of General Banking',
        subjectCode: 'LPGB',
        tourName: 'Sonali Bank JAIBB Circle',
        chapters: const [StudyChapter(id: 'c1', number: 1, title: 'First')],
        materials: [material],
        solutionTexts: {
          'm1': '''
### প্রশ্ন ১ [মান: ১০]
ব্যাংক কাকে বলে?
ব্যাংক হলো আমানত গ্রহণকারী ও ঋণদানকারী প্রতিষ্ঠান।

### প্রশ্ন ২ [মান: ১০]
কেওয়াইসি কী?
গ্রাহককে সনাক্তকরণ প্রক্রিয়া।
''',
        },
        isBengali: true,
        scopedToChapter: scoped,
      );
    }

    test('its cover names the chapter and counts its questions, in Bengali',
        () {
      final cover = StudyBookletPdfGenerator.coverText(
        chapterContent(scoped: true),
        isBengali: true,
      );

      expect(cover.subtitle, 'অধ্যায় ১: First');
      expect(cover.highlight1, '• ২টি প্রশ্ন ও বিস্তারিত সমাধান');
      expect(cover.highlight1, isNot(contains('বিগত পরীক্ষা সেশন')));
    });

    test('its cover names the chapter and counts its questions, in English',
        () {
      final cover = StudyBookletPdfGenerator.coverText(
        chapterContent(scoped: true),
        isBengali: false,
      );

      expect(cover.subtitle, 'Chapter 1: First');
      expect(cover.highlight1, '• 2 Questions with Detailed Solutions');
    });

    test(
        'the whole-book cover keeps its past-session line for a banking subject',
        () {
      final cover = StudyBookletPdfGenerator.coverText(
        chapterContent(scoped: false),
        isBengali: true,
      );

      expect(
          cover.subtitle, startsWith('Laws and Practice of General Banking —'));
      expect(cover.highlight1, contains('বিগত পরীক্ষা সেশন'));
    });

    test('a one-chapter booklet is made as a PDF', () async {
      final bytes = await generator.generateBookletPdf(
        chapterContent(scoped: true),
        isBengali: true,
      );

      expect(bytes.length, greaterThan(2000));
      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    });
  });
}
