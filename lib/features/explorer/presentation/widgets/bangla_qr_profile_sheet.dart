import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/colors.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../tour_group/domain/services/bangla_qr_engine.dart';
import '../../../tour_group/domain/services/payment_profile_service.dart';
import '../../../tour_group/domain/services/smart_qr_enhancer.dart';

/// Shows an adaptive modal sheet for managing, uploading, and auto-enhancing the user's permanent Bangla QR.
Future<PaymentProfileInfo?> showBanglaQrProfileSheet(
  BuildContext context, {
  required String uid,
  PaymentProfileInfo? initialProfile,
}) {
  final f = context.forest;

  return showModalBottomSheet<PaymentProfileInfo>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 580),
    backgroundColor: f.sheet,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => BanglaQrProfileSheet(
      uid: uid,
      initialProfile: initialProfile,
    ),
  );
}

class BanglaQrProfileSheet extends StatefulWidget {
  const BanglaQrProfileSheet({
    super.key,
    required this.uid,
    this.initialProfile,
  });

  final String uid;
  final PaymentProfileInfo? initialProfile;

  @override
  State<BanglaQrProfileSheet> createState() => _BanglaQrProfileSheetState();
}

class _BanglaQrProfileSheetState extends State<BanglaQrProfileSheet> {
  late final TextEditingController _accountController;
  late String _selectedProvider;
  late String _selectedAccountType;

  Uint8List? _enhancedBytes;
  Uint8List? _rawPickedBytes;
  bool _showOriginal = false;
  bool _wasAutoCropped = false;
  bool _isProcessingImage = false;
  bool _isSaving = false;
  String? _savedQrUrl;

  @override
  void initState() {
    super.initState();
    _savedQrUrl = widget.initialProfile?.banglaQrUrl;
    _accountController = TextEditingController(
      text: widget.initialProfile?.accountNumber ?? '',
    );
    _selectedProvider = widget.initialProfile?.provider ?? 'bkash';
    _selectedAccountType = widget.initialProfile?.accountType ?? 'personal';
  }

  @override
  void dispose() {
    _accountController.dispose();
    super.dispose();
  }

