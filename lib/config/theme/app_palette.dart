import 'package:flutter/material.dart';

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.canvas,
    required this.surface,
    required this.primary,
    required this.onPrimary,
    required this.primaryIdle,
    required this.ink,
    required this.muted,
    required this.outline,
    required this.fieldFill,
    required this.pill,
    required this.navIndicator,
    required this.iconTile,
    required this.selectedTile,
    required this.danger,
    required this.warning,
    required this.chartSeries,
  });

  /// Page background behind every scaffold.
  final Color canvas;

  /// Raised card / sheet / nav-bar background.
  final Color surface;

  /// Brand green. Used for the `+` button, user bubbles and active sliders.
  final Color primary;

  /// Foreground on top of [primary].
  final Color onPrimary;

  /// Desaturated [primary] for the send button's disabled state only.
  final Color primaryIdle;

  /// Primary text colour.
  final Color ink;

  /// Secondary text: timestamps, metrics, hints, slider labels.
  final Color muted;

  /// Hairline borders on cards, fields and chips.
  final Color outline;

  /// Fill of the search field and the filter chips.
  final Color fieldFill;

  /// Fill of the small `T 0.70` temperature pill.
  final Color pill;

  /// Fill of the selected navigation-bar indicator.
  final Color navIndicator;

  /// Fill of the rounded icon square on a session row.
  final Color iconTile;

  /// Fill of the selected row in the loaded-models sheet.
  final Color selectedTile;

  /// Destructive actions (session delete, error states).
  final Color danger;

  /// Cautions that are not failures: a quant large enough to strain the device.
  final Color warning;

  /// One colour per line on a multi-series chart, in the order lines are
  /// drawn. Five, because the agents that chart anything cap themselves at
  /// five rows; a sixth series wraps round to the first.
  ///
  /// The last two reuse the warning and danger hues on purpose — a chart that
  /// introduced colours found nowhere else in the app would read as belonging
  /// to a different one.
  final List<Color> chartSeries;

  /// The colour for series [index], wrapping when there are more lines than
  /// colours.
  Color seriesAt(int index) => chartSeries[index % chartSeries.length];

  /// Sampled from the mockups: the sheets darken the page to exactly 80% black.
  static const Color scrim = Color(0xCC000000);

  static const AppPalette light = AppPalette(
    canvas: Color(0xFFF6FCF7),
    surface: Color(0xFFFFFFFF),
    primary: Color(0xFF00722E),
    onPrimary: Color(0xFFFFFFFF),
    primaryIdle: Color(0xFF7FB896),
    ink: Color(0xFF0E1F12),
    muted: Color(0xFF556959),
    outline: Color(0xFFC2D8C5),
    fieldFill: Color(0xFFDDF4E1),
    pill: Color(0xFFD0EED5),
    navIndicator: Color(0xFFCCE3D5),
    iconTile: Color(0xFFD9EAE0),
    selectedTile: Color(0xFFDEEEE4),
    danger: Color(0xFFA33328),
    warning: Color(0xFFB26B00),
    chartSeries: <Color>[
      Color(0xFF00722E),
      Color(0xFF1565A8),
      Color(0xFF6A3FA0),
      Color(0xFFB26B00),
      Color(0xFFA33328),
    ],
  );

  static const AppPalette dark = AppPalette(
    canvas: Color(0xFF0B140E),
    surface: Color(0xFF14201A),
    primary: Color(0xFF3DBE6E),
    onPrimary: Color(0xFF04210F),
    primaryIdle: Color(0xFF3F6B51),
    ink: Color(0xFFE6F2E9),
    muted: Color(0xFF93A89A),
    outline: Color(0xFF2A3B31),
    fieldFill: Color(0xFF1B2A22),
    pill: Color(0xFF1F3328),
    navIndicator: Color(0xFF23382C),
    iconTile: Color(0xFF1B2A22),
    selectedTile: Color(0xFF1E3227),
    danger: Color(0xFFE79289),
    warning: Color(0xFFE0A33C),
    chartSeries: <Color>[
      Color(0xFF3DBE6E),
      Color(0xFF56A8E8),
      Color(0xFFB08BE0),
      Color(0xFFE0A33C),
      Color(0xFFE79289),
    ],
  );

  @override
  AppPalette copyWith({
    Color? canvas,
    Color? surface,
    Color? primary,
    Color? onPrimary,
    Color? primaryIdle,
    Color? ink,
    Color? muted,
    Color? outline,
    Color? fieldFill,
    Color? pill,
    Color? navIndicator,
    Color? iconTile,
    Color? selectedTile,
    Color? danger,
    Color? warning,
    List<Color>? chartSeries,
  }) {
    return AppPalette(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      primaryIdle: primaryIdle ?? this.primaryIdle,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      outline: outline ?? this.outline,
      fieldFill: fieldFill ?? this.fieldFill,
      pill: pill ?? this.pill,
      navIndicator: navIndicator ?? this.navIndicator,
      iconTile: iconTile ?? this.iconTile,
      selectedTile: selectedTile ?? this.selectedTile,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
      chartSeries: chartSeries ?? this.chartSeries,
    );
  }

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      canvas: Color.lerp(canvas, other.canvas, t) ?? canvas,
      surface: Color.lerp(surface, other.surface, t) ?? surface,
      primary: Color.lerp(primary, other.primary, t) ?? primary,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t) ?? onPrimary,
      primaryIdle: Color.lerp(primaryIdle, other.primaryIdle, t) ?? primaryIdle,
      ink: Color.lerp(ink, other.ink, t) ?? ink,
      muted: Color.lerp(muted, other.muted, t) ?? muted,
      outline: Color.lerp(outline, other.outline, t) ?? outline,
      fieldFill: Color.lerp(fieldFill, other.fieldFill, t) ?? fieldFill,
      pill: Color.lerp(pill, other.pill, t) ?? pill,
      navIndicator:
          Color.lerp(navIndicator, other.navIndicator, t) ?? navIndicator,
      iconTile: Color.lerp(iconTile, other.iconTile, t) ?? iconTile,
      selectedTile:
          Color.lerp(selectedTile, other.selectedTile, t) ?? selectedTile,
      danger: Color.lerp(danger, other.danger, t) ?? danger,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      chartSeries: <Color>[
        for (final (index, colour) in chartSeries.indexed)
          Color.lerp(colour, other.seriesAt(index), t) ?? colour,
      ],
    );
  }
}

/// Shorthand for reading the palette off the current theme.
extension AppPaletteX on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}
