import 'dart:developer' as developer;

import '../models/sampler_settings.dart';
import '../sources/json_file_store.dart';

/// Storage for the sampling configuration, in `settings.json`.
class SettingsRepository {
  const SettingsRepository(this._store);

  final JsonFileStore _store;

  static const String _settingsKey = 'sampler';

  Future<SamplerSettings> load() async {
    final document = await _store.read();
    final raw = document?[_settingsKey];
    if (raw is! Map<String, dynamic>) return const SamplerSettings();
    try {
      return SamplerSettings.fromJson(raw);
    } catch (error, stackTrace) {
      developer.log(
        'Falling back to default sampler settings',
        name: 'SettingsRepository',
        error: error,
        stackTrace: stackTrace,
      );
      return const SamplerSettings();
    }
  }

  Future<void> save(SamplerSettings settings) =>
      // Merge, not write: `AppSettingsRepository` shares this document.
      _store.merge(<String, dynamic>{_settingsKey: settings.toJson()});
}
