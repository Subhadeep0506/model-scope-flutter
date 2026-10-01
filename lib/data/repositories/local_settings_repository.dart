import 'dart:developer' as developer;

import '../models/sampler_settings.dart';
import '../sources/json_file_store.dart';
import 'settings_repository.dart';

/// [SettingsRepository] backed by a JSON file in the app's documents directory.
class LocalSettingsRepository implements SettingsRepository {
  const LocalSettingsRepository(this._store);

  final JsonFileStore _store;

  static const String _settingsKey = 'sampler';

  @override
  Future<SamplerSettings> load() async {
    final document = await _store.read();
    final raw = document?[_settingsKey];
    if (raw is! Map<String, dynamic>) return const SamplerSettings();
    try {
      return SamplerSettings.fromJson(raw);
    } catch (error, stackTrace) {
      developer.log(
        'Falling back to default sampler settings',
        name: 'LocalSettingsRepository',
        error: error,
        stackTrace: stackTrace,
      );
      return const SamplerSettings();
    }
  }

  @override
  Future<void> save(SamplerSettings settings) =>
      // Merge, not write: `AppSettingsRepository` keeps its own key in the same
      // document, and a wholesale write would drop it.
      _store.merge(<String, dynamic>{_settingsKey: settings.toJson()});
}
