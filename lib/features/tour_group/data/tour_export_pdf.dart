import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/models/logistics_models.dart';
import '../domain/models/tour_export_data.dart';
import '../domain/models/tour_group.dart';
import '../domain/models/tour_post_models.dart';
import '../domain/services/trip_ledger_engine.dart';
import 'tour_export_images.dart';

/// The texts the PDF needs, in the language the app is showing.
class TourPdfLabels {
  const TourPdfLabels({
    required this.text,
    required this.number,
    required this.date,
    required this.dateTime,
  });

  /// Looks up a translation key and fills its `{name}` placeholders from [args].
  final String Function(String key, {Map<String, Object>? args}) text;

  /// Writes a count or an amount with this language's digits.
  final String Function(Object n) number;

  /// A date, such as 25 Oct 2026.
  final String Function(DateTime date) date;

  /// A date and time, to the minute.
  final String Function(DateTime date) dateTime;
}

/// Builds the whole tour as one PDF: a cover, a contents list, then one section
/// per part of the tour. Pictures are fetched first ([onImages] reports them),
/// so the layout itself never waits on the network.
Future<Uint8List> buildTourPdf({
  required TourExportData data,
  required TourExportImages images,
  required TourPdfLabels labels,
  void Function(int done, int total)? onImages,
  bool compress = true,
}) async {
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/HindSiliguri-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/HindSiliguri-Bold.ttf'),
  );
  final bengali = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSansBengali.ttf'),
  );
  await images.prefetch(_pictureUrls(data), onProgress: onImages);

  final writer = _TourPdfWriter(data: data, images: images, labels: labels);
  final document = pw.Document(
    compress: compress,
    // The bundled fonts have no slanted cut, so italic text uses the regular
    // face. The built-in Helvetica would show Bengali as blank boxes.
    theme: pw.ThemeData.withFont(
      base: regular,
      bold: bold,
      italic: regular,
      boldItalic: bold,
      fontFallback: [bengali],
    ),
    title: data.group.name,
    author: 'Bhromon',
    creator: 'Bhromon',
  );
  document
    ..addPage(writer.cover())
    ..addPage(writer.pages());
  return document.save();
}

/// Every picture the PDF will show, so they can all be fetched up front.
Iterable<String> _pictureUrls(TourExportData data) sync* {
  for (final post in data.posts) {
    yield* _postPictures(post);
  }
  for (final story in data.stories) {
    yield story.mediaUrl;
  }
  for (final highlight in data.highlights) {
    yield highlight.coverUrl;
  }
}

/// The pictures of a post: its photos, or the cover frame of a video.
List<String> _postPictures(TourPostItem post) {
  final urls = post.images.where((url) => url.isNotEmpty).toList();
  if (urls.isNotEmpty) return urls;
  final cover = post.coverUrl;
  return cover == null || cover.isEmpty ? const [] : [cover];
}

class _TourPdfWriter {
  _TourPdfWriter({
    required this.data,
    required this.images,
    required this.labels,
  });

  final TourExportData data;
  final TourExportImages images;
  final TourPdfLabels labels;

  static final PdfColor _green = PdfColor.fromHex('#1B4332');
  static final PdfColor _gold = PdfColor.fromHex('#B08D2B');
  static final PdfColor _ink = PdfColor.fromHex('#111827');
  static final PdfColor _muted = PdfColor.fromHex('#6B7280');
  static final PdfColor _line = PdfColor.fromHex('#D1D5DB');
  static final PdfColor _tint = PdfColor.fromHex('#F3F4F6');

  static const PdfPageFormat _format = PdfPageFormat.a4;
  static const double _margin = 40;
  static final double _contentWidth = PdfPageFormat.a4.width - 2 * _margin;

  /// Emoji have no glyphs in the PDF fonts, so they are dropped from the text.
  static final RegExp _emoji = RegExp(
    '[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}]',
    unicode: true,
  );

  String _amount(int paisa) =>
      labels.number(TripLedgerEngine.formatTaka(paisa));

