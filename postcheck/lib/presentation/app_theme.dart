import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Apple-style mobile tokens. This supersedes the older B2B/Notion palette.
abstract final class PostCheckPalette {
  static const primary = Color(0xFF007AFF);
  static const primaryPressed = Color(0xFF005FCC);
  static const navy = Color(0xFF1C1C1E);
  static const link = primary;
  static const canvas = Colors.white;
  static const surface = Color(0xFFF2F2F7);
  static const soft = Color(0xFFF9F9FB);
  static const border = Color(0xFFE5E5EA);
  static const borderStrong = Color(0xFFC7C7CC);
  static const ink = Color(0xFF1C1C1E);
  static const charcoal = Color(0xFF3A3A3C);
  static const secondary = Color(0xFF636366);
  static const tertiary = Color(0xFF8E8E93);
  static const blue = Color(0xFFE5F0FF);
  static const blueSoft = Color(0xFFF0F6FF);
}

ThemeData buildPostCheckTheme() {
  const font = '.SF Pro Text';
  final base = ThemeData(
    useMaterial3: true,
    platform: TargetPlatform.iOS,
    fontFamily: font,
    colorScheme: ColorScheme.fromSeed(seedColor: PostCheckPalette.primary)
        .copyWith(
          primary: PostCheckPalette.primary,
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: PostCheckPalette.ink,
          onSurfaceVariant: PostCheckPalette.secondary,
          outlineVariant: PostCheckPalette.border,
          surfaceTint: Colors.transparent,
        ),
    cupertinoOverrideTheme: const CupertinoThemeData(
      primaryColor: CupertinoColors.activeBlue,
      brightness: Brightness.light,
    ),
  );
  final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(28));
  const label = TextStyle(
    fontFamily: font,
    fontSize: 17,
    fontWeight: FontWeight.w600,
  );
  return base.copyWith(
    scaffoldBackgroundColor: PostCheckPalette.surface,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.black.withValues(alpha: .04),
    textTheme: base.textTheme
        .copyWith(
          headlineLarge: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            height: 1.16,
            letterSpacing: -.8,
          ),
          headlineMedium: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            height: 1.2,
            letterSpacing: -.5,
          ),
          titleLarge: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
          titleMedium: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
          titleSmall: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
          bodyLarge: const TextStyle(fontSize: 17, height: 1.4),
          bodyMedium: const TextStyle(fontSize: 15, height: 1.4),
          bodySmall: const TextStyle(
            fontSize: 13,
            height: 1.35,
            color: PostCheckPalette.secondary,
          ),
          labelLarge: label,
        )
        .apply(
          fontFamily: font,
          bodyColor: PostCheckPalette.ink,
          displayColor: PostCheckPalette.ink,
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: PostCheckPalette.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      titleTextStyle: TextStyle(
        fontFamily: font,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: PostCheckPalette.ink,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: pill,
        textStyle: label,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        backgroundColor: PostCheckPalette.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: PostCheckPalette.border,
        disabledForegroundColor: PostCheckPalette.tertiary,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 50),
        shape: pill,
        textStyle: label,
        side: BorderSide.none,
        foregroundColor: PostCheckPalette.primary,
        backgroundColor: PostCheckPalette.blue,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        foregroundColor: PostCheckPalette.primary,
        textStyle: const TextStyle(
          fontFamily: font,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.all(16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: PostCheckPalette.primary),
      ),
      hintStyle: const TextStyle(color: PostCheckPalette.tertiary),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: PostCheckPalette.soft,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: PostCheckPalette.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: PostCheckPalette.border,
      thickness: .5,
      space: 20,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Colors.white,
      selectedColor: PostCheckPalette.blue,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(
        fontFamily: font,
        fontSize: 14,
        color: PostCheckPalette.ink,
      ),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      titleTextStyle: TextStyle(
        fontFamily: font,
        fontSize: 17,
        color: PostCheckPalette.ink,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: font,
        fontSize: 13,
        color: PostCheckPalette.secondary,
      ),
      iconColor: PostCheckPalette.primary,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: PostCheckPalette.navy,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  );
}
