// lib/features/tour_group/data/monthly_ledger_pdf.dart
//
// Automated Bangla PDF Monthly Ledger & MFS (bKash/Nagad/Rocket/Upay) Audit Statement
// generator for Bhromon using `package:bangla_pdf/widgets.dart`.

import 'dart:typed_data';
import 'package:bangla_pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';

import '../domain/models/expense_models.dart';
import '../domain/services/trip_ledger_engine.dart';

/// Localization and Bengali numeral formatting utilities for Bangla PDF generation.
class BanglaLedgerFormatter {
  static const List<String> _banglaDigits = [
    '০',
    '১',
    '২',
    '৩',
    '৪',
    '৫',
    '৬',
    '৭',
    '৮',
    '৯',
  ];

  static const List<String> _banglaMonths = [
    'জানুয়ারি',
    'ফেব্রুয়ারি',
    'মার্চ',
    'এপ্রিল',
    'মে',
    'জুন',
    'জুলাই',
    'আগস্ট',
    'সেপ্টেম্বর',
    'অক্টোবর',
    'নভেম্বর',
    'ডিসেম্বর',
  ];

  /// Converts ASCII digits in [input] to Bengali digits (`০-৯`).
  static String toBanglaDigits(String input) {
    final sb = StringBuffer();
    for (final codeUnit in input.codeUnits) {
      if (codeUnit >= 48 && codeUnit <= 57) {
        sb.write(_banglaDigits[codeUnit - 48]);
      } else {
        sb.writeCharCode(codeUnit);
      }
    }
    return sb.toString();
  }

  /// Formats integer [paisa] into standard Bangladeshi Taka string in Bangla numerals (`৳ ১,২৫০.৫০`).
  static String formatTakaBangla(int paisa, {bool showSign = false}) {
    final isNegative = paisa < 0;
    final absPaisa = paisa.abs();
    final taka = absPaisa ~/ 100;
    final remPaisa = absPaisa % 100;

    final formattedInt = _formatIndianGrouping(taka);
    final decPart =
        remPaisa > 0 ? '.${remPaisa.toString().padLeft(2, '0')}' : '';
    final prefix = isNegative
        ? '-৳ '
        : (showSign && paisa > 0)
            ? '+৳ '
            : '৳ ';
    return '$prefix${toBanglaDigits('$formattedInt$decPart')}';
  }

  /// Formats integer [taka] using Bangladeshi/South Asian लाख/হাজার grouping (`1,25,000`).
  static String _formatIndianGrouping(int value) {
    final s = value.toString();
    if (s.length <= 3) return s;
    final lastThree = s.substring(s.length - 3);
    var other = s.substring(0, s.length - 3);
    final reg = RegExp(r'\B(?=(\d{2})+(?!\d))');
    other = other.replaceAll(reg, ',');
    return '$other,$lastThree';
  }

  static String formatMonthYearBangla(int year, int month) {
    final mName = _banglaMonths[(month - 1).clamp(0, 11)];
    return '$mName ${toBanglaDigits(year.toString())}';
  }

  static String formatShortDateBangla(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    return toBanglaDigits('$d/$m/$y');
  }

  static String archetypeBanglaBadge(String archetype) {
    switch (archetype.trim().toLowerCase()) {
      case 'samity':
        return 'সমিতি মাসিক তহবিল ও কিস্তি প্রতিবেদন';
      case 'mess':
        return 'মেস মাসিক বাজার, মিল ও হিসাব বিবরণী';
      case 'society':
        return 'হাউজিং সোসাইটি মাসিক সার্ভিস চার্জ ও লেজার';
      case 'tour':
      case 'trip':
        return 'ভ্রমণ ও গ্রুপ খরচ চূড়ান্ত প্রতিবেদন';
      case 'family':
        return 'পারিবারিক মাসিক আয়-ব্যয় বিবরণী';
      default:
        return 'গ্রুপ মাসিক আর্থিক হিসাব বিবরণী';
    }
  }
}

/// Generates a print-ready multi-page Bangla PDF statement from a [MonthlyLedgerStatement].
class MonthlyLedgerPdfGenerator {
  static const PdfColor _primaryNavy = PdfColor.fromInt(0xFF1A365D);
  static const PdfColor _accentTeal = PdfColor.fromInt(0xFF0D9488);
  static const PdfColor _surfaceTint = PdfColor.fromInt(0xFFF1F5F9);
  static const PdfColor _borderGrey = PdfColor.fromInt(0xFFCBD5E1);
  static const PdfColor _mutedText = PdfColor.fromInt(0xFF475569);

