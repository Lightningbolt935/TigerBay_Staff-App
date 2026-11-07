import 'package:flutter/material.dart';

/// Central color palette derived from the TigerBay Staff App UI screenshots.
/// Black / off-white surfaces with a warm gold accent, plus semantic
/// status colors for table states and validation chips.
class AppColors {
  AppColors._();

  // Brand
  static const Color primaryBlack = Color(0xFF0B0B0C);
  static const Color gold = Color(0xFFC9A24B);
  static const Color goldLight = Color(0xFFE9DDBB);
  static const Color goldPale = Color(0xFFF5EFDD);

  // Surfaces
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF7F7F8);
  static const Color border = Color(0xFFECECEE);

  // Text
  static const Color textPrimary = Color(0xFF15161A);
  static const Color textSecondary = Color(0xFF8A8B92);
  static const Color textOnDark = Color(0xFFFFFFFF);

  // Status / semantic
  static const Color success = Color(0xFF2FA84F);
  static const Color successBg = Color(0xFFE6F6E9);
  static const Color danger = Color(0xFFE0503A);
  static const Color dangerBg = Color(0xFFFBE3DF);
  static const Color warning = Color(0xFFC9A24B);

  // Table status colors (Table Control screen)
  static const Color tableAvailable = Color(0xFFEFF7EF);
  static const Color tableAvailableText = Color(0xFF2FA84F);
  static const Color tableOccupied = Color(0xFFFBE3E1);
  static const Color tableOccupiedText = Color(0xFFD84C3A);
  static const Color tableReserved = Color(0xFFF6EFC9);
  static const Color tableReservedText = Color(0xFF8A7420);
}
