import 'package:flutter/material.dart';
import 'colors.dart';

class AppTheme {
  // Bengali-first font stack: NotoSansBengali handles Bengali/Bangla codepoints (U+0980-U+09FF)
  // HindSiliguri is the fallback for Latin characters.
  static const _fontFamily = 'NotoSansBengali';
  static const _fontFamilyFallback = ['HindSiliguri'];

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: _fontFamily,
      fontFamilyFallback: _fontFamilyFallback,
      brightness: Brightness.light,
      primaryColor: AppColors.midGreen,
      scaffoldBackgroundColor: AppColors.backgroundLight,
      colorScheme: const ColorScheme.light(
        primary: AppColors.midGreen,
        secondary: AppColors.leafGreen,
        background: AppColors.backgroundLight,
        surface: Colors.white,
        error: AppColors.amber,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkGreen,
        foregroundColor: AppColors.offWhite,
        elevation: 0,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: AppColors.darkText, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(color: AppColors.darkText, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: AppColors.darkText),
        bodyMedium: TextStyle(color: AppColors.grayText),
      ),
      cardTheme: CardTheme(
        color: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: _fontFamily,
      fontFamilyFallback: _fontFamilyFallback,
      brightness: Brightness.dark,
      primaryColor: AppColors.leafGreen,
      scaffoldBackgroundColor: AppColors.backgroundDark,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.leafGreen,
        secondary: AppColors.mintGreen,
        background: AppColors.backgroundDark,
        surface: AppColors.cardDark,
        error: AppColors.amber,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.black,
        foregroundColor: AppColors.offWhite,
        elevation: 0,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: AppColors.offWhite, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(color: AppColors.offWhite, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: AppColors.offWhite),
        bodyMedium: TextStyle(color: AppColors.tierUnverified),
      ),
      cardTheme: CardTheme(
        color: AppColors.cardDark,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
