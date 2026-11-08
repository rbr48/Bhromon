import 'dart:typed_data';

import 'package:bangla_pdf/bangla_pdf.dart'
    show BanglaFontManager, BanglaPdf, BanglaShapingMode;
import 'package:bangla_pdf/widgets.dart' as pw;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';

import '../domain/models/date_codec.dart';
import '../domain/models/meal_log.dart';
import '../domain/models/tour_group.dart';
import '../domain/services/meal_engine.dart';
import 'monthly_ledger_pdf.dart' show BanglaLedgerFormatter;

/// The data payload needed to render a printable Mess 31-day Meal Sheet and Balance PDF.
class MessMealSheetData {
  const MessMealSheetData({
    required this.group,
    required this.month,
    required this.balance,
    this.dailyLogs = const [],
    required this.generatedAt,
  });

  final TourGroup group;
  final DateTime month;
  final MessMonthlyBalance balance;
  final List<MealLog> dailyLogs;
  final DateTime generatedAt;
}

/// Builds a print-ready, professional Bengali PDF document for mess monthly meal rates
/// and 31-day member meal sheet.
Future<Uint8List> buildMessMealSheetPdf({
  required MessMealSheetData data,
  bool compress = true,
}) async {
  final regularBytes =
      await rootBundle.load('assets/fonts/HindSiliguri-Regular.ttf');
  final boldBytes = await rootBundle.load('assets/fonts/HindSiliguri-Bold.ttf');
  final bengaliBytes =
      await rootBundle.load('assets/fonts/NotoSansBengali.ttf');

  final regular = pw.Font.ttf(regularBytes);
  final bold = pw.Font.ttf(boldBytes);
  final bengali = pw.Font.ttf(bengaliBytes);

  BanglaPdf.configure(
    shapingMode: BanglaShapingMode.unicode,
    defaultFont: regular,
    fallbackFonts: [bengali, BanglaFontManager().defaultFont],
  );

  final document = pw.Document(
    compress: compress,
    theme: pw.ThemeData.withFont(
      base: regular,
      bold: bold,
      italic: regular,
      boldItalic: bold,
      fontFallback: [bengali, BanglaFontManager().defaultFont],
    ),
    title: '${data.group.name} - মেস মিল হিসাব বিবরণী',
    author: 'Bhromon',
    creator: 'Bhromon',
  );

  final writer = _MessMealPdfWriter(data);

  // Page 1: Monthly Balance Sheet & Member Ledgers
  document.addPage(writer.buildSummaryPage());

  // Page 2: 31-day daily meal matrix (if logs exist)
  if (data.dailyLogs.isNotEmpty) {
    document.addPage(writer.buildDailyLogPage());
  }

  return document.save();
}

class _MessMealPdfWriter {
  _MessMealPdfWriter(this.data);

  final MessMealSheetData data;

  static const _navy = PdfColor.fromInt(0xFF14241B);
  static const _green = PdfColor.fromInt(0xFF10B981);
  static const _surface = PdfColor.fromInt(0xFFF0FDF4);
  static const _border = PdfColor.fromInt(0xFFE2E8F0);
  static const _textMuted = PdfColor.fromInt(0xFF64748B);
  static const _textDark = PdfColor.fromInt(0xFF0F172A);

