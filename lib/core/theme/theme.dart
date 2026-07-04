import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'colors.dart';

/// Bhromon design system.
///
/// Every screen inherits from these themes — component styling belongs here,
/// not in individual widgets. Both themes are built from a seeded Material 3
/// color scheme overridden with the brand forest-green palette, a full
/// Bengali-first typography scale, and a complete set of component themes so
/// buttons, inputs, dialogs, sheets and chips look consistent everywhere.
class AppTheme {
  // Bengali-first font stack: NotoSansBengali handles Bengali/Bangla codepoints (U+0980-U+09FF)
  // HindSiliguri is the fallback for Latin characters.
  static const _fontFamily = 'NotoSansBengali';
  static const _fontFamilyFallback = ['HindSiliguri'];

  // Shared shape language
  static const double radiusSmall = 10;
  static const double radiusMedium = 14;
  static const double radiusLarge = 20;
  static const double radiusSheet = 24;

  static ThemeData get lightTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.midGreen,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.midGreen,
      secondary: AppColors.leafGreen,
      tertiary: AppColors.gold,
      error: AppColors.amber,
      surface: Colors.white,
    );
    return _build(scheme);
  }

  static ThemeData get darkTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.midGreen,
      brightness: Brightness.dark,
    ).copyWith(
      // Mint reads far better than leaf green on dark surfaces, and it is
      // already the accent used across the dark screens.
      primary: AppColors.mintGreen,
      onPrimary: const Color(0xFF06281A),
      secondary: AppColors.leafGreen,
      tertiary: AppColors.lightGold,
      error: AppColors.amber,
      surface: AppColors.cardDark,
    );
    return _build(scheme);
  }

  static ThemeData _build(ColorScheme scheme) {
    final bool isDark = scheme.brightness == Brightness.dark;
    final Color textColor = isDark ? AppColors.offWhite : AppColors.darkText;
    final Color mutedColor =
        isDark ? AppColors.tierUnverified : AppColors.grayText;
    final Color outlineFaint =
        (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08);

    // Bengali script needs slightly taller line boxes than Latin; height 1.4+
    // keeps matras and hasanta from clipping.
    final textTheme = TextTheme(
      displayLarge: TextStyle(
          fontSize: 48,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          height: 1.2,
          color: textColor),
      displayMedium: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          height: 1.2,
          color: textColor),
      displaySmall: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.25,
          height: 1.25,
          color: textColor),
      headlineLarge: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.25,
          height: 1.3,
          color: textColor),
      headlineMedium: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          height: 1.3,
          color: textColor),
      headlineSmall: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          height: 1.3,
          color: textColor),
      titleLarge: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          height: 1.35,
          color: textColor),
      titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          height: 1.4,
          color: textColor),
      titleSmall: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
          height: 1.4,
          color: textColor),
      bodyLarge: TextStyle(fontSize: 15, height: 1.45, color: textColor),
      bodyMedium: TextStyle(fontSize: 13.5, height: 1.45, color: mutedColor),
      bodySmall: TextStyle(fontSize: 12, height: 1.4, color: mutedColor),
      labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: textColor),
      labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: mutedColor),
      labelSmall: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: mutedColor),
    );

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusMedium),
    );
    const buttonPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 14);
    const buttonMinSize = Size(64, 48); // 48dp touch target

    return ThemeData(
      useMaterial3: true,
      fontFamily: _fontFamily,
      fontFamilyFallback: _fontFamilyFallback,
      brightness: scheme.brightness,
      colorScheme: scheme,
      primaryColor: scheme.primary,
      scaffoldBackgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,

      // Predictive back on Android 14+ (falls back to standard transitions
      // when the gesture isn't active); native Cupertino slide on iOS.
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),

      appBarTheme: AppBarTheme(
        backgroundColor:
            isDark ? AppColors.backgroundDark : AppColors.darkGreen,
        foregroundColor: AppColors.offWhite,
        elevation: 0,
        scrolledUnderElevation: 2,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle:
            textTheme.titleLarge?.copyWith(color: AppColors.offWhite),
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.light
                .copyWith(statusBarColor: Colors.transparent),
      ),

      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: isDark ? 0 : 1,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          side: isDark ? BorderSide(color: outlineFaint) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          padding: buttonPadding,
          minimumSize: buttonMinSize,
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          padding: buttonPadding,
          minimumSize: buttonMinSize,
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(
              color: scheme.primary.withValues(alpha: 0.6), width: 1.2),
          padding: buttonPadding,
          minimumSize: buttonMinSize,
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(48, 40),
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.035),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: textTheme.bodyLarge?.copyWith(color: mutedColor),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: BorderSide(color: outlineFaint),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: BorderSide(color: outlineFaint),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: BorderSide(color: scheme.error, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: BorderSide(color: scheme.error, width: 1.6),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSheet),
        ),
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyLarge,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: scheme.surface,
        // The app's sheets draw their own drag handles — the themed one
        // would render a duplicate.
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(radiusSheet)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF2A2A2A) : AppColors.darkText,
        contentTextStyle:
            textTheme.bodyLarge?.copyWith(color: AppColors.offWhite),
        actionTextColor: AppColors.mintGreen,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
        elevation: 4,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : AppColors.paleGreen.withValues(alpha: 0.5),
        selectedColor: scheme.primary.withValues(alpha: isDark ? 0.25 : 0.18),
        labelStyle: textTheme.labelLarge?.copyWith(fontSize: 13),
        side: BorderSide(color: outlineFaint),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: mutedColor,
        textColor: textColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
      dividerTheme: DividerThemeData(
        color: outlineFaint,
        thickness: 1,
        space: 1,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
        textStyle: textTheme.bodyLarge,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: mutedColor,
        indicatorColor: scheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle:
            textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w500),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? const Color(0xFF161616) : Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: 0.18),
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : mutedColor,
          ),
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? scheme.onPrimary
                : mutedColor),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? scheme.primary
                : outlineFaint),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? scheme.primary
                : Colors.transparent),
        side: BorderSide(color: mutedColor, width: 1.6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? scheme.primary
                : mutedColor),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: outlineFaint,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.15),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: outlineFaint,
        circularTrackColor: outlineFaint,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A2A2A) : AppColors.darkText,
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: AppColors.offWhite),
      ),
    );
  }
}
