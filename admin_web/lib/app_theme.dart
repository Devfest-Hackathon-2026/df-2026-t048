import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Tokens adapted from docs/design-reference-matraice.md for the mobile app.
abstract final class PostCheckPalette {
  /// フィルター選択・主ボタンで共通利用。
  static const primary = Color(0xFF0A6CF1);
  static const primaryPressed = Color(0xFF0858C7);
  static const navy = Color(0xFF0A1530);
  static const link = Color(0xFF0A6CF1);
  static const canvas = Colors.white;
  static const surface = Color(0xFFF6F5F4);
  static const soft = Color(0xFFFAFAF9);
  static const border = Color(0xFFE5E3DF);
  static const borderStrong = Color(0xFFC8C4BE);
  static const ink = Color(0xFF1A1A1A);
  static const charcoal = Color(0xFF37352F);
  static const secondary = Color(0xFF5D5B54);
  static const tertiary = Color(0xFF787671);
  static const blue = Color(0xFFDBEAFE);
  static const blueSoft = Color(0xFFEFF6FF);
}

const _fontFamily = 'Noto Sans JP';
const _fontFallbacks = <String>[
  'Yu Gothic UI',
  'Yu Gothic',
  'Hiragino Sans',
  'sans-serif',
];

TextStyle _jp({
  double? fontSize,
  FontWeight? fontWeight,
  double? height,
  Color? color,
}) => TextStyle(
  fontFamily: _fontFamily,
  fontFamilyFallback: _fontFallbacks,
  fontSize: fontSize,
  fontWeight: fontWeight,
  height: height,
  color: color,
);

ThemeData buildPostCheckTheme() {
  const p = PostCheckPalette.primary;
  const ink = PostCheckPalette.ink;
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
  final label = _jp(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );
  final scheme =
      ColorScheme.fromSeed(seedColor: p, brightness: Brightness.light).copyWith(
        primary: p,
        onPrimary: Colors.white,
        primaryContainer: PostCheckPalette.blue,
        onPrimaryContainer: PostCheckPalette.navy,
        secondary: PostCheckPalette.charcoal,
        secondaryContainer: PostCheckPalette.blue,
        onSecondaryContainer: PostCheckPalette.navy,
        tertiary: PostCheckPalette.link,
        tertiaryContainer: PostCheckPalette.blueSoft,
        surface: PostCheckPalette.canvas,
        onSurface: ink,
        onSurfaceVariant: PostCheckPalette.secondary,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: PostCheckPalette.soft,
        surfaceContainer: PostCheckPalette.surface,
        surfaceContainerHigh: PostCheckPalette.surface,
        surfaceContainerHighest: PostCheckPalette.border,
        outline: PostCheckPalette.borderStrong,
        outlineVariant: PostCheckPalette.border,
        surfaceTint: Colors.transparent,
      );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: _fontFamily,
    fontFamilyFallback: _fontFallbacks,
  );
  return base.copyWith(
    scaffoldBackgroundColor: PostCheckPalette.surface,
    textTheme: base.textTheme.copyWith(
      headlineMedium: _jp(
        fontSize: 26,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: ink,
      ),
      titleLarge: _jp(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: ink,
      ),
      titleMedium: _jp(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: ink,
      ),
      titleSmall: _jp(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.5,
        color: ink,
      ),
      bodyLarge: _jp(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: PostCheckPalette.charcoal,
      ),
      bodyMedium: _jp(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: PostCheckPalette.charcoal,
      ),
      bodySmall: _jp(
        fontSize: 13,
        height: 1.5,
        color: PostCheckPalette.secondary,
      ),
      labelLarge: label,
      labelSmall: _jp(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.4,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: PostCheckPalette.navy,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: _jp(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Colors.white,
        height: 1.3,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
        shape: WidgetStatePropertyAll(shape),
        textStyle: WidgetStatePropertyAll(label),
        elevation: const WidgetStatePropertyAll(0),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? PostCheckPalette.tertiary
              : Colors.white,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? PostCheckPalette.border
              : s.contains(WidgetState.pressed)
              ? PostCheckPalette.primaryPressed
              : p,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        foregroundColor: ink,
        backgroundColor: Colors.transparent,
        disabledForegroundColor: PostCheckPalette.tertiary,
        side: const BorderSide(color: PostCheckPalette.borderStrong),
        shape: shape,
        textStyle: label,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: PostCheckPalette.link,
        minimumSize: const Size(44, 44),
        shape: shape,
        textStyle: label,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      constraints: const BoxConstraints(minHeight: 48),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: PostCheckPalette.borderStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: PostCheckPalette.borderStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: p, width: 2),
      ),
      hintStyle: _jp(color: PostCheckPalette.tertiary),
      labelStyle: _jp(color: PostCheckPalette.secondary),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: PostCheckPalette.border),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: const DividerThemeData(
      color: PostCheckPalette.border,
      thickness: 1,
      space: 24,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Colors.white,
      selectedColor: PostCheckPalette.blue,
      surfaceTintColor: Colors.transparent,
      side: const BorderSide(color: PostCheckPalette.border),
      labelStyle: _jp(
        color: PostCheckPalette.navy,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      padding: const EdgeInsets.all(4),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
        textStyle: WidgetStatePropertyAll(label),
        foregroundColor: const WidgetStatePropertyAll(PostCheckPalette.navy),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? PostCheckPalette.blue
              : Colors.white,
        ),
        side: const WidgetStatePropertyAll(
          BorderSide(color: PostCheckPalette.borderStrong),
        ),
        shape: WidgetStatePropertyAll(shape),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: PostCheckPalette.secondary,
      titleTextStyle: _jp(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: ink,
        height: 1.5,
      ),
      subtitleTextStyle: _jp(
        fontSize: 13,
        color: PostCheckPalette.secondary,
        height: 1.5,
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: PostCheckPalette.navy,
      behavior: SnackBarBehavior.floating,
    ),
  );
}
