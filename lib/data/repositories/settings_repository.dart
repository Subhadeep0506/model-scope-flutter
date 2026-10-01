import '../models/sampler_settings.dart';

/// Storage for the sampling configuration.
abstract interface class SettingsRepository {
  Future<SamplerSettings> load();

  Future<void> save(SamplerSettings settings);
}
