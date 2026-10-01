import '../models/api_keys.dart';
import '../sources/secure_key_store.dart';

/// Storage for the third-party credentials on the Settings screen.
abstract interface class ApiKeyRepository {
  /// Every key, with an empty string for the ones never entered.
  Future<Map<ApiKeyKind, String>> loadAll();

  Future<String> read(ApiKeyKind kind);

  Future<void> write(ApiKeyKind kind, String value);
}

/// [ApiKeyRepository] over the platform keychain.
class SecureApiKeyRepository implements ApiKeyRepository {
  const SecureApiKeyRepository(this._store);

  final SecureKeyStore _store;

  @override
  Future<Map<ApiKeyKind, String>> loadAll() async {
    final keys = <ApiKeyKind, String>{};
    for (final kind in ApiKeyKind.values) {
      keys[kind] = await read(kind);
    }
    return keys;
  }

  @override
  Future<String> read(ApiKeyKind kind) async =>
      await _store.read(kind.storageKey) ?? '';

  @override
  Future<void> write(ApiKeyKind kind, String value) =>
      _store.write(kind.storageKey, value.trim());
}
