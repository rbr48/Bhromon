import 'dart:typed_data';

import 'package:bangla_pdf/bangla_pdf.dart'
    show BanglaFontManager, BanglaPdf, BanglaShapingMode;
import 'package:bangla_pdf/widgets.dart' as pw;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';

import '../domain/services/study_pack_rules.dart';

/// The words of the study pack's headings and labels, in the language the member reads.
class StudyPackLabels {
  const StudyPackLabels({
    required this.summaries,
    required this.answers,
    required this.glossary,
    required this.recaps,
    required this.materials,
    required this.covered,
    required this.hard,
    required this.openQuestions,
    required this.link,
    required this.footer,
  });

  final String summaries;
  final String answers;
  final String glossary;
  final String recaps;
  final String materials;
  final String covered;
  final String hard;
  final String openQuestions;
  final String link;
  final String footer;
}

/// Makes the study pack of a book as a PDF, on the device. The bundled fonts and the Bengali shaping are the same as
/// the tour record uses, so Bengali letters join and vowel signs sit in the right place. The pack carries only what
/// [pack] holds: titles, summaries, answers, terms, recaps, and links. No file and no score goes in.
Future<Uint8List> buildStudyPackPdf(
    StudyPack pack, StudyPackLabels labels) async {
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

  final document = pw.Document(
    compress: true,
    theme: pw.ThemeData.withFont(
      base: regular,
      bold: bold,
      italic: regular,
      boldItalic: bold,
      fontFallback: [bengali, BanglaFontManager().defaultFont],
    ),
    title: pack.bookTitle,
    author: 'Bhromon',
    creator: 'Bhromon',
  );

  pw.Widget heading(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
        child: pw.Text(
          text,
          style:
              const pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
        ),
      );

  pw.Widget bold1(String text) => pw.Text(
        text,
        style: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
      );

  final body = <pw.Widget>[
    pw.Text(
      pack.bookTitle,
      style: const pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
    ),
    if (pack.chapters.isNotEmpty) ...[
      heading(labels.summaries),
      for (final chapter in pack.chapters) ...[
        bold1('${chapter.number}. ${chapter.title}'),
        pw.SizedBox(height: 4),
        pw.Text(chapter.summary),
        pw.SizedBox(height: 10),
      ],
    ],
    if (pack.answers.isNotEmpty) ...[
      heading(labels.answers),
      for (final answer in pack.answers) ...[
        bold1(answer.question),
        pw.SizedBox(height: 4),
        pw.Text(answer.answer),
        pw.SizedBox(height: 10),
      ],
    ],
    if (pack.terms.isNotEmpty) ...[
      heading(labels.glossary),
      for (final term in pack.terms)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Text('${term.term} — ${term.definition}'),
        ),
    ],
    if (pack.recaps.isNotEmpty) ...[
      heading(labels.recaps),
      for (final recap in pack.recaps) ...[
        bold1(recap.title),
        if (recap.covered.isNotEmpty)
          pw.Text('${labels.covered}: ${recap.covered}'),
        if (recap.hard.isNotEmpty) pw.Text('${labels.hard}: ${recap.hard}'),
        for (final question in recap.openQuestions)
          pw.Text('${labels.openQuestions}: $question'),
        pw.SizedBox(height: 10),
      ],
    ],
    if (pack.materials.isNotEmpty) ...[
      heading(labels.materials),
      for (final material in pack.materials)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Text(
            material.url == null
                ? material.title
                : '${material.title} — ${labels.link}: ${material.url}',
          ),
        ),
    ],
  ];

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      footer: (context) => pw.Text(
        labels.footer,
        style: const pw.TextStyle(fontSize: 8),
      ),
      build: (context) => body,
    ),
  );
  return document.save();
}
