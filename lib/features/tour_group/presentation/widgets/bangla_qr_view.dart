import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
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

  Color get _providerColor {
    switch (payload.provider) {
      case BanglaQrProvider.bkash:
        return const Color(0xFFE2136E);
      case BanglaQrProvider.nagad:
        return const Color(0xFFF7931E);
      case BanglaQrProvider.rocket:
        return const Color(0xFF8C3494);
      case BanglaQrProvider.upay:
        return const Color(0xFF005696);
      case BanglaQrProvider.cellfin:
        return const Color(0xFF00875A);
      case BanglaQrProvider.bank:
        return const Color(0xFF00695C);
    }
  }

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
                      color: _providerColor,
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

/// Opens an adaptive modal bottom sheet displaying a generated Bangla QR bill,
/// with real-time phone number validation and custom "My QR" image upload.
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
    builder: (ctx) => BanglaQrSheetModal(initialPayload: payload),
  );
}

/// Interactive sheet providing dynamic EMVCo Bangla QR generation and custom QR image upload.
class BanglaQrSheetModal extends StatefulWidget {
  const BanglaQrSheetModal({
    super.key,
    required this.initialPayload,
  });

  final BanglaQrPayload initialPayload;

  @override
  State<BanglaQrSheetModal> createState() => _BanglaQrSheetModalState();
}

