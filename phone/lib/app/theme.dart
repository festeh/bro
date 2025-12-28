import 'package:flutter/material.dart';
import 'tokens.dart';

class AppTheme {
  static ThemeData get dark => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Tokens.background,
    colorScheme: const ColorScheme.dark(
      primary: Tokens.primary,
      secondary: Tokens.success,
      surface: Tokens.surface,
      error: Tokens.error,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Tokens.surface,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Tokens.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w500,
      ),
    ),
    cardTheme: CardThemeData(
      color: Tokens.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
    ),
    iconTheme: const IconThemeData(
      color: Tokens.textSecondary,
      size: Tokens.iconSizeMd,
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Tokens.textPrimary),
      bodyMedium: TextStyle(color: Tokens.textSecondary),
      bodySmall: TextStyle(color: Tokens.textTertiary),
      titleMedium: TextStyle(
        color: Tokens.textPrimary,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}
