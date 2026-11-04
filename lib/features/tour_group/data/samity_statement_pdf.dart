import 'dart:typed_data';

import 'package:bangla_pdf/bangla_pdf.dart'
    show BanglaFontManager, BanglaPdf, BanglaShapingMode;
import 'package:bangla_pdf/widgets.dart' as pw;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';

import '../domain/models/samity_models.dart';
import '../domain/models/tour_group.dart';
import '../domain/services/samity_engine.dart';
import '../domain/services/trip_ledger_engine.dart';
import 'tour_export_pdf.dart' show TourPdfLabels;

/// The inputs needed to render a samity statement PDF.
class SamityStatementData {
  const SamityStatementData({
    required this.group,
    required this.members,
    required this.payments,
    required this.payouts,
    required this.generatedAt,
  });

  final TourGroup group;
  final List<TourMember> members;
  final List<SamityPayment> payments;
  final List<SamityPayout> payouts;
  final DateTime generatedAt;
}

/// Builds a professional, downloadable PDF ledger statement for a samity group.
Future<Uint8List> buildSamityStatementPdf({
  required SamityStatementData data,
  required TourPdfLabels labels,
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

  final writer = _SamityPdfWriter(data: data, labels: labels);
  final document = pw.Document(
    compress: compress,
    theme: pw.ThemeData.withFont(
      base: regular,
      bold: bold,
      italic: regular,
      boldItalic: bold,
      fontFallback: [bengali, BanglaFontManager().defaultFont],
    ),
    title: '${data.group.name} - Statement',
    author: 'Bhromon',
    creator: 'Bhromon',
  );

  document.addPage(writer.buildPage());
  return document.save();
}

class _SamityPdfWriter {
  _SamityPdfWriter({required this.data, required this.labels})
      : ledger = SamityLedger(
          config: data.group.samity,
          payments: data.payments,
          payouts: data.payouts,
          today: data.generatedAt,
        );

  final SamityStatementData data;
  final TourPdfLabels labels;
  final SamityLedger ledger;

  static final PdfColor _primary = PdfColor.fromHex('#1B4332');
  static final PdfColor _gold = PdfColor.fromHex('#B08D2B');
  static final PdfColor _ink = PdfColor.fromHex('#111827');
  static final PdfColor _muted = PdfColor.fromHex('#6B7280');
  static final PdfColor _line = PdfColor.fromHex('#E5E7EB');
  static final PdfColor _surface = PdfColor.fromHex('#F9FAFB');
  static final PdfColor _green = PdfColor.fromHex('#10B981');
  static final PdfColor _red = PdfColor.fromHex('#EF4444');

  static const PdfPageFormat _format = PdfPageFormat.a4;
  static const double _margin = 32;

  String _clean(String? text) {
    if (text == null) return '';
    return text
        .replaceAll(
            RegExp(
                r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}]',
                unicode: true),
            '')
        .trim();
  }

  String _memberName(String email) {
    for (final m in data.members) {
      if (m.email.toLowerCase() == email.toLowerCase()) {
        final name = _clean(m.displayName);
        return name.isNotEmpty ? name : m.email;
      }
    }
    return email;
  }

  int get _totalCollectedTaka =>
      data.payments.fold(0, (sum, p) => sum + p.amountTaka);

  int get _totalPaidOutTaka =>
      data.payouts.fold(0, (sum, p) => sum + p.amountTaka);

  String _formatTaka(int taka) =>
      labels.number(TripLedgerEngine.formatTaka(taka * 100));

  String _statusLabel(SamityCycleStatus status) => switch (status) {
        SamityCycleStatus.upcoming => labels.text('samity_status_upcoming'),
        SamityCycleStatus.due => labels.text('samity_status_due'),
        SamityCycleStatus.overdue => labels.text('samity_status_overdue'),
        SamityCycleStatus.collected => labels.text('samity_status_collected'),
        SamityCycleStatus.paidOut => labels.text('samity_status_paid_out'),
      };

  PdfColor _statusColor(SamityCycleStatus status) => switch (status) {
        SamityCycleStatus.upcoming => _muted,
        SamityCycleStatus.due => _gold,
        SamityCycleStatus.overdue => _red,
        SamityCycleStatus.collected => _primary,
        SamityCycleStatus.paidOut => _green,
      };

  pw.MultiPage buildPage() {
    return pw.MultiPage(
      pageFormat: _format,
      margin: const pw.EdgeInsets.all(_margin),
      header: (context) => _buildHeader(),
      footer: (context) => _buildFooter(context),
      build: (context) => [
        pw.SizedBox(height: 12),
        _buildSummaryCards(),
        pw.SizedBox(height: 18),
        _buildScheduleSection(),
        pw.SizedBox(height: 18),
        _buildBalancesSection(),
      ],
    );
  }

  pw.Widget _buildHeader() {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 12),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _primary, width: 2)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'BHROMON',
                style: pw.TextStyle(
                  color: _gold,
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                _clean(data.group.name),
                style: pw.TextStyle(
                  color: _primary,
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                labels.text('samity_pdf_title'),
                style: pw.TextStyle(
                    color: _ink, fontSize: 13, fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                labels.text(
                  'samity_pdf_generated',
                  args: {'date': labels.dateTime(data.generatedAt)},
                ),
                style: pw.TextStyle(color: _muted, fontSize: 8.5),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                labels.text(
                  'samity_pdf_cycles',
                  args: {'count': labels.number(ledger.schedule.length)},
                ),
                style: pw.TextStyle(color: _muted, fontSize: 8.5),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildFooter(pw.Context context) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _line, width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Bhromon • Free and Open Source Community Operating System',
            style: pw.TextStyle(color: _muted, fontSize: 7.5),
          ),
          pw.Text(
            '${context.pageNumber} / ${context.pagesCount}',
            style: pw.TextStyle(color: _muted, fontSize: 7.5),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildSummaryCards() {
    final config = data.group.samity;
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _surface,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: _line, width: 0.8),
      ),
      child: pw.Row(
        children: [
          _summaryItem(
            labels.text('samity_contribution_label'),
            '${_formatTaka(config.contributionTaka)} / mo',
          ),
          _summaryDivider(),
          _summaryItem(
            labels
                .text('samity_pot', args: {'amount': ''})
                .replaceAll(':', '')
                .trim(),
            _formatTaka(config.potTaka),
          ),
          _summaryDivider(),
          _summaryItem(
            labels
                .text('samity_pdf_total_collected', args: {'amount': ''})
                .replaceAll(':', '')
                .trim(),
            _formatTaka(_totalCollectedTaka),
            color: _green,
          ),
          _summaryDivider(),
          _summaryItem(
            labels
                .text('samity_pdf_total_paid_out', args: {'amount': ''})
                .replaceAll(':', '')
                .trim(),
            _formatTaka(_totalPaidOutTaka),
            color: _primary,
          ),
        ],
      ),
    );
  }

  pw.Widget _summaryDivider() {
    return pw.Container(
      width: 1,
      height: 28,
      margin: const pw.EdgeInsets.symmetric(horizontal: 8),
      color: _line,
    );
  }

  pw.Widget _summaryItem(String label, String value, {PdfColor? color}) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(color: _muted, fontSize: 8),
            maxLines: 1,
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            style: pw.TextStyle(
              color: color ?? _ink,
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildScheduleSection() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          labels.text('samity_pdf_schedule_title'),
          style: pw.TextStyle(
            color: _primary,
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder(
            horizontalInside: pw.BorderSide(color: _line, width: 0.5),
            bottom: pw.BorderSide(color: _line, width: 0.8),
          ),
          columnWidths: {
            0: const pw.FixedColumnWidth(40),
            1: const pw.FixedColumnWidth(80),
            2: const pw.FlexColumnWidth(2),
            3: const pw.FixedColumnWidth(75),
            4: const pw.FixedColumnWidth(75),
            5: const pw.FixedColumnWidth(70),
          },
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: _primary),
              children: [
                _tableHeader('#'),
                _tableHeader(labels.text('samity_pdf_due_date')),
                _tableHeader(labels.text('samity_pdf_recipient')),
                _tableHeader(labels.text('samity_pdf_target'),
                    align: pw.TextAlign.right),
                _tableHeader(labels.text('samity_pdf_collected'),
                    align: pw.TextAlign.right),
                _tableHeader(labels.text('samity_pdf_status'),
                    align: pw.TextAlign.center),
              ],
            ),
            for (final cycle in ledger.schedule) _cycleRow(cycle),
          ],
        ),
      ],
    );
  }

  pw.TableRow _cycleRow(SamityCycle cycle) {
    final status = ledger.statusOf(cycle);
    final collected = ledger.collectedFor(cycle.index);
    final recipientName = _memberName(cycle.recipientEmail);

    return pw.TableRow(
      decoration: pw.BoxDecoration(
        color: cycle.index % 2 == 1 ? _surface : PdfColors.white,
      ),
      children: [
        _tableCell(labels.number(cycle.number)),
        _tableCell(labels.date(cycle.dueOn)),
        _tableCell(recipientName),
        _tableCell(_formatTaka(cycle.potTaka), align: pw.TextAlign.right),
        _tableCell(_formatTaka(collected), align: pw.TextAlign.right),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: pw.BoxDecoration(
              color: _statusColor(status),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
            ),
            alignment: pw.Alignment.center,
            child: pw.Text(
              _statusLabel(status),
              style: const pw.TextStyle(color: PdfColors.white, fontSize: 7),
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _buildBalancesSection() {
    final standings = ledger.standings();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          labels.text('samity_pdf_standings_title'),
          style: pw.TextStyle(
            color: _primary,
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder(
            horizontalInside: pw.BorderSide(color: _line, width: 0.5),
            bottom: pw.BorderSide(color: _line, width: 0.8),
          ),
          columnWidths: {
            0: const pw.FlexColumnWidth(2.5),
            1: const pw.FixedColumnWidth(100),
            2: const pw.FixedColumnWidth(100),
            3: const pw.FixedColumnWidth(80),
          },
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: _primary),
              children: [
                _tableHeader(labels.text('samity_pdf_member')),
                _tableHeader(labels.text('samity_pdf_paid'),
                    align: pw.TextAlign.right),
                _tableHeader(labels.text('samity_pdf_due'),
                    align: pw.TextAlign.right),
                _tableHeader(labels.text('samity_pdf_status'),
                    align: pw.TextAlign.center),
              ],
            ),
            for (var i = 0; i < standings.length; i++)
              _standingRow(standings[i], i % 2 == 1),
          ],
        ),
      ],
    );
  }

  pw.TableRow _standingRow(SamityStanding standing, bool zebra) {
    final memberName = _memberName(standing.email);
    final hasDue = standing.owedTaka > 0;

    return pw.TableRow(
      decoration: pw.BoxDecoration(color: zebra ? _surface : PdfColors.white),
      children: [
        _tableCell(memberName),
        _tableCell(_formatTaka(standing.paidTaka), align: pw.TextAlign.right),
        _tableCell(
          _formatTaka(standing.owedTaka),
          align: pw.TextAlign.right,
          color: hasDue ? _red : null,
          bold: hasDue,
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: pw.BoxDecoration(
              color: hasDue ? _red : _green,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
            ),
            alignment: pw.Alignment.center,
            child: pw.Text(
              hasDue
                  ? labels.text('samity_status_overdue')
                  : labels.text('samity_pdf_clear'),
              style: const pw.TextStyle(color: PdfColors.white, fontSize: 7),
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _tableHeader(String text,
      {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        text,
        textAlign: align,
        style: const pw.TextStyle(
          color: PdfColors.white,
          fontSize: 8.5,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  pw.Widget _tableCell(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
    PdfColor? color,
    bool bold = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          color: color ?? _ink,
          fontSize: 8,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }
}
