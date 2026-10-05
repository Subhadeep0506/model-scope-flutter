import '../models/api_keys.dart';
import '../sources/secure_key_store.dart';

/// Storage for the third-party credentials on the Settings screen, kept in the
/// platform keychain.
class ApiKeyRepository {
  const ApiKeyRepository(this._store);

  final SecureKeyStore _store;

  /// Every key, with an empty string for the ones never entered.
  Future<Map<ApiKeyKind, String>> loadAll() async {
    final keys = <ApiKeyKind, String>{};
    for (final kind in ApiKeyKind.values) {
      keys[kind] = await read(kind);
    }
    return keys;
  }

  Future<String> read(ApiKeyKind kind) async =>
      await _store.read(kind.storageKey) ?? '';

  Future<void> write(ApiKeyKind kind, String value) =>
      _store.write(kind.storageKey, value.trim());
}
