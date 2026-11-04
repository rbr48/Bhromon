import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr/qr.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/colors.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../domain/services/bangla_qr_engine.dart';

/// Renders a native Bangla QR code with payment breakdown and copy/share utilities.
class BanglaQrView extends StatelessWidget {
  const BanglaQrView({
    super.key,
    required this.payload,
    this.size = 200.0,
  });

  final BanglaQrPayload payload;
  final double size;

  @override
  Widget build(BuildContext context) {
    final rawData = BanglaQrEngine.generate(payload);
    final qrCode = QrCode.fromData(
      data: rawData,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    final qrImage = QrImage(qrCode);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(
                size: Size(size, size),
                painter: _QrPainter(qrImage: qrImage),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2136E),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      payload.provider.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'BANGLA QR',
                    style: TextStyle(
                      color: Color(0xFF1B4332),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QrPainter extends CustomPainter {
  const _QrPainter({required this.qrImage});

  final QrImage qrImage;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF111827)
      ..style = PaintingStyle.fill;

    final moduleCount = qrImage.moduleCount;
    final moduleSize = size.width / moduleCount;

    for (var x = 0; x < moduleCount; x++) {
      for (var y = 0; y < moduleCount; y++) {
        if (qrImage.isDark(y, x)) {
          final rect = Rect.fromLTWH(
            x * moduleSize,
            y * moduleSize,
            moduleSize,
            moduleSize,
          );
          canvas.drawRect(rect, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter oldDelegate) =>
      oldDelegate.qrImage != qrImage;
}

/// Opens an adaptive modal bottom sheet displaying a generated Bangla QR bill.
Future<void> showBanglaQrSheet(
  BuildContext context, {
  required BanglaQrPayload payload,
}) {
  final f = context.forest;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    backgroundColor: f.sheet,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: f.text24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Bangla QR Payment',
              style: TextStyle(
                color: f.text,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Scan with bKash, Nagad, or any Bangladeshi banking app',
              style: TextStyle(color: f.text60, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            BanglaQrView(payload: payload, size: 200),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: f.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: f.divider12),
              ),
              child: Column(
                children: [
                  if (payload.amountTaka != null &&
                      payload.amountTaka! > 0) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Amount',
                            style: TextStyle(color: f.text70, fontSize: 13)),
                        Text(
                          '৳ ${payload.amountTaka}',
                          style: TextStyle(
                            color: f.readable(AppColors.gold),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Divider(color: f.divider12, height: 16),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Payee',
                          style: TextStyle(color: f.text70, fontSize: 13)),
                      Text(
                        payload.payeeName,
                        style: TextStyle(
                            color: f.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Account (${payload.provider.displayName})',
                          style: TextStyle(color: f.text70, fontSize: 13)),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            payload.accountNumber,
                            style: TextStyle(
                                color: f.text,
                                fontSize: 13,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(
                                  ClipboardData(text: payload.accountNumber));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Account number copied'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            child: Icon(Icons.copy_rounded,
                                size: 15, color: f.accentText),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (payload.reference != null &&
                      payload.reference!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Reference',
                            style: TextStyle(color: f.text70, fontSize: 13)),
                        Text(
                          payload.reference!,
                          style: TextStyle(color: f.text60, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.share_rounded, size: 16),
                label: const Text('Share Payment Details'),
                onPressed: () {
                  final details = StringBuffer()
                    ..writeln('Bhromon Payment Details')
                    ..writeln('Payee: ${payload.payeeName}')
                    ..writeln('Provider: ${payload.provider.displayName}')
                    ..writeln('Account: ${payload.accountNumber}');
                  if (payload.amountTaka != null && payload.amountTaka! > 0) {
                    details.writeln('Amount: ৳ ${payload.amountTaka}');
                  }
                  if (payload.reference != null &&
                      payload.reference!.isNotEmpty) {
                    details.writeln('Ref: ${payload.reference}');
                  }
                  SharePlus.instance.share(
                    ShareParams(text: details.toString().trim()),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
