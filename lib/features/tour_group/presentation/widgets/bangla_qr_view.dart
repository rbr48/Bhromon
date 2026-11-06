import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr/qr.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/colors.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../domain/services/bangla_qr_engine.dart';
import '../../domain/services/payment_profile_service.dart';
import '../../domain/services/smart_qr_enhancer.dart';

/// Supported account classification for MFS payments.
enum MfsAccountType {
  personal,
  merchant,
}

/// Renders a native Bangla QR code with payment breakdown and copy/share utilities.
class BanglaQrView extends StatelessWidget {
  const BanglaQrView({
    super.key,
    required this.payload,
    this.size = 200.0,
    this.isPersonal = true,
  });

  final BanglaQrPayload payload;
  final double size;
  final bool isPersonal;

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
                  Text(
                    isPersonal ? 'SEND MONEY' : 'BANGLA QR',
                    style: TextStyle(
                      color: isPersonal
                          ? const Color(0xFFB78103)
                          : const Color(0xFF1B4332),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              if (isPersonal) ...[
                const SizedBox(height: 6),
                const Text(
                  '* অ্যাপ স্ক্যানারে সমস্যা হলে নম্বর কপি করে সেন্ড মানি করুন',
                  style: TextStyle(
                    color: Color(0xFF856404),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
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
  String? savedQrUrl,
  bool isOwnQr = false,
  String? payeeUid,
  VoidCallback? onQrSavedToProfile,
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
    builder: (ctx) => BanglaQrSheetModal(
      initialPayload: payload,
      savedQrUrl: savedQrUrl,
      isOwnQr: isOwnQr,
      payeeUid: payeeUid,
      onQrSavedToProfile: onQrSavedToProfile,
    ),
  );
}

/// Interactive sheet providing dynamic EMVCo Bangla QR generation and custom QR image upload.
class BanglaQrSheetModal extends StatefulWidget {
  const BanglaQrSheetModal({
    super.key,
    required this.initialPayload,
    this.savedQrUrl,
    this.isOwnQr = false,
    this.payeeUid,
    this.onQrSavedToProfile,
  });

  final BanglaQrPayload initialPayload;
  final String? savedQrUrl;
  final bool isOwnQr;
  final String? payeeUid;
  final VoidCallback? onQrSavedToProfile;

  @override
  State<BanglaQrSheetModal> createState() => _BanglaQrSheetModalState();
}

class _BanglaQrSheetModalState extends State<BanglaQrSheetModal> {
  late int _activeTab; // 0: Dynamic QR, 1: My QR Image
  MfsAccountType _accountType = MfsAccountType.personal;
  late BanglaQrPayload _payload;
  late final TextEditingController _phoneController;
  late final TextEditingController _amountController;
  Uint8List? _customQrBytes;
  bool _wasAutoCropped = false;
  bool _isUploading = false;
  bool _isSavingToProfile = false;
  bool _isSavedToProfile = false;
  String? _effectiveSavedQrUrl;

  @override
  void initState() {
    super.initState();
    _effectiveSavedQrUrl = widget.savedQrUrl;
    _activeTab =
        (_effectiveSavedQrUrl != null && _effectiveSavedQrUrl!.isNotEmpty)
            ? 1
            : 0;
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
        maxWidth: 2000,
        imageQuality: 95,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        final enhanced = SmartQrEnhancer.process(bytes);
        if (mounted) {
          setState(() {
            if (enhanced != null) {
              _customQrBytes = enhanced.bytes;
              _wasAutoCropped = enhanced.isAutoCropped;
              if (enhanced.detectedProvider != null) {
                for (final p in BanglaQrProvider.values) {
                  if (p.name.toLowerCase() ==
                      enhanced.detectedProvider!.toLowerCase()) {
                    _payload = _payload.copyWith(provider: p);
                    break;
                  }
                }
              }
            } else {
              _customQrBytes = bytes;
              _wasAutoCropped = false;
            }
            _isSavedToProfile = false;
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

  Future<void> _saveToProfile() async {
    if (_customQrBytes == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSavingToProfile = true);
    try {
      final saved = await PaymentProfileService.savePaymentQr(
        uid: user.uid,
        imageBytes: _customQrBytes!,
        accountNumber: _phoneController.text.trim(),
        provider: _payload.provider.name,
        accountType: _accountType.name,
      );

      if (saved != null && mounted) {
        setState(() {
          _isSavedToProfile = true;
          _effectiveSavedQrUrl = saved.banglaQrUrl;
        });
        widget.onQrSavedToProfile?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '✅ বাংলা কিউআর আপনার প্রোফাইলে স্থায়ীভাবে সংরক্ষিত হয়েছে!',
              style: TextStyle(
                fontFamily: 'NotoSansBengali',
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: AppColors.mintGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('প্রোফাইলে সেভ ব্যর্থ হয়েছে: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingToProfile = false);
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

  Widget _buildAccountTypeSelector(ForestPalette f) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
              onTap: () =>
                  setState(() => _accountType = MfsAccountType.personal),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: _accountType == MfsAccountType.personal
                      ? f.accentText.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.person,
                      size: 15,
                      color: _accountType == MfsAccountType.personal
                          ? f.accentText
                          : f.text60,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'ব্যক্তিগত (Send Money)',
                      style: TextStyle(
                        color: _accountType == MfsAccountType.personal
                            ? f.accentText
                            : f.text60,
                        fontWeight: _accountType == MfsAccountType.personal
                            ? FontWeight.bold
                            : FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () =>
                  setState(() => _accountType = MfsAccountType.merchant),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: _accountType == MfsAccountType.merchant
                      ? f.accentText.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.storefront,
                      size: 15,
                      color: _accountType == MfsAccountType.merchant
                          ? f.accentText
                          : f.text60,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'মার্চেন্ট (Bangla QR)',
                      style: TextStyle(
                        color: _accountType == MfsAccountType.merchant
                            ? f.accentText
                            : f.text60,
                        fontWeight: _accountType == MfsAccountType.merchant
                            ? FontWeight.bold
                            : FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalNoticeCard(ForestPalette f) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9E6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD54F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, color: Color(0xFFB78103), size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ব্যক্তিগত অ্যাকাউন্ট নির্দেশনা (Send Money)',
                  style: TextStyle(
                    color: Color(0xFF7F5400),
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'বিকাশ ও নগদ অ্যাপের ইন-অ্যাপ কিউআর স্ক্যানার শুধুমাত্র রেজিস্টার্ড মার্চেন্টদের জন্য কাজ করে। ব্যক্তিগত অ্যাকাউন্টে টাকা পাঠাতে নম্বরটি কপি করে আপনার বিকাশ বা নগদ অ্যাপে "সেন্ড মানি" করুন।',
            style: TextStyle(
              color: Color(0xFF5D4037),
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1B4332),
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.copy, size: 14),
                  label: const Text(
                    'নম্বর কপি করুন (সেন্ড মানি)',
                    style:
                        TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    Clipboard.setData(
                        ClipboardData(text: _payload.accountNumber));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'নম্বর কপি হয়েছে! বিকাশ/নগদে গিয়ে সেন্ড মানি করুন।'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1B4332),
                  side: const BorderSide(color: Color(0xFF1B4332)),
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.photo_library_outlined, size: 14),
                label: const Text(
                  'কিউআর ছবি',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                onPressed: () => setState(() => _activeTab = 1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMerchantNoticeCard(ForestPalette f) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFA5D6A7)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified, color: Color(0xFF2E7D32), size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'মার্চেন্ট বাংলা কিউআর: বিকাশ, নগদ বা যেকোনো ব্যাংক অ্যাপ (CellFin, CityTouch, EBL ইত্যাদি) দিয়ে সরাসরি স্ক্যান করে পেমেন্ট সম্পন্ন করুন।',
              style: TextStyle(
                color: Color(0xFF1B5E20),
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderSelector(ForestPalette f) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
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

        return ChoiceChip(
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
                if (p == BanglaQrProvider.bank) {
                  _accountType = MfsAccountType.merchant;
                }
              });
            }
          },
        );
      }).toList(),
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
              _buildAccountTypeSelector(f),
              _buildProviderSelector(f),
              const SizedBox(height: 12),
              BanglaQrView(
                payload: _payload,
                size: 190,
                isPersonal: _accountType == MfsAccountType.personal,
              ),
              if (_accountType == MfsAccountType.personal)
                _buildPersonalNoticeCard(f)
              else
                _buildMerchantNoticeCard(f),
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
                    child: Builder(
                      builder: (context) {
                        final isBankOrMerchant =
                            _accountType == MfsAccountType.merchant ||
                                _payload.provider == BanglaQrProvider.bank;
                        return TextField(
                          controller: _phoneController,
                          keyboardType: isBankOrMerchant
                              ? TextInputType.text
                              : TextInputType.phone,
                          inputFormatters: isBankOrMerchant
                              ? [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'[a-zA-Z0-9\-\s]')),
                                  LengthLimitingTextInputFormatter(24),
                                ]
                              : [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(11),
                                ],
                          style: TextStyle(
                              color: f.text,
                              fontSize: 13,
                              fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            labelText: isBankOrMerchant
                                ? 'প্রাপকের অ্যাকাউন্ট / আইডি'
                                : 'প্রাপকের মোবাইল নম্বর (১১ ডিজিট)',
                            labelStyle:
                                TextStyle(color: f.text70, fontSize: 11.5),
                            hintText: isBankOrMerchant
                                ? 'অ্যাকাউন্ট বা মার্চেন্ট আইডি'
                                : '01XXXXXXXXX',
                            hintStyle: TextStyle(color: f.text24, fontSize: 12),
                            prefixIcon: Icon(
                                isBankOrMerchant
                                    ? Icons.account_balance
                                    : Icons.phone_android,
                                size: 18,
                                color: f.accentText),
                            suffixIcon: _payload.isPhoneAccount
                                ? const Icon(Icons.check_circle,
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
                            final cleaned = isBankOrMerchant
                                ? val.trim()
                                : BanglaQrPayload.normalizePhone(val);
                            setState(() {
                              _payload = _payload.copyWith(
                                accountNumber: cleaned.isNotEmpty
                                    ? cleaned
                                    : widget.initialPayload.accountNumber,
                              );
                            });
                          },
                        );
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
              // Tab 1: Custom "My QR" image upload or saved profile QR
              if (_customQrBytes == null &&
                  (_effectiveSavedQrUrl == null ||
                      _effectiveSavedQrUrl!.isEmpty)) ...[
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
                      Icon(Icons.qr_code_scanner,
                          size: 52, color: f.accentText),
                      const SizedBox(height: 12),
                      Text(
                        'bKash বা Nagad-এর "My QR" ছবি যোগ করুন',
                        style: TextStyle(
                          fontFamily: 'NotoSansBengali',
                          color: f.text,
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'অ্যাপ থেকে স্ক্রিনশট বা ছবি দিলে আমাদের স্মার্ট এডিটর স্বয়ংক্রিয়ভাবে ক্রপ ও পরিষ্কার করে নেবে।',
                        style: TextStyle(
                            fontFamily: 'NotoSansBengali',
                            color: f.text60,
                            fontSize: 12),
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
                        icon: const Icon(Icons.photo_library, size: 18),
                        label: const Text(
                          'গ্যালারি থেকে ছবি বাছাই করুন',
                          style: TextStyle(
                              fontFamily: 'NotoSansBengali',
                              fontWeight: FontWeight.bold),
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
                        child: _customQrBytes != null
                            ? Image.memory(
                                _customQrBytes!,
                                height: 220,
                                width: 220,
                                fit: BoxFit.contain,
                              )
                            : Image.network(
                                _effectiveSavedQrUrl!,
                                height: 220,
                                width: 220,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const SizedBox(
                                  height: 160,
                                  child: Center(
                                    child: Icon(Icons.broken_image,
                                        size: 40, color: Colors.grey),
                                  ),
                                ),
                              ),
                      ),
                      if (_wasAutoCropped) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.mintGreen.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_fix_high_rounded,
                                  size: 14, color: AppColors.mintGreen),
                              SizedBox(width: 5),
                              Text(
                                'স্মার্ট এডিটিং: স্বয়ংক্রিয়ভাবে ক্রপ ও পরিষ্কার করা হয়েছে',
                                style: TextStyle(
                                  fontFamily: 'NotoSansBengali',
                                  color: AppColors.mintGreen,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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
                              fontFamily: 'NotoSansBengali',
                              color: Color(0xFF111827),
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_customQrBytes != null &&
                    (widget.isOwnQr ||
                        FirebaseAuth.instance.currentUser?.uid ==
                            widget.payeeUid)) ...[
                  const SizedBox(height: 10),
                  if (_isSavedToProfile)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.mintGreen.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_rounded,
                              size: 16, color: AppColors.mintGreen),
                          SizedBox(width: 6),
                          Text(
                            'প্রোফাইলে স্থায়ীভাবে সংরক্ষিত আছে',
                            style: TextStyle(
                              fontFamily: 'NotoSansBengali',
                              color: AppColors.mintGreen,
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.mintGreen,
                        foregroundColor: AppColors.darkGreen,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: _isSavingToProfile
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.darkGreen),
                            )
                          : const Icon(Icons.bookmark_add_rounded, size: 16),
                      label: Text(
                        _isSavingToProfile
                            ? 'সংরক্ষণ হচ্ছে...'
                            : 'আমার প্রোফাইলেও স্থায়ীভাবে সেভ করুন',
                        style: const TextStyle(
                            fontFamily: 'NotoSansBengali',
                            fontWeight: FontWeight.bold,
                            fontSize: 12),
                      ),
                      onPressed: _isSavingToProfile ? null : _saveToProfile,
                    ),
                ],
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text(
                        'ছবি পরিবর্তন',
                        style: TextStyle(fontFamily: 'NotoSansBengali'),
                      ),
                      onPressed: _pickQrImage,
                    ),
                    const SizedBox(width: 12),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.redAccent),
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text(
                        'মুছে ফেলুন',
                        style: TextStyle(fontFamily: 'NotoSansBengali'),
                      ),
                      onPressed: () => setState(() {
                        _customQrBytes = null;
                        _effectiveSavedQrUrl = null;
                        _wasAutoCropped = false;
                      }),
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
                            child:
                                Icon(Icons.copy, size: 15, color: f.accentText),
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
                icon: const Icon(Icons.share, size: 16),
                label: const Text('Share Payment Details'),
                onPressed: () {
                  final details = StringBuffer()
                    ..writeln('Bhromon Payment Details')
                    ..writeln('Payee: ${_payload.payeeName}')
                    ..writeln('Provider: ${_payload.provider.displayName}')
                    ..writeln('Account: ${_payload.accountNumber}')
                    ..writeln(
                        'Type: ${_accountType == MfsAccountType.personal ? 'Send Money (ব্যক্তিগত)' : 'Merchant Payment (মার্চেন্ট)'}');
                  if (_payload.amountTaka != null && _payload.amountTaka! > 0) {
                    details.writeln('Amount: ৳ ${_payload.amountTaka}');
                  }
                  if (_payload.reference != null &&
                      _payload.reference!.isNotEmpty) {
                    details.writeln('Ref: ${_payload.reference}');
                  }
                  if (_accountType == MfsAccountType.personal) {
                    details.writeln(
                        'Note: বিকাশ/নগদ অ্যাপে "সেন্ড মানি" (Send Money) করুন।');
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
