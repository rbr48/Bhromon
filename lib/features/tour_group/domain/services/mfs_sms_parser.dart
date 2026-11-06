// lib/features/tour_group/domain/services/mfs_sms_parser.dart
//
// Auto-parses bKash, Nagad, Rocket, and Upay confirmation SMS / clipboard snippets
// into structured MFS payment fields and validates duplicate TrxIDs per group.

import '../models/expense_models.dart';

class ParsedMfsSms {
  final MfsProvider provider;
  final String trxId;
  final int amountPaisa;
  final int feePaisa;
  final String? counterpartyMaskedPhone;
  final DateTime? transactionTime;
  final String rawText;

  const ParsedMfsSms({
    required this.provider,
    required this.trxId,
    required this.amountPaisa,
    this.feePaisa = 0,
    this.counterpartyMaskedPhone,
    this.transactionTime,
    required this.rawText,
  });

  MfsPaymentInfo toMfsPaymentInfo({
    bool feeAbsorbedByGroup = false,
    bool isReceiver = false,
  }) {
    return MfsPaymentInfo(
      provider: provider,
      trxId: trxId,
      senderMaskedPhone: isReceiver ? counterpartyMaskedPhone : null,
      receiverMaskedPhone: isReceiver ? null : counterpartyMaskedPhone,
      feePaisa: feePaisa,
      feeAbsorbedByGroup: feeAbsorbedByGroup,
      status: MfsVerificationStatus.unverified,
    );
  }
}

class MfsSmsParser {
  // Matches bKash: "TrxID BKL890XYZ1 at 05/11/2026 14:32"
  static final RegExp _bkashTrxRegex = RegExp(
    r'\bTrxID\s*:?\s*([A-Z0-9]{10})\b',
    caseSensitive: false,
  );

  // Matches Nagad: "TxnID: 73N89A1B or TxnID 73N89A1B2C"
  static final RegExp _nagadTrxRegex = RegExp(
    r'\bTxn\s*ID\s*:?\s*([A-Z0-9]{8,12})\b',
    caseSensitive: false,
  );

  // Matches Rocket: "TxnId: 4920183920"
  static final RegExp _rocketTrxRegex = RegExp(
    r'\b(?:TxnId|Trans\s*ID)\s*:?\s*([0-9A-Z]{8,14})\b',
    caseSensitive: false,
  );

