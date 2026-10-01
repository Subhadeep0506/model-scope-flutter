import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/providers.dart';
import '../../data/models/app_settings.dart';

/// Owns the Appearance and Runtime defaults sections.
///
/// Unlike the sampler, these cannot be pushed onto a model that is already
/// running — context size, thread count and GPU offload are all arguments to
/// `Chat.fromPath`. Changing one therefore releases the loaded model so the
/// next conversation picks the new value up.
class AppSettingsViewModel extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() => ref.read(appSettingsRepositoryProvider).load();

  /// Appearance only; no reload needed.
  Future<void> setThemeMode(ThemeMode mode) =>
      _save((s) => s.copyWith(themeMode: mode), reloadModel: false);

  Future<void> setContextLength(int tokens) =>
      _save((s) => s.copyWith(contextLength: tokens));

  /// Pass null to hand thread count back to `nobodywho`'s auto-detection.
  Future<void> setCpuThreads(int? threads) => _save(
    (s) => s.copyWith(cpuThreads: threads, clearCpuThreads: threads == null),
  );

  Future<void> setUseGpu(bool enabled) =>
      _save((s) => s.copyWith(useGpu: enabled));

  AppSettings get current => state.value ?? const AppSettings();

  /// Applies [change] to the stored settings and persists the result.
  ///
  /// Awaits the build rather than reading `current`, so a tap that lands while
  /// settings.json is still being read edits what is on disk instead of the
  /// defaults — which the load would then overwrite anyway.
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
