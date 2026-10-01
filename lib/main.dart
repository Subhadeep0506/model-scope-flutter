import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nobodywho/nobodywho.dart';
import 'package:path_provider/path_provider.dart';

import 'config/di/providers.dart';
import 'config/di/view_models.dart';
import 'config/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
      routerConfig: ref.watch(routerProvider),
    );
  }
}
