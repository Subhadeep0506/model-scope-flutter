import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/providers.dart';
import '../../data/models/sampler_settings.dart';

class SamplerViewModel extends AsyncNotifier<SamplerSettings> {
  @override
  Future<SamplerSettings> build() =>
      ref.read(settingsRepositoryProvider).load();

  Future<void> apply(SamplerSettings settings) async {
    if (settings == current) return;
    state = AsyncData<SamplerSettings>(settings);
    await ref.read(settingsRepositoryProvider).save(settings);
    await ref.read(llmServiceProvider).applySettings(settings);
  }

  Future<void> resetToDefaults() => apply(const SamplerSettings());
  SamplerSettings get current => state.value ?? const SamplerSettings();
}
