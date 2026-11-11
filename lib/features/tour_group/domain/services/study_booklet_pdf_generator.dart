import 'dart:typed_data';

import 'package:bangla_pdf/bangla_pdf.dart'
    show BanglaFontManager, BanglaPdf, BanglaShapingMode;
import 'package:bangla_pdf/widgets.dart' as pw;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';

import '../models/study_material_models.dart';
import '../models/study_models.dart';
import '../models/study_syllabus_models.dart';
import 'ppc_curve.dart';
import 'ppc_pdf_figure.dart';

/// One part of a question's model solution: prose, or a figure in its place.
sealed class StudyBookletPiece {
  const StudyBookletPiece();
}

/// Prose from the solution, cleaned for the page.
final class StudyBookletText extends StudyBookletPiece {
  final String text;

  const StudyBookletText(this.text);
}

/// A chart from a `chart:ppc` fence, drawn as vector art where the fence was.
final class StudyBookletFigure extends StudyBookletPiece {
  final PpcSpec spec;

  const StudyBookletFigure(this.spec);
}

/// Question data for inclusion in the printable examination booklet.
class StudyBookletQuestionItem {
  final String questionNumber;
  final String title;
  final String? moduleCode;

  /// The model solution in order: prose, with any figures between it.
  final List<StudyBookletPiece> pieces;

  const StudyBookletQuestionItem({
    required this.questionNumber,
    required this.title,
    this.moduleCode,
    required this.pieces,
  });

  /// The prose of the solution, without its figures.
  String get solutionText => pieces
      .whereType<StudyBookletText>()
      .map((piece) => piece.text)
      .join('\n\n');
}

/// Chapter/exam session data for the printable booklet.
class StudyBookletChapterItem {
  final int number;
  final String title;
  final List<StudyBookletQuestionItem> questions;

  const StudyBookletChapterItem({
    required this.number,
    required this.title,
    required this.questions,
  });
}

/// Complete content specification for the printable booklet and poster generator.
class StudyBookletContent {
  final String subjectTitle;
  final String? subjectCode;
  final String tourName;
  final String? tourDescription;
  final String? inviteCode;
  final List<StudyBookletChapterItem> chapters;

  const StudyBookletContent({
    required this.subjectTitle,
    this.subjectCode,
    required this.tourName,
    this.tourDescription,
    this.inviteCode,
    required this.chapters,
  });
}

/// Thrown by [StudyBookletPdfGenerator.generateBookletPdf] when the caller cancels it.
class StudyBookletCancelled implements Exception {
  const StudyBookletCancelled();
}

/// Service generating duplex-printable A4 booklets and branch notice board posters.
/// 100% deterministic native PDF layout using [bangla_pdf] with zero external AI calls.
class StudyBookletPdfGenerator {
  const StudyBookletPdfGenerator();

  /// Extracts questions and model solutions from chapters and materials into a [StudyBookletContent].
  static StudyBookletContent extractContent({
    required String subjectTitle,
    String? subjectCode,
    required String tourName,
    String? tourDescription,
    String? inviteCode,
    required List<StudyChapter> chapters,
    required List<StudyMaterial> materials,
    required Map<String, String> solutionTexts,
    bool isBengali = true,
  }) {
    final chapterItems = <StudyBookletChapterItem>[];

    for (final chapter in chapters) {
      final chapterMaterials = materials
          .where((m) => m.chapterId == chapter.id && m.isPublished)
          .toList();

      // Find preferred material (Bengali vs English)
      StudyMaterial? targetMaterial;
      if (isBengali) {
        for (final m in chapterMaterials) {
          if (m.title.contains('বাংলা') ||
              m.title.toLowerCase().contains('bangla')) {
            targetMaterial = m;
            break;
          }
        }
        targetMaterial ??=
            chapterMaterials.isNotEmpty ? chapterMaterials.first : null;
      } else {
        for (final m in chapterMaterials) {
          if (m.title.toLowerCase().contains('english') ||
              !m.title.contains('বাংলা')) {
            targetMaterial = m;
            break;
          }
        }
        targetMaterial ??=
            chapterMaterials.isNotEmpty ? chapterMaterials.first : null;
      }

      String? rawContent;
      if (targetMaterial != null) {
        rawContent = solutionTexts[targetMaterial.id] ?? targetMaterial.body;
      }

      final questionItems = <StudyBookletQuestionItem>[];
      if (rawContent != null && rawContent.trim().isNotEmpty) {
        final parsedQuestions = _parseQuestionsFromMarkdown(
          rawContent,
          subjectTitle: subjectTitle,
        );
        questionItems.addAll(parsedQuestions);
      }

      chapterItems.add(
        StudyBookletChapterItem(
          number: chapter.number,
          title: chapter.title,
          questions: questionItems,
        ),
      );
    }

    return StudyBookletContent(
      subjectTitle: subjectTitle,
      subjectCode: subjectCode,
      tourName: tourName,
      tourDescription: tourDescription,
      inviteCode: inviteCode,
      chapters: chapterItems,
    );
  }