  /// Plain text ready for the PDF: no emoji, and cut to [max] characters.
  String _clean(String? value, {int max = 500}) {
    final plain = (value ?? '')
        .replaceAll(_emoji, '')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
    return plain.length <= max ? plain : '${plain.substring(0, max)}…';
  }

  pw.TextStyle _style({
    double size = 10,
    bool bold = false,
    bool italic = false,
    PdfColor? color,
  }) {
    return pw.TextStyle(
      fontSize: size,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      fontStyle: italic ? pw.FontStyle.italic : pw.FontStyle.normal,
      color: color ?? _ink,
      lineSpacing: 2,
    );
  }

  pw.Widget _para(
    String value, {
    double size = 10,
    PdfColor? color,
    bool italic = false,
  }) {
    return pw.Text(
      _clean(value, max: 4000),
      style: _style(size: size, color: color, italic: italic),
    );
  }

  pw.Widget _meta(String value) {
    return pw.Text(
      _clean(value, max: 300),
      style: _style(size: 8.5, color: _muted),
    );
  }

  pw.Widget _empty() {
    return pw.Text(
      labels.text('pdf_none'),
      style: _style(color: _muted, italic: true),
    );
  }

  pw.Widget _subtitle(String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 12, bottom: 6),
      child: pw.Text(
        value,
        style: _style(size: 12, bold: true, color: _green),
      ),
    );
  }

  pw.Widget _keyValue(String label, String value) {
    if (value.trim().isEmpty) return pw.SizedBox();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 120,
            child: pw.Text(
              label,
              style: _style(size: 9.5, bold: true, color: _muted),
            ),
          ),
          pw.Expanded(child: pw.Text(value, style: _style(size: 10))),
        ],
      ),
    );
  }

  pw.Widget _tag(String label) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(left: 6),
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      color: _gold,
      child: pw.Text(
        label,
        style: _style(size: 8, bold: true, color: PdfColors.white),
      ),
    );
  }

  pw.Widget _total(String label, int paisa) {
    return pw.Expanded(
      child: pw.Container(
        margin: const pw.EdgeInsets.only(right: 6),
        padding: const pw.EdgeInsets.all(10),
        color: _tint,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: _style(size: 9, color: _muted)),
            pw.SizedBox(height: 3),
            pw.Text(
              _amount(paisa),
              style: _style(size: 14, bold: true, color: _green),
            ),
          ],
        ),
      ),
    );
  }

  /// A section title, optionally with its count. A new page starts the section
  /// unless it is the first one after the cover.
  List<pw.Widget> _heading(
    String title, {
    int? count,
    bool newPage = true,
  }) {
    return [
      if (newPage) pw.NewPage(),
      pw.Text(
        count == null ? title : '$title  ·  ${labels.number(count)}',
        style: _style(size: 18, bold: true, color: _green),
      ),
      pw.SizedBox(height: 4),
      pw.Container(width: 56, height: 2, color: _gold),
      pw.SizedBox(height: 14),
    ];
  }

  pw.Widget _table(List<String> headers, List<List<String>> rows) {
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerStyle: _style(size: 9, bold: true, color: PdfColors.white),
      headerDecoration: pw.BoxDecoration(color: _green),
      headerAlignment: pw.Alignment.centerLeft,
      cellStyle: _style(size: 9),
      cellAlignment: pw.Alignment.topLeft,
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      border: pw.TableBorder.all(color: _line, width: 0.5),
    );
  }

  /// Fits a picture of the given pixel size into the page, keeping its shape.
  ({double width, double height}) _fit(int pixelWidth, int pixelHeight) {
    const maxHeight = 380.0;
    if (pixelWidth <= 0 || pixelHeight <= 0) {
      return (width: _contentWidth, height: 200);
    }
    var width = _contentWidth;
    var height = width * pixelHeight / pixelWidth;
    if (height > maxHeight) {
      height = maxHeight;
      width = maxHeight * pixelWidth / pixelHeight;
    }
    return (width: width, height: height);
  }

  pw.Widget _photo(String url) {
    final photo = images.ready(url);
    if (photo == null) {
      return pw.Container(
        width: _contentWidth,
        height: 56,
        color: _tint,
        alignment: pw.Alignment.center,
        child: pw.Text(
          labels.text('pdf_photo_missing'),
          style: _style(size: 9, color: _muted, italic: true),
        ),
      );
    }
    final size = _fit(photo.width, photo.height);
    return pw.Image(
      photo.image,
      width: size.width,
      height: size.height,
      fit: pw.BoxFit.contain,
    );
  }

  String _roleLabel(TourRole role) {
    if (role == TourRole.owner) return labels.text('prof_role_owner');
    if (role == TourRole.admin) return labels.text('hub_role_admin');
    return labels.text('hub_role_member');
  }

  pw.Page cover() {
    final spent =
        data.expenses.fold<int>(0, (sum, expense) => sum + expense.amountPaisa);
    final dates = '${labels.date(data.group.startDate)} – '
        '${labels.date(data.group.endDate)}';
    return pw.Page(
      pageFormat: _format,
      margin: const pw.EdgeInsets.all(0),
      build: (context) => pw.Container(
        height: _format.height,
        color: _green,
        padding: const pw.EdgeInsets.fromLTRB(48, 84, 48, 56),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              _clean(data.group.name, max: 120),
              style: _style(size: 34, bold: true, color: PdfColors.white),
            ),
            pw.SizedBox(height: 14),
            pw.Text(
              _clean(data.group.destination, max: 120),
              style: _style(size: 16, color: _gold),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              dates,
              style: _style(size: 11, color: PdfColors.grey300),
            ),
            pw.Spacer(),
            pw.Row(
              children: [
                _coverStat(
                  labels.number(data.members.length),
                  labels.text('pdf_members'),
                ),
                _coverStat(
                  labels.number(data.posts.length),
                  labels.text('pdf_posts'),
                ),
                _coverStat(
                  labels.number(data.notices.length),
                  labels.text('pdf_section_notices'),
                ),
                _coverStat(_amount(spent), labels.text('pdf_spent')),
              ],
            ),
            pw.SizedBox(height: 28),
            pw.Text(
              labels.text(
                'pdf_cover_created',
                args: {'date': labels.dateTime(data.exportedAt)},
              ),
              style: _style(size: 9.5, color: PdfColors.grey300),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _coverStat(String value, String label) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            value,
            style: _style(size: 22, bold: true, color: PdfColors.white),
          ),
          pw.Text(
            label,
            style: _style(size: 9, color: PdfColors.grey300),
          ),
        ],
      ),
    );
  }

  /// Every section, in the order the contents list shows them.
  pw.MultiPage pages() {
    return pw.MultiPage(
      pageFormat: _format,
      margin: const pw.EdgeInsets.fromLTRB(_margin, 48, _margin, 48),
      // The default page limit (20) would cut a long trip short.
      maxPages: 10000,
      header: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 6),
        margin: const pw.EdgeInsets.only(bottom: 14),
        decoration: pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: _line, width: 0.6),
          ),
        ),
        child: pw.Text(
          _clean(data.group.name, max: 120),
          style: _style(size: 8, color: _muted),
        ),
      ),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          labels.text(
            'pdf_page_of',
            args: {
              'page': labels.number(context.pageNumber),
              'total': labels.number(context.pagesCount),
            },
          ),
          style: _style(size: 8, color: _muted),
        ),
      ),
      build: (context) => [
        ..._contents(),
        ..._overview(),
        ..._members(),
        ..._journey(),
        ..._notices(),
        ..._money(),
        ..._checklist(),
        ..._transport(),
        ..._rooms(),
        ..._safety(),
        ..._feed(),
        ..._stories(),
        ..._highlights(),
      ],
    );
  }

  List<pw.Widget> _contents() {
    final entries = <(String, int?)>[
      (labels.text('pdf_section_overview'), null),
      (labels.text('pdf_section_members'), data.members.length),
      (labels.text('pdf_section_journey'), data.checkpoints.length),
      (labels.text('pdf_section_notices'), data.notices.length),
      (labels.text('pdf_section_money'), data.expenses.length),
      (labels.text('pdf_section_checklist'), data.checklist.length),
      (labels.text('pdf_section_transport'), data.vehicles.length),
      (labels.text('pdf_section_rooms'), data.hotelRooms.length),
      (labels.text('pdf_section_safety'), data.safetyAlerts.length),
      (labels.text('pdf_section_feed'), data.posts.length),
      (labels.text('pdf_section_stories'), data.stories.length),
      (labels.text('pdf_section_highlights'), data.highlights.length),
    ];
    return [
      ..._heading(labels.text('pdf_contents'), newPage: false),
      for (final (title, count) in entries) ...[
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 6),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(title, style: _style(size: 11, bold: true)),
              ),
              if (count != null)
                pw.Text(
                  labels.number(count),
                  style: _style(size: 11, color: _muted),
                ),
            ],
          ),
        ),
        pw.Divider(color: _line, thickness: 0.5),
      ],
    ];
  }

  List<pw.Widget> _overview() {
    final group = data.group;
    final stops = group.effectiveStops;
    final meeting = [
      if ((group.meetingPointTitle ?? '').trim().isNotEmpty)
        group.meetingPointTitle!.trim(),
      if ((group.meetingPointNote ?? '').trim().isNotEmpty)
        group.meetingPointNote!.trim(),
    ].join(' — ');
    return [
      ..._heading(labels.text('pdf_section_overview')),
      if (group.description.trim().isNotEmpty) ...[
        _para(group.description),
        pw.SizedBox(height: 10),
      ],
      _keyValue(labels.text('pdf_destination'), _clean(group.destination)),
      _keyValue(labels.text('pdf_origin'), _clean(group.originCity)),
      _keyValue(
        labels.text('pdf_dates'),
        '${labels.date(group.startDate)} – ${labels.date(group.endDate)}',
      ),
      _keyValue(labels.text('pdf_meeting_point'), _clean(meeting)),
      _subtitle(labels.text('pdf_stops')),
      if (stops.isEmpty)
        _empty()
      else
        _table(
          [
            labels.text('pdf_col_name'),
            labels.text('pdf_col_date'),
            labels.text('pdf_col_stay'),
            labels.text('pdf_col_detail'),
          ],
          [
            for (final stop in stops)
              [
                _clean(stop.name, max: 120),
                '${labels.date(stop.arrive)} – ${labels.date(stop.leave)}',
                _clean(stop.stay, max: 80),
                _clean(stop.notes, max: 300),
              ],
          ],
        ),
    ];
  }

  List<pw.Widget> _members() {
    return [
      ..._heading(
        labels.text('pdf_section_members'),
        count: data.members.length,
      ),
      if (data.members.isEmpty)
        _empty()
      else
        _table(
          [
            labels.text('pdf_col_name'),
            labels.text('pdf_col_role'),
            labels.text('pdf_col_family'),
            labels.text('pdf_col_joined'),
          ],
          [
            for (final member in data.members)
              [
                _clean(member.displayName, max: 80),
                _roleLabel(member.role),
                labels.number(member.familyCount),
                labels.date(member.joinedAt),
              ],
          ],
        ),
    ];
  }

  List<pw.Widget> _journey() {
    return [
      ..._heading(
        labels.text('pdf_section_journey'),
        count: data.checkpoints.length,
      ),
      if (data.checkpoints.isEmpty)
        _empty()
      else
        _table(
          [
            labels.text('pdf_col_name'),
            labels.text('pdf_col_status'),
            labels.text('pdf_col_when'),
            labels.text('pdf_col_detail'),
          ],
          [
            for (final checkpoint in data.checkpoints)
              [
                _clean(checkpoint.name, max: 120),
                checkpoint.visitedAt == null
                    ? labels.text('pdf_not_visited')
                    : labels.text('pdf_visited'),
                checkpoint.visitedAt == null
                    ? ''
                    : labels.dateTime(checkpoint.visitedAt!),
                _clean(checkpoint.notes, max: 300),
              ],
          ],
        ),
    ];
  }

  List<pw.Widget> _notices() {
    final notices = [...data.notices]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return [
      ..._heading(
        labels.text('pdf_section_notices'),
        count: notices.length,
      ),
      if (notices.isEmpty) _empty(),
      for (final notice in notices) ...[
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                _clean(notice.title, max: 200),
                style: _style(size: 12, bold: true),
              ),
            ),
            if (notice.pinned) _tag(labels.text('pdf_pinned')),
            if (notice.urgent) _tag(labels.text('pdf_urgent')),
          ],
        ),
        pw.SizedBox(height: 2),
        _meta(
          '${_clean(notice.author, max: 80)} · '
          '${labels.dateTime(notice.createdAt)}',
        ),
        if (notice.eventAt != null)
          _meta(
            '${labels.text('pdf_event')}: '
            '${labels.dateTime(notice.eventAt!)}'
            '${(notice.place ?? '').trim().isEmpty ? '' : ' · ${_clean(notice.place, max: 120)}'}',
          ),
        if (notice.content.trim().isNotEmpty) _para(notice.content),
        pw.SizedBox(height: 12),
      ],
    ];
  }

  List<pw.Widget> _money() {
    final spent = data.expenses.fold<int>(0, (sum, e) => sum + e.amountPaisa);
    final collected =
        data.deposits.fold<int>(0, (sum, d) => sum + d.amountPaisa);
    final settled =
        data.transfers.fold<int>(0, (sum, t) => sum + t.amountPaisa);
    return [
      ..._heading(labels.text('pdf_section_money')),
      pw.Row(
        children: [
          _total(labels.text('pdf_spent'), spent),
          _total(labels.text('pdf_collected'), collected),
          _total(labels.text('pdf_settled'), settled),
        ],
      ),
      _subtitle(labels.text('pdf_expenses')),
      if (data.expenses.isEmpty)
        _empty()
      else
        _table(
          [
            labels.text('pdf_col_date'),
            labels.text('pdf_col_name'),
            labels.text('pdf_col_category'),
            labels.text('pdf_col_amount'),
            labels.text('pdf_col_paid_by'),
          ],
          [
            for (final expense in data.expenses)
              [
                labels.date(expense.date),
                _clean(expense.title, max: 120),
                _clean(expense.category, max: 60),
                _amount(expense.amountPaisa),
                _clean(expense.paidByName, max: 80),
              ],
          ],
        ),
      _subtitle(labels.text('pdf_deposits')),
      if (data.deposits.isEmpty)
        _empty()
      else
        _table(
          [
            labels.text('pdf_col_date'),
            labels.text('pdf_col_member'),
            labels.text('pdf_col_amount'),
            labels.text('pdf_col_detail'),
          ],
          [
            for (final deposit in data.deposits)
              [
                labels.date(deposit.date),
                _clean(deposit.memberName, max: 80),
                _amount(deposit.amountPaisa),
                _clean(deposit.notes, max: 200),
              ],
          ],
        ),
      _subtitle(labels.text('pdf_settlements')),
      if (data.transfers.isEmpty)
        _empty()
      else
        _table(
          [
            labels.text('pdf_col_date'),
            labels.text('pdf_col_from_to'),
            labels.text('pdf_col_amount'),
            labels.text('pdf_col_detail'),
          ],
          [
            for (final transfer in data.transfers)
              [
                labels.date(transfer.date),
                '${_clean(transfer.fromName, max: 80)} → '
                    '${_clean(transfer.toName, max: 80)}',
                _amount(transfer.amountPaisa),
                _clean(transfer.notes, max: 200),
              ],
          ],
        ),
    ];
  }

  List<pw.Widget> _checklist() {
    return [
      ..._heading(
        labels.text('pdf_section_checklist'),
        count: data.checklist.length,
      ),
      if (data.checklist.isEmpty)
        _empty()
      else
        _table(
          [
            labels.text('pdf_col_name'),
            labels.text('pdf_col_category'),
            labels.text('pdf_col_status'),
          ],
          [
            for (final item in data.checklist)
              [
                _clean(item.title, max: 160),
                _clean(item.category, max: 60),
                item.checkedBy.isEmpty
                    ? labels.text('pdf_open')
                    : labels.text('pdf_done'),
              ],
          ],
        ),
    ];
  }

  List<pw.Widget> _transport() {
    final hasCoach = data.coachSeats.isNotEmpty;
    return [
      ..._heading(
        labels.text('pdf_section_transport'),
        count: data.vehicles.length + (hasCoach ? 1 : 0),
      ),
      if (data.vehicles.isEmpty && !hasCoach) _empty(),
      if (data.vehicles.isNotEmpty)
        _table(
          [
            labels.text('pdf_col_name'),
            labels.text('pdf_col_number'),
            labels.text('pdf_col_route'),
            labels.text('pdf_col_departure'),
          ],
          [
            for (final vehicle in data.vehicles)
              [
                _clean(vehicle.name, max: 120),
                _clean(vehicle.number, max: 60),
                _clean(vehicle.route, max: 160),
                vehicle.departure == null
                    ? ''
                    : labels.dateTime(vehicle.departure!),
              ],
          ],
        ),
      for (final vehicle in data.vehicles)
        ..._seatPlan(
          _clean(vehicle.name, max: 120),
          data.vehicleSeats[vehicle.id] ?? const <BusSeat>[],
        ),
      if (hasCoach) ..._seatPlan(labels.text('pdf_coach'), data.coachSeats),
    ];
  }

  /// The seats of one vehicle that have a passenger, by seat number.
  List<pw.Widget> _seatPlan(String title, List<BusSeat> seats) {
    final assigned = seats
        .where((seat) => (seat.assignedMemberName ?? '').trim().isNotEmpty)
        .toList();
    return [
      _subtitle(title),
      if (assigned.isEmpty)
        _empty()
      else
        _table(
          [labels.text('pdf_col_seat'), labels.text('pdf_col_member')],
          [
            for (final seat in assigned)
              [
                _clean(seat.seatNumber, max: 20),
                _clean(seat.assignedMemberName, max: 80),
              ],
          ],
        ),
    ];
  }

  List<pw.Widget> _rooms() {
    return [
      ..._heading(
        labels.text('pdf_section_rooms'),
        count: data.hotelRooms.length,
      ),
      if (data.hotelRooms.isEmpty)
        _empty()
      else
        _table(
          [
            labels.text('pdf_col_room'),
            labels.text('pdf_col_hotel'),
            labels.text('pdf_col_capacity'),
            labels.text('pdf_col_guests'),
          ],
          [
            for (final room in data.hotelRooms)
              [
                _clean(room.roomNumber, max: 20),
                _clean(room.hotelName.isEmpty ? room.title : room.hotelName,
                    max: 120),
                labels.number(room.capacity),
                _clean(room.assignedMemberNames.join(', '), max: 300),
              ],
          ],
        ),
    ];
  }

  /// Alerts only: when, who and whether it was closed. Locations are left out.
  List<pw.Widget> _safety() {
    return [
      ..._heading(
        labels.text('pdf_section_safety'),
        count: data.safetyAlerts.length,
      ),
      if (data.safetyAlerts.isEmpty)
        _empty()
      else
        _table(
          [
            labels.text('pdf_col_when'),
            labels.text('pdf_col_who'),
            labels.text('pdf_col_status'),
          ],
          [
            for (final alert in data.safetyAlerts)
              [
                alert.createdAt == null
                    ? ''
                    : labels.dateTime(alert.createdAt!),
                _clean(alert.senderName, max: 80),
                alert.resolved
                    ? labels.text('pdf_resolved')
                    : labels.text('pdf_open_alert'),
              ],
          ],
        ),
    ];
  }

  List<pw.Widget> _feed() {
    final posts = data.posts;
    return [
      ..._heading(labels.text('pdf_section_feed'), count: posts.length),
      if (posts.isEmpty) _empty(),
      for (final post in posts) ..._postBlock(post),
    ];
  }

  List<pw.Widget> _postBlock(TourPostItem post) {
    final comments = data.comments[post.id] ?? const <TourCommentItem>[];
    final tags = [
      if (post.isPinned) labels.text('pdf_pinned'),
      if (post.isReel) labels.text('pdf_reel'),
      if (post.isArchived) labels.text('pdf_archived'),
    ];
    final likes = post.hideLikeCount
        ? labels.text('pdf_hidden_likes')
        : labels.text(
            'pdf_likes',
            args: {'count': labels.number(post.likes.length)},
          );
    return [
      pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              _clean(post.authorName, max: 80),
              style: _style(size: 11, bold: true),
            ),
          ),
          pw.Text(
            labels.dateTime(post.createdAt),
            style: _style(size: 8.5, color: _muted),
          ),
        ],
      ),
      if (post.location.trim().isNotEmpty) _meta(post.location),
      if (tags.isNotEmpty) _meta(tags.join(' · ')),
      for (final url in _postPictures(post)) _photo(url),
      if (post.caption.trim().isNotEmpty) _para(post.caption),
      pw.SizedBox(height: 3),
      _meta(
        '$likes · '
        '${labels.text('pdf_comments', args: {
              'count': labels.number(comments.length)
            })}',
      ),
      for (final comment in comments) _commentRow(comment),
      pw.SizedBox(height: 10),
      pw.Divider(color: _line, thickness: 0.6),
      pw.SizedBox(height: 10),
    ];
  }

  pw.Widget _commentRow(TourCommentItem comment) {
    final text = _clean(comment.text, max: 600);
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(width: comment.isReply ? 18 : 0),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _meta(
                '${_clean(comment.authorName, max: 80)} · '
                '${labels.dateTime(comment.createdAt)}',
              ),
              if (text.isNotEmpty) pw.Text(text, style: _style(size: 9.5)),
              pw.SizedBox(height: 5),
            ],
          ),
        ),
      ],
    );
  }

  List<pw.Widget> _stories() {
    return [
      ..._heading(
        labels.text('pdf_section_stories'),
        count: data.stories.length,
      ),
      if (data.stories.isEmpty) _empty(),
      for (final story in data.stories) ...[
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                _clean(story.authorName, max: 80),
                style: _style(size: 11, bold: true),
              ),
            ),
            pw.Text(
              labels.dateTime(story.createdAt),
              style: _style(size: 8.5, color: _muted),
            ),
          ],
        ),
        if (story.isVideo) _meta(labels.text('pdf_video')),
        if (story.mediaUrl.isNotEmpty) _photo(story.mediaUrl),
        if ((story.caption ?? '').trim().isNotEmpty) _para(story.caption!),
        pw.SizedBox(height: 10),
        pw.Divider(color: _line, thickness: 0.6),
        pw.SizedBox(height: 10),
      ],
    ];
  }

  List<pw.Widget> _highlights() {
    return [
      ..._heading(
        labels.text('pdf_section_highlights'),
        count: data.highlights.length,
      ),
      if (data.highlights.isEmpty) _empty(),
      for (final highlight in data.highlights) ...[
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                _clean(highlight.title, max: 120),
                style: _style(size: 12, bold: true),
              ),
            ),
            _meta(
              labels.text(
                'pdf_story_count',
                args: {'count': labels.number(highlight.storyIds.length)},
              ),
            ),
          ],
        ),
        _meta(labels.dateTime(highlight.createdAt)),
        if (highlight.coverUrl.isNotEmpty) _photo(highlight.coverUrl),
        pw.SizedBox(height: 12),
      ],
    ];
  }
}
