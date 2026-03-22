import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppThemeExtension extends ThemeExtension<AppThemeExtension> {
  final Color success;
  final Color danger;
  final Color warning;
  final Color glassBackground;
  final Color cardShadow;
  final Color connectionActive;
  final Color connectionInactive;
  final Color textMuted;

  const AppThemeExtension({
    required this.success,
    required this.danger,
    required this.warning,
    required this.glassBackground,
    required this.cardShadow,
    required this.connectionActive,
    required this.connectionInactive,
    required this.textMuted,
  });

  @override
  AppThemeExtension copyWith({
    Color? success,
    Color? danger,
    Color? warning,
    Color? glassBackground,
    Color? cardShadow,
    Color? connectionActive,
    Color? connectionInactive,
    Color? textMuted,
  }) {
    return AppThemeExtension(
      success: success ?? this.success,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
      glassBackground: glassBackground ?? this.glassBackground,
      cardShadow: cardShadow ?? this.cardShadow,
      connectionActive: connectionActive ?? this.connectionActive,
      connectionInactive: connectionInactive ?? this.connectionInactive,
      textMuted: textMuted ?? this.textMuted,
    );
  }

  @override
  AppThemeExtension lerp(ThemeExtension<AppThemeExtension>? other, double t) {
    if (other is! AppThemeExtension) return this;
    return AppThemeExtension(
      success: Color.lerp(success, other.success, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      glassBackground: Color.lerp(glassBackground, other.glassBackground, t)!,
      cardShadow: Color.lerp(cardShadow, other.cardShadow, t)!,
      connectionActive: Color.lerp(connectionActive, other.connectionActive, t)!,
      connectionInactive: Color.lerp(connectionInactive, other.connectionInactive, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
    );
  }
}

class AppTheme {
  static const Color _primaryBlue = Color(0xFF007AFF);
  static const Color _darkBackground = Color(0xFF0A0A0A);
  static const Color _lightBackground = Color(0xFFF9FAFB);

  static final TextTheme _textTheme = GoogleFonts.interTextTheme();

  static ThemeData get light {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: _primaryBlue,
      scaffoldBackgroundColor: _lightBackground,
      colorScheme: const ColorScheme.light(
        primary: _primaryBlue,
        secondary: _primaryBlue,
        surface: Colors.white,
      ),
      textTheme: _textTheme.apply(
        bodyColor: const Color(0xFF111827),
        displayColor: const Color(0xFF111827),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.black87),
        titleTextStyle: TextStyle(
          color: Colors.black87,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          fontFamily: 'Inter',
        ),
      ),
      extensions: [
        AppThemeExtension(
          success: const Color(0xFF34C759),
          danger: const Color(0xFFFF3B30),
          warning: const Color(0xFFFF9500),
          glassBackground: Colors.white.withValues(alpha: 0.8),
          cardShadow: Colors.black.withValues(alpha: 0.05),
          connectionActive: const Color(0xFF34C759),
          connectionInactive: const Color(0xFFFF3B30),
          textMuted: const Color(0xFF6B7280),
        ),
      ],
    );
  }

  static ThemeData get dark {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: _primaryBlue,
      scaffoldBackgroundColor: _darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: _primaryBlue,
        secondary: _primaryBlue,
        surface: Color(0xFF121212), // slightly lighter than background
      ),
      textTheme: _textTheme.apply(
        bodyColor: const Color(0xFFF9FAFB),
        displayColor: const Color(0xFFF9FAFB),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          fontFamily: 'Inter',
        ),
      ),
      extensions: [
        AppThemeExtension(
          success: const Color(0xFF30D158),
          danger: const Color(0xFFFF453A),
          warning: const Color(0xFFFF9F0A),
          glassBackground: Colors.white.withValues(alpha: 0.05),
          cardShadow: Colors.transparent,
          connectionActive: const Color(0xFF30D158),
          connectionInactive: const Color(0xFFFF453A),
          textMuted: const Color(0xFF9CA3AF),
        ),
      ],
    );
  }
}

extension AppThemeExtensionX on BuildContext {
  AppThemeExtension get appColors => Theme.of(this).extension<AppThemeExtension>()!;
}
