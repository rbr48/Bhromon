import 'dart:convert';

/// Supported mobile financial services (MFS) and banking rails in Bangladesh.
enum BanglaQrProvider {
  bkash('bKash', 'BKASH'),
  nagad('Nagad', 'NAGAD'),
  rocket('Rocket', 'ROCKET'),
  upay('Upay', 'UPAY'),
  cellfin('CellFin', 'CELLFIN'),
  bank('Bangla QR', 'BANGLAQR');

  const BanglaQrProvider(this.displayName, this.guid);

  final String displayName;
  final String guid;
}

/// Specifications for generating a standard Bangladesh Bank Bangla QR / EMVCo payload.
class BanglaQrPayload {
  const BanglaQrPayload({
    required this.accountNumber,
    required this.payeeName,
    this.provider = BanglaQrProvider.bkash,
    this.amountTaka,
    this.reference,
    this.city = 'Dhaka',
  });

  /// The bKash, Nagad, Rocket, or bank account number.
  final String accountNumber;

  /// The name of the payee or group administrator.
  final String payeeName;

  /// The financial institution or MFS provider.
  final BanglaQrProvider provider;

  /// Optional payment amount in whole taka.
  final int? amountTaka;

  /// Optional bill reference or note.
  final String? reference;

  /// Merchant city (defaults to 'Dhaka').
  final String city;

  /// Normalizes Bangladeshi phone numbers to the canonical 11-digit `01XXXXXXXXX` format.
  static String normalizePhone(String raw) {
    var cleaned = raw.replaceAll(RegExp(r'[\s\-]'), '').trim();
    if (cleaned.startsWith('+8801')) {
      cleaned = cleaned.substring(3);
    } else if (cleaned.startsWith('8801')) {
      cleaned = cleaned.substring(2);
    }
    return cleaned;
  }

  /// Returns true if [accountNumber] matches standard 11-digit Bangladeshi mobile format.
  bool get isPhoneAccount {
    final cleaned = normalizePhone(accountNumber);
    return RegExp(r'^01[3-9]\d{8}$').hasMatch(cleaned);
  }

  BanglaQrPayload copyWith({
    String? accountNumber,
    String? payeeName,
    BanglaQrProvider? provider,
    int? amountTaka,
    String? reference,
    String? city,
  }) {
    return BanglaQrPayload(
      accountNumber: accountNumber ?? this.accountNumber,
      payeeName: payeeName ?? this.payeeName,
      provider: provider ?? this.provider,
      amountTaka: amountTaka ?? this.amountTaka,
      reference: reference ?? this.reference,
      city: city ?? this.city,
    );
  }
}

/// Generates interoperable Bangladesh Bank standard Bangla QR (EMVCo Merchant-Presented) codes.
class BanglaQrEngine {
  const BanglaQrEngine._();

  static String _tlv(String tag, String value) {
    final length = utf8.encode(value).length.toString().padLeft(2, '0');
    return '$tag$length$value';
  }

  /// Calculates CRC-16/CCITT-FALSE (polynomial 0x1021, init 0xFFFF).
  static int calculateCrc16(String input) {
    var crc = 0xFFFF;
    final bytes = utf8.encode(input);
    for (final b in bytes) {
      crc ^= (b << 8);
      for (var i = 0; i < 8; i++) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    return crc;
  }

  /// Builds a fully standard EMVCo / Bangladesh Bank Bangla QR payload string.
  static String generate(BanglaQrPayload payload) {
    final buffer = StringBuffer();

    // 00: Payload Format Indicator (01)
    buffer.write(_tlv('00', '01'));

    // 01: Point of Initiation Method: 12 = dynamic (if amount given), 11 = static
    buffer.write(_tlv('01',
        payload.amountTaka != null && payload.amountTaka! > 0 ? '12' : '11'));

    // 26: Merchant Account Information
    final sub00 = _tlv('00', payload.provider.guid);
    final accountStr = payload.isPhoneAccount
        ? BanglaQrPayload.normalizePhone(payload.accountNumber)
        : payload.accountNumber.replaceAll(RegExp(r'\s+'), '');
    final sub01 = _tlv('01', accountStr);
    buffer.write(_tlv('26', '$sub00$sub01'));

    // 52: Merchant Category Code
    buffer.write(_tlv('52', '0000'));

    // 53: Transaction Currency: 050 = BDT
    buffer.write(_tlv('53', '050'));

    // 54: Transaction Amount
    if (payload.amountTaka != null && payload.amountTaka! > 0) {
      buffer.write(_tlv('54', '${payload.amountTaka}.00'));
    }

    // 58: Country Code: BD
    buffer.write(_tlv('58', 'BD'));

    // 59: Merchant / Payee Name (max 25 characters)
    final cleanName =
        payload.payeeName.replaceAll(RegExp(r'[^\w\s\.-]'), '').trim();
    final name = cleanName.isEmpty ? 'Bhromon Payee' : cleanName;
    buffer.write(_tlv('59', name.length > 25 ? name.substring(0, 25) : name));

    // 60: Merchant City (max 15 characters)
    final city = payload.city.trim().isEmpty ? 'Dhaka' : payload.city.trim();
    buffer.write(_tlv('60', city.length > 15 ? city.substring(0, 15) : city));

    // 62: Additional Data Field Template (Reference / Note)
    if (payload.reference != null && payload.reference!.isNotEmpty) {
      final ref =
          payload.reference!.replaceAll(RegExp(r'[^\w\s\.-]'), '').trim();
      if (ref.isNotEmpty) {
        final sub01 = _tlv('01', ref.length > 25 ? ref.substring(0, 25) : ref);
        buffer.write(_tlv('62', sub01));
      }
    }

    // 63: CRC prefix
    buffer.write('6304');
    final payloadToCrc = buffer.toString();
    final crc = calculateCrc16(payloadToCrc);
    final crcHex = crc.toRadixString(16).toUpperCase().padLeft(4, '0');

    return '$payloadToCrc$crcHex';
  }
}
