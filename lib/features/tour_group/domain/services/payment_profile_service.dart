import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/services/media_upload_service.dart';

/// Stored payment profile details of a Bhromon user.
class PaymentProfileInfo {
  const PaymentProfileInfo({
    this.banglaQrUrl,
    this.accountNumber,
    this.provider,
    this.accountType,
  });

  final String? banglaQrUrl;
  final String? accountNumber;
  final String? provider;
  final String? accountType;

  bool get hasQr => banglaQrUrl != null && banglaQrUrl!.trim().isNotEmpty;
  bool get isPersonal => (accountType ?? 'personal') == 'personal';

  factory PaymentProfileInfo.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const PaymentProfileInfo();
    return PaymentProfileInfo(
      banglaQrUrl:
          data['banglaQrUrl'] as String? ?? data['paymentQrUrl'] as String?,
      accountNumber: data['paymentAccountNumber'] as String? ??
          data['mfsNumber'] as String? ??
          data['phone'] as String?,
      provider:
          data['paymentProvider'] as String? ?? data['mfsProvider'] as String?,
      accountType: data['paymentAccountType'] as String? ??
          data['accountType'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (banglaQrUrl != null) 'banglaQrUrl': banglaQrUrl,
      if (accountNumber != null) 'paymentAccountNumber': accountNumber,
      if (provider != null) 'paymentProvider': provider,
      if (accountType != null) 'paymentAccountType': accountType,
    };
  }
}

/// Manages uploading, reading, and clearing permanent Bangla QR & MFS payment profiles.
class PaymentProfileService {
  const PaymentProfileService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Fetches the payment profile for a specific user ID.
  static Future<PaymentProfileInfo> getPaymentProfile(String uid) async {
    if (uid.isEmpty) return const PaymentProfileInfo();
    try {
      final doc =
          await _firestore.collection('explorer_profiles').doc(uid).get();
      if (!doc.exists) return const PaymentProfileInfo();
      return PaymentProfileInfo.fromMap(doc.data());
    } catch (_) {
      return const PaymentProfileInfo();
    }
  }

  /// Uploads enhanced QR image bytes and permanently stores the payment details in the user's profile.
  static Future<PaymentProfileInfo?> savePaymentQr({
    required String uid,
    required Uint8List imageBytes,
    required String accountNumber,
    required String provider,
    String accountType = 'personal',
  }) async {
    if (uid.isEmpty || imageBytes.isEmpty) return null;

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storagePath = 'explorer_profiles/$uid/bangla_qr_$timestamp.jpg';

      final uploadedUrl = await MediaUploadService.uploadBytes(
        bytes: imageBytes,
        path: storagePath,
        contentType: 'image/jpeg',
      );

      if (uploadedUrl.isEmpty) {
        return null;
      }

      final profileInfo = PaymentProfileInfo(
        banglaQrUrl: uploadedUrl,
        accountNumber: accountNumber.trim(),
        provider: provider.trim(),
        accountType: accountType.trim(),
      );

      await _firestore.collection('explorer_profiles').doc(uid).set(
            profileInfo.toMap(),
            SetOptions(merge: true),
          );

      return profileInfo;
    } catch (_) {
      return null;
    }
  }

  /// Removes the stored payment QR from the user's profile.
  static Future<bool> deletePaymentQr(String uid) async {
    if (uid.isEmpty) return false;
    try {
      await _firestore.collection('explorer_profiles').doc(uid).update({
        'banglaQrUrl': FieldValue.delete(),
        'paymentQrUrl': FieldValue.delete(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}
