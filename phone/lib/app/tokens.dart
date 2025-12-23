import 'dart:ui';

abstract class Tokens {
  // Colors
  static const background = Color(0xFF121212);
  static const surface = Color(0xFF1E1E1E);
  static const surfaceVariant = Color(0xFF2C2C2C);
  static const primary = Color(0xFF64B5F6); // Blue 300
  static const success = Color(0xFF81C784); // Green 300
  static const error = Color(0xFFE57373); // Red 300
  static const warning = Color(0xFFFFB74D); // Orange 300
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xB3FFFFFF); // 70% white
  static const textTertiary = Color(0x80FFFFFF); // 50% white

  // Spacing
  static const spacingXs = 4.0;
  static const spacingSm = 8.0;
  static const spacingMd = 16.0;
  static const spacingLg = 24.0;
  static const spacingXl = 32.0;

  // Radii
  static const radiusSm = 8.0;
  static const radiusMd = 12.0;
  static const radiusLg = 16.0;

  // Icons
  static const iconSizeSm = 20.0;
  static const iconSizeMd = 24.0;
  static const iconSizeLg = 32.0;

  // Durations
  static const durationFast = Duration(milliseconds: 150);
  static const durationNormal = Duration(milliseconds: 300);
}