  static List<StudyBookletQuestionItem> _parseQuestionsFromMarkdown(
    String text, {
    required String subjectTitle,
  }) {
    final questionPattern = RegExp(
      r'^(#{1,3})\s+(.*?(?:Question|প্রশ্ন|PART|GROUP|বিভাগ).*?)$',
      multiLine: true,
      caseSensitive: false,
    );

    var matches = questionPattern.allMatches(text).toList();

    if (matches.isEmpty) {
      final generalPattern = RegExp(
        r'^(#{1,3})\s+(.+)$',
        multiLine: true,
      );
      final generalMatches = generalPattern.allMatches(text).toList();
      if (generalMatches.length >= 2) {
        matches = generalMatches;
      }
    }

    if (matches.isEmpty) {
      return [
        StudyBookletQuestionItem(
          questionNumber: '1',
          title: 'Examination Solution',
          pieces: solutionPieces(text),
        ),
      ];
    }

    final questions = <StudyBookletQuestionItem>[];

    for (int i = 0; i < matches.length; i++) {
      final match = matches[i];
      final headingText = match.group(2)?.trim() ?? '';
      final start = match.start;
      final end = (i + 1 < matches.length) ? matches[i + 1].start : text.length;
      final sectionText = text.substring(start, end).trim();

      // Clean title from backslash escaped brackets like \[Marks: ...\]
      final clean = headingText
          .replaceAll(r'\[', '[')
          .replaceAll(r'\]', ']')
          .replaceAll('**', '')
          .trim();

      final mod =
          StudySyllabusCatalog.identifyModule(subjectTitle, sectionText);

      // Extract solution text (text below the heading)
      final headingLineEnd = sectionText.indexOf('\n');
      final solutionBody =
          (headingLineEnd != -1 && headingLineEnd < sectionText.length)
              ? sectionText.substring(headingLineEnd).trim()
              : sectionText;

      questions.add(
        StudyBookletQuestionItem(
          questionNumber: '${i + 1}',
          title: clean,
          moduleCode: mod?.code,
          pieces: solutionPieces(solutionBody),
        ),
      );
    }

    return questions;
  }

  static String _sanitizeMarkdownForPdf(String raw) {
    return raw
        .replaceAll(r'\[', '[')
        .replaceAll(r'\]', ']')
        .replaceAll(RegExp(r'\*\*|__'), '')
        .replaceAll(RegExp(r'`{1,3}'), '')
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  /// Splits a solution into prose and figures, in order. A `chart:ppc` fence
  /// that parses becomes a [StudyBookletFigure]; anything else stays in the prose
  /// and is cleaned as before. A solution with no figure is one prose piece,
  /// exactly as it was before figures existed.
  static List<StudyBookletPiece> solutionPieces(String raw) {
    final text = raw.replaceAll('\r\n', '\n');
    final fence = RegExp(
      r'^```[ \t]*chart:ppc[ \t]*\n([\s\S]*?)^```[ \t]*$',
      multiLine: true,
    );
    final pieces = <StudyBookletPiece>[];
    var cursor = 0;
    for (final match in fence.allMatches(text)) {
      final spec = PpcSpec.parse(match.group(1) ?? '');
      if (spec == null) continue;
      pieces
        ..add(StudyBookletText(
          _sanitizeMarkdownForPdf(text.substring(cursor, match.start)),
        ))
        ..add(StudyBookletFigure(spec));
      cursor = match.end;
    }
    pieces.add(
      StudyBookletText(_sanitizeMarkdownForPdf(text.substring(cursor))),
    );
    return [
      for (final piece in pieces)
        if (piece is! StudyBookletText || piece.text.isNotEmpty) piece,
    ];
  }

  /// Loads fonts and configures [BanglaPdf] for typography.
  Future<pw.Document> _createDocument(String title) async {
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/HindSiliguri-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/HindSiliguri-Bold.ttf'),
    );
    final bengali = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansBengali.ttf'),
    );

