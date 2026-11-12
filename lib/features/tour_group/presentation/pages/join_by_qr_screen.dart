import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../domain/services/invite_join_link.dart';

/// Reads a group's QR code with the camera, in the phone app and in a browser. A pasted invite link
/// or code works too. The screen returns the invite code it read, and the caller opens the join
/// page, where the person confirms before joining.
class JoinByQrScreen extends StatefulWidget {
  /// Whether the camera runs. Tests turn it off; the paste field is always there.
  final bool scannerEnabled;

  const JoinByQrScreen({super.key, this.scannerEnabled = true});

  @override
  State<JoinByQrScreen> createState() => _JoinByQrScreenState();
}

class _JoinByQrScreenState extends State<JoinByQrScreen> {
  final TextEditingController _pasteCtrl = TextEditingController();
  MobileScannerController? _scanner;
  String? _problem;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    if (widget.scannerEnabled) {
      _scanner = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        formats: const [BarcodeFormat.qrCode],
      );
    }
  }

  @override
  void dispose() {
    _scanner?.dispose();
    _pasteCtrl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && inviteCodeFromScan(value) != null) {
        _take(value);
        return;
      }
    }
    if (capture.barcodes.isNotEmpty) _refuse();
  }

  /// Hands [raw] back as the invite, once. Text that is not a group invite is refused.
  void _take(String raw) {
    if (_finished) return;
    final code = inviteCodeFromScan(raw);
    if (code == null) {
      _refuse();
      return;
    }
    _finished = true;
    unawaited(_scanner?.stop());
    Navigator.of(context).pop(code);
  }

  void _refuse() {
    if (_finished) return;
    final message = context.l10n.translate('join_scan_invalid');
    if (_problem == message) return;
    setState(() => _problem = message);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final f = context.forest;
    final scanner = _scanner;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.translate('join_scan_title'))),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: scanner == null
                  ? Center(
                      child: Icon(Icons.qr_code_scanner_rounded,
                          size: 72, color: f.text54),
                    )
                  : Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        MobileScanner(
                          controller: scanner,
                          onDetect: _onDetect,
                          errorBuilder: (context, error) => Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                l10n.translate('join_scan_camera_denied'),
                                textAlign: TextAlign.center,
                                style: TextStyle(color: f.text70),
                              ),
                            ),
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.all(16),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            l10n.translate('join_scan_hint'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
            ),
            if (_problem != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  _problem!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _pasteCtrl,
                      textInputAction: TextInputAction.go,
                      onSubmitted: _take,
                      decoration: InputDecoration(
                        labelText: l10n.translate('join_scan_paste_hint'),
                        filled: true,
                        fillColor: f.inset26,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.mintGreen,
                      foregroundColor: AppColors.darkGreen,
                    ),
                    onPressed: () => _take(_pasteCtrl.text),
                    child: Text(l10n.translate('join_scan_continue')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
