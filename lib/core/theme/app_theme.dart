import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand tokens
  static const Color primaryBlue = Color(0xFF1C5484);
  static const Color lightCyan   = Color(0xFF8EE3EF);

  // Dark surface ramp
  static const Color bg0 = Color(0xFF0B1220);
  static const Color bg1 = Color(0xFF0F172A);
  static const Color bg2 = Color(0xFF1B2535);
  static const Color bg3 = Color(0xFF243041);
  static const Color outlineSoft = Color(0x223C4D63);
  static const Color outlineHard = Color(0x33425A78);

  // Text colors
  static const Color textStrong = Colors.white;
  static const Color textMed    = Color(0xCCFFFFFF);
  static const Color textMute   = Color(0x99FFFFFF);
  static const Color textFaint  = Color(0x66FFFFFF);

  static ThemeData get theme {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme(
        brightness: Brightness.dark,
        primary: primaryBlue,
        onPrimary: Colors.white,
        secondary: lightCyan,
        onSecondary: Colors.black,
        error: const Color(0xFFFF6B6B),
        onError: Colors.white,
        surface: bg2,
        onSurface: textStrong,
        surfaceContainerHighest: bg1,
        surfaceContainerHigh: bg2,
        surfaceContainer: bg2,
        surfaceContainerLow: bg1,
        surfaceContainerLowest: bg0,
        outline: outlineHard,
      ),
      scaffoldBackgroundColor: bg1,
      splashFactory: InkSplash.splashFactory,
    );

    final text = GoogleFonts.montserratTextTheme(base.textTheme).apply(
      bodyColor: textMed,
      displayColor: textMed,
      decorationColor: textMute,
    );

    return base.copyWith(
      // Typography
      textTheme: text.copyWith(
        headlineSmall: text.headlineSmall?.copyWith(
          color: textStrong, fontWeight: FontWeight.w700, letterSpacing: .2),
        titleLarge : text.titleLarge ?.copyWith(color: textStrong, fontWeight: FontWeight.w700),
        titleMedium: text.titleMedium?.copyWith(color: textStrong, fontWeight: FontWeight.w600),
        titleSmall : text.titleSmall ?.copyWith(color: textMed,    fontWeight: FontWeight.w600),
        bodyLarge  : text.bodyLarge  ?.copyWith(color: textMed,  height: 1.35),
        bodyMedium : text.bodyMedium ?.copyWith(color: textMed,  height: 1.35),
        bodySmall  : text.bodySmall  ?.copyWith(color: textMute, height: 1.35),
        labelLarge : text.labelLarge ?.copyWith(color: textStrong, fontWeight: FontWeight.w600),
        labelMedium: text.labelMedium?.copyWith(color: textMed,    fontWeight: FontWeight.w600),
        labelSmall : text.labelSmall ?.copyWith(color: textMute),
      ),

      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: bg1,
        foregroundColor: textStrong,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),

      // Cards
      cardTheme: const CardThemeData(
        color: bg2,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
          side: BorderSide(color: outlineSoft, width: 1),
        ),
      ),

      // List tiles
      listTileTheme: const ListTileThemeData(
        iconColor: textMed,
        textColor: textMed,
        subtitleTextStyle: TextStyle(color: textMute),
        contentPadding: EdgeInsets.symmetric(horizontal: 12),
      ),

      // Inputs
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: bg3,
        hintStyle: TextStyle(color: textFaint),
        labelStyle: TextStyle(color: textMed, fontWeight: FontWeight.w600),
        helperStyle: TextStyle(color: textMute),
        errorStyle: TextStyle(color: Color(0xFFFFB4A9)),
        prefixIconColor: textMute,
        suffixIconColor: textMute,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: outlineSoft),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: outlineSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: outlineHard, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: Color(0xFFFF6B6B)),
        ),
      ),

      // Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: lightCyan,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textStrong,
          side: const BorderSide(color: outlineHard),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),

      // Chips
      chipTheme: ChipThemeData(
        backgroundColor: bg3,
        disabledColor: bg3,
        labelStyle: const TextStyle(color: textMed, fontWeight: FontWeight.w600),
        secondaryLabelStyle: const TextStyle(color: textStrong),
        selectedColor: primaryBlue.withOpacity(.25),
        secondarySelectedColor: primaryBlue,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: const BorderSide(color: outlineSoft),
        ),
      ),

      // Tabs (Material 3 “Data” type)
      tabBarTheme: const TabBarThemeData(
        labelColor: textStrong,
        unselectedLabelColor: textMute,
        indicatorSize: TabBarIndicatorSize.tab,
      ),

      // Icons / dividers / tooltips
      iconTheme: const IconThemeData(color: textMed),
      dividerColor: outlineSoft,
      tooltipTheme: const TooltipThemeData(
        decoration: BoxDecoration(
          color: bg3,
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        textStyle: TextStyle(color: textStrong),
      ),

      // Snackbars
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: bg3,
        contentTextStyle:
            TextStyle(color: textStrong, fontWeight: FontWeight.w600),
        behavior: SnackBarBehavior.floating,
      ),

      // Dialogs (Material 3 “Data” type)
      dialogTheme: const DialogThemeData(
        backgroundColor: bg2,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: outlineSoft, width: 1),
        ),
        titleTextStyle: TextStyle(
          color: textStrong, fontWeight: FontWeight.w700, fontSize: 18),
        contentTextStyle: TextStyle(color: textMed, height: 1.4),
      ),
    );
  }
}