class _BanglaQrSheetModalState extends State<BanglaQrSheetModal> {
  int _activeTab = 0; // 0: Dynamic QR, 1: My QR Image
  late BanglaQrPayload _payload;
  late final TextEditingController _phoneController;
  late final TextEditingController _amountController;
  Uint8List? _customQrBytes;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _payload = widget.initialPayload;
    final initialPhone = widget.initialPayload.isPhoneAccount
        ? BanglaQrPayload.normalizePhone(widget.initialPayload.accountNumber)
        : '';
    _phoneController = TextEditingController(text: initialPhone);
    _amountController = TextEditingController(
      text: widget.initialPayload.amountTaka != null &&
              widget.initialPayload.amountTaka! > 0
          ? widget.initialPayload.amountTaka.toString()
          : '',
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickQrImage() async {
    setState(() => _isUploading = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 90,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        if (mounted) {
          setState(() {
            _customQrBytes = bytes;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load image: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Widget _buildTabSwitcher(ForestPalette f) {
    return Container(
      decoration: BoxDecoration(
        color: f.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: f.divider12),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _activeTab = 0),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _activeTab == 0
                      ? f.accentText.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  'ডায়নামিক কিউআর',
                  style: TextStyle(
                    color: _activeTab == 0 ? f.accentText : f.text60,
                    fontWeight:
                        _activeTab == 0 ? FontWeight.bold : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _activeTab = 1),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _activeTab == 1
                      ? f.accentText.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  'কিউআর ছবি (গ্যালারি)',
                  style: TextStyle(
                    color: _activeTab == 1 ? f.accentText : f.text60,
                    fontWeight:
                        _activeTab == 1 ? FontWeight.bold : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderSelector(ForestPalette f) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: BanglaQrProvider.values.map((p) {
          final isSelected = _payload.provider == p;
          Color color;
          switch (p) {
            case BanglaQrProvider.bkash:
              color = const Color(0xFFE2136E);
              break;
            case BanglaQrProvider.nagad:
              color = const Color(0xFFF7931E);
              break;
            case BanglaQrProvider.rocket:
              color = const Color(0xFF8C3494);
              break;
            case BanglaQrProvider.upay:
              color = const Color(0xFF005696);
              break;
            case BanglaQrProvider.cellfin:
              color = const Color(0xFF00875A);
              break;
            case BanglaQrProvider.bank:
              color = const Color(0xFF00695C);
              break;
          }

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              selected: isSelected,
              label: Text(p.displayName),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : f.text,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              selectedColor: color,
              backgroundColor: f.card,
              side: BorderSide(
                color: isSelected ? color : f.divider12,
              ),
              onSelected: (val) {
                if (val) {
                  setState(() {
                    _payload = _payload.copyWith(provider: p);
                  });
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = context.forest;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
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
            const SizedBox(height: 14),
            Text(
              Localizations.maybeLocaleOf(context)?.languageCode == 'bn'
                  ? 'বাংলা কিউআর ও এমএফএস পেমেন্ট'
                  : 'Bangla QR & MFS Payment',
              style: TextStyle(
                color: f.text,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              Localizations.maybeLocaleOf(context)?.languageCode == 'bn'
                  ? 'বিকাশ, নগদ, রকেট বা যেকোনো বাংলাদেশি ব্যাংক অ্যাপ দিয়ে স্ক্যান করুন'
                  : 'Scan with bKash, Nagad, Rocket, or any Bangladeshi bank app',
              style: TextStyle(color: f.text60, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            _buildTabSwitcher(f),
            const SizedBox(height: 16),
            if (_activeTab == 0) ...[
              _buildProviderSelector(f),
              const SizedBox(height: 14),
              BanglaQrView(payload: _payload, size: 190),
              if (!_payload.isPhoneAccount) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3CD),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFFEEBA)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: Color(0xFF856404), size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'bKash/Nagad অ্যাপে সরাসরি স্ক্যানের জন্য প্রাপকের ১১ ডিজিটের মোবাইল নম্বর দিন।',
                          style: TextStyle(
                            color: Color(0xFF856404),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(11),
                      ],
                      style: TextStyle(
                          color: f.text,
                          fontSize: 13,
                          fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: 'প্রাপকের মোবাইল নম্বর (১১ ডিজিট)',
                        labelStyle: TextStyle(color: f.text70, fontSize: 11.5),
                        hintText: '01XXXXXXXXX',
                        hintStyle: TextStyle(color: f.text24, fontSize: 12),
                        prefixIcon: Icon(Icons.phone_android_rounded,
                            size: 18, color: f.accentText),
                        suffixIcon: _payload.isPhoneAccount
                            ? const Icon(Icons.check_circle_rounded,
                                color: Colors.green, size: 18)
                            : null,
                        filled: true,
                        fillColor: f.card,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: f.divider12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: _payload.isPhoneAccount
                                ? Colors.green.withValues(alpha: 0.6)
                                : f.divider12,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: f.accentText, width: 1.5),
                        ),
                      ),
                      onChanged: (val) {
                        final normalized = BanglaQrPayload.normalizePhone(val);
                        setState(() {
                          _payload = _payload.copyWith(
                            accountNumber: normalized.isNotEmpty
                                ? normalized
                                : widget.initialPayload.accountNumber,
                          );
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      style: TextStyle(
                          color: f.text,
                          fontSize: 13,
                          fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: 'টাকার পরিমাণ (৳)',
                        labelStyle: TextStyle(color: f.text70, fontSize: 11.5),
                        hintText: 'ঐচ্ছিক',
                        hintStyle: TextStyle(color: f.text24, fontSize: 12),
                        prefixIcon: Icon(Icons.payments_outlined,
                            size: 18, color: f.accentText),
                        filled: true,
                        fillColor: f.card,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: f.divider12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: f.accentText, width: 1.5),
                        ),
                      ),
                      onChanged: (val) {
                        final amt = int.tryParse(val);
                        setState(() {
                          _payload = _payload.copyWith(amountTaka: amt);
                        });
                      },
                    ),
                  ),
                ],
              ),
            ] else ...[
              // Tab 1: Custom "My QR" image upload
              if (_customQrBytes == null) ...[
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                  decoration: BoxDecoration(
                    color: f.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: f.divider12),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.qr_code_scanner_rounded,
                          size: 52, color: f.accentText),
                      const SizedBox(height: 12),
                      Text(
                        'bKash বা Nagad-এর "My QR" ছবি যোগ করুন',
                        style: TextStyle(
                          color: f.text,
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'অ্যাপ থেকে ডাউনলোড করা বা স্ক্রিনশট নেওয়া অফিশিয়াল কিউআর গ্যালারি থেকে নির্বাচন করুন।',
                        style: TextStyle(color: f.text60, fontSize: 11.5),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.mintGreen,
                          foregroundColor: AppColors.darkGreen,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12),
                        ),
                        icon: const Icon(Icons.photo_library_rounded, size: 18),
                        label: const Text(
                          'গ্যালারি থেকে ছবি বাছাই করুন',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: _isUploading ? null : _pickQrImage,
                      ),
                    ],
                  ),
                ),
              ] else ...[
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
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(
                          _customQrBytes!,
                          height: 220,
                          width: 220,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1B4332),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'OFFICIAL QR',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _payload.payeeName,
                            style: const TextStyle(
                              color: Color(0xFF111827),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('ছবি পরিবর্তন'),
                      onPressed: _pickQrImage,
                    ),
                    const SizedBox(width: 12),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.redAccent),
                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                      label: const Text('মুছে ফেলুন'),
                      onPressed: () => setState(() => _customQrBytes = null),
                    ),
                  ],
                ),
              ],
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: f.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: f.divider12),
              ),
              child: Column(
                children: [
                  if (_payload.amountTaka != null &&
                      _payload.amountTaka! > 0) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Amount',
                            style: TextStyle(color: f.text70, fontSize: 13)),
                        Text(
                          '৳ ${_payload.amountTaka}',
                          style: TextStyle(
                            color: f.readable(AppColors.gold),
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Divider(color: f.divider12, height: 14),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        Localizations.maybeLocaleOf(context)?.languageCode ==
                                'bn'
                            ? 'প্রাপক'
                            : 'Payee',
                        style: TextStyle(color: f.text70, fontSize: 13),
                      ),
                      Text(
                        _payload.payeeName,
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
                      Text(
                        Localizations.maybeLocaleOf(context)?.languageCode ==
                                'bn'
                            ? 'অ্যাকাউন্ট (${_payload.provider.displayName})'
                            : 'Account (${_payload.provider.displayName})',
                        style: TextStyle(color: f.text70, fontSize: 13),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _payload.accountNumber,
                            style: TextStyle(
                                color: f.text,
                                fontSize: 13,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(
                                  ClipboardData(text: _payload.accountNumber));
                              final isBn = Localizations.maybeLocaleOf(context)
                                      ?.languageCode ==
                                  'bn';
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(isBn
                                      ? 'অ্যাকাউন্ট নম্বর কপি করা হয়েছে'
                                      : 'Account number copied'),
                                  duration: const Duration(seconds: 1),
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
                  if (_payload.reference != null &&
                      _payload.reference!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          Localizations.maybeLocaleOf(context)?.languageCode ==
                                  'bn'
                              ? 'রেফারেন্স'
                              : 'Reference',
                          style: TextStyle(color: f.text70, fontSize: 13),
                        ),
                        Text(
                          (Localizations.maybeLocaleOf(context)?.languageCode ==
                                      'bn' &&
                                  _payload.reference == 'Settlement')
                              ? 'হিসাব মেলানো'
                              : _payload.reference!,
                          style: TextStyle(color: f.text60, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.share_rounded, size: 16),
                label: const Text('Share Payment Details'),
                onPressed: () {
                  final details = StringBuffer()
                    ..writeln('Bhromon Payment Details')
                    ..writeln('Payee: ${_payload.payeeName}')
                    ..writeln('Provider: ${_payload.provider.displayName}')
                    ..writeln('Account: ${_payload.accountNumber}');
                  if (_payload.amountTaka != null && _payload.amountTaka! > 0) {
                    details.writeln('Amount: ৳ ${_payload.amountTaka}');
                  }
                  if (_payload.reference != null &&
                      _payload.reference!.isNotEmpty) {
                    details.writeln('Ref: ${_payload.reference}');
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
    );
  }
}
