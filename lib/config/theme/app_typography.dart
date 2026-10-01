import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Type scale for the app.
///
/// The mockups pair a geometric sans for UI text with a monospace for *every*
/// piece of metadata — overlines, timestamps, `Q8_0`, `T 0.70`, tok/s readouts
/// and the sampling slider labels. Outfit and JetBrains Mono are the closest
/// Google Fonts match.
abstract final class AppTypography {
  /// Sans face used for all UI copy.
  static TextStyle sans({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
  }) => GoogleFonts.outfit(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );

  /// Monospace face used for all metadata.
  static TextStyle mono({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
  }) => GoogleFonts.jetBrainsMono(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );

  static TextTheme textTheme(Color ink, Color muted) => TextTheme(
    // "Chats", "Quant notes"
    displaySmall: sans(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      color: ink,
      height: 1.15,
      letterSpacing: -0.5,
    ),
    // Sheet titles: "Loaded models", "Sampling", "Attach"
    titleLarge: sans(fontSize: 18, fontWeight: FontWeight.w700, color: ink),
    // Session title, model name in the strip and the models sheet
    titleMedium: sans(fontSize: 16, fontWeight: FontWeight.w600, color: ink),
    titleSmall: sans(fontSize: 15, fontWeight: FontWeight.w600, color: ink),
    // Assistant message body
    bodyLarge: sans(
      fontSize: 15,
      fontWeight: FontWeight.w400,
      color: ink,
      height: 1.5,
    ),
    bodyMedium: sans(fontSize: 14, fontWeight: FontWeight.w400, color: ink),
    bodySmall: sans(fontSize: 13, fontWeight: FontWeight.w400, color: muted),
    // "Reset to defaults"
    labelLarge: sans(fontSize: 15, fontWeight: FontWeight.w500, color: ink),
    // Navigation bar labels
    labelMedium: sans(fontSize: 12, fontWeight: FontWeight.w500, color: muted),
    labelSmall: sans(fontSize: 11, fontWeight: FontWeight.w500, color: muted),
  );
}

/// Monospace styles, kept out of [TextTheme] because it has no mono slots.
@immutable
class AppMonoText extends ThemeExtension<AppMonoText> {
  const AppMonoText({required this.muted, required this.ink});

  final Color muted;
  final Color ink;

  /// "1 LOCAL SESSIONS", "SESSION · 12:08 PM"
  TextStyle get overline => AppTypography.mono(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: muted,
    letterSpacing: 1.2,
  );

  /// "118ms · 93.4 tok/s · 96 tok", "Sep 30, 2026, 12:08 PM"
  TextStyle get meta => AppTypography.mono(
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
    color: muted,
  );

  /// "Q8_0", "T 0.70"
  TextStyle get tag => AppTypography.mono(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: muted,
  );

  /// "TEMPERATURE", "TOP_P", "TOP_K", "MAX_TOKENS"
  TextStyle get sliderLabel => AppTypography.mono(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: muted,
    letterSpacing: 1.0,
  );

  /// The green value printed opposite each slider label.
  TextStyle get sliderValue =>
      AppTypography.mono(fontSize: 13, fontWeight: FontWeight.w600, color: ink);

  @override
  AppMonoText copyWith({Color? muted, Color? ink}) =>
      AppMonoText(muted: muted ?? this.muted, ink: ink ?? this.ink);

  @override
  AppMonoText lerp(covariant AppMonoText? other, double t) {
    if (other == null) return this;
    return AppMonoText(
      muted: Color.lerp(muted, other.muted, t) ?? muted,
      ink: Color.lerp(ink, other.ink, t) ?? ink,
    );
  }
}

/// Shorthand for reading the mono styles off the current theme.
extension AppMonoTextX on BuildContext {
  AppMonoText get mono =>
      Theme.of(this).extension<AppMonoText>() ??
      const AppMonoText(muted: Color(0xFF556959), ink: Color(0xFF0E1F12));
}
