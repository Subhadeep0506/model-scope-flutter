import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keeps the status and navigation bar icons legible against the app's canvas.
///
/// Nothing else sets this: no screen has an [AppBar], so Material's
/// `AppBarTheme.systemOverlayStyle` — the usual route — never applies, and
/// without it the bars keep whatever the Android launch theme left behind,
/// which is light-mode icons regardless of the app's brightness.
///
/// Installed through `MaterialApp.builder` so it sits *inside* the theme. The
/// brightness has to be the resolved one: `themeMode` defaults to
/// [ThemeMode.system], so reading the stored preference would say `system`
/// rather than which of the two the device actually picked.
class SystemBarStyle extends StatelessWidget {
  const SystemBarStyle({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Icons contrast with the canvas behind them, so a dark app wants light
    // icons and the other way round.
    final icons = Theme.of(context).brightness == Brightness.dark
        ? Brightness.light
        : Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Theme.of(context).brightness,
        statusBarIconBrightness: icons,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: icons,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: child,
    );
  }
}
