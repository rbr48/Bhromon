class PhoneFormatter {
  /// Cleans and formats phone numbers to E.164 format with Bangladesh prefix (+880).
  ///
  /// Examples:
  /// - `01712345678` -> `+8801712345678`
  /// - `1712345678` -> `+8801712345678`
  /// - `8801712345678` -> `+8801712345678`
  /// - `+8801712345678` -> `+8801712345678`
  /// - `+881712345678` -> `+8801712345678`
  /// - `881712345678` -> `+8801712345678`
  /// - `+14155552671` -> `+14155552671` (other international prefixes kept as is)
  static String format(String input) {
    if (input.isEmpty) return '';

    // Remove all whitespace, dashes, parentheses, etc. Keep digits and '+'
    String cleaned = input.replaceAll(RegExp(r'[^0-9+]'), '');

    if (cleaned.startsWith('+')) {
      if (cleaned.startsWith('+88')) {
        if (!cleaned.startsWith('+880')) {
          // E.g. +881712345678 -> +8801712345678
          return '+880${cleaned.substring(3)}';
        }
      }
      return cleaned;
    } else if (cleaned.startsWith('880')) {
      return '+$cleaned';
    } else if (cleaned.startsWith('88')) {
      // E.g. 881712345678 -> +8801712345678
      return '+880${cleaned.substring(2)}';
    } else if (cleaned.startsWith('0')) {
      // E.g. 01712345678 -> +8801712345678
      return '+88$cleaned';
    } else {
      // E.g. 1712345678 -> +8801712345678
      return '+880$cleaned';
    }
  }
}
