import 'dart:developer' as developer;

import '../models/app_settings.dart';
import '../sources/json_file_store.dart';

/// Storage for the appearance and runtime-default settings.
abstract interface class AppSettingsRepository {
  Future<AppSettings> load();

  Future<void> save(AppSettings settings);
}

/// [AppSettingsRepository] sharing `settings.json` with the sampler settings.
///
/// Writes go through [JsonFileStore.merge] so the two repositories cannot
/// overwrite each other's key.
class LocalAppSettingsRepository implements AppSettingsRepository {
  const LocalAppSettingsRepository(this._store);

  final JsonFileStore _store;

  static const String _appKey = 'app';

  @override
  Future<AppSettings> load() async {
    final document = await _store.read();
    final raw = document?[_appKey];
    if (raw is! Map<String, dynamic>) return const AppSettings();
    try {
      return AppSettings.fromJson(raw);
    } catch (error, stackTrace) {
      developer.log(
        'Falling back to default app settings',
        name: 'LocalAppSettingsRepository',
        error: error,
        stackTrace: stackTrace,
      );
      return const AppSettings();
    }
  }

  @override
  Future<void> save(AppSettings settings) =>
      _store.merge(<String, dynamic>{_appKey: settings.toJson()});
}
