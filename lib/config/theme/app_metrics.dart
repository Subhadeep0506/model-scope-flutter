import 'package:flutter/material.dart';

/// Sizing and shape tokens, measured from the mockups in `assets/design/`.
///
/// Every number here came out of a pixel measurement of the PNGs rather than a
/// guess, so keeping widgets on these tokens is what keeps the build faithful.
@immutable
class AppMetrics extends ThemeExtension<AppMetrics> {
  const AppMetrics();

  /// Horizontal page padding either side of the content column.
  double get pagePadding => 18;

  /// Edge of the square icon buttons: `+`, back, tune, attach, send, and the
  /// rounded icon square on a session row.
  double get squareButton => 44;

  /// Height of the search field, the filter chips and the model strip.
  double get control => 40;

  /// Height of a session row card.
  double get sessionCard => 98;

  /// Height of the bottom navigation bar.
  double get navBar => 72;

  /// Size of the selected navigation indicator pill.
  Size get navIndicator => const Size(64, 32);

  /// A user bubble never grows past this fraction of the content width.
  double get bubbleMaxWidthFactor => 0.68;

  double get radiusCard => 10;
  double get radiusControl => 10;
  double get radiusBubble => 10;
  double get radiusSheet => 20;
  double get radiusPill => 6;

  BorderRadius get cardShape => BorderRadius.circular(radiusCard);
  BorderRadius get controlShape => BorderRadius.circular(radiusControl);
  BorderRadius get sheetShape =>
      BorderRadius.vertical(top: Radius.circular(radiusSheet));

  /// Spacing scale. Gaps in the mockups land on multiples of four.
  double get gapXs => 4;
  double get gapSm => 8;
  double get gapMd => 12;
  double get gapLg => 16;
  double get gapXl => 24;

  @override
  AppMetrics copyWith() => const AppMetrics();

  @override
  AppMetrics lerp(covariant AppMetrics? other, double t) => this;
}

/// Shorthand for reading the metrics off the current theme.
extension AppMetricsX on BuildContext {
  AppMetrics get metrics =>
      Theme.of(this).extension<AppMetrics>() ?? const AppMetrics();
}
