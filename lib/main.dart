import 'dart:async';
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
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await NobodyWho.init();
  final documents = await getApplicationDocumentsDirectory();
  final container = ProviderContainer(
    overrides: [documentsDirectoryProvider.overrideWithValue(documents)],
  );
  container.read(downloadViewModelProvider);
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ModelScopeApp(),
    ),
  );

  afterFirstFrame(container);
}

@visibleForTesting
void afterFirstFrame(ProviderContainer container) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(container.read(modelDownloaderProvider).askToNotify());
    _logSystemBarInsets();
  });
}

void _logSystemBarInsets() {
  final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
  if (view == null) return;
  final ratio = view.devicePixelRatio;
  developer.log(
    'System bar insets in dp — top ${(view.padding.top / ratio).round()}, '
    'bottom ${(view.padding.bottom / ratio).round()}',
    name: 'main',
  );
}

class ModelScopeApp extends ConsumerWidget {
  const ModelScopeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode =
        ref.watch(appSettingsViewModelProvider).value?.themeMode ??
        ThemeMode.system;

    return MaterialApp.router(
      title: 'ModelScope',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      builder: (_, child) =>
          SystemBarStyle(child: child ?? const SizedBox.shrink()),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
