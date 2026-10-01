import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/providers.dart';
import '../../data/models/sampler_settings.dart';

/// Owns the sampling configuration behind the Sampling sheet.
///
/// Changes are pushed straight onto the loaded model, so a slider takes effect
/// on the next reply without rebuilding the chat.
class SamplerViewModel extends AsyncNotifier<SamplerSettings> {
  @override
  Future<SamplerSettings> build() =>
      ref.read(settingsRepositoryProvider).load();

  /// Stores [settings], then forwards them to the model.
  ///
  /// `maxTokens` is the exception: the sampler API has no token cap, so the
  /// chat view model reads that one back and enforces it while streaming.
  Future<void> apply(SamplerSettings settings) async {
    if (settings == current) return;
    state = AsyncData<SamplerSettings>(settings);
    await ref.read(settingsRepositoryProvider).save(settings);
    await ref.read(llmServiceProvider).applySettings(settings);
  }

  Future<void> resetToDefaults() => apply(const SamplerSettings());

  /// The settings in force right now, falling back to the designed defaults
  /// while the stored ones are still loading.
  SamplerSettings get current => state.value ?? const SamplerSettings();
}
