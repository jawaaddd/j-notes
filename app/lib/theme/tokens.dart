import 'package:flutter/material.dart';

/// Color tokens from the Figma "Color Palette" collection. Every color in the
/// UI comes from here.
abstract final class AppColors {
  static const background = Color(0xFF212121);
  static const cardBackground = Color(0xFF3B3B3B);
  static const cardBorder = Color(0xFF303030);
  static const headingText = Color(0xFFA4EE99);
  static const primaryText = Color(0xFFE5FFCA);
  static const bodyText = Color(0xFFF3F3F3);
  static const mutedText = Color(0xFFABABAB);
  static const accent = Color(0xFFFFDBA1);
  static const danger = Color(0xFFFF8A80);
  static const indicator = Color(0xFF73E462);

  /// The tag colors anyone can pick, keyed by the API's color names.
  static const palette = <String, Color>{
    'pink': Color(0xFFF28FAD),
    'blue': Color(0xFF8AB4F8),
    'violet': Color(0xFFC3A6FF),
    'cyan': Color(0xFF6FD3E0),
    'orange': Color(0xFFF5A97F),
  };

  /// "yellow" is reserved for the Urgent tag, which shows in Accent.
  static const urgentColor = 'yellow';

  static Color tag(String name) => name == urgentColor ? accent : palette[name] ?? mutedText;
}

abstract final class AppRadii {
  static const window = 12.0;
  static const modal = 14.0;
  static const card = 10.0;
  static const control = 8.0; // buttons and inputs
  static const row = 6.0; // menus and nav rows
  static const chip = 4.0;
}

/// Type scale from the spec: Geist for UI text, Geist Mono for metadata,
/// dates, counts, and raw input.
abstract final class AppText {
  static const _sans = 'Geist';
  static const _mono = 'GeistMono';

  static TextStyle sans(double size, {FontWeight weight = FontWeight.w400, Color color = AppColors.bodyText, double? height}) =>
      TextStyle(fontFamily: _sans, fontSize: size, fontWeight: weight, color: color, height: height);

  static TextStyle mono(double size, {FontWeight weight = FontWeight.w400, Color color = AppColors.mutedText, double? height}) =>
      TextStyle(fontFamily: _mono, fontSize: size, fontWeight: weight, color: color, height: height);

  static final pageTitle = sans(24, weight: FontWeight.w600, color: AppColors.headingText);
  static final modalTitle = sans(22, weight: FontWeight.w600, color: AppColors.headingText);
  static final subtitle = sans(13, color: AppColors.mutedText);
  static final cardTitle = sans(14, weight: FontWeight.w500, color: AppColors.primaryText, height: 1.4);
  static final body = sans(13);
  static final listTitle = sans(13, weight: FontWeight.w600, color: AppColors.headingText);
  static final sectionLabel = mono(11, weight: FontWeight.w500);
  static final meta = mono(12);
  static final metaSmall = mono(11);
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    canvasColor: AppColors.background,
    colorScheme: base.colorScheme.copyWith(
      surface: AppColors.background,
      primary: AppColors.accent,
      onPrimary: AppColors.background,
      secondary: AppColors.headingText,
      error: AppColors.danger,
      outline: AppColors.cardBorder,
    ),
    textTheme: base.textTheme.apply(fontFamily: 'Geist', bodyColor: AppColors.bodyText, displayColor: AppColors.bodyText),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.accent,
      selectionColor: Color(0x55FFDBA1),
      selectionHandleColor: AppColors.accent,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: AppColors.cardBackground, borderRadius: BorderRadius.circular(AppRadii.row)),
      textStyle: AppText.sans(12),
      waitDuration: const Duration(milliseconds: 300),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(AppColors.cardBackground),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.row),
            side: const BorderSide(color: AppColors.cardBorder),
          ),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(
        textStyle: WidgetStatePropertyAll(AppText.sans(13)),
        foregroundColor: const WidgetStatePropertyAll(AppColors.bodyText),
        minimumSize: const WidgetStatePropertyAll(Size(160, 34)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
        overlayColor: const WidgetStatePropertyAll(Color(0x14FFFFFF)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.modal),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      headerBackgroundColor: AppColors.cardBackground,
      headerForegroundColor: AppColors.primaryText,
      todayForegroundColor: const WidgetStatePropertyAll(AppColors.accent),
      todayBorder: const BorderSide(color: AppColors.accent),
    ),
    scrollbarTheme: const ScrollbarThemeData(thumbColor: WidgetStatePropertyAll(Color(0x33FFFFFF)), thickness: WidgetStatePropertyAll(6)),
  );
}
