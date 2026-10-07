import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/providers.dart';
import '../../data/models/api_keys.dart';
import 'api_keys_state.dart';

/// Owns the API keys section.
class ApiKeysViewModel extends AsyncNotifier<ApiKeysState> {
  @override
  Future<ApiKeysState> build() async =>
      ApiKeysState(keys: await ref.read(apiKeyRepositoryProvider).loadAll());

  /// Stores [value] for [kind], dropping any stale verification result — a key
  /// that has been edited has not been checked.
  Future<void> setKey(ApiKeyKind kind, String value) async {
    final existing = current;
    if (existing.keyOf(kind) == value.trim()) return;

    state = AsyncData<ApiKeysState>(
      existing.copyWith(
        keys: <ApiKeyKind, String>{...existing.keys, kind: value.trim()},
        verification: <ApiKeyKind, VerifyState>{...existing.verification}
          ..remove(kind),
      ),
    );
    await ref.read(apiKeyRepositoryProvider).write(kind, value);
  }

  /// Checks a key against its own service and reports what came back.
  ///
  /// The token comes from state rather than the keychain: the card flushes
  /// what is on screen before calling this, and state is written before that
  /// write completes — so Verify always checks what the user is looking at.
  Future<void> verify(ApiKeyKind kind) async {
    if (!kind.isVerifiable) return;

    final token = current.keyOf(kind);
    if (token.isEmpty) {
      _setVerification(kind, const VerifyFailed('Enter a key first.'));
      return;
    }

    _setVerification(kind, const VerifyChecking());
    try {
      final summary = await ref
          .read(apiKeyVerifierProvider)
          .verify(kind, token);
      _setVerification(kind, VerifyPassed(summary));
    } catch (error) {
      _setVerification(kind, VerifyFailed('$error'));
    }
  }

  ApiKeysState get current =>
      state.value ?? const ApiKeysState(keys: <ApiKeyKind, String>{});

  void _setVerification(ApiKeyKind kind, VerifyState result) {
    final existing = current;
    state = AsyncData<ApiKeysState>(
      existing.copyWith(
        verification: <ApiKeyKind, VerifyState>{
          ...existing.verification,
          kind: result,
        },
      ),
    );
  }
}
