import 'package:flutter/material.dart';

/// @deprecated Use [AppTheme] from `config/app_theme.dart` instead.
/// All typography presets have been merged into AppTheme.
class AppTypography {
  static const appName = TextStyle(
    fontFamily: 'Inter',
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: Color(0xFF2563EB),
    letterSpacing: 0.2,
  );

  static const tabActive = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  static const tabInactive = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  static const postUsername = TextStyle(
    fontFamily: 'Inter',
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: Color(0xFF111827),
  );

  static const postMeta = TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: Color(0xFF6B7280),
  );

  static const postContent = TextStyle(
    fontFamily: 'Inter',
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: Color(0xFF111827),
  );

  static const bottomNavLabel = TextStyle(
    fontFamily: 'Inter',
    fontSize: 11,
    fontWeight: FontWeight.w500,
  );

  static const actionCount = TextStyle(
    fontFamily: 'Inter',
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: Color(0xFF3A3A3C),
  );
}
