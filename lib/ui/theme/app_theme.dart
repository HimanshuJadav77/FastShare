import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Premium iOS-style Theme Extension for "Anti-Gravity" effects
class AppThemeExtension extends ThemeExtension<AppThemeExtension> {
  final Color success;
  final Color danger;
  final Color warning;
  final Color glassBackground;
  final List<BoxShadow> antiGravityShadow;
  final Color textMuted;
  final Gradient primaryGradient;
  final Color cardShadow;
  final Color connectionActive;
  final Color connectionInactive;

  const AppThemeExtension({
    required this.success,
    required this.danger,
    required this.warning,
    required this.glassBackground,
    required this.antiGravityShadow,
    required this.textMuted,
    required this.primaryGradient,
    required this.cardShadow,
    required this.connectionActive,
    required this.connectionInactive,
  });

  @override
  AppThemeExtension copyWith({
    Color? success,
    Color? danger,
    Color? warning,
    Color? glassBackground,
    List<BoxShadow>? antiGravityShadow,
    Color? textMuted,
    Gradient? primaryGradient,
    Color? cardShadow,
    Color? connectionActive,
    Color? connectionInactive,
  }) {
    return AppThemeExtension(
      success: success ?? this.success,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
      glassBackground: glassBackground ?? this.glassBackground,
      antiGravityShadow: antiGravityShadow ?? this.antiGravityShadow,
      textMuted: textMuted ?? this.textMuted,
      primaryGradient: primaryGradient ?? this.primaryGradient,
      cardShadow: cardShadow ?? this.cardShadow,
      connectionActive: connectionActive ?? this.connectionActive,
      connectionInactive: connectionInactive ?? this.connectionInactive,
    );
  }

  @override
  AppThemeExtension lerp(ThemeExtension<AppThemeExtension>? other, double t) {
    if (other is! AppThemeExtension) return this;
    return AppThemeExtension(
      success: Color.lerp(success, other.success, t) ?? success,
      danger: Color.lerp(danger, other.danger, t) ?? danger,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      glassBackground: Color.lerp(glassBackground, other.glassBackground, t) ?? glassBackground,
      antiGravityShadow: antiGravityShadow,
      textMuted: Color.lerp(textMuted, other.textMuted, t) ?? textMuted,
      primaryGradient: Gradient.lerp(primaryGradient, other.primaryGradient, t) ?? primaryGradient,
      cardShadow: Color.lerp(cardShadow, other.cardShadow, t) ?? cardShadow,
      connectionActive: Color.lerp(connectionActive, other.connectionActive, t) ?? connectionActive,
      connectionInactive: Color.lerp(connectionInactive, other.connectionInactive, t) ?? connectionInactive,
    );
  }
}

class AppTheme {
  // iOS 18 Primary Colors
  static const Color _iosBlue = Color(0xFF007AFF);
  static const Color _iosIndigo = Color(0xFF5856D6);
  static const Color _darkBackground = Color(0xFF000000); // True Black for OLED
  static const Color _lightBackground = Color(0xFFF2F2F7); // iOS Light Gray

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: _iosBlue,
      scaffoldBackgroundColor: _lightBackground,
      colorScheme: const ColorScheme.light(
        primary: _iosBlue,
        secondary: _iosIndigo,
        surface: Colors.white,
      ),
      textTheme: GoogleFonts.interTextTheme().apply(
        bodyColor: Colors.black,
        displayColor: Colors.black,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.inter(
          color: Colors.black,
          fontSize: 20,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.5,
        ),
      ),
      extensions: [
        AppThemeExtension(
          success: const Color(0xFF34C759),
          danger: const Color(0xFFFF3B30),
          warning: const Color(0xFFFF9500),
          glassBackground: Colors.white.withValues(alpha: 0.4),
          antiGravityShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 30,
              offset: const Offset(0, 15),
            ),
          ],
          textMuted: const Color(0xFF8E8E93),
          primaryGradient: const LinearGradient(
            colors: [_iosBlue, _iosIndigo],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          cardShadow: Colors.black.withValues(alpha: 0.03),
          connectionActive: const Color(0xFF34C759),
          connectionInactive: const Color(0xFF8E8E93),
        ),
      ],
    );
  }

  static ThemeData get dark {
    final base = ThemeData.dark();
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: _iosBlue,
      scaffoldBackgroundColor: _darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: _iosBlue,
        secondary: _iosIndigo,
        surface: Color(0xFF1C1C1E),
        onSurface: Colors.white,
        onSurfaceVariant: Color(0xFF8E8E93),
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.5,
        ),
      ),
      extensions: [
        AppThemeExtension(
          success: const Color(0xFF30D158),
          danger: const Color(0xFFFF453A),
          warning: const Color(0xFFFF9F0A),
          glassBackground: const Color(0xFF1C1C1E).withValues(alpha: 0.4),
          antiGravityShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 30,
              offset: const Offset(0, 15),
            ),
          ],
          textMuted: const Color(0xFF8E8E93),
          primaryGradient: const LinearGradient(
            colors: [_iosBlue, _iosIndigo],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          cardShadow: Colors.transparent,
          connectionActive: const Color(0xFF30D158),
          connectionInactive: const Color(0xFF8E8E93),
        ),
      ],
    );
  }
}

extension AppThemeX on BuildContext {
  AppThemeExtension get appColors => Theme.of(this).extension<AppThemeExtension>()!;
  TextTheme get text => Theme.of(this).textTheme;
}