  pw.Page buildSummaryPage() {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            pw.SizedBox(height: 18),
            _buildStatsCards(),
            pw.SizedBox(height: 18),
            _buildMemberTableTitle(),
            pw.SizedBox(height: 8),
            _buildMemberTable(),
            pw.Spacer(),
            _buildFooter(),
          ],
        );
      },
    );
  }

  pw.Widget _buildHeader() {
    final monthName = BanglaLedgerFormatter.formatMonthYearBangla(
      data.month.year,
      data.month.month,
    );

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: _navy,
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                data.group.name,
                style: const pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'মেস মিল ও বাজার মাসিক হিসাব বিবরণী · $monthName',
                style: const pw.TextStyle(
                  color: _green,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'তারিখ: ${BanglaLedgerFormatter.formatShortDateBangla(data.generatedAt)}',
                style: const pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 10,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'তৈরি করেছে: ভ্রমণ (Bhromon)',
                style: const pw.TextStyle(
                  color: _textMuted,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildStatsCards() {
    final totalBazar =
        BanglaLedgerFormatter.formatTakaBangla(data.balance.totalBazarPaisa);
    final totalMeals = BanglaLedgerFormatter.toBanglaDigits(
        data.balance.totalMeals.toString());
    final mealRate = BanglaLedgerFormatter.toBanglaDigits(
        data.balance.mealRateTaka.toStringAsFixed(2));
    final totalDue =
        BanglaLedgerFormatter.formatTakaBangla(data.balance.totalDuePaisa);

    return pw.Row(
      children: [
        _buildStatBox(
            'মোট বাজার খরচ', totalBazar, const PdfColor.fromInt(0xFFD97706)),
        pw.SizedBox(width: 10),
        _buildStatBox('মোট খাওয়া মিল', '$totalMeals টি', _textDark),
        pw.SizedBox(width: 10),
        _buildStatBox('মিল রেট (প্রতি মিল)', '৳ $mealRate', _green),
        pw.SizedBox(width: 10),
        _buildStatBox(
            'মোট বকেয়া', totalDue, const PdfColor.fromInt(0xFFEF4444)),
      ],
    );
  }

  pw.Widget _buildStatBox(String label, String value, PdfColor valueColor) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: pw.BoxDecoration(
          color: _surface,
          borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.all(color: _border),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label,
              style: const pw.TextStyle(color: _textMuted, fontSize: 9),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              value,
              style: pw.TextStyle(
                color: valueColor,
                fontWeight: pw.FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _buildMemberTableTitle() {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'সদস্যদের চূড়ান্ত ব্যালেন্স শিট',
          style: const pw.TextStyle(
            color: _textDark,
            fontWeight: pw.FontWeight.bold,
            fontSize: 13,
          ),
        ),
        pw.Text(
          'মোট সদস্য: ${BanglaLedgerFormatter.toBanglaDigits(data.balance.memberBalances.length.toString())} জন',
          style: const pw.TextStyle(color: _textMuted, fontSize: 10),
        ),
      ],
    );
  }

  pw.Widget _buildMemberTable() {
    final headers = [
      'সদস্যের নাম',
      'মিল',
      'মিল খরচ',
      'বাজার পরিশোধ',
      'জমা ও সেটলমেন্ট',
      'নেট ব্যালেন্স',
      'অবস্থা',
    ];

    final rows = <List<String>>[];

    for (final mb in data.balance.memberBalances) {
      final status = mb.isRefund
          ? 'ফেরত পাবে'
          : mb.isDue
              ? 'বকেয়া'
              : 'পরিশোধিত';

      final net = mb.isRefund
          ? '+${BanglaLedgerFormatter.formatTakaBangla(mb.netBalancePaisa)}'
          : mb.isDue
              ? '-${BanglaLedgerFormatter.formatTakaBangla(mb.netBalancePaisa.abs())}'
              : '৳ ০';

      final totalPaid =
          mb.depositPaidPaisa + mb.settledPaidPaisa - mb.refundReceivedPaisa;

      rows.add([
        mb.displayName,
        '${BanglaLedgerFormatter.toBanglaDigits(mb.mealCount.toString())} টি',
        BanglaLedgerFormatter.formatTakaBangla(mb.mealCostPaisa),
        BanglaLedgerFormatter.formatTakaBangla(mb.bazarPaidPaisa),
        BanglaLedgerFormatter.formatTakaBangla(totalPaid),
        net,
        status,
      ]);
    }

    return pw.Table(
      border: pw.TableBorder.all(color: _border, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(2.5),
        1: const pw.FlexColumnWidth(1.2),
        2: const pw.FlexColumnWidth(1.8),
        3: const pw.FlexColumnWidth(1.8),
        4: const pw.FlexColumnWidth(2.0),
        5: const pw.FlexColumnWidth(2.0),
        6: const pw.FlexColumnWidth(1.6),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _surface),
          children: headers.map((h) {
            return pw.Padding(
              padding:
                  const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 6),
              child: pw.Text(
                h,
                style: const pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 9,
                  color: _textDark,
                ),
              ),
            );
          }).toList(),
        ),
        ...rows.asMap().entries.map((entry) {
          final isEven = entry.key % 2 == 0;
          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: isEven ? PdfColors.white : _surface,
            ),
            children: entry.value.map((cell) {
              return pw.Padding(
                padding:
                    const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                child: pw.Text(
                  cell,
                  style: const pw.TextStyle(fontSize: 8.5, color: _textDark),
                ),
              );
            }).toList(),
          );
        }),
      ],
    );
  }

  pw.Page buildDailyLogPage() {
    return pw.Page(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      build: (ctx) {
        final daysInMonth = mealDaysInMonth(data.month);
        final members = data.balance.memberBalances;

        // Build mapping: dateKey -> email -> total meals
        final dayMap = <int, Map<String, int>>{};
        for (final log in data.dailyLogs) {
          final parts = log.dateKey.split('-');
          if (parts.length == 3) {
            final d = int.tryParse(parts[2]);
            if (d != null) {
              dayMap.putIfAbsent(d, () => {})[normalizeEmail(log.email)] =
                  log.total;
            }
          }
        }

        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              '${data.group.name} - ৩১ দিনের দৈনিক মিল চার্ট (${BanglaLedgerFormatter.formatMonthYearBangla(data.month.year, data.month.month)})',
              style: const pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: _navy,
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(color: _border, width: 0.5),
              children: [
                // Header row: Member, 1..31, Total
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: _surface),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      child: pw.Text('সদস্য',
                          style: const pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 7)),
                    ),
                    for (int day = 1; day <= daysInMonth; day++)
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(2),
                        child: pw.Center(
                          child: pw.Text(
                            BanglaLedgerFormatter.toBanglaDigits(
                                day.toString()),
                            style: const pw.TextStyle(
                                fontWeight: pw.FontWeight.bold, fontSize: 6.5),
                          ),
                        ),
                      ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      child: pw.Center(
                        child: pw.Text('মোট',
                            style: const pw.TextStyle(
                                fontWeight: pw.FontWeight.bold, fontSize: 7)),
                      ),
                    ),
                  ],
                ),
                // Rows for each member
                for (final mb in members)
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(3),
                        child: pw.Text(mb.displayName,
                            style: const pw.TextStyle(fontSize: 7)),
                      ),
                      for (int day = 1; day <= daysInMonth; day++)
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Center(
                            child: pw.Text(
                              BanglaLedgerFormatter.toBanglaDigits(
                                (dayMap[day]?[mb.email] ?? 0).toString(),
                              ),
                              style: const pw.TextStyle(fontSize: 6.5),
                            ),
                          ),
                        ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(3),
                        child: pw.Center(
                          child: pw.Text(
                            BanglaLedgerFormatter.toBanglaDigits(
                                mb.mealCount.toString()),
                            style: const pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 7,
                                color: _green),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            pw.Spacer(),
            _buildFooter(),
          ],
        );
      },
    );
  }

  pw.Widget _buildFooter() {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _border, width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'ভ্রমণ মেস ম্যানেজার · Bhromon Mess Ledger Engine',
            style: const pw.TextStyle(color: _textMuted, fontSize: 8),
          ),
          pw.Text(
            'https://bhromon.fun',
            style: const pw.TextStyle(color: _textMuted, fontSize: 8),
          ),
        ],
      ),
    );
  }
}