  /// Builds the PDF document bytes for sharing, printing, or saving locally.
  Future<Uint8List> generate(
    MonthlyLedgerStatement statement, {
    String? preparedByName,
  }) async {
    final pdf = pw.Document(
      title:
          '${statement.groupTitle} - ${BanglaLedgerFormatter.formatMonthYearBangla(statement.year, statement.month)}',
      author: preparedByName ?? 'Bhromon Ledger Engine',
      creator: 'Bhromon Open-Source Group Manager (bangla_pdf)',
    );

    final generatedAtStr =
        BanglaLedgerFormatter.formatShortDateBangla(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => _buildHeader(statement, generatedAtStr),
        footer: (context) => _buildFooter(
            context, statement, preparedByName ?? 'গ্রুপ অ্যাডমিন'),
        build: (context) => [
          pw.SizedBox(height: 12),
          _buildKpiSummaryStrip(statement),
          pw.SizedBox(height: 18),
          _buildSectionTitle(
              '১. সদস্যভিত্তিক মাসিক চূড়ান্ত হিসাব (Member Standing)'),
          pw.SizedBox(height: 6),
          _buildMemberStandingsTable(statement),
          pw.SizedBox(height: 18),
          _buildSectionTitle(
            '২. মোবাইল ব্যাংকিং (bKash / Nagad / Rocket) লেনদেন অডিট লগ',
          ),
          pw.SizedBox(height: 6),
          _buildMfsAuditTable(statement),
          if (statement.recommendedSettlements.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            _buildSectionTitle(
                '৩. বকেয়া নিষ্পত্তির প্রস্তাবনা (Settle-Up Plan)'),
            pw.SizedBox(height: 6),
            _buildRecommendedSettlementsTable(statement),
          ],
          if (statement.monthExpenses.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            _buildSectionTitle(
                '৪. মাসিক খরচের বিস্তারিত তালিকা (Itemized Expenses)'),
            pw.SizedBox(height: 6),
            _buildExpensesTable(statement),
          ],
          pw.SizedBox(height: 24),
          _buildSignatureBlock(statement),
        ],
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildHeader(
    MonthlyLedgerStatement statement,
    String generatedAtStr,
  ) {
    final periodLabel = BanglaLedgerFormatter.formatMonthYearBangla(
      statement.year,
      statement.month,
    );
    final badgeText =
        BanglaLedgerFormatter.archetypeBanglaBadge(statement.groupArchetype);

    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: _primaryNavy, width: 1.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                statement.groupTitle,
                style: const pw.TextStyle(
                  fontSize: 18,
                  color: _primaryNavy,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                badgeText,
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: _accentTeal,
                ),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: const pw.BoxDecoration(
                  color: _primaryNavy,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Text(
                  'হিসাব কাল: $periodLabel',
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.white,
                  ),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'প্রস্তুতির তারিখ: $generatedAtStr | কোড: #${statement.verificationDigest}',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: _mutedText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildKpiSummaryStrip(MonthlyLedgerStatement statement) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        _buildKpiCard(
          label: 'প্রারম্ভিক জের (Opening)',
          value: BanglaLedgerFormatter.formatTakaBangla(
            statement.totalOpeningNetPaisa,
          ),
          subtitle: 'পূর্ববর্তী মাসের উদ্বৃত্ত',
        ),
        pw.SizedBox(width: 8),
        _buildKpiCard(
          label: 'মোট খরচ (Total Expenses)',
          value: BanglaLedgerFormatter.formatTakaBangla(
            statement.totalMonthExpensesPaisa,
          ),
          subtitle:
              'মোট ${BanglaLedgerFormatter.toBanglaDigits(statement.monthExpenses.length.toString())}টি অনুমোদিত খরচ',
        ),
        pw.SizedBox(width: 8),
        _buildKpiCard(
          label: 'যাচাইকৃত MFS জমা',
          value: BanglaLedgerFormatter.formatTakaBangla(
            statement.totalVerifiedMfsCollectionsPaisa,
          ),
          subtitle:
              'MFS চার্জ: ${BanglaLedgerFormatter.formatTakaBangla(statement.totalMfsFeesPaisa)}',
        ),
        pw.SizedBox(width: 8),
        _buildKpiCard(
          label: 'অপেক্ষমাণ MFS (Pending)',
          value: BanglaLedgerFormatter.formatTakaBangla(
            statement.totalPendingMfsCollectionsPaisa,
          ),
          subtitle: 'অ্যাডমিন যাচাইয়ের অপেক্ষায়',
        ),
      ],
    );
  }

  pw.Widget _buildKpiCard({
    required String label,
    required String value,
    required String subtitle,
  }) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          color: _surfaceTint,
          border: pw.Border.all(color: _borderGrey, width: 0.75),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label,
              style: const pw.TextStyle(fontSize: 8.5, color: _mutedText),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              value,
              style: const pw.TextStyle(fontSize: 12, color: _primaryNavy),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              subtitle,
              style: const pw.TextStyle(fontSize: 7.5, color: _mutedText),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _buildSectionTitle(String title) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const pw.BoxDecoration(
        color: _surfaceTint,
        border: pw.Border(
          left: pw.BorderSide(color: _accentTeal, width: 3),
        ),
      ),
      child: pw.Text(
        title,
        style: const pw.TextStyle(fontSize: 11, color: _primaryNavy),
      ),
    );
  }

  pw.Widget _buildMemberStandingsTable(MonthlyLedgerStatement statement) {
    final headers = [
      'সদস্যের নাম',
      'প্রারম্ভিক জের',
      'মাসিক অংশ (Share)',
      'মোট জমা / খরচ',
      'অপেক্ষমাণ MFS',
      'চূড়ান্ত অবস্থা (Net)',
    ];

    final data = statement.memberStandings.map((s) {
      final netPaisa = s.closingNetBalancePaisa;
      final netStatus = netPaisa > 0
          ? 'পাওনা ${BanglaLedgerFormatter.formatTakaBangla(netPaisa)}'
          : netPaisa < 0
              ? 'বকেয়া ${BanglaLedgerFormatter.formatTakaBangla(netPaisa.abs())}'
              : 'পরিশোধিত (৳ ০)';

      return [
        s.memberName,
        BanglaLedgerFormatter.formatTakaBangla(
          s.openingBalancePaisa,
          showSign: true,
        ),
        BanglaLedgerFormatter.formatTakaBangla(s.currentMonthSharePaisa),
        BanglaLedgerFormatter.formatTakaBangla(s.netVerifiedContributionPaisa),
        BanglaLedgerFormatter.formatTakaBangla(s.pendingMfsSubmittedPaisa),
        netStatus,
      ];
    }).toList();

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      border: pw.TableBorder.all(color: _borderGrey, width: 0.5),
      headerDecoration: const pw.BoxDecoration(color: _primaryNavy),
      headerStyle: const pw.TextStyle(fontSize: 9, color: PdfColors.white),
      cellStyle: const pw.TextStyle(fontSize: 8.5, color: PdfColors.black),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerRight,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
        5: pw.Alignment.centerRight,
      },
    );
  }

  pw.Widget _buildMfsAuditTable(MonthlyLedgerStatement statement) {
    if (statement.mfsAuditLog.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _borderGrey, width: 0.5),
        ),
        child: pw.Text(
          'এই মাসে কোনো মোবাইল ব্যাংকিং (bKash / Nagad / Rocket) TrxID লেনদেন নথিভুক্ত হয়নি।',
          style: const pw.TextStyle(fontSize: 8.5, color: _mutedText),
        ),
      );
    }

    final headers = [
      'তারিখ',
      'প্রেরক / সদস্য',
      'মাধ্যম (MFS)',
      'TrxID / রেফারেন্স',
      'নম্বর',
      'চার্জ (Fee)',
      'পরিমাণ (৳)',
      'অবস্থা',
    ];

    final data = statement.mfsAuditLog.map((entry) {
      final phone = entry.mfsInfo.senderMaskedPhone ??
          entry.mfsInfo.receiverMaskedPhone ??
          '-';
      return [
        BanglaLedgerFormatter.formatShortDateBangla(entry.date),
        entry.payerName,
        entry.mfsInfo.provider.shortLabel,
        entry.mfsInfo.normalizedTrxId ?? '-',
        phone,
        BanglaLedgerFormatter.formatTakaBangla(entry.mfsInfo.feePaisa),
        BanglaLedgerFormatter.formatTakaBangla(entry.principalPaisa),
        entry.mfsInfo.status.banglaLabel,
      ];
    }).toList();

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      border: pw.TableBorder.all(color: _borderGrey, width: 0.5),
      headerDecoration: const pw.BoxDecoration(color: _accentTeal),
      headerStyle: const pw.TextStyle(fontSize: 8.5, color: PdfColors.white),
      cellStyle: const pw.TextStyle(fontSize: 8, color: PdfColors.black),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.center,
        3: pw.Alignment.centerLeft,
        4: pw.Alignment.centerLeft,
        5: pw.Alignment.centerRight,
        6: pw.Alignment.centerRight,
        7: pw.Alignment.center,
      },
    );
  }

  pw.Widget _buildRecommendedSettlementsTable(
    MonthlyLedgerStatement statement,
  ) {
    final headers = [
      'প্রদানকারী সদস্য (Debtor)',
      'গ্রহণকারী সদস্য / তহবিল (Creditor)',
      'প্রদেয় পরিমাণ (Amount to Pay)',
    ];

    final data = statement.recommendedSettlements.map((t) {
      return [
        t.fromMemberName,
        t.toMemberName,
        BanglaLedgerFormatter.formatTakaBangla(t.amountPaisa),
      ];
    }).toList();

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      border: pw.TableBorder.all(color: _borderGrey, width: 0.5),
      headerDecoration: const pw.BoxDecoration(color: _primaryNavy),
      headerStyle: const pw.TextStyle(fontSize: 8.5, color: PdfColors.white),
      cellStyle: const pw.TextStyle(fontSize: 8.5, color: PdfColors.black),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerRight,
      },
    );
  }

  pw.Widget _buildExpensesTable(MonthlyLedgerStatement statement) {
    final headers = [
      'তারিখ',
      'খরচের বিবরণ',
      'ক্যাটাগরি',
      'প্রদানকারী',
      'মাধ্যম / TrxID',
      'মোট পরিমাণ',
    ];

    final data = statement.monthExpenses.map((exp) {
      final mfsBadge = exp.mfsInfo == null ||
              exp.mfsInfo!.provider == MfsProvider.cash
          ? 'নগদ ক্যাশ'
          : '${exp.mfsInfo!.provider.shortLabel} (${exp.mfsInfo!.normalizedTrxId ?? "-"})';
      return [
        BanglaLedgerFormatter.formatShortDateBangla(exp.date),
        exp.title,
        exp.category,
        exp.paidByName ?? exp.addedByEmail,
        mfsBadge,
        BanglaLedgerFormatter.formatTakaBangla(exp.effectiveAmountPaisa),
      ];
    }).toList();

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      border: pw.TableBorder.all(color: _borderGrey, width: 0.5),
      headerDecoration: const pw.BoxDecoration(color: _primaryNavy),
      headerStyle: const pw.TextStyle(fontSize: 8.5, color: PdfColors.white),
      cellStyle: const pw.TextStyle(fontSize: 8, color: PdfColors.black),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerLeft,
        3: pw.Alignment.centerLeft,
        4: pw.Alignment.centerLeft,
        5: pw.Alignment.centerRight,
      },
    );
  }

  pw.Widget _buildSignatureBlock(MonthlyLedgerStatement statement) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        _buildSignLine('প্রস্তুতকারক / মেস ম্যানেজার'),
        _buildSignLine('কোষাধ্যক্ষ / ক্যাশিয়ার (Treasurer)'),
        _buildSignLine('সভাপতি / অডিটর অনুমোদন'),
      ],
    );
  }

  pw.Widget _buildSignLine(String roleTitle) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          width: 140,
          height: 28,
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: _mutedText, width: 0.75),
            ),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          roleTitle,
          style: const pw.TextStyle(fontSize: 8.5, color: _mutedText),
        ),
      ],
    );
  }

  pw.Widget _buildFooter(
    pw.Context context,
    MonthlyLedgerStatement statement,
    String preparedBy,
  ) {
    final pageNum = BanglaLedgerFormatter.toBanglaDigits(
      context.pageNumber.toString(),
    );
    final pageCount = BanglaLedgerFormatter.toBanglaDigits(
      context.pagesCount.toString(),
    );

    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: _borderGrey, width: 0.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'ভ্রমণ (Bhromon) ওপেন-সোর্স প্ল্যাটফর্ম | প্রস্তুতকারক: $preparedBy | SHA-256: #${statement.verificationDigest}',
            style: const pw.TextStyle(fontSize: 7.5, color: _mutedText),
          ),
          pw.Text(
            'পৃষ্ঠা $pageNum / $pageCount',
            style: const pw.TextStyle(fontSize: 8, color: _primaryNavy),
          ),
        ],
      ),
    );
  }
}
