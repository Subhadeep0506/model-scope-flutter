import 'package:checks/checks.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/config/di/view_models.dart';
import 'package:model_scope_flutter/data/models/app_settings.dart';
import 'package:model_scope_flutter/presentation/view_models/app_settings_view_model.dart';

import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAppSettingsRepository repository;
  late FakeLlmService llm;
  late ProviderContainer container;

  ProviderContainer containerWith([AppSettings? stored]) {
    repository = FakeAppSettingsRepository(stored ?? const AppSettings());
    llm = FakeLlmService();
    return ProviderContainer.test(
      retry: noRetry,
      overrides: fakeOverrides(
        llm: llm,
        sessions: FakeSessionRepository(),
        appSettings: repository,
      ),
    );
  }

  AppSettingsViewModel notifier() =>
      container.read(appSettingsViewModelProvider.notifier);

  Future<AppSettings> settings() =>
      container.read(appSettingsViewModelProvider.future);

  test('the stored settings are what the screen opens on', () async {
    container = containerWith(
      const AppSettings(
        themeMode: ThemeMode.light,
        contextLength: 2048,
        cpuThreads: 6,
        useGpu: false,
      ),
    );

    final loaded = await settings();

    check(loaded.themeMode).equals(ThemeMode.light);
    check(loaded.contextLength).equals(2048);
    check(loaded.cpuThreads).equals(6);
    check(loaded.useGpu).isFalse();
  });

  test('a fresh install follows the system theme', () async {
    container = containerWith();

    final loaded = await settings();

    check(loaded.themeMode).equals(ThemeMode.system);
  });

  test('changing the theme persists without touching the model', () async {
    // Switching to dark mid-conversation must not drop the weights.
    container = containerWith();
    await settings();

    await notifier().setThemeMode(ThemeMode.dark);

    check(repository.stored.themeMode).equals(ThemeMode.dark);
    check(llm.disposeCalls).equals(0);
  });

  test('changing the context length releases the loaded model', () async {
    container = containerWith();
    await settings();

    await notifier().setContextLength(8192);

    // Context size is a `Chat.fromPath` argument, so the running
    // model cannot adopt it; the next chat open reloads instead.
    check(repository.stored.contextLength).equals(8192);
    check(llm.disposeCalls).equals(1);
  });

  test('changing the thread count releases the loaded model', () async {
    container = containerWith();
    await settings();

    await notifier().setCpuThreads(8);

    check(repository.stored.cpuThreads).equals(8);
    check(llm.disposeCalls).equals(1);
  });

  test('auto threads is stored as null, not as a number', () async {
    // The slider's lowest slot hands detection back to the library.
    container = containerWith(const AppSettings(cpuThreads: 8));
    await settings();

    await notifier().setCpuThreads(null);

    check(repository.stored.cpuThreads).isNull();
    check((await settings()).cpuThreads).isNull();
  });

  test('toggling GPU offload releases the loaded model', () async {
    container = containerWith();
    await settings();

    await notifier().setUseGpu(false);

    check(repository.stored.useGpu).isFalse();
    check(llm.disposeCalls).equals(1);
  });

  test('setting a value to what it already is writes nothing', () async {
    // Sliders report their value continuously while dragging.
    container = containerWith();
    await settings();

    await notifier().setContextLength(AppSettings.defaultContextLength);

    // No needless write, and no needless unload of a loaded model.
    check(repository.saveCalls).equals(0);
    check(llm.disposeCalls).equals(0);
  });

  test('an edit made before the load finishes is not lost', () async {
    // The Settings screen is reachable before settings.json is read.
    container = containerWith(const AppSettings(contextLength: 2048));

    // No await on the load first, deliberately.
    await notifier().setUseGpu(false);

    // The edit applies to the stored settings, not to the defaults.
    final loaded = await settings();
    check(loaded.contextLength).equals(2048);
    check(loaded.useGpu).isFalse();
    check(repository.stored.contextLength).equals(2048);
  });
}
