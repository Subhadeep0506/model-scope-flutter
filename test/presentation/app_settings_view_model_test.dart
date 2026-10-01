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
    // Arrange
    container = containerWith(
      const AppSettings(
        themeMode: ThemeMode.light,
        contextLength: 2048,
        cpuThreads: 6,
        useGpu: false,
      ),
    );

    // Act
    final loaded = await settings();

    // Assert
    check(loaded.themeMode).equals(ThemeMode.light);
    check(loaded.contextLength).equals(2048);
    check(loaded.cpuThreads).equals(6);
    check(loaded.useGpu).isFalse();
  });

  test('a fresh install follows the system theme', () async {
    // Arrange
    container = containerWith();

    // Act
    final loaded = await settings();

    // Assert
    check(loaded.themeMode).equals(ThemeMode.system);
  });

  test('changing the theme persists without touching the model', () async {
    // Arrange — switching to dark mid-conversation must not drop the weights.
    container = containerWith();
    await settings();

    // Act
    await notifier().setThemeMode(ThemeMode.dark);

    // Assert
    check(repository.stored.themeMode).equals(ThemeMode.dark);
    check(llm.disposeCalls).equals(0);
  });

  test('changing the context length releases the loaded model', () async {
    // Arrange
    container = containerWith();
    await settings();

    // Act
    await notifier().setContextLength(8192);

    // Assert — context size is a `Chat.fromPath` argument, so the running
    // model cannot adopt it; the next chat open reloads instead.
    check(repository.stored.contextLength).equals(8192);
    check(llm.disposeCalls).equals(1);
  });

  test('changing the thread count releases the loaded model', () async {
    // Arrange
    container = containerWith();
    await settings();

    // Act
    await notifier().setCpuThreads(8);

    // Assert
    check(repository.stored.cpuThreads).equals(8);
    check(llm.disposeCalls).equals(1);
  });

  test('auto threads is stored as null, not as a number', () async {
    // Arrange — the slider's lowest slot hands detection back to the library.
    container = containerWith(const AppSettings(cpuThreads: 8));
    await settings();

    // Act
    await notifier().setCpuThreads(null);

    // Assert
    check(repository.stored.cpuThreads).isNull();
    check((await settings()).cpuThreads).isNull();
  });

  test('toggling GPU offload releases the loaded model', () async {
    // Arrange
    container = containerWith();
    await settings();

    // Act
    await notifier().setUseGpu(false);

    // Assert
    check(repository.stored.useGpu).isFalse();
    check(llm.disposeCalls).equals(1);
  });

  test('setting a value to what it already is writes nothing', () async {
    // Arrange — sliders report their value continuously while dragging.
    container = containerWith();
    await settings();

    // Act
    await notifier().setContextLength(AppSettings.defaultContextLength);

    // Assert — no needless write, and no needless unload of a loaded model.
    check(repository.saveCalls).equals(0);
    check(llm.disposeCalls).equals(0);
  });

  test('an edit made before the load finishes is not lost', () async {
    // Arrange — the Settings screen is reachable before settings.json is read.
    container = containerWith(const AppSettings(contextLength: 2048));

    // Act — no await on the load first, deliberately.
    await notifier().setUseGpu(false);

    // Assert — the edit applies to the stored settings, not to the defaults.
    final loaded = await settings();
    check(loaded.contextLength).equals(2048);
    check(loaded.useGpu).isFalse();
    check(repository.stored.contextLength).equals(2048);
  });
}