  // Matches principal amount: "Send Money Tk 1,500.00", "Cash Out Tk 2000.00", "Amount: Tk 500.00"
  static final RegExp _amountRegex = RegExp(
    r'(?:Send\s+Money|Cash\s+Out|Payment|Received\s+Tk|Amount\s*:?\s*Tk|Tk\.?)\s*([0-9,]+(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );

  // Matches Fee: "Fee Tk 18.50" or "Charge: Tk 5.00"
  static final RegExp _feeRegex = RegExp(
    r'(?:Fee|Charge|ক্যাশ আউট চার্জ|ফি)\s*:?\s*(?:Tk\.?|৳)?\s*([0-9,]+(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );

  // Matches Bangladeshi mobile number (013-019)
  static final RegExp _bdPhoneRegex = RegExp(
    r'\b(?:\+?88)?(01[3-9][0-9]{2}[0-9\*]{4}[0-9]{2})\b',
  );

  // Matches DD/MM/YYYY HH:MM timestamp
  static final RegExp _dateTimeRegex = RegExp(
    r'\b(\d{2})/(\d{2})/(\d{4})\s+(\d{2}):(\d{2})\b',
  );

  /// Normalizes Bengali digits (০-৯) to ASCII digits (0-9) before regex matching.
  static String normalizeBanglaDigits(String input) {
    const banglaDigits = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
    var output = input;
    for (var i = 0; i < banglaDigits.length; i++) {
      output = output.replaceAll(banglaDigits[i], i.toString());
    }
    return output;
  }

  /// Masks a Bangladeshi phone number to privacy-safe format `017****4821`.
  static String maskBdPhone(String rawPhone) {
    final cleaned =
        normalizeBanglaDigits(rawPhone).replaceAll(RegExp(r'^\+?88'), '');
    if (cleaned.length == 11 && cleaned.startsWith('01')) {
      return '${cleaned.substring(0, 3)}****${cleaned.substring(7)}';
    }
    return cleaned;
  }

  /// Parses an MFS SMS or clipboard snippet into a [ParsedMfsSms], or returns null if unrecognized.
  static ParsedMfsSms? parse(String rawSms) {
    final normalized = normalizeBanglaDigits(rawSms.trim());
    if (normalized.isEmpty) return null;

    MfsProvider? provider;
    String? trxId;

    final lower = normalized.toLowerCase();
    final bkashMatch = _bkashTrxRegex.firstMatch(normalized);
    final nagadMatch = _nagadTrxRegex.firstMatch(normalized);
    final rocketMatch = _rocketTrxRegex.firstMatch(normalized);

    if (lower.contains('upay') && bkashMatch != null) {
      provider = MfsProvider.upay;
      trxId = bkashMatch.group(1)!.toUpperCase();
    } else if (bkashMatch != null) {
      provider = MfsProvider.bkash;
      trxId = bkashMatch.group(1)!.toUpperCase();
    } else if (nagadMatch != null) {
      provider = MfsProvider.nagad;
      trxId = nagadMatch.group(1)!.toUpperCase();
    } else if (rocketMatch != null) {
      provider = MfsProvider.rocket;
      trxId = rocketMatch.group(1)!.toUpperCase();
    }

    if (provider == null || trxId == null) {
      return null;
    }

    final amountMatch = _amountRegex.firstMatch(normalized);
    if (amountMatch == null) return null;
    final amountPaisa = _parseTakaToPaisa(amountMatch.group(1)!);
    if (amountPaisa <= 0) return null;

    var feePaisa = 0;
    final feeMatch = _feeRegex.firstMatch(normalized);
    if (feeMatch != null) {
      feePaisa = _parseTakaToPaisa(feeMatch.group(1)!);
    }

    String? maskedPhone;
    final phoneMatch = _bdPhoneRegex.firstMatch(normalized);
    if (phoneMatch != null) {
      maskedPhone = maskBdPhone(phoneMatch.group(1)!);
    }

    DateTime? parsedDate;
    final dtMatch = _dateTimeRegex.firstMatch(normalized);
    if (dtMatch != null) {
      final day = int.parse(dtMatch.group(1)!);
      final month = int.parse(dtMatch.group(2)!);
      final year = int.parse(dtMatch.group(3)!);
      final hour = int.parse(dtMatch.group(4)!);
      final minute = int.parse(dtMatch.group(5)!);
      parsedDate = DateTime(year, month, day, hour, minute);
    }

    return ParsedMfsSms(
      provider: provider,
      trxId: trxId,
      amountPaisa: amountPaisa,
      feePaisa: feePaisa,
      counterpartyMaskedPhone: maskedPhone,
      transactionTime: parsedDate,
      rawText: rawSms,
    );
  }

  static int _parseTakaToPaisa(String takaStr) {
    final cleaned = takaStr.replaceAll(',', '').trim();
    final parts = cleaned.split('.');
    final taka = int.tryParse(parts[0]) ?? 0;
    var paisa = 0;
    if (parts.length > 1) {
      final frac = parts[1].padRight(2, '0').substring(0, 2);
      paisa = int.tryParse(frac) ?? 0;
    }
    return (taka * 100) + paisa;
  }
}

/// Validates MFS TrxID formatting and prevents duplicate TrxID submission within the same group.
class MfsTrxIdValidator {
  static final RegExp _alphanumericTrx = RegExp(r'^[A-Z0-9]{8,14}$');

  /// Validates format of [trxId] for the given [provider].
  /// Returns null if valid, or a localized Bangla error message if invalid.
  static String? validateFormat({
    required MfsProvider provider,
    required String? trxId,
  }) {
    if (!provider.requiresTrxId) return null;
    final cleaned = trxId?.trim().toUpperCase() ?? '';
    if (cleaned.isEmpty) {
      return '${provider.banglaLabel}-এর জন্য TrxID প্রদান করা আবশ্যক।';
    }
    if (provider == MfsProvider.bkash && cleaned.length != 10) {
      return 'বিকাশ (bKash) TrxID অবশ্যই ১০ অক্ষরের হতে হবে (যেমন: BKL890XYZ1)।';
    }
    if (!_alphanumericTrx.hasMatch(cleaned)) {
      return 'অবৈধ TrxID ফরম্যাট। শুধুমাত্র ইংরেজি অক্ষর এবং সংখ্যা ব্যবহার করুন।';
    }
    return null;
  }

  /// Checks whether [trxId] is already used in the same [tourId] across existing
  /// [expenses] or [settlements] (excluding [ignoreRecordId] during edits).
  static bool isDuplicateTrxId({
    required String tourId,
    required String trxId,
    required Iterable<ExpenseItem> expenses,
    required Iterable<SettlementRecord> settlements,
    String? ignoreRecordId,
  }) {
    final target = trxId.trim().toUpperCase();
    if (target.isEmpty) return false;

    for (final exp in expenses) {
      if (exp.tourId != tourId || exp.id == ignoreRecordId) continue;
      if (exp.mfsInfo?.normalizedTrxId == target) {
        return true;
      }
    }

    for (final set in settlements) {
      if (set.tourId != tourId || set.id == ignoreRecordId) continue;
      if (set.mfsInfo.normalizedTrxId == target) {
        return true;
      }
    }

    return false;
  }
}
