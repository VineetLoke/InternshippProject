import 'package:flutter/material.dart';

/// Central color palette for FocusGuard.
/// No color should be hardcoded outside of this file.
@immutable
class AppColors {
  const AppColors._();

  // ── Base ────────────────────────────────────────────────────────────────
  static const Color darkBackground = Color(0xFF0D0D0D);
  static const Color surface = Color(0xFF1A1A1A);
  static const Color surfaceVariant = Color(0xFF2A2A2A);
  static const Color card = Color(0xFF1E1E1E);

  // ── Text ────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF5F5F5);
  static const Color textSecondary = Color(0xFF888888);
  static const Color textMuted = Color(0xFF555555);

  // ── Accent ─────────────────────────────────────────────────────────────-
  static const Color accent = Color(0xFFC6A85A);
  static const Color accentLight = Color(0xFFE0C878);
  static const Color accentDark = Color(0xFFA08A40);

  // ── Semantic ────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFFA726);
  static const Color error = Color(0xFFEF5350);
  static const Color info = Color(0xFF42A5F5);

  // ── Feature-specific ────────────────────────────────────────────────────
  static const Color instagram = Color(0xFFE1306C);
  static const Color reddit = Color(0xFFFF4500);
  static const Color twitter = Color(0xFF1DA1F2);
  static const Color chrome = Color(0xFF4285F4);

  // ── Overlay ─────────────────────────────────────────────────────────────
  static const Color overlayBackground = Color(0xFF0D0D0D);
  static const Color overlayQuote = Color(0xFFF5F5F5);
  static const Color overlayAuthor = Color(0xFF888888);

  // ── Legacy migration helpers (to be removed after refactor) ──────────────
  static MaterialColor get legacyBlue => Colors.blue;
  static MaterialColor get legacyGreen => Colors.green;
  static MaterialColor get legacyRed => Colors.red;
  static MaterialColor get legacyOrange => Colors.orange;
  static MaterialColor get legacyAmber => Colors.amber;
}
