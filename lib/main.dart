import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nobodywho/nobodywho.dart';
import 'package:path_provider/path_provider.dart';

import 'config/di/providers.dart';
import 'config/di/view_models.dart';
import 'config/theme/app_theme.dart';
import 'presentation/widgets/system_bar_style.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Draw behind the system bars rather than inheriting whatever the embedding
  // defaults to. Android 15 enforces this anyway; stating it keeps the two
  // platforms on the same footing, and every screen already pads itself with a
  // `SafeArea`.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Loads the native inference library. It has to finish before any `Chat` is
  // created, so it is awaited here rather than lazily in the service.
  await NobodyWho.init();

  final documents = await getApplicationDocumentsDirectory();

  runApp(
    ProviderScope(
      overrides: [documentsDirectoryProvider.overrideWithValue(documents)],
      child: const ModelScopeApp(),
    ),
  );

  _logSystemBarInsets();
}

/// Reports the system bar insets the platform hands Flutter, once.
///
/// Every screen wraps its body in a [SafeArea], so a header drawn under the
/// clock means the inset never arrived rather than that the padding is missing.
/// Read off the view instead of a [MediaQuery] so this stays out of any build
/// method, and after the first frame because the view has no padding before it.
void _logSystemBarInsets() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
    if (view == null) return;
    final ratio = view.devicePixelRatio;
    developer.log(
      'System bar insets in dp — top ${(view.padding.top / ratio).round()}, '
      'bottom ${(view.padding.bottom / ratio).round()}',
      name: 'main',
    );
  });
}

class ModelScopeApp extends ConsumerWidget {
  const ModelScopeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Follow the device until the stored preference has been read, so the
    // first frame never flashes the wrong brightness.
    final themeMode =
        ref.watch(appSettingsViewModelProvider).value?.themeMode ??
        ThemeMode.system;

    return MaterialApp.router(
      title: 'ModelScope',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      // Inside the theme, so the overlay style sees the brightness the device
      // resolved rather than the `system` that `themeMode` reports.
      builder: (_, child) =>
          SystemBarStyle(child: child ?? const SizedBox.shrink()),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
