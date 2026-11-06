import 'package:flutter/material.dart';

/// The colours of the chat screens, for the active theme.
///
/// The dark values are exactly the colours the chat screens used before they
/// followed the theme, so dark mode looks the same. The light values follow a
/// WhatsApp-style light palette. Use `context.chat` instead of fixed colours in
/// chat code; colours drawn over photos and videos can stay fixed.
class ChatPalette {
  const ChatPalette._(this.isDark);

  static const ChatPalette dark = ChatPalette._(true);
  static const ChatPalette light = ChatPalette._(false);

  final bool isDark;

  /// The brand accent: buttons, ticks, links, unread badges.
  Color get accent =>
      isDark ? const Color(0xFF52B788) : const Color(0xFF2D6A4F);

  /// The accent as a text or icon colour. In light mode it is darker, so it
  /// stays readable on light surfaces; buttons keep [accent].
  Color get accentText =>
      isDark ? const Color(0xFF52B788) : const Color(0xFF2D6A4F);

  /// Money owed to you.
  Color get owedToYou =>
      isDark ? const Color(0xFF53BDEB) : const Color(0xFF027EB5);

  /// Money you owe.
  Color get youOwe =>
      isDark ? const Color(0xFFFFB74D) : const Color(0xFFB45309);

  /// Read receipts.
  Color get readTick => const Color(0xFF53BDEB);

  /// The conversation background behind the bubbles.
  Color get wallpaper =>
      isDark ? const Color(0xFF0D1A12) : const Color(0xFFEFEAE2);

  /// The faint doodles drawn on the wallpaper.
  Color get wallpaperDoodle => isDark
      ? Colors.white.withValues(alpha: 0.015)
      : Colors.black.withValues(alpha: 0.035);

  /// App bars, sheets, dialogs and menus.
  Color get bar => isDark ? const Color(0xFF14241B) : Colors.white;

  /// Incoming bubbles and the message input.
  Color get panel => isDark ? const Color(0xFF1B2E23) : Colors.white;

  /// Text fields and chips on a bar or panel.
  Color get field => isDark ? const Color(0xFF233D2F) : const Color(0xFFF0F2F5);

  /// Recessed areas, such as a quoted message inside a bubble.
  Color get recessed =>
      isDark ? const Color(0xFF16241C) : const Color(0xFFF0F2F5);

  /// The deepest recessed areas.
  Color get recessedDeep =>
      isDark ? const Color(0xFF121E17) : const Color(0xFFE9EDEF);

  /// Outgoing bubbles.
  Color get outgoing =>
      isDark ? const Color(0xFF1B4332) : const Color(0xFFD9FDD3);

  /// Cards and quotes inside an outgoing bubble.
  Color get outgoingRecessed =>
      isDark ? const Color(0xFF143325) : const Color(0xFFC5EBBE);

  /// Grey used for timestamps and secondary icons.
  Color get grey => isDark ? const Color(0xFF8696A0) : const Color(0xFF667781);

  /// Main text and icons.
  Color get text => isDark ? Colors.white : const Color(0xFF111B21);

  /// Text and icons at the old white70 strength.
  Color get text70 => isDark ? Colors.white70 : const Color(0xFF3B4A54);

  /// Text and icons at the old white60 strength.
  Color get text60 => isDark ? Colors.white60 : const Color(0xFF54656F);

  /// Secondary text at the old white54 strength.
  // Light: 4.98:1 on the pale own bubble and 5.6:1 on white. It was 4.19:1 on the
  // own bubble.
  Color get text54 => isDark ? Colors.white54 : const Color(0xFF5C6B73);

  /// Hints and disabled text at the old white38 strength.
  Color get text38 => isDark ? Colors.white38 : const Color(0xFF8696A0);

  /// Faint text at the old white30 strength.
  Color get text30 => isDark ? Colors.white30 : const Color(0x61000000);

  /// Faint marks at the old white24 strength.
  Color get text24 => isDark ? Colors.white24 : const Color(0x42000000);

  /// Dividers at the old white12 strength.
  Color get divider12 => isDark ? Colors.white12 : const Color(0x1F000000);

  /// Dividers at the old white10 strength.
  Color get divider10 => isDark ? Colors.white10 : const Color(0x14000000);
}

/// `context.chat` is the chat palette for the active theme.
extension ChatPaletteContext on BuildContext {
  ChatPalette get chat => Theme.of(this).brightness == Brightness.dark
      ? ChatPalette.dark
      : ChatPalette.light;
}