  Future<void> _pickAndProcessImage() async {
    setState(() => _isProcessingImage = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2000,
        imageQuality: 95,
      );

      if (picked != null) {
        final rawBytes = await picked.readAsBytes();

        _rawPickedBytes = rawBytes;
        _showOriginal = false;

        // Run smart on-device auto-enhancement
        final enhanced = SmartQrEnhancer.process(rawBytes);
        if (enhanced != null && mounted) {
          setState(() {
            _enhancedBytes = enhanced.bytes;
            _wasAutoCropped = enhanced.isAutoCropped;
            if (enhanced.detectedProvider != null) {
              _selectedProvider = enhanced.detectedProvider!;
              if (enhanced.detectedProvider!.toLowerCase() == 'bangla_qr') {
                _selectedAccountType = 'merchant';
              }
            }
          });
        } else if (mounted) {
          setState(() {
            _enhancedBytes = rawBytes;
            _wasAutoCropped = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ছবি বাছাই ব্যর্থ হয়েছে: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingImage = false);
      }
    }
  }

  Future<void> _saveProfileQr() async {
    final bytesToSave = (_showOriginal && _rawPickedBytes != null)
        ? _rawPickedBytes
        : _enhancedBytes;
    if (bytesToSave == null && (_savedQrUrl == null || _savedQrUrl!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('অনুগ্রহ করে কিউআরের ছবি নির্বাচন করুন।')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      PaymentProfileInfo? result;
      if (bytesToSave != null) {
        result = await PaymentProfileService.savePaymentQr(
          uid: widget.uid,
          imageBytes: bytesToSave,
          accountNumber: _accountController.text.trim(),
          provider: _selectedProvider,
          accountType: _selectedAccountType,
        );
      } else {
        // Just update account details without changing image
        result = PaymentProfileInfo(
          banglaQrUrl: _savedQrUrl,
          accountNumber: _accountController.text.trim(),
          provider: _selectedProvider,
          accountType: _selectedAccountType,
        );
        await PaymentProfileService.savePaymentQr(
          uid: widget.uid,
          imageBytes: Uint8List(0), // No-op for image if URL already exists
          accountNumber: _accountController.text.trim(),
          provider: _selectedProvider,
          accountType: _selectedAccountType,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '✅ বাংলা কিউআর সফলভাবে প্রোফাইলে সংরক্ষিত হয়েছে!',
              style: TextStyle(
                fontFamily: 'NotoSansBengali',
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: AppColors.mintGreen,
          ),
        );
        Navigator.of(context).pop(result);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('সংরক্ষণ ব্যর্থ হয়েছে: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteQr() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('কিউআর মুছে ফেলতে চান?'),
        content: const Text(
          'আপনার প্রোফাইল থেকে সংরক্ষিত কিউআর ছবিটি স্থায়ীভাবে মুছে যাবে।',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.amber),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('মুছে ফেলুন'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isSaving = true);
      await PaymentProfileService.deletePaymentQr(widget.uid);
      if (mounted) {
        Navigator.of(context).pop(const PaymentProfileInfo());
      }
    }
  }

  Color _getProviderColor(String provider) {
    switch (provider.toLowerCase()) {
      case 'bkash':
        return const Color(0xFFE2136E);
      case 'nagad':
        return const Color(0xFFF7931E);
      case 'rocket':
        return const Color(0xFF8C3494);
      case 'upay':
        return const Color(0xFF005696);
      case 'cellfin':
        return const Color(0xFF00875A);
      default:
        return const Color(0xFF00695C);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = context.forest;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: 20 + bottomInset,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: f.isDark ? Colors.white24 : Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header Title
            Row(
              children: [
                const Icon(Icons.qr_code_2_rounded,
                    size: 24, color: AppColors.mintGreen),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'বাংলা কিউআর ও পেমেন্ট প্রোফাইল',
                    style: TextStyle(
                      fontFamily: 'NotoSansBengali',
                      color: f.text,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_savedQrUrl != null && _savedQrUrl!.isNotEmpty)
                  IconButton(
                    tooltip: 'কিউআর মুছে ফেলুন',
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.redAccent, size: 20),
                    onPressed: _isSaving ? null : _deleteQr,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'এখানে একবার আপনার বিকাশ, নগদ বা ব্যাংক কিউআর সেভ করে রাখলে লেজারে খরচের হিসাব মেলানোর সময় মেম্বাররা সরাসরি এটি দেখতে পাবেন।',
              style: TextStyle(
                fontFamily: 'NotoSansBengali',
                color: f.text70,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),

            // QR Preview Area
            Center(
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _enhancedBytes != null ||
                            (_savedQrUrl != null && _savedQrUrl!.isNotEmpty)
                        ? AppColors.mintGreen
                        : f.divider12,
                    width: 1.5,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _isProcessingImage
                      ? const Center(child: CircularProgressIndicator())
                      : (_enhancedBytes != null || _rawPickedBytes != null)
                          ? Image.memory(
                              (_showOriginal && _rawPickedBytes != null)
                                  ? _rawPickedBytes!
                                  : _enhancedBytes!,
                              fit: BoxFit.contain,
                            )
                          : (_savedQrUrl != null && _savedQrUrl!.isNotEmpty)
                              ? Image.network(
                                  _savedQrUrl!,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => const Center(
                                    child: Icon(Icons.broken_image,
                                        size: 40, color: Colors.grey),
                                  ),
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.qr_code_scanner_rounded,
                                        size: 48, color: f.text24),
                                    const SizedBox(height: 8),
                                    Text(
                                      'কোনো কিউআর যোগ করা নেই',
                                      style: TextStyle(
                                        fontFamily: 'NotoSansBengali',
                                        color: f.text60,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                ),
              ),
            ),

            if (_wasAutoCropped) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.mintGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.mintGreen.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.auto_fix_high_rounded,
                        size: 15, color: AppColors.mintGreen),
                    const SizedBox(width: 6),
                    Text(
                      _showOriginal
                          ? 'আসল ছবি প্রদর্শিত হচ্ছে'
                          : 'স্মার্ট এডিটিং: কিউআর স্বয়ংক্রিয়ভাবে ক্রপ ও নিখুঁত করা হয়েছে!',
                      style: const TextStyle(
                        fontFamily: 'NotoSansBengali',
                        color: AppColors.mintGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              if (_rawPickedBytes != null) ...[
                const SizedBox(height: 4),
                Center(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                    ),
                    icon: Icon(
                      _showOriginal
                          ? Icons.auto_fix_high_rounded
                          : Icons.image_outlined,
                      size: 14,
                      color: f.accentText,
                    ),
                    label: Text(
                      _showOriginal
                          ? 'স্মার্ট ক্রপ করা ছবি ব্যবহার করুন'
                          : 'আসল ছবি ব্যবহার করুন',
                      style: TextStyle(
                        fontFamily: 'NotoSansBengali',
                        color: f.accentText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: () =>
                        setState(() => _showOriginal = !_showOriginal),
                  ),
                ),
              ],
            ],

            const SizedBox(height: 12),

            // Pick Image Button
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: f.accentText,
                side: BorderSide(color: f.accentText),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: Text(
                _enhancedBytes != null ||
                        (_savedQrUrl != null && _savedQrUrl!.isNotEmpty)
                    ? 'গ্যালারি থেকে ছবি পরিবর্তন করুন'
                    : 'গ্যালারি থেকে কিউআর ছবি বাছাই করুন',
                style: const TextStyle(
                  fontFamily: 'NotoSansBengali',
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed:
                  _isProcessingImage || _isSaving ? null : _pickAndProcessImage,
            ),

            const SizedBox(height: 16),

            // Provider Selector
            Text(
              'পেমেন্ট প্রোভাইডার',
              style: TextStyle(
                fontFamily: 'NotoSansBengali',
                color: f.text,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final provider in BanglaQrProvider.values)
                  ChoiceChip(
                    label: Text(provider.displayName),
                    selected: _selectedProvider.toLowerCase() ==
                            provider.name.toLowerCase() ||
                        ((_selectedProvider.toLowerCase() == 'bangla_qr' ||
                                _selectedProvider.toLowerCase() ==
                                    'banglaqr') &&
                            provider == BanglaQrProvider.bank),
                    selectedColor: _getProviderColor(provider.name)
                        .withValues(alpha: 0.22),
                    labelStyle: TextStyle(
                      fontFamily: 'NotoSansBengali',
                      fontSize: 12,
                      fontWeight: (_selectedProvider.toLowerCase() ==
                                  provider.name.toLowerCase() ||
                              ((_selectedProvider.toLowerCase() ==
                                          'bangla_qr' ||
                                      _selectedProvider.toLowerCase() ==
                                          'banglaqr') &&
                                  provider == BanglaQrProvider.bank))
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: (_selectedProvider.toLowerCase() ==
                                  provider.name.toLowerCase() ||
                              ((_selectedProvider.toLowerCase() ==
                                          'bangla_qr' ||
                                      _selectedProvider.toLowerCase() ==
                                          'banglaqr') &&
                                  provider == BanglaQrProvider.bank))
                          ? _getProviderColor(provider.name)
                          : f.text70,
                    ),
                    side: BorderSide(
                      color: (_selectedProvider.toLowerCase() ==
                                  provider.name.toLowerCase() ||
                              ((_selectedProvider.toLowerCase() ==
                                          'bangla_qr' ||
                                      _selectedProvider.toLowerCase() ==
                                          'banglaqr') &&
                                  provider == BanglaQrProvider.bank))
                          ? _getProviderColor(provider.name)
                          : f.divider12,
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedProvider = provider.name;
                          if (provider == BanglaQrProvider.bank) {
                            _selectedAccountType = 'merchant';
                          }
                        });
                      }
                    },
                  ),
              ],
            ),

            const SizedBox(height: 14),

            // Account Type Selector (Personal Send Money vs Merchant Bangla QR)
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () =>
                        setState(() => _selectedAccountType = 'personal'),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 10),
                      decoration: BoxDecoration(
                        color: _selectedAccountType == 'personal'
                            ? AppColors.mintGreen.withValues(alpha: 0.15)
                            : f.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _selectedAccountType == 'personal'
                              ? AppColors.mintGreen
                              : f.divider12,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.person,
                              size: 16,
                              color: _selectedAccountType == 'personal'
                                  ? AppColors.mintGreen
                                  : f.text60),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'ব্যক্তিগত (Send Money)',
                              style: TextStyle(
                                fontFamily: 'NotoSansBengali',
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _selectedAccountType == 'personal'
                                    ? AppColors.mintGreen
                                    : f.text70,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () =>
                        setState(() => _selectedAccountType = 'merchant'),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 10),
                      decoration: BoxDecoration(
                        color: _selectedAccountType == 'merchant'
                            ? AppColors.darkGreen.withValues(alpha: 0.2)
                            : f.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _selectedAccountType == 'merchant'
                              ? AppColors.mintGreen
                              : f.divider12,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.storefront,
                              size: 16,
                              color: _selectedAccountType == 'merchant'
                                  ? AppColors.mintGreen
                                  : f.text60),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'মার্চেন্ট (Bangla QR)',
                              style: TextStyle(
                                fontFamily: 'NotoSansBengali',
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _selectedAccountType == 'merchant'
                                    ? AppColors.mintGreen
                                    : f.text70,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Account / Phone Number Input
            Builder(
              builder: (context) {
                final isBankOrMerchant = _selectedAccountType == 'merchant' ||
                    _selectedProvider.toLowerCase() == 'bank' ||
                    _selectedProvider.toLowerCase() == 'bangla_qr' ||
                    _selectedProvider.toLowerCase() == 'banglaqr';
                return TextField(
                  controller: _accountController,
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
                    fontFamily: 'NotoSansBengali',
                    color: f.text,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    labelText: isBankOrMerchant
                        ? 'ব্যাংক অ্যাকাউন্ট বা মার্চেন্ট আইডি'
                        : 'অ্যাকাউন্ট বা মোবাইল নম্বর (১১ ডিজিট)',
                    labelStyle: TextStyle(
                      fontFamily: 'NotoSansBengali',
                      color: f.text70,
                      fontSize: 13,
                    ),
                    hintText: isBankOrMerchant
                        ? '১৩-১৭ ডিজিটের অ্যাকাউন্ট নম্বর বা আইডি'
                        : '01XXXXXXXXX',
                    hintStyle: TextStyle(
                      fontFamily: 'NotoSansBengali',
                      color: f.text24,
                      fontSize: 13,
                    ),
                    prefixIcon: Icon(
                      isBankOrMerchant
                          ? Icons.account_balance_rounded
                          : Icons.phone_android_rounded,
                      size: 18,
                      color: f.accentText,
                    ),
                    filled: true,
                    fillColor: f.card,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: f.divider12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: f.accentText, width: 1.5),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 18),

            // Save Button
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.mintGreen,
                foregroundColor: AppColors.darkGreen,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(AppColors.darkGreen),
                      ),
                    )
                  : const Icon(Icons.save_rounded, size: 20),
              label: Text(
                _isSaving
                    ? 'সংরক্ষণ হচ্ছে...'
                    : 'প্রোফাইলে স্থায়ীভাবে সংরক্ষণ করুন',
                style: const TextStyle(
                  fontFamily: 'NotoSansBengali',
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              onPressed:
                  _isSaving || _isProcessingImage ? null : _saveProfileQr,
            ),
          ],
        ),
      ),
    );
  }
}
