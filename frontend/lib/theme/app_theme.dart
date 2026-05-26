import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for the PDF → Obsidian app.
abstract final class AppColors {
  static const background = Color(0xFF080A0F);
  static const backgroundElevated = Color(0xFF0E1118);
  static const surface = Color(0xFF151A24);
  static const surfaceMuted = Color(0xFF10141C);
  static const surfaceInset = Color(0xFF0B0E14);

  static const border = Color(0xFF2A3342);
  static const borderStrong = Color(0xFF3A4658);

  static const primary = Color(0xFF7C9CFF);
  static const primaryDeep = Color(0xFF4B6FE8);
  static const accent = Color(0xFF3DD68C);
  static const accentDeep = Color(0xFF1F9D5C);
  static const warning = Color(0xFFF5B942);
  static const error = Color(0xFFFF8F82);

  static const textPrimary = Color(0xFFF2F6FC);
  static const textSecondary = Color(0xFF9AA8BC);
  static const textMuted = Color(0xFF6B7A8F);

  static const headerBg = Color(0xFF0D1017);
  static const glowPrimary = Color(0x337C9CFF);
  static const glowAccent = Color(0x333DD68C);
}

abstract final class AppRadii {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const pill = 999.0;
}

abstract final class AppDecorations {
  static BoxDecoration card({
    Color? borderColor,
    bool elevated = true,
  }) {
    return BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      border: Border.all(
        color: borderColor ?? AppColors.border,
        width: 1.2,
      ),
      boxShadow: elevated
          ? const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ]
          : null,
    );
  }

  static BoxDecoration insetField() {
    return BoxDecoration(
      color: AppColors.surfaceInset,
      borderRadius: BorderRadius.circular(AppRadii.sm),
      border: Border.all(color: AppColors.border),
    );
  }

  static BoxDecoration iconBadge(Color color) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          color.withAlpha(56),
          color.withAlpha(20),
        ],
      ),
      borderRadius: BorderRadius.circular(AppRadii.sm),
      border: Border.all(color: color.withAlpha(70)),
    );
  }

  static BoxDecoration primaryGradientButton() {
    return BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.primaryDeep, AppColors.primary],
      ),
      borderRadius: BorderRadius.circular(AppRadii.sm),
      boxShadow: const [
        BoxShadow(
          color: Color(0x404B6FE8),
          blurRadius: 14,
          offset: Offset(0, 4),
        ),
      ],
    );
  }

  static BoxDecoration accentGradientButton() {
    return BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.accentDeep, AppColors.accent],
      ),
      borderRadius: BorderRadius.circular(AppRadii.sm),
      boxShadow: const [
        BoxShadow(
          color: Color(0x403DD68C),
          blurRadius: 14,
          offset: Offset(0, 4),
        ),
      ],
    );
  }
}

ThemeData buildAppTheme() {
  final baseText = GoogleFonts.plusJakartaSansTextTheme(
    ThemeData(brightness: Brightness.dark).textTheme,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: AppColors.surface,
      error: AppColors.error,
      onPrimary: Colors.white,
      onSecondary: Color(0xFF07130D),
      onSurface: AppColors.textPrimary,
    ),
    textTheme: baseText.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surface,
      contentTextStyle: GoogleFonts.plusJakartaSans(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceInset,
      labelStyle: GoogleFonts.plusJakartaSans(
        color: AppColors.textSecondary,
        fontSize: 13,
      ),
      hintStyle: GoogleFonts.plusJakartaSans(color: AppColors.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: const BorderSide(color: AppColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        textStyle: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
        side: const BorderSide(color: AppColors.borderStrong),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
      ),
    ),
  );
}

/// Ambient gradient orbs behind the main content.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned(
          top: -120,
          right: -80,
          child: _GlowOrb(
            size: 320,
            color: AppColors.glowPrimary,
          ),
        ),
        const Positioned(
          bottom: -100,
          left: -60,
          child: _GlowOrb(
            size: 280,
            color: AppColors.glowAccent,
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.background,
                  AppColors.background.withAlpha(250),
                  const Color(0xFF0A0D14),
                ],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, Colors.transparent],
        ),
      ),
    );
  }
}

/// Gradient primary / accent action button.
class GradientActionButton extends StatelessWidget {
  const GradientActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.busy = false,
    this.variant = GradientButtonVariant.primary,
    this.minWidth = 132,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy;
  final GradientButtonVariant variant;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final decoration = variant == GradientButtonVariant.accent
        ? AppDecorations.accentGradientButton()
        : AppDecorations.primaryGradientButton();

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          child: Ink(
            decoration: enabled
                ? decoration
                : BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: minWidth, minHeight: 42),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (busy)
                      const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    else
                      Icon(
                        icon,
                        size: 18,
                        color: variant == GradientButtonVariant.accent
                            ? const Color(0xFF07130D)
                            : Colors.white,
                      ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: variant == GradientButtonVariant.accent
                            ? const Color(0xFF07130D)
                            : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum GradientButtonVariant { primary, accent }
