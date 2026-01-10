import 'dart:ui';

abstract class AppTokens {
  // Colors - Background
  static const Color backgroundPrimary = Color(0xFF0D0D0D);
  static const Color backgroundSecondary = Color(0xFF1A1A1A);
  static const Color backgroundTertiary = Color(0xFF262626);
  static const Color surfaceCard = Color(0xFF1E1E1E);

  // Colors - Accent
  static const Color accentPrimary = Color(0xFF3B82F6);
  static const Color accentRecording = Color(0xFFEF4444);
  static const Color accentWarning = Color(0xFFF59E0B);
  static const Color accentSuccess = Color(0xFF22C55E);

  // Colors - Text
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFA3A3A3);
  static const Color textTertiary = Color(0xFF737373);

  // Colors - Waveform
  static const Color waveformActive = Color(0xFF3B82F6);
  static const Color waveformInactive = Color(0xFF404040);

  // Spacing
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 32.0;

  // Radii
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusFull = 999.0;

  // Typography
  static const double fontSizeXs = 10.0;
  static const double fontSizeSm = 12.0;
  static const double fontSizeMd = 14.0;
  static const double fontSizeLg = 16.0;
  static const double fontSizeXl = 20.0;
  static const double fontSizeXxl = 24.0;

  // Font Weights
  static const FontWeight fontWeightNormal = FontWeight.w400;
  static const FontWeight fontWeightMedium = FontWeight.w500;
  static const FontWeight fontWeightSemibold = FontWeight.w600;
  static const FontWeight fontWeightBold = FontWeight.w700;

  // Animations
  static const Duration animFast = Duration(milliseconds: 150);
  static const Duration animMedium = Duration(milliseconds: 300);
  static const Duration animSlow = Duration(milliseconds: 500);

  // Sizes
  static const double recordButtonSize = 64.0;
  static const double recordButtonIconSize = 28.0;
  static const double waveformBarWidth = 3.0;
  static const double waveformBarGap = 2.0;
  static const double waveformHeight = 40.0;
}
