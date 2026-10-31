/// The family's emergency numbers, kept on the circle so every member can call or
/// text them in an emergency. Pure Dart, so the rules for a number are tested
/// without a device.
library;

/// How many numbers a circle keeps. The rules refuse a longer list.
const int kMaxEmergencyContacts = 10;

/// One number the family can call or text.
class EmergencyContact {
  const EmergencyContact({required this.name, required this.phone});

  final String name;

  /// The number as it is dialled, from [normalizeEmergencyPhone].
  final String phone;

  Map<String, dynamic> toMap() => {'name': name, 'phone': phone};

  /// Reads one stored number. Returns null when the stored phone is no longer valid.
  static EmergencyContact? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final phone = normalizeEmergencyPhone(raw['phone']?.toString() ?? '');
    if (phone == null) return null;
    final name = (raw['name']?.toString() ?? '').trim();
    return EmergencyContact(name: name.isEmpty ? phone : name, phone: phone);
  }
}

/// Reads the stored list, keeping only valid numbers and at most
/// [kMaxEmergencyContacts] of them.
List<EmergencyContact> parseEmergencyContacts(Object? raw) {
  if (raw is! List) return const [];
  final contacts = <EmergencyContact>[];
  for (final item in raw) {
    final contact = EmergencyContact.fromMap(item);
    if (contact != null) contacts.add(contact);
    if (contacts.length == kMaxEmergencyContacts) break;
  }
  return contacts;
}

/// The phone number as it should be dialled, or null when it cannot be dialled.
///
/// Spaces, dashes and brackets are dropped, and Bengali digits become ASCII ones.
/// A leading "+" is kept. A number needs 7 to 15 digits, and nothing else.
String? normalizeEmergencyPhone(String raw) {
  final ascii = _asciiDigits(raw.trim());
  if (!RegExp(r'^\+?[0-9 ()\-]+$').hasMatch(ascii)) return null;
  final digits = ascii.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length < 7 || digits.length > 15) return null;
  return ascii.startsWith('+') ? '+$digits' : digits;
}

/// A text message to several numbers at once. Android and iOS both take the
/// numbers separated by commas, and the body is percent-encoded.
Uri emergencySmsUri(List<String> numbers, String body) {
  return Uri.parse(
    'sms:${numbers.join(',')}?body=${Uri.encodeComponent(body)}',
  );
}

/// The Bengali digits zero to nine, from their code points (U+09E6 to U+09EF).
final List<int> _bengaliDigitCodes = [for (var i = 0; i < 10; i++) 0x09E6 + i];

String _asciiDigits(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final index = _bengaliDigitCodes.indexOf(rune);
    buffer.write(index >= 0 ? '$index' : String.fromCharCode(rune));
  }
  return buffer.toString();
}
