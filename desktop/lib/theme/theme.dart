import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData buildAppTheme() => ThemeData.dark().copyWith(
      scaffoldBackgroundColor: AppTokens.backgroundPrimary,
      colorScheme: const ColorScheme.dark(
        primary: AppTokens.accentPrimary,
        secondary: AppTokens.accentPrimary,
        surface: AppTokens.surfaceCard,
        error: AppTokens.accentRecording,
        onPrimary: AppTokens.textPrimary,
        onSecondary: AppTokens.textPrimary,
        onSurface: AppTokens.textPrimary,
        onError: AppTokens.textPrimary,
      ),
      cardTheme: CardThemeData(
        color: AppTokens.surfaceCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppTokens.backgroundPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppTokens.textPrimary,
          fontSize: AppTokens.fontSizeXl,
          fontWeight: AppTokens.fontWeightSemibold,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppTokens.accentPrimary,
        foregroundColor: AppTokens.textPrimary,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusFull),
        ),
      ),
      iconTheme: const IconThemeData(
        color: AppTokens.textPrimary,
        size: 24,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: AppTokens.textPrimary,
          fontSize: AppTokens.fontSizeXxl,
          fontWeight: AppTokens.fontWeightBold,
        ),
        headlineMedium: TextStyle(
          color: AppTokens.textPrimary,
          fontSize: AppTokens.fontSizeXl,
          fontWeight: AppTokens.fontWeightSemibold,
        ),
        titleLarge: TextStyle(
          color: AppTokens.textPrimary,
          fontSize: AppTokens.fontSizeLg,
          fontWeight: AppTokens.fontWeightMedium,
        ),
        titleMedium: TextStyle(
          color: AppTokens.textPrimary,
          fontSize: AppTokens.fontSizeMd,
          fontWeight: AppTokens.fontWeightMedium,
        ),
        bodyLarge: TextStyle(
          color: AppTokens.textPrimary,
          fontSize: AppTokens.fontSizeMd,
          fontWeight: AppTokens.fontWeightNormal,
        ),
        bodyMedium: TextStyle(
          color: AppTokens.textSecondary,
          fontSize: AppTokens.fontSizeSm,
          fontWeight: AppTokens.fontWeightNormal,
        ),
        bodySmall: TextStyle(
          color: AppTokens.textTertiary,
          fontSize: AppTokens.fontSizeXs,
          fontWeight: AppTokens.fontWeightNormal,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppTokens.backgroundTertiary,
        thickness: 1,
        space: 0,
      ),
    );
