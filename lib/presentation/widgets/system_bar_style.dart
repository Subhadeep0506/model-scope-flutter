import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keeps the status and navigation bar icons legible against the app's canvas.
/// Nothing else sets this — no screen has an [AppBar] — so without it the bars
/// keep the Android launch theme's light icons at any app brightness.
///
/// Installed through `MaterialApp.builder` so it sits *inside* the theme and
/// reads the resolved brightness, not the stored [ThemeMode.system].
class SystemBarStyle extends StatelessWidget {
  const SystemBarStyle({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Icons contrast with the canvas behind them.
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
