import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/providers.dart';
import '../../data/models/app_settings.dart';

/// Owns the Appearance and Runtime defaults sections.
class AppSettingsViewModel extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() => ref.read(appSettingsRepositoryProvider).load();

  Future<void> setThemeMode(ThemeMode mode) =>
      _save((s) => s.copyWith(themeMode: mode), reloadModel: false);

  Future<void> setContextLength(int tokens) =>
      _save((s) => s.copyWith(contextLength: tokens));

  Future<void> setCpuThreads(int? threads) => _save(
    (s) => s.copyWith(cpuThreads: threads, clearCpuThreads: threads == null),
  );

  Future<void> setUseGpu(bool enabled) =>
      _save((s) => s.copyWith(useGpu: enabled));

  AppSettings get current => state.value ?? const AppSettings();

  Future<void> _save(
    AppSettings Function(AppSettings) change, {
    bool reloadModel = true,
  }) async {
    final existing = await future;
    final next = change(existing);
    if (next == existing) return;
    state = AsyncData<AppSettings>(next);
    await ref.read(appSettingsRepositoryProvider).save(next);
    if (reloadModel) await ref.read(llmServiceProvider).dispose();
  }
}
