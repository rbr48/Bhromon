// lib/features/tour_group/data/itinerary_pdf.dart
//
// Printable Multi-Stop Tour Itinerary & Route Plan PDF generator for Bhromon
// using `package:bangla_pdf/widgets.dart`.

import 'dart:typed_data';
import 'package:bangla_pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';

import '../domain/models/itinerary_models.dart';
import '../domain/models/tour_activity_models.dart';
import '../domain/models/tour_group.dart';
import '../domain/services/route_engine.dart';

/// Localization and Bengali numeral formatting utilities for Itinerary PDF.
class BanglaItineraryFormatter {
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
    'জানুয়ারি',
    'ফেব্রুয়ারি',
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

  static String formatShortDateBangla(DateTime dt) {
    final day = toBanglaDigits(dt.day.toString());
    final month = _banglaMonths[dt.month - 1];
    final year = toBanglaDigits(dt.year.toString());
    return '$day $month, $year';
  }

  static String modeBangla(TransportMode mode) {
    switch (mode) {
      case TransportMode.road:
        return 'সড়কপথ (বাস/কার)';
      case TransportMode.rail:
        return 'রেলপথ (ট্রেন)';
      case TransportMode.air:
        return 'আকাশপথ (বিমান)';
      case TransportMode.river:
        return 'নৌপথ (লঞ্চ/জাহাজ)';
      case TransportMode.sea:
        return 'সমুদ্রপথ (জাহাজ/স্পিডবোট)';
      case TransportMode.jeep:
        return 'চান্দের গাড়ি / জিপ';
      case TransportMode.boat:
        return 'নৌকা / ট্রলার';
      case TransportMode.trek:
        return 'হাঁটা / ট্র্যাকিং';
    }
  }

  static String checkpointKindBangla(CheckpointKind kind) =>
      kind.label(isBn: true);
}

/// Generates a comprehensive, printable multi-stop itinerary and route roadmap PDF.
class ItineraryPdfGenerator {
  static const PdfColor _primaryNavy =
      PdfColor.fromInt(0xFF1B3B36); // Forest dark
  static const PdfColor _accentTeal = PdfColor.fromInt(0xFF2E6F5E);
  static const PdfColor _surfaceTint = PdfColor.fromInt(0xFFF4F8F6);
  static const PdfColor _borderGrey = PdfColor.fromInt(0xFFCBD5E1);
  static const PdfColor _mutedText = PdfColor.fromInt(0xFF475569);

