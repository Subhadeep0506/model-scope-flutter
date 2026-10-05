import 'dart:developer' as developer;

import '../models/app_settings.dart';
import '../sources/json_file_store.dart';

/// Storage for the appearance and runtime-default settings. Shares
/// `settings.json` with the sampler settings, so writes go through
/// [JsonFileStore.merge] rather than overwriting the whole document.
class AppSettingsRepository {
  const AppSettingsRepository(this._store);

  final JsonFileStore _store;

  static const String _appKey = 'app';

  Future<AppSettings> load() async {
    final document = await _store.read();
    final raw = document?[_appKey];
    if (raw is! Map<String, dynamic>) return const AppSettings();
    try {
      return AppSettings.fromJson(raw);
    } catch (error, stackTrace) {
      developer.log(
        'Falling back to default app settings',
        name: 'AppSettingsRepository',
        error: error,
        stackTrace: stackTrace,
      );
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) =>
      _store.merge(<String, dynamic>{_appKey: settings.toJson()});
}
