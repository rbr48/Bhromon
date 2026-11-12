import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

/// Quiet margin around a code, in modules. Scanners need it to find the edges of the code.
const int inviteQrQuietModules = 4;

/// The QR matrix for [data], with medium error correction.
QrImage inviteQrImage(String data) => QrImage(
      QrCode.fromData(
        data: data,
        errorCorrectLevel: QrErrorCorrectLevel.M,
      ),
    );

/// A group's QR code: dark modules on white, which scanners read most reliably.
class InviteQrCode extends StatelessWidget {
  final String data;
  final double size;

  const InviteQrCode({super.key, required this.data, this.size = 220});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _InviteQrPainter(inviteQrImage(data))),
    );
  }
}

/// The QR code for [data] as a PNG of [pixels] square, with the same margin as the card on screen.
Future<Uint8List> renderInviteQrPng(String data, {int pixels = 1024}) async {
  final image = inviteQrImage(data);
  final side = pixels.toDouble();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, side, side));
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, side, side),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  _drawModules(canvas, image, side / _moduleSpan(image));
  final picture = recorder.endRecording();
  final rendered = await picture.toImage(pixels, pixels);
  final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
  rendered.dispose();
  picture.dispose();
  if (bytes == null) {
    throw StateError('The QR code could not be drawn.');
  }
  return bytes.buffer.asUint8List();
}

/// Modules across the whole picture, margins included.
int _moduleSpan(QrImage image) => image.moduleCount + inviteQrQuietModules * 2;

/// Draws each dark module of [image] as a square [cell] pixels wide, inside the quiet margin.
void _drawModules(ui.Canvas canvas, QrImage image, double cell) {
  final dark = ui.Paint()..color = const ui.Color(0xFF000000);
  for (var row = 0; row < image.moduleCount; row++) {
    for (var col = 0; col < image.moduleCount; col++) {
      if (!image.isDark(row, col)) continue;
      canvas.drawRect(
        ui.Rect.fromLTWH(
          (col + inviteQrQuietModules) * cell,
          (row + inviteQrQuietModules) * cell,
          cell,
          cell,
        ),
        dark,
      );
    }
  }
}

class _InviteQrPainter extends CustomPainter {
  final QrImage image;

  const _InviteQrPainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    _drawModules(canvas, image, size.shortestSide / _moduleSpan(image));
  }

  @override
  bool shouldRepaint(covariant _InviteQrPainter oldDelegate) =>
      oldDelegate.image != image;
}