    BanglaPdf.configure(
      shapingMode: BanglaShapingMode.unicode,
      defaultFont: regular,
      fallbackFonts: [bengali, BanglaFontManager().defaultFont],
    );

    return pw.Document(
      compress: true,
      theme: pw.ThemeData.withFont(
        base: regular,
        bold: bold,
        italic: regular,
        boldItalic: bold,
        fontFallback: [bengali, BanglaFontManager().defaultFont],
      ),
      title: title,
      author: 'Bhromon Banking Study Circle',
      creator: 'Bhromon',
    );
  }

  /// Returns whether this booklet or poster belongs to a banking exam circle (IBB / JAIBB / AIBB).
  static bool isBankingContent(StudyBookletContent content) {
    final titleAndName =
        '${content.tourName} ${content.subjectTitle} ${content.subjectCode ?? ''}'
            .toLowerCase();
    return RegExp(r'\b(jaibb|aibb|ibb|banking|banker)\b', caseSensitive: false)
            .hasMatch(titleAndName) ||
        titleAndName.contains('ব্যাংকিং') ||
        titleAndName.contains('ব্যাংকার্স');
  }

  /// Generates a duplex-printable A4 examination question bank & model solutions booklet.
  ///
  /// The chapters are laid out one at a time, with a pause after each, so the screen stays
  /// responsive on the web, where the layout runs on the only thread. [onProgress] is told
  /// how many chapters are done. When [isCancelled] turns true the work stops at the next
  /// chapter with [StudyBookletCancelled].
  Future<Uint8List> generateBookletPdf(
    StudyBookletContent content, {
    bool isBengali = true,
    bool Function()? isCancelled,
    void Function(int done, int total)? onProgress,
  }) async {
    final doc = await _createDocument('${content.subjectTitle} - Exam Booklet');
    final total = content.chapters.length;
    var done = 0;
    Future<void> breathe() async {
      // Lets the frame, the taps and the timers run before the next chapter.
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (isCancelled?.call() ?? false) throw const StudyBookletCancelled();
    }

    final isBanking = isBankingContent(content);

    // 1. Cover Page
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context context) {
          final institutionBadge = isBanking
              ? (isBengali
                  ? 'দ্য ইনস্টিটিউট অব ব্যাংকার্স, বাংলাদেশ (IBB)'
                  : 'THE INSTITUTE OF BANKERS, BANGLADESH (IBB)')
              : (content.tourName.isNotEmpty
                  ? '${content.tourName.toUpperCase()} STUDY CIRCLE'
                  : (isBengali
                      ? 'পরীক্ষা প্রস্তুতি ও স্টাডি সার্কেল বুকলেট'
                      : 'EXAM PREPARATION & STUDY BOOKLET'));

          final subtitleText = isBanking
              ? (isBengali
                  ? '${content.subjectTitle} — বিগত প্রশ্নপত্র ও মডেল সমাধান'
                  : '${content.subjectTitle} — Question Bank & Examiner-Grade Solutions')
              : (isBengali
                  ? '${content.subjectTitle} — প্রশ্নব্যাংক ও পরীক্ষক-মানের মডেল সমাধান'
                  : '${content.subjectTitle} — Question Bank & Model Solutions');

          final highlight1 = isBanking
              ? (isBengali
                  ? '• ৭টি বিগত পরীক্ষা সেশন (৯৬তম - ৭ম নতুন BPE)'
                  : '• 7 Past Exam Sessions (96th BPE - 7th New BPE)')
              : (isBengali
                  ? '• ${content.chapters.isNotEmpty ? content.chapters.length : 1}টি অধ্যায় অন্তর্ভুক্ত'
                  : '• ${content.chapters.isNotEmpty ? content.chapters.length : 1} Chapters Included');

          final highlight2 = isBengali
              ? '• ১০০% নির্ভুল পরীক্ষক-মানের বিস্তারিত সমাধান'
              : '• 100% Comprehensive Examiner-Grade Solutions';

          final highlight3 = isBanking
              ? (isBengali
                  ? '• সিলেবাস মডিউল ম্যাপিং ও ডুও-ল্যাঙ্গুয়েজ সাপোর্ট'
                  : '• Official Syllabus Module Mapping (A-E)')
              : (isBengali
                  ? '• অফলাইন ভল্ট ও ডুও-ল্যাঙ্গুয়েজ স্টাডি সাপোর্ট'
                  : '• Offline Vault & Dual-Language Study Support');

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Spacer(flex: 1),
              // Institutional Header
              pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: pw.BoxDecoration(
                  color: const PdfColor(0.08, 0.25, 0.18),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Text(
                  institutionBadge,
                  style: const pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 24),

              // Subject Title
              pw.Text(
                content.subjectTitle,
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(
                  fontSize: 26,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor(0.08, 0.25, 0.18),
                ),
              ),
              if (content.subjectCode != null &&
                  content.subjectCode!.trim().isNotEmpty) ...[
                pw.SizedBox(height: 8),
                pw.Text(
                  'Subject Code: ${content.subjectCode!.trim()}',
                  style: const pw.TextStyle(
                    fontSize: 13,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
              pw.SizedBox(height: 16),
              pw.Container(
                width: 120,
                height: 2.5,
                color: const PdfColor(0.08, 0.25, 0.18),
              ),
              pw.SizedBox(height: 16),

              // Subtitle
              pw.Text(
                subtitleText,
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(
                  fontSize: 14,
                  color: PdfColors.grey800,
                ),
              ),
              pw.SizedBox(height: 24),

              // Feature Badges
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                      color: const PdfColor(0.08, 0.25, 0.18), width: 1),
                  borderRadius: pw.BorderRadius.circular(8),
                  color: const PdfColor(0.96, 0.98, 0.97),
                ),
                child: pw.Column(
                  children: [
                    pw.Text(
                      highlight1,
                      style: const pw.TextStyle(fontSize: 10.5),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      highlight2,
                      style: const pw.TextStyle(fontSize: 10.5),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      highlight3,
                      style: const pw.TextStyle(fontSize: 10.5),
                    ),
                  ],
                ),
              ),
              pw.Spacer(flex: 2),

              // Footer Metadata
              pw.Divider(color: PdfColors.grey400),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Study Circle: ${content.tourName}',
                    style: const pw.TextStyle(
                        fontSize: 9.5, color: PdfColors.grey700),
                  ),
                  if (content.inviteCode != null)
                    pw.Text(
                      'Invite Code: ${content.inviteCode}',
                      style: const pw.TextStyle(
                        fontSize: 9.5,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor(0.08, 0.25, 0.18),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );

    // 2. Table of Contents & Chapter Content
    for (final chapter in content.chapters) {
      onProgress?.call(done, total);
      await breathe();
      done++;
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (pw.Context ctx) {
            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 12),
              padding: const pw.EdgeInsets.only(bottom: 4),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.8),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    content.subjectTitle,
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey600),
                  ),
                  pw.Text(
                    chapter.title,
                    style: const pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor(0.08, 0.25, 0.18),
                    ),
                  ),
                ],
              ),
            );
          },
          footer: (pw.Context ctx) {
            return pw.Container(
              margin: const pw.EdgeInsets.only(top: 12),
              padding: const pw.EdgeInsets.only(top: 4),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  top: pw.BorderSide(color: PdfColors.grey300, width: 0.8),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '${content.subjectTitle} ${isBengali ? 'স্টাডি বুকলেট' : 'Study Booklet'}',
                    style: const pw.TextStyle(
                        fontSize: 8.5, color: PdfColors.grey500),
                  ),
                  pw.Text(
                    'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                    style: const pw.TextStyle(
                        fontSize: 8.5, color: PdfColors.grey600),
                  ),
                ],
              ),
            );
          },
          build: (pw.Context ctx) {
            return [
              // Chapter Banner
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 16),
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: pw.BoxDecoration(
                  color: const PdfColor(0.93, 0.96, 0.94),
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(
                      color: const PdfColor(0.08, 0.25, 0.18), width: 0.8),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Chapter ${chapter.number}: ${chapter.title}',
                      style: const pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor(0.08, 0.25, 0.18),
                      ),
                    ),
                    pw.Text(
                      '${chapter.questions.length} Questions',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
              ),

              // Questions & Answers
              for (final q in chapter.questions) ...[
                pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 14),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // Question Title Header
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.grey200,
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.Row(
                          children: [
                            if (q.moduleCode != null) ...[
                              pw.Container(
                                padding: const pw.EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: pw.BoxDecoration(
                                  color: const PdfColor(0.08, 0.25, 0.18),
                                  borderRadius: pw.BorderRadius.circular(3),
                                ),
                                child: pw.Text(
                                  'Mod ${q.moduleCode}',
                                  style: const pw.TextStyle(
                                    color: PdfColors.white,
                                    fontSize: 8.5,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                              ),
                              pw.SizedBox(width: 6),
                            ],
                            pw.Expanded(
                              child: pw.Text(
                                q.title,
                                style: const pw.TextStyle(
                                  fontSize: 11,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.black,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      pw.SizedBox(height: 6),

                      // Solution Body: prose, with each figure in its place
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 4),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            for (final (index, piece) in q.pieces.indexed) ...[
                              if (index > 0) pw.SizedBox(height: 6),
                              switch (piece) {
                                StudyBookletText(:final text) => pw.Text(
                                    text,
                                    style: const pw.TextStyle(
                                      fontSize: 9.5,
                                      lineSpacing: 2,
                                      color: PdfColors.grey900,
                                    ),
                                  ),
                                StudyBookletFigure(:final spec) => pw.Center(
                                    child: ppcPdfFigure(spec, width: 440),
                                  ),
                              },
                            ],
                          ],
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Divider(color: PdfColors.grey300, thickness: 0.5),
                    ],
                  ),
                ),
              ],
            ];
          },
        ),
      );
    }

    onProgress?.call(total, total);
    await breathe();
    return doc.save();
  }

  /// Generates a high-impact A4 recruitment & notice board poster for bank branches.
  Future<Uint8List> generateBranchNoticePoster(
    StudyBookletContent content, {
    Uint8List? qrImageBytes,
  }) async {
    final doc = await _createDocument('${content.tourName} - Branch Poster');

    final isBanking = isBankingContent(content);

    final posterHeaderBadge = isBanking
        ? 'THE INSTITUTE OF BANKERS, BANGLADESH (IBB)'
        : (content.tourName.isNotEmpty
            ? '${content.tourName.toUpperCase()} NOTICE BOARD'
            : 'STUDY CIRCLE NOTICE BOARD');

    final posterMainHeading = content.subjectTitle.isNotEmpty &&
            content.subjectTitle != content.tourName
        ? content.subjectTitle
        : (content.tourName.isNotEmpty
            ? content.tourName
            : (isBanking
                ? 'JAIBB Examination Preparation'
                : 'Study Circle Preparation'));

    final posterSubtitle = isBanking
        ? (content.subjectTitle.isNotEmpty &&
                content.subjectTitle != posterMainHeading
            ? '${content.subjectTitle} — ব্যাংকিং প্রফেশনাল পরীক্ষা প্রস্তুতি'
            : 'ব্যাংকিং প্রফেশনাল পরীক্ষা প্রস্তুতি স্টাডি সার্কেল')
        : (content.subjectTitle.isNotEmpty &&
                content.subjectTitle != posterMainHeading
            ? '${content.subjectTitle} — পরীক্ষা প্রস্তুতি ও স্টাডি সার্কেল'
            : 'সম্মিলিত পরীক্ষা প্রস্তুতি স্টাডি সার্কেল');

    final posterHighlight1 = isBanking
        ? '৭টি বিগত পরীক্ষার প্রশ্ন ও পরীক্ষক-মানের মডেল সমাধান (বাংলা ও ইংরেজি)'
        : 'সম্মিলিত অধ্যায়ভিত্তিক প্রস্তুতি ও পরীক্ষক-মানের মডেল সমাধান';

    final posterHighlight6 = isBanking
        ? 'দৈনিক ব্রাঞ্চ স্টাডি স্ট্রিক ও সহকর্মী অ্যাকাউন্টেবিলিটি'
        : 'দৈনিক স্টাডি স্ট্রিক ও সহপাঠী অ্যাকাউন্টেবিলিটি';

    final posterFooter = isBanking
        ? 'শাখার নোটিশ বোর্ডে লাগিয়ে সহকর্মীদের সাথে একসাথে ব্যাংকিং ডিপ্লোমা প্রস্তুতি নিন'
        : 'নোটিশ বোর্ডে লাগিয়ে সহপাঠী ও বন্ধুদের সাথে একসাথে স্টাডি সার্কেলে যোগ দিন';

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(
                  color: const PdfColor(0.08, 0.25, 0.18), width: 3),
              borderRadius: pw.BorderRadius.circular(12),
            ),
            padding: const pw.EdgeInsets.all(24),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                // Top Header Badge
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: pw.BoxDecoration(
                    color: const PdfColor(0.08, 0.25, 0.18),
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Text(
                    posterHeaderBadge,
                    style: const pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(height: 16),

                // Main Heading
                pw.Text(
                  posterMainHeading,
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor(0.08, 0.25, 0.18),
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  posterSubtitle,
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(
                    fontSize: 16,
                    color: PdfColors.grey800,
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Container(
                  width: 80,
                  height: 2,
                  color: const PdfColor(0.08, 0.25, 0.18),
                ),
                pw.SizedBox(height: 16),

                // Group Name Banner
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.symmetric(vertical: 8),
                  decoration: pw.BoxDecoration(
                    color: const PdfColor(0.93, 0.96, 0.94),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Text(
                    content.tourName,
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor(0.08, 0.25, 0.18),
                    ),
                  ),
                ),
                pw.SizedBox(height: 16),

                // Feature Highlights Grid
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    children: [
                      _posterFeatureRow('•', posterHighlight1),
                      _posterFeatureRow('•',
                          '৫-বক্স লাইটনার অ্যালগরিদম স্পেসড-রিপিটিশন ফ্ল্যাশকার্ড'),
                      _posterFeatureRow('•',
                          '৩ ঘণ্টার পূর্ণাঙ্গ টাইমড এক্সাম সিমুলেটর ও স্ক্র্যাচপ্যাড'),
                      _posterFeatureRow('•',
                          'কমিউট অডিও প্লেয়ার — ট্রাফিক ও হাঁটার সময় হাতবিহীন সমাধান শ্রবণ'),
                      _posterFeatureRow('•',
                          '১০০% অফলাইন ভল্ট — নেটওয়ার্ক ছাড়া জিরো-ডাটা প্রস্তুতি'),
                      _posterFeatureRow('•', posterHighlight6),
                    ],
                  ),
                ),
                pw.SizedBox(height: 20),

                // QR Code Section
                pw.Text(
                  'স্ক্যান করে এখনই স্টাডি সার্কেলে যোগ দিন',
                  style: const pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor(0.08, 0.25, 0.18),
                  ),
                ),
                pw.SizedBox(height: 8),

                if (content.inviteCode != null &&
                    content.inviteCode!.trim().isNotEmpty) ...[
                  pw.Container(
                    width: 140,
                    height: 140,
                    padding: const pw.EdgeInsets.all(6),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                          color: const PdfColor(0.08, 0.25, 0.18), width: 1.5),
                      borderRadius: pw.BorderRadius.circular(8),
                      color: PdfColors.white,
                    ),
                    child: pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data:
                          'https://app.bhromon.fun/#/join?code=${content.inviteCode!.trim()}',
                      width: 128,
                      height: 128,
                    ),
                  ),
                ] else if (qrImageBytes != null) ...[
                  pw.Container(
                    width: 140,
                    height: 140,
                    padding: const pw.EdgeInsets.all(6),
                    decoration: pw.BoxDecoration(
                      border:
                          pw.Border.all(color: PdfColors.grey400, width: 1.5),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Image(pw.MemoryImage(qrImageBytes)),
                  ),
                ] else ...[
                  pw.Container(
                    width: 140,
                    height: 140,
                    decoration: pw.BoxDecoration(
                      border:
                          pw.Border.all(color: PdfColors.grey400, width: 1.5),
                      borderRadius: pw.BorderRadius.circular(8),
                      color: PdfColors.grey100,
                    ),
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      'QR CODE',
                      style: const pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ),
                ],
                pw.SizedBox(height: 10),

                // Invite Code Box
                if (content.inviteCode != null) ...[
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    decoration: pw.BoxDecoration(
                      color: const PdfColor(0.08, 0.25, 0.18),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Text(
                      'Invite Code: ${content.inviteCode}',
                      style: const pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ],
                pw.Spacer(),

                // Notice Board Footer
                pw.Divider(color: PdfColors.grey300),
                pw.Text(
                  posterFooter,
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(
                    fontSize: 9.5,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'ভ্রমণ (Bhromon) অ্যাপ • ১০০% ফ্রি ও ওপেন সোর্স',
                  style: const pw.TextStyle(
                    fontSize: 8.5,
                    color: PdfColors.grey500,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    return doc.save();
  }

  pw.Widget _posterFeatureRow(String bullet, String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            bullet,
            style: const pw.TextStyle(
              color: PdfColor(0.08, 0.25, 0.18),
              fontWeight: pw.FontWeight.bold,
              fontSize: 11,
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Text(
              text,
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey900),
            ),
          ),
        ],
      ),
    );
  }
}