  Future<Uint8List> generate({
    required TourGroup group,
    List<RouteCheckpoint> checkpoints = const [],
    String? preparedByName,
  }) async {
    final routePlan = RoutePlan.of(group);
    final stops = group.effectiveStops;

    final pdf = pw.Document(
      title: '${group.name} - ভ্রমণ পরিকল্পনা ও নির্দেশিকা',
      author: preparedByName ?? 'Bhromon Route Engine',
      creator: 'Bhromon Open-Source Travel Assistant (bangla_pdf)',
    );

    final generatedAtStr =
        BanglaItineraryFormatter.formatShortDateBangla(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => _buildHeader(group, generatedAtStr),
        footer: (context) => _buildFooter(context, group, preparedByName),
        build: (context) => [
          pw.SizedBox(height: 12),
          _buildTripOverview(group, routePlan, stops),
          pw.SizedBox(height: 18),
          _buildSectionTitle('১. গন্তব্য ও অবস্থান সূচি (Stops & Stays)'),
          pw.SizedBox(height: 6),
          _buildStopsTable(stops),
          pw.SizedBox(height: 18),
          _buildSectionTitle(
              '২. যাত্রা ও রুট রোডম্যাপ (Route & Transport Legs)'),
          pw.SizedBox(height: 6),
          _buildLegsTable(routePlan),
          if (checkpoints.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            _buildSectionTitle('৩. নির্ধারিত বিরতি ও চেকপয়েন্ট (Checkpoints)'),
            pw.SizedBox(height: 6),
            _buildCheckpointsTable(checkpoints),
          ],
          if (group.emergencyContacts.isNotEmpty ||
              (group.meetingPointTitle?.isNotEmpty ?? false)) ...[
            pw.SizedBox(height: 18),
            _buildSectionTitle(
                '৪. জরুরি তথ্য ও জমায়েতের স্থান (Important Info)'),
            pw.SizedBox(height: 6),
            _buildImportantInfoCard(group),
          ],
        ],
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildHeader(TourGroup group, String generatedAtStr) {
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
                group.name,
                style: const pw.TextStyle(
                  fontSize: 18,
                  color: _primaryNavy,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'ভ্রমণ পরিকল্পনা ও অফিসিয়াল গাইডলাইন (Official Itinerary)',
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
                  'ইনভাইট কোড: ${group.inviteCode}',
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.white,
                  ),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'তারিখ: $generatedAtStr | Bhromon',
                style: const pw.TextStyle(fontSize: 8, color: _mutedText),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildFooter(
      pw.Context context, TourGroup group, String? preparedByName) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 14),
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: _borderGrey, width: 0.8),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'প্রস্তুতকারক: ${preparedByName ?? "গ্রুপ অ্যাডমিন"} · ভ্রমণ অ্যাপ (ভ্রমণ সুন্দর হোক)',
            style: const pw.TextStyle(fontSize: 8, color: _mutedText),
          ),
          pw.Text(
            'পৃষ্ঠা ${BanglaItineraryFormatter.toBanglaDigits(context.pageNumber.toString())} / ${BanglaItineraryFormatter.toBanglaDigits(context.pagesCount.toString())}',
            style: const pw.TextStyle(fontSize: 8, color: _mutedText),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildSectionTitle(String title) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: const pw.BoxDecoration(
        color: _surfaceTint,
        border: pw.Border(
          left: pw.BorderSide(color: _accentTeal, width: 3),
        ),
      ),
      child: pw.Text(
        title,
        style: const pw.TextStyle(
          fontSize: 11,
          color: _primaryNavy,
        ),
      ),
    );
  }

  pw.Widget _buildTripOverview(
      TourGroup group, RoutePlan routePlan, List<TourStop> stops) {
    final startStr =
        BanglaItineraryFormatter.formatShortDateBangla(group.startDate);
    final endStr =
        BanglaItineraryFormatter.formatShortDateBangla(group.endDate);
    final daysStr =
        BanglaItineraryFormatter.toBanglaDigits(group.totalDays.toString());
    final nightsStr =
        BanglaItineraryFormatter.toBanglaDigits(group.totalNights.toString());
    final totalKmStr = routePlan.totalKm > 0
        ? '${BanglaItineraryFormatter.toBanglaDigits(routePlan.totalKm.toString())} কিমি (আনুমানিক)'
        : 'হিসাবাধীন';

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: _surfaceTint,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: _borderGrey, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'মূল গন্তব্য: ${group.destination}',
                style: const pw.TextStyle(fontSize: 12, color: _primaryNavy),
              ),
              pw.Text(
                'যাত্রার সময়কাল: $daysStr দিন ($nightsStr রাত)',
                style: const pw.TextStyle(fontSize: 10, color: _accentTeal),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'সময়সীমা: $startStr হতে $endStr',
                style: const pw.TextStyle(fontSize: 9, color: _mutedText),
              ),
              pw.Text(
                'মোট দূরত্ব: $totalKmStr',
                style: const pw.TextStyle(fontSize: 9, color: _mutedText),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildStopsTable(List<TourStop> stops) {
    return pw.Table(
      border: pw.TableBorder.all(color: _borderGrey, width: 0.5),
      columnWidths: const {
        0: pw.FixedColumnWidth(28),
        1: pw.FlexColumnWidth(2.5),
        2: pw.FlexColumnWidth(2.2),
        3: pw.FlexColumnWidth(2.2),
        4: pw.FixedColumnWidth(38),
        5: pw.FlexColumnWidth(2.8),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _surfaceTint),
          children: [
            _cellHeader('#', align: pw.TextAlign.center),
            _cellHeader('গন্তব্য / স্টপ'),
            _cellHeader('আগমন'),
            _cellHeader('প্রস্থান'),
            _cellHeader('রাত', align: pw.TextAlign.center),
            _cellHeader('আবাসন / নোট'),
          ],
        ),
        for (var i = 0; i < stops.length; i++) ...[
          _buildStopRow(stops[i], i + 1),
        ],
      ],
    );
  }

  pw.TableRow _buildStopRow(TourStop stop, int index) {
    final arriveStr =
        BanglaItineraryFormatter.formatShortDateBangla(stop.arrive);
    final leaveStr = BanglaItineraryFormatter.formatShortDateBangla(stop.leave);
    final nightsStr =
        BanglaItineraryFormatter.toBanglaDigits(stop.nights.toString());
    final stayOrNotes = [
      if (stop.stay.isNotEmpty) 'আবাসন: ${stop.stay}',
      if (stop.notes.isNotEmpty) stop.notes,
    ].join('\n');

    return pw.TableRow(
      children: [
        _cellText(BanglaItineraryFormatter.toBanglaDigits(index.toString()),
            align: pw.TextAlign.center),
        _cellText(stop.name),
        _cellText(arriveStr),
        _cellText(leaveStr),
        _cellText(nightsStr, align: pw.TextAlign.center),
        _cellText(stayOrNotes.isEmpty ? '—' : stayOrNotes),
      ],
    );
  }

  pw.Widget _buildLegsTable(RoutePlan routePlan) {
    return pw.Table(
      border: pw.TableBorder.all(color: _borderGrey, width: 0.5),
      columnWidths: const {
        0: pw.FixedColumnWidth(28),
        1: pw.FlexColumnWidth(3.2),
        2: pw.FlexColumnWidth(2.6),
        3: pw.FlexColumnWidth(2.0),
        4: pw.FlexColumnWidth(2.2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _surfaceTint),
          children: [
            _cellHeader('#', align: pw.TextAlign.center),
            _cellHeader('রুট পর্যায় (Leg)'),
            _cellHeader('যানবাহন'),
            _cellHeader('দূরত্ব', align: pw.TextAlign.right),
            _cellHeader('আনুমানিক সময়', align: pw.TextAlign.right),
          ],
        ),
        for (var i = 0; i < routePlan.legs.length; i++) ...[
          _buildLegRow(routePlan.legs[i], i + 1),
        ],
      ],
    );
  }

  pw.TableRow _buildLegRow(RouteLeg leg, int index) {
    final fromTo = '${leg.from.name} → ${leg.to.name}';
    final modeStr = BanglaItineraryFormatter.modeBangla(leg.plan.mode);
    final kmStr = leg.km != null
        ? '${BanglaItineraryFormatter.toBanglaDigits(leg.km.toString())} কিমি'
        : '—';
    final dur = leg.duration;
    final durStr = dur != null
        ? '${BanglaItineraryFormatter.toBanglaDigits(dur.inHours.toString())} ঘ: ${BanglaItineraryFormatter.toBanglaDigits((dur.inMinutes % 60).toString())} মি'
        : '—';

    return pw.TableRow(
      children: [
        _cellText(BanglaItineraryFormatter.toBanglaDigits(index.toString()),
            align: pw.TextAlign.center),
        _cellText(fromTo),
        _cellText(modeStr),
        _cellText(kmStr, align: pw.TextAlign.right),
        _cellText(durStr, align: pw.TextAlign.right),
      ],
    );
  }

  pw.Widget _buildCheckpointsTable(List<RouteCheckpoint> checkpoints) {
    return pw.Table(
      border: pw.TableBorder.all(color: _borderGrey, width: 0.5),
      columnWidths: const {
        0: pw.FixedColumnWidth(28),
        1: pw.FlexColumnWidth(3.0),
        2: pw.FlexColumnWidth(2.6),
        3: pw.FlexColumnWidth(4.4),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _surfaceTint),
          children: [
            _cellHeader('#', align: pw.TextAlign.center),
            _cellHeader('বিরতি স্থান'),
            _cellHeader('ধরন'),
            _cellHeader('নোট / বিবরণ'),
          ],
        ),
        for (var i = 0; i < checkpoints.length; i++) ...[
          pw.TableRow(
            children: [
              _cellText(
                  BanglaItineraryFormatter.toBanglaDigits((i + 1).toString()),
                  align: pw.TextAlign.center),
              _cellText(checkpoints[i].name),
              _cellText(BanglaItineraryFormatter.checkpointKindBangla(
                  checkpoints[i].kind)),
              _cellText(
                  checkpoints[i].notes.isEmpty ? '—' : checkpoints[i].notes),
            ],
          ),
        ],
      ],
    );
  }

  pw.Widget _buildImportantInfoCard(TourGroup group) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: _borderGrey, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (group.meetingPointTitle?.isNotEmpty ?? false) ...[
            pw.Text(
              'জমায়েতের স্থান: ${group.meetingPointTitle}',
              style: const pw.TextStyle(fontSize: 10, color: _primaryNavy),
            ),
            if (group.meetingPointNote?.isNotEmpty ?? false) ...[
              pw.SizedBox(height: 2),
              pw.Text(
                'নির্দেশনা: ${group.meetingPointNote}',
                style: const pw.TextStyle(fontSize: 9, color: _mutedText),
              ),
            ],
            pw.SizedBox(height: 6),
          ],
          if (group.emergencyContacts.isNotEmpty) ...[
            pw.Text(
              'জরুরি যোগাযোগ:',
              style: const pw.TextStyle(fontSize: 10, color: _primaryNavy),
            ),
            pw.SizedBox(height: 2),
            for (final contact in group.emergencyContacts)
              pw.Text(
                '• ${contact.name}: ${BanglaItineraryFormatter.toBanglaDigits(contact.phone)}',
                style: const pw.TextStyle(fontSize: 9, color: _mutedText),
              ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _cellHeader(String text,
      {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      alignment: _toAlignment(align),
      child: pw.Text(
        text,
        textAlign: align,
        style: const pw.TextStyle(
          fontSize: 9,
          color: _primaryNavy,
        ),
      ),
    );
  }

  static pw.Widget _cellText(String text,
      {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      alignment: _toAlignment(align),
      child: pw.Text(
        text,
        textAlign: align,
        style: const pw.TextStyle(
          fontSize: 8.5,
          color: PdfColors.black,
        ),
      ),
    );
  }

  static pw.Alignment _toAlignment(pw.TextAlign align) {
    switch (align) {
      case pw.TextAlign.center:
        return pw.Alignment.center;
      case pw.TextAlign.right:
        return pw.Alignment.centerRight;
      case pw.TextAlign.left:
      default:
        return pw.Alignment.centerLeft;
    }
  }
}
