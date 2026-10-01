import 'package:flutter/material.dart';

import 'app_metrics.dart';
import 'app_palette.dart';
import 'app_typography.dart';

/// Material 3 themes built on top of the sampled design tokens.
abstract final class AppTheme {
  static ThemeData get light => _build(AppPalette.light, Brightness.light);

  static ThemeData get dark => _build(AppPalette.dark, Brightness.dark);

  static ThemeData _build(AppPalette palette, Brightness brightness) {
    final textTheme = AppTypography.textTheme(palette.ink, palette.muted);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: palette.primary,
          brightness: brightness,
        ).copyWith(
          primary: palette.primary,
          onPrimary: palette.onPrimary,
          surface: palette.canvas,
          onSurface: palette.ink,
          surfaceContainerLowest: palette.surface,
          surfaceContainer: palette.surface,
          onSurfaceVariant: palette.muted,
          outline: palette.outline,
          outlineVariant: palette.outline,
          secondaryContainer: palette.fieldFill,
          onSecondaryContainer: palette.ink,
          error: palette.danger,
          scrim: AppPalette.scrim,
        );

    const metrics = AppMetrics();

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.canvas,
      canvasColor: palette.canvas,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      extensions: <ThemeExtension<dynamic>>[
        palette,
        metrics,
        AppMonoText(muted: palette.muted, ink: palette.primary),
      ],
      dividerTheme: DividerThemeData(
        color: palette.outline,
        thickness: 1,
        space: 1,
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: metrics.cardShape),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.canvas,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: AppPalette.scrim,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: metrics.sheetShape),
        showDragHandle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: palette.navIndicator,
        height: metrics.navBar,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorShape: const StadiumBorder(),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? palette.primary
                : palette.muted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? textTheme.labelMedium?.copyWith(
                  color: palette.primary,
                  fontWeight: FontWeight.w600,
                )
              : textTheme.labelMedium,
        ),
      ),
      // The mockups use the round-thumb slider, which is the default shape, so
      // the `year2023` opt-out is deliberately left unset here.
      sliderTheme: SliderThemeData(
        activeTrackColor: palette.primary,
        inactiveTrackColor: palette.fieldFill,
        thumbColor: palette.surface,
        overlayColor: palette.primary.withValues(alpha: 0.12),
        trackHeight: 4,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.ink,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: palette.canvas),
        actionTextColor: palette.primaryIdle,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: metrics.cardShape),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        hintStyle: textTheme.bodyMedium?.copyWith(color: palette.muted),
        contentPadding: EdgeInsets.symmetric(
          horizontal: metrics.gapMd,
          vertical: metrics.gapMd,
        ),
        border: OutlineInputBorder(
          borderRadius: metrics.controlShape,
          borderSide: BorderSide(color: palette.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: metrics.controlShape,
          borderSide: BorderSide(color: palette.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: metrics.controlShape,
          borderSide: BorderSide(color: palette.primary, width: 1.5),
        ),
      ),
      // The GPU toggle in `settings-3.png` is a solid green pill with a white
      // thumb and no outline, which is not what M3 gives by default.
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.onPrimary
              : palette.surface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.primary
              : palette.fieldFill,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : palette.outline,
        ),
        thumbIcon: const WidgetStatePropertyAll<Icon?>(null),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.ink,
          backgroundColor: palette.surface,
          side: BorderSide(color: palette.outline),
          textStyle: textTheme.labelLarge,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: metrics.controlShape),
        ),
      ),
    );
  }
}
