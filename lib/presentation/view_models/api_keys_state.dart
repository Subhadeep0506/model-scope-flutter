import '../../data/models/api_keys.dart';

/// The stored credentials plus the outcome of the last Verify press.
class ApiKeysState {
  const ApiKeysState({required this.keys, this.verification = const {}});

  final Map<ApiKeyKind, String> keys;
  final Map<ApiKeyKind, VerifyState> verification;

  String keyOf(ApiKeyKind kind) => keys[kind] ?? '';

  VerifyState verificationOf(ApiKeyKind kind) =>
      verification[kind] ?? const VerifyIdle();

  ApiKeysState copyWith({
    Map<ApiKeyKind, String>? keys,
    Map<ApiKeyKind, VerifyState>? verification,
  }) => ApiKeysState(
    keys: keys ?? this.keys,
    verification: verification ?? this.verification,
  );
}
