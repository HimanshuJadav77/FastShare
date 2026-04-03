import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:wifi_ftp/ui/theme/app_theme.dart';
import 'package:wifi_ftp/ui/theme/app_animations.dart';

/// Shared glass app bar used across every screen.
/// Floats over the scrollable body, has fully rounded corners (iOS pill style),
/// and applies a backdrop blur that bleeds through to the content below.
class FsAppBar extends StatelessWidget {
  final String title;
  final String? subtitle;

  /// Left action — defaults to a back chevron if [onBack] is provided.
  final VoidCallback? onBack;

  /// Optional right-side widget (e.g. disconnect button, clear button).
  final Widget? trailing;

  const FsAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    final ext = context.appColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Padding(
        // Horizontal inset gives the floating effect
        padding: EdgeInsets.only(top: topPadding + 12, left: 16, right: 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.52),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.18)
                      : Colors.black.withValues(alpha: 0.06),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // ── Back button ──
                  if (onBack != null)
                    AppAnimations.scaleOnTap(
                      onTap: onBack,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.07)
                              : Colors.black.withValues(alpha: 0.05),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 8),

                  const SizedBox(width: 8),

                  // ── Title + optional subtitle ──
                  Expanded(
                    child: subtitle != null
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                              ),
                              Text(
                                subtitle!,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: ext.textMuted,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          )
                        : Text(
                            title,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                  ),

                  // ── Trailing action ──
                  if (trailing != null) ...[
                    trailing!,
                    const SizedBox(width: 4),
                  ] else
                    const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Convenience: height to offset body content below this bar.
  static double bodyTopPadding(BuildContext context) {
    return MediaQuery.paddingOf(context).top + 12 + 60 + 16;
  }
}
